import hashlib
import uuid
from datetime import datetime

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import (
    AuditEvent, Building, CaptureSet, FarmOrganization, InferenceJob, InventoryCampaign,
    InventorySession, MediaAsset, OrganizationMembership, Pen, UploadBlob, UploadPackage,
)
from .serializers import (
    BuildingSerializer, FarmOrganizationSerializer, InferenceJobSerializer, InventoryCampaignSerializer,
    InventorySessionSerializer, MediaAssetSerializer, PenSerializer, UploadPackageSerializer,
)
from .services.blob_storage import blob_store
from .tasks import run_counting_job


def visible_organization_ids(user):
    if user.is_staff:
        return FarmOrganization.objects.values_list("id", flat=True)
    return OrganizationMembership.objects.filter(user=user, is_active=True).values_list("organization_id", flat=True)


def assert_org_access(user, organization_id):
    if not user.is_staff and not OrganizationMembership.objects.filter(
        user=user, organization_id=organization_id, is_active=True
    ).exists():
        raise PermissionDenied("无权访问该猪场组织。")


def assert_org_admin(user, organization_id):
    if user.is_staff:
        return
    if not OrganizationMembership.objects.filter(
        user=user,
        organization_id=organization_id,
        is_active=True,
        role__in=[OrganizationMembership.Role.ADMIN, OrganizationMembership.Role.REVIEWER],
    ).exists():
        raise PermissionDenied("需要组织审核或管理员权限。")


class OrganizationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = FarmOrganizationSerializer

    def get_queryset(self):
        return FarmOrganization.objects.filter(id__in=visible_organization_ids(self.request.user))


class BuildingViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = BuildingSerializer

    def get_queryset(self):
        return Building.objects.filter(organization_id__in=visible_organization_ids(self.request.user), is_active=True)


class PenViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = PenSerializer

    def get_queryset(self):
        return Pen.objects.filter(building__organization_id__in=visible_organization_ids(self.request.user), is_active=True)


class CampaignViewSet(viewsets.ModelViewSet):
    serializer_class = InventoryCampaignSerializer

    def get_queryset(self):
        return InventoryCampaign.objects.filter(organization_id__in=visible_organization_ids(self.request.user))

    def perform_create(self, serializer):
        assert_org_admin(self.request.user, serializer.validated_data["organization"].id)
        serializer.save()


class InventorySessionViewSet(viewsets.ModelViewSet):
    serializer_class = InventorySessionSerializer

    def get_queryset(self):
        return InventorySession.objects.select_related("pen__building__organization").filter(
            pen__building__organization_id__in=visible_organization_ids(self.request.user)
        )

    def perform_create(self, serializer):
        pen = serializer.validated_data["pen"]
        assert_org_access(self.request.user, pen.building.organization_id)
        campaign = serializer.validated_data.get("campaign")
        if campaign and campaign.organization_id != pen.building.organization_id:
            raise ValidationError("盘点周期与栏舍不属于同一组织。")
        serializer.save(created_by=self.request.user)

    @action(detail=True, methods=["post"])
    def confirm(self, request, pk=None):
        session = self.get_object()
        assert_org_admin(request.user, session.organization.id)
        count = request.data.get("count")
        if count is None:
            latest = session.inference_jobs.filter(status=InferenceJob.Status.SUCCEEDED).order_by("-created_at").first()
            if not latest or not hasattr(latest, "result"):
                raise ValidationError("没有可确认的模型结果；请提供人工确认数量。")
            count = latest.result.raw_count
        try:
            count = int(count)
        except (TypeError, ValueError):
            raise ValidationError("count 必须是非负整数。")
        if count < 0:
            raise ValidationError("count 必须是非负整数。")
        with transaction.atomic():
            session.manual_count = count
            session.status = InventorySession.Status.CONFIRMED
            session.confirmed_by = request.user
            session.confirmed_at = timezone.now()
            session.save()
            MediaAsset.objects.filter(capture_set__session=session, state=MediaAsset.State.ACTIVE).update(state=MediaAsset.State.LOCKED)
            AuditEvent.objects.create(
                organization=session.organization,
                actor=request.user,
                action=AuditEvent.Action.COUNT_CONFIRMED,
                target_type="InventorySession",
                target_id=str(session.id),
                reason=request.data.get("reason", ""),
                payload={"count": count},
            )
        return Response(self.get_serializer(session).data)


class UploadPackageCreateView(APIView):
    """Create/recover a package. Blob records make file-level retries idempotent."""

    def post(self, request):
        try:
            package_id = uuid.UUID(str(request.data["package_id"]))
            session_id = uuid.UUID(str(request.data["session_id"]))
        except (KeyError, ValueError):
            raise ValidationError("package_id 和 session_id 必须是 UUID。")
        key = str(request.data.get("idempotency_key", "")).strip()
        if not key:
            raise ValidationError("idempotency_key 为必填项。")
        session = InventorySession.objects.select_related("pen__building__organization").get(pk=session_id)
        assert_org_access(request.user, session.organization.id)
        blobs = request.data.get("blobs", [])
        if not isinstance(blobs, list) or not blobs:
            raise ValidationError("blobs 必须是非空数组。")
        with transaction.atomic():
            package, created = UploadPackage.objects.get_or_create(
                id=package_id,
                defaults={"session": session, "idempotency_key": key},
            )
            if not created and (package.session_id != session.id or package.idempotency_key != key):
                raise ValidationError("package_id 已由另一会话或幂等键使用。")
            for blob in blobs:
                try:
                    asset_id = uuid.UUID(str(blob["asset_id"]))
                    relative_path = str(blob["relative_path"])
                    sha256 = str(blob["sha256"]).lower()
                    byte_size = int(blob["byte_size"])
                    content_type = str(blob["content_type"])
                except (KeyError, ValueError, TypeError):
                    raise ValidationError("blob 元数据不完整或无效。")
                if len(sha256) != 64 or byte_size <= 0 or "/" in relative_path or "\\" in relative_path:
                    raise ValidationError("blob 哈希、大小或 relative_path 无效。")
                UploadBlob.objects.get_or_create(
                    package=package,
                    asset_id=asset_id,
                    defaults={
                        "relative_path": relative_path,
                        "sha256": sha256,
                        "byte_size": byte_size,
                        "content_type": content_type,
                    },
                )
        return Response(UploadPackageSerializer(package).data, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


class UploadBlobView(APIView):
    def put(self, request, package_id, asset_id):
        package = UploadPackage.objects.select_related("session__pen__building__organization").get(pk=package_id)
        assert_org_access(request.user, package.session.organization.id)
        if package.status == UploadPackage.Status.COMMITTED:
            return Response({"detail": "package 已提交。"}, status=status.HTTP_409_CONFLICT)
        blob = UploadBlob.objects.get(package=package, asset_id=asset_id)
        body = request.body
        if len(body) != blob.byte_size:
            raise ValidationError("文件大小与创建包时的声明不一致。")
        actual_hash = hashlib.sha256(body).hexdigest()
        if actual_hash != blob.sha256:
            raise ValidationError("SHA-256 校验失败。")
        blob_store.put_bytes(f"uploads/{package.id}/blobs/{blob.asset_id}", body, blob.content_type)
        blob.uploaded_at = timezone.now()
        blob.save(update_fields=["uploaded_at", "updated_at"])
        if not package.blobs.filter(uploaded_at__isnull=True).exists():
            package.status = UploadPackage.Status.AWAITING_MANIFEST
            package.save(update_fields=["status", "updated_at"])
        return Response({"asset_id": str(asset_id), "uploaded": True})


class UploadManifestView(APIView):
    def put(self, request, package_id):
        package = UploadPackage.objects.select_related("session__pen__building__organization").get(pk=package_id)
        assert_org_access(request.user, package.session.organization.id)
        if package.status == UploadPackage.Status.COMMITTED:
            return Response({"detail": "package 已提交。"}, status=status.HTTP_409_CONFLICT)
        manifest = request.data
        self._validate_manifest(package, manifest)
        manifest["_server_quality_flags"] = self._find_near_duplicates(package, manifest)
        package.manifest = manifest
        package.status = UploadPackage.Status.READY_TO_COMMIT
        package.save(update_fields=["manifest", "status", "updated_at"])
        return Response({"package_id": str(package.id), "status": package.status})

    @staticmethod
    def _validate_manifest(package, manifest):
        if not isinstance(manifest, dict):
            raise ValidationError("manifest 必须是对象。")
        capture = manifest.get("capture_set", {})
        media = manifest.get("media", [])
        try:
            uuid.UUID(str(capture["client_capture_id"]))
            kind = capture["kind"]
        except (KeyError, ValueError):
            raise ValidationError("capture_set.client_capture_id 与 kind 为必填项。")
        if kind not in CaptureSet.Kind.values or not isinstance(media, list) or not media:
            raise ValidationError("采集组类型或媒体列表无效。")
        blobs = {str(blob.asset_id): blob for blob in package.blobs.all()}
        supplied_positions = set()
        for item in media:
            asset_id = str(item.get("asset_id", ""))
            blob = blobs.get(asset_id)
            if not blob or not blob.uploaded_at:
                raise ValidationError(f"媒体 {asset_id} 未完成上传。")
            if item.get("sha256", "").lower() != blob.sha256 or int(item.get("byte_size", -1)) != blob.byte_size:
                raise ValidationError(f"媒体 {asset_id} 的 manifest 与 Blob 声明不一致。")
            supplied_positions.add(item.get("view_position"))
        expected = {
            CaptureSet.Kind.SINGLE: {MediaAsset.ViewPosition.SINGLE},
            CaptureSet.Kind.LEFT_CENTER_RIGHT: {MediaAsset.ViewPosition.LEFT, MediaAsset.ViewPosition.CENTER, MediaAsset.ViewPosition.RIGHT},
            CaptureSet.Kind.VIDEO: {MediaAsset.ViewPosition.VIDEO},
        }[kind]
        if supplied_positions != expected or len(media) != len(expected):
            raise ValidationError("媒体视图与采集组类型不匹配。")
        duplicate_hashes = [str(item["sha256"]).lower() for item in media]
        if len(set(duplicate_hashes)) != len(duplicate_hashes):
            raise ValidationError("同一采集组不能包含重复图片。")
        existing = MediaAsset.objects.filter(
            organization=package.session.organization,
            sha256__in=duplicate_hashes,
        ).exclude(state=MediaAsset.State.DELETED)
        if existing.exists():
            raise ValidationError({"duplicate_media_ids": [str(value) for value in existing.values_list("id", flat=True)]})

    @staticmethod
    def _find_near_duplicates(package, manifest):
        """Near duplicates are review signals only; exact SHA-256 matches are blocked above."""
        hashes = [str(item.get("perceptual_hash", "")).lower() for item in manifest.get("media", [])]
        hashes = [value for value in hashes if len(value) == 16 and all(char in "0123456789abcdef" for char in value)]
        if not hashes:
            return []
        existing = MediaAsset.objects.filter(organization=package.session.organization).exclude(
            Q(perceptual_hash="") | Q(state=MediaAsset.State.DELETED)
        ).values_list("id", "perceptual_hash")
        flags = []
        for candidate in hashes:
            candidate_number = int(candidate, 16)
            for media_id, known in existing:
                if len(known) == 16 and (candidate_number ^ int(known, 16)).bit_count() <= 8:
                    flags.append({"code": "near_duplicate", "media_id": str(media_id)})
        return flags


class UploadCommitView(APIView):
    def post(self, request, package_id):
        with transaction.atomic():
            package = UploadPackage.objects.select_for_update().select_related("session__pen__building__organization").get(pk=package_id)
            assert_org_access(request.user, package.session.organization.id)
            if package.status == UploadPackage.Status.COMMITTED:
                jobs = InferenceJob.objects.filter(session=package.session, capture_set__client_capture_id=package.manifest["capture_set"]["client_capture_id"])
                return Response({"package_id": str(package.id), "status": package.status, "job_ids": [str(job.id) for job in jobs]})
            if package.status != UploadPackage.Status.READY_TO_COMMIT:
                raise ValidationError("Manifest 尚未校验完成。")
            UploadManifestView._validate_manifest(package, package.manifest)
            capture_spec = package.manifest["capture_set"]
            capture_set = CaptureSet.objects.create(
                session=package.session,
                client_capture_id=capture_spec["client_capture_id"],
                kind=capture_spec["kind"],
                requires_manual_review=capture_spec["kind"] in {CaptureSet.Kind.LEFT_CENTER_RIGHT, CaptureSet.Kind.VIDEO},
                quality_flags=package.manifest.get("_server_quality_flags", []),
            )
            blobs = {str(blob.asset_id): blob for blob in package.blobs.all()}
            for item in package.manifest["media"]:
                blob = blobs[str(item["asset_id"])]
                MediaAsset.objects.create(
                    organization=package.session.organization,
                    capture_set=capture_set,
                    view_position=item["view_position"],
                    original_name=item.get("original_name", blob.relative_path),
                    content_type=blob.content_type,
                    byte_size=blob.byte_size,
                    sha256=blob.sha256,
                    perceptual_hash=item.get("perceptual_hash", ""),
                    storage_key=f"uploads/{package.id}/blobs/{blob.asset_id}",
                    roi=item.get("roi", {}),
                    exif=item.get("exif", {}),
                )
            job = InferenceJob.objects.create(
                session=package.session,
                capture_set=capture_set,
                provider_key=settings.COUNTING_PROVIDER,
            )
            package.status = UploadPackage.Status.COMMITTED
            package.committed_at = timezone.now()
            package.save(update_fields=["status", "committed_at", "updated_at"])
            package.session.status = InventorySession.Status.PROCESSING
            package.session.save(update_fields=["status", "updated_at"])
            AuditEvent.objects.create(
                organization=package.session.organization,
                actor=request.user,
                action=AuditEvent.Action.PACKAGE_COMMITTED,
                target_type="UploadPackage",
                target_id=str(package.id),
                payload={"capture_set_id": str(capture_set.id), "job_id": str(job.id)},
            )
            transaction.on_commit(lambda: run_counting_job.delay(str(job.id)))
        return Response({"package_id": str(package.id), "status": package.status, "job_id": str(job.id)}, status=status.HTTP_201_CREATED)


class MediaAssetViewSet(mixins.ListModelMixin, mixins.DestroyModelMixin, viewsets.GenericViewSet):
    serializer_class = MediaAssetSerializer

    def get_queryset(self):
        return MediaAsset.objects.filter(organization_id__in=visible_organization_ids(self.request.user)).select_related("capture_set__session")

    def destroy(self, request, *args, **kwargs):
        media = self.get_object()
        if media.state == MediaAsset.State.LOCKED:
            return Response({"detail": "已用于盘点的媒体已锁定；请由管理员执行带原因的覆盖操作。"}, status=status.HTTP_409_CONFLICT)
        media.state = MediaAsset.State.DELETED
        media.deleted_at = timezone.now()
        media.save(update_fields=["state", "deleted_at", "updated_at"])
        AuditEvent.objects.create(
            organization=media.organization,
            actor=request.user,
            action=AuditEvent.Action.MEDIA_DELETED,
            target_type="MediaAsset",
            target_id=str(media.id),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"])
    def override_delete(self, request, pk=None):
        media = self.get_object()
        assert_org_admin(request.user, media.organization_id)
        reason = str(request.data.get("reason", "")).strip()
        if not reason:
            raise ValidationError("管理员覆盖删除必须填写原因。")
        media.state = MediaAsset.State.DELETED
        media.deleted_at = timezone.now()
        media.save(update_fields=["state", "deleted_at", "updated_at"])
        AuditEvent.objects.create(
            organization=media.organization,
            actor=request.user,
            action=AuditEvent.Action.MEDIA_OVERRIDE,
            target_type="MediaAsset",
            target_id=str(media.id),
            reason=reason,
        )
        return Response({"id": str(media.id), "state": media.state})


class DailyReportView(APIView):
    def get(self, request):
        organization_id = request.query_params.get("organization_id")
        if not organization_id:
            raise ValidationError("organization_id 为必填项。")
        assert_org_access(request.user, organization_id)
        sessions = InventorySession.objects.filter(
            pen__building__organization_id=organization_id,
            status=InventorySession.Status.CONFIRMED,
        ).select_related("pen")
        rows = [{
            "session_id": str(session.id), "pen_id": session.pen_id, "pen_code": session.pen.code,
            "business_date": session.business_date, "count": session.manual_count,
        } for session in sessions]
        return Response({"rows": rows})


class CampaignReportView(APIView):
    def get(self, request, campaign_id):
        campaign = InventoryCampaign.objects.get(pk=campaign_id)
        assert_org_access(request.user, campaign.organization_id)
        values = {}
        for session in campaign.sessions.filter(status=InventorySession.Status.CONFIRMED).select_related("pen"):
            values.setdefault(session.pen_id, {"pen_code": session.pen.code, "counts": []})["counts"].append(session.manual_count)
        rows = [{
            "pen_id": pen_id, "pen_code": data["pen_code"], "days": len(data["counts"]),
            "mean": sum(data["counts"]) / len(data["counts"]),
            "rounded_count": round(sum(data["counts"]) / len(data["counts"])),
        } for pen_id, data in values.items()]
        return Response({"campaign_id": campaign_id, "aggregation_method": campaign.aggregation_method, "rows": rows})


class MockErpSyncView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request):
        organization_id = request.data.get("organization_id")
        try:
            organization = FarmOrganization.objects.get(pk=organization_id)
        except FarmOrganization.DoesNotExist:
            raise ValidationError("organization_id 必须指向现有组织。")
        AuditEvent.objects.create(
            organization=organization,
            actor=request.user,
            action=AuditEvent.Action.ERP_SYNC,
            target_type="ErpOrganizationProvider",
            target_id="mock",
            reason="Kingdee API contract has not been configured; mock sync completed.",
        )
        return Response({"provider": "mock", "synced": 0, "detail": "等待金蝶接口字段与凭据。"})
