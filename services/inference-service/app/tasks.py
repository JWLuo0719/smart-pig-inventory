from .celery_app import celery_app
from .providers import get_provider
from .schemas import CountingJobRequest


@celery_app.task(name="inference.count", bind=True, max_retries=3)
def run_counting_job(self, payload: dict) -> dict:
    request = CountingJobRequest.model_validate(payload)
    result = get_provider().count(request)
    return result.model_dump(mode="json")

