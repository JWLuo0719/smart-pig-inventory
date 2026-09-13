import httpx
from pydantic import ValidationError

from .celery_app import celery_app
from .callback import TransientCallbackError, deliver_result
from .providers import get_provider
from .schemas import CountingJobRequest, CountingJobResult


@celery_app.task(name="inference.count", bind=True, max_retries=3)
def run_counting_job(self, payload: dict) -> dict:
    request = CountingJobRequest.model_validate(payload)
    try:
        if request.capture_kind == "video":
            model = request.requested_model
            result = CountingJobResult(
                status="review_required", count=None,
                warnings=["Video evidence requires manual review; automated video counting is not enabled"],
                model_key=model.model_key, model_version=model.version,
                model_checksum=model.checksum, adapter_version=model.adapter_version,
                inference_source="manual-video-evidence", latency_ms=0,
            )
        else:
            result = get_provider().count(request)
    except Exception as exception:  # The business service still needs an auditable terminal result.
        model = request.requested_model
        failure_code, failure_message = classify_provider_failure(exception)
        result = CountingJobResult(
            status="failed",
            count=None,
            warnings=["The counting provider failed before returning a result"],
            model_key=model.model_key,
            model_version=model.version,
            model_checksum=model.checksum,
            adapter_version=model.adapter_version,
            inference_source="provider-error",
            latency_ms=0,
            failure_code=failure_code,
            failure_message=failure_message,
        )
    try:
        deliver_result(request.job_id, result)
    except TransientCallbackError as exception:
        raise self.retry(exc=exception, countdown=min(60, 2 ** (self.request.retries + 1))) from exception
    return result.model_dump(mode="json")


def classify_provider_failure(exception: Exception) -> tuple[str, str]:
    if isinstance(exception, httpx.TimeoutException):
        return "PROVIDER_TIMEOUT", "Counting provider timed out before returning a result"
    if isinstance(exception, httpx.NetworkError):
        return "PROVIDER_UNAVAILABLE", "Counting provider could not be reached"
    if isinstance(exception, httpx.HTTPStatusError):
        return "PROVIDER_HTTP_STATUS", f"Counting provider returned HTTP {exception.response.status_code}"
    if isinstance(exception, ValidationError):
        return "PROVIDER_INVALID_RESULT", "Counting provider returned a result that violates the contract"
    if isinstance(exception, (ValueError, TypeError)):
        return "PROVIDER_CONTRACT_ERROR", "Counting provider response failed product safety validation"
    return "PROVIDER_ERROR", "Counting provider failed before returning a result"

