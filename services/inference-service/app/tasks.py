from .celery_app import celery_app
from .callback import TransientCallbackError, deliver_result
from .providers import get_provider
from .schemas import CountingJobRequest, CountingJobResult


@celery_app.task(name="inference.count", bind=True, max_retries=3)
def run_counting_job(self, payload: dict) -> dict:
    request = CountingJobRequest.model_validate(payload)
    try:
        result = get_provider().count(request)
    except Exception as exception:  # The business service still needs an auditable terminal result.
        model = request.requested_model
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
            failure_code="PROVIDER_ERROR",
            failure_message=str(exception)[:1000],
        )
    try:
        deliver_result(request.job_id, result)
    except TransientCallbackError as exception:
        raise self.retry(exc=exception, countdown=min(60, 2 ** (self.request.retries + 1))) from exception
    return result.model_dump(mode="json")

