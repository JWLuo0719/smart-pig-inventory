from pathlib import Path
from time import perf_counter
from tempfile import TemporaryDirectory

from celery import shared_task
from django.conf import settings
from django.db import transaction

from .models import CountResult, InferenceJob, InventorySession, MediaAsset
from .services.blob_storage import blob_store
from .services.inference import ProviderUnavailable, get_counting_provider, is_detection_inside_roi


@shared_task(bind=True, autoretry_for=(ConnectionError,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def run_counting_job(self, job_id: str):
    """Run one capture set through the configured, versioned counting provider."""
    with transaction.atomic():
        job = InferenceJob.objects.select_for_update().select_related("session", "capture_set").get(pk=job_id)
        if job.status in {InferenceJob.Status.SUCCEEDED, InferenceJob.Status.REVIEW_REQUIRED}:
            return job.status
        job.status = InferenceJob.Status.RUNNING
        job.save(update_fields=["status", "updated_at"])

    media = list(job.capture_set.media_assets.filter(state=MediaAsset.State.ACTIVE).order_by("view_position"))
    provider = get_counting_provider()
    started = perf_counter()
    try:
        with TemporaryDirectory(prefix="pig-inventory-") as directory:
            files = [blob_store.materialize(asset.storage_key, Path(directory) / str(asset.id)) for asset in media]
            result = provider.count(files)
    except ProviderUnavailable as exc:
        with transaction.atomic():
            job = InferenceJob.objects.select_for_update().get(pk=job_id)
            job.status = InferenceJob.Status.REVIEW_REQUIRED
            job.provider_key = provider.key
            job.error_code = "provider_unavailable"
            job.error_detail = str(exc)
            job.latency_ms = round((perf_counter() - started) * 1000)
            job.save()
            InventorySession.objects.filter(pk=job.session_id).update(status=InventorySession.Status.REVIEW_REQUIRED)
        return "review_required"
    except Exception as exc:  # provider failures are preserved for safe retry/review
        with transaction.atomic():
            job = InferenceJob.objects.select_for_update().get(pk=job_id)
            job.status = InferenceJob.Status.FAILED
            job.provider_key = provider.key
            job.error_code = "provider_error"
            job.error_detail = str(exc)
            job.latency_ms = round((perf_counter() - started) * 1000)
            job.save()
            InventorySession.objects.filter(pk=job.session_id).update(status=InventorySession.Status.FAILED)
        raise

    # HTTP model responses are post-filtered against the photo's valid pen ROI.
    # Multi-view/video providers must implement their own validated geometry logic.
    if len(media) == 1 and result.detections and media[0].roi:
        detections = [detection for detection in result.detections if is_detection_inside_roi(detection, media[0].roi)]
        if len(detections) != len(result.detections):
            result = result.__class__(
                raw_count=len(detections), detections=detections,
                quality_flags=[*result.quality_flags, "roi_filtered"],
                model_key=result.model_key, model_version=result.model_version,
                model_checksum=result.model_checksum, latency_ms=result.latency_ms,
            )

    with transaction.atomic():
        job = InferenceJob.objects.select_for_update().get(pk=job_id)
        job.status = InferenceJob.Status.SUCCEEDED
        job.provider_key = provider.key
        job.model_key = result.model_key
        job.model_version = result.model_version
        job.model_checksum = result.model_checksum
        job.latency_ms = result.latency_ms or round((perf_counter() - started) * 1000)
        job.save()
        CountResult.objects.update_or_create(
            job=job,
            defaults={
                "raw_count": result.raw_count,
                "detections": [d.__dict__ for d in result.detections],
                "quality_flags": result.quality_flags,
                "is_final": False,
            },
        )
        MediaAsset.objects.filter(capture_set=job.capture_set, state=MediaAsset.State.ACTIVE).update(state=MediaAsset.State.LOCKED)
        InventorySession.objects.filter(pk=job.session_id).update(status=InventorySession.Status.REVIEW_REQUIRED)
    return "succeeded"
