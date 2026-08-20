import hashlib
import uuid
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from .models import (
    Building, CaptureSet, FarmOrganization, InferenceJob, InventoryCampaign,
    InventorySession, MediaAsset, OrganizationMembership, Pen,
)
from .tasks import run_counting_job
from .services.inference import Detection, is_detection_inside_roi


class InventoryApiTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user("operator", password="test-password")
        self.org = FarmOrganization.objects.create(code="F001", name="测试猪场")
        self.building = Building.objects.create(organization=self.org, code="B01", name="一栋")
        self.pen = Pen.objects.create(building=self.building, code="P01", name="一栏")
        OrganizationMembership.objects.create(organization=self.org, user=self.user, role=OrganizationMembership.Role.ADMIN)
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def _session(self, campaign=None, count=None):
        return InventorySession.objects.create(
            pen=self.pen,
            campaign=campaign,
            business_date=date(2026, 8, 17),
            created_by=self.user,
            status=InventorySession.Status.CONFIRMED if count is not None else InventorySession.Status.DRAFT,
            manual_count=count,
        )

    def _package(self, session, body=b"photo-bytes", asset_id=None):
        package_id, asset_id = uuid.uuid4(), asset_id or uuid.uuid4()
        sha256 = hashlib.sha256(body).hexdigest()
        create = self.client.post("/api/v1/packages/", {
            "package_id": str(package_id), "session_id": str(session.id), "idempotency_key": "capture-001",
            "blobs": [{"asset_id": str(asset_id), "relative_path": "single.jpg", "sha256": sha256,
                       "byte_size": len(body), "content_type": "image/jpeg"}],
        }, format="json")
        self.assertIn(create.status_code, (200, 201), create.content)
        upload = self.client.put(
            f"/api/v1/packages/{package_id}/blobs/{asset_id}/", body, content_type="application/octet-stream"
        )
        self.assertEqual(upload.status_code, 200, upload.content)
        manifest = {
            "capture_set": {"client_capture_id": str(uuid.uuid4()), "kind": "single"},
            "media": [{"asset_id": str(asset_id), "relative_path": "single.jpg", "view_position": "single",
                       "original_name": "single.jpg", "sha256": sha256, "byte_size": len(body),
                       "content_type": "image/jpeg", "roi": {"type": "polygon", "points": []}}],
        }
        response = self.client.put(f"/api/v1/packages/{package_id}/manifest/", manifest, format="json")
        return package_id, asset_id, response

    @override_settings(CELERY_TASK_ALWAYS_EAGER=True, COUNTING_PROVIDER="unavailable")
    def test_package_commit_is_idempotent_and_unavailable_model_requires_review(self):
        session = self._session()
        package_id, _, manifest = self._package(session)
        self.assertEqual(manifest.status_code, 200, manifest.content)
        committed = self.client.post(f"/api/v1/packages/{package_id}/commit/")
        self.assertEqual(committed.status_code, 201, committed.content)
        job = InferenceJob.objects.get(pk=committed.data["job_id"])
        run_counting_job(str(job.id))
        job.refresh_from_db()
        session.refresh_from_db()
        self.assertEqual(job.status, InferenceJob.Status.REVIEW_REQUIRED)
        self.assertEqual(session.status, InventorySession.Status.REVIEW_REQUIRED)
        retried = self.client.post(f"/api/v1/packages/{package_id}/commit/")
        self.assertEqual(retried.status_code, 200)
        self.assertEqual(retried.data["job_ids"], [str(job.id)])

    def test_exact_duplicate_photo_is_rejected_across_sessions(self):
        body = b"same-photo"
        first = self._session()
        package_id, _, manifest = self._package(first, body)
        self.assertEqual(manifest.status_code, 200)
        self.assertEqual(self.client.post(f"/api/v1/packages/{package_id}/commit/").status_code, 201)
        second = self._session()
        _, _, duplicate_manifest = self._package(second, body)
        self.assertEqual(duplicate_manifest.status_code, 400)
        self.assertIn("duplicate_media_ids", duplicate_manifest.data)

    def test_locked_media_cannot_be_deleted_but_admin_override_is_audited(self):
        session = self._session()
        capture = CaptureSet.objects.create(session=session, kind="single", client_capture_id=uuid.uuid4())
        media = MediaAsset.objects.create(
            organization=self.org, capture_set=capture, view_position="single", original_name="locked.jpg",
            content_type="image/jpeg", byte_size=10, sha256="a" * 64, storage_key="locked.jpg", state=MediaAsset.State.LOCKED,
        )
        denied = self.client.delete(f"/api/v1/media/{media.id}/")
        self.assertEqual(denied.status_code, 409)
        deleted = self.client.post(f"/api/v1/media/{media.id}/override_delete/", {"reason": "管理员复核错误照片"}, format="json")
        self.assertEqual(deleted.status_code, 200)
        media.refresh_from_db()
        self.assertEqual(media.state, MediaAsset.State.DELETED)

    def test_campaign_report_uses_confirmed_daily_counts_only(self):
        campaign = InventoryCampaign.objects.create(
            organization=self.org, name="月末盘点", start_date=date(2026, 8, 1), end_date=date(2026, 8, 31)
        )
        self._session(campaign=campaign, count=10)
        session = self._session(campaign=campaign, count=14)
        session.business_date = date(2026, 8, 18)
        session.save()
        draft = self._session(campaign=campaign)
        draft.business_date = date(2026, 8, 19)
        draft.save()
        response = self.client.get(f"/api/v1/reports/campaigns/{campaign.id}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["rows"][0]["mean"], 12)
        self.assertEqual(response.data["rows"][0]["rounded_count"], 12)

    def test_roi_filters_neighbor_pen_detection_by_box_center(self):
        roi = {"type": "rect", "x": 0, "y": 0, "width": 100, "height": 100}
        self.assertTrue(is_detection_inside_roi(Detection(bbox=[10, 10, 30, 30], confidence=0.9), roi))
        self.assertFalse(is_detection_inside_roi(Detection(bbox=[150, 10, 190, 30], confidence=0.9), roi))
