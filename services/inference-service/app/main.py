from fastapi import FastAPI, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .providers import get_provider
from .schemas import CountingJobRequest
from .tasks import run_counting_job


app = FastAPI(title="Pig Inventory Inference Contract", version="0.1.0")


class JobAccepted(BaseModel):
    job_id: str
    task_id: str
    status: str = "queued"


@app.get("/health/live")
def live() -> dict[str, bool]:
    return {"alive": True}


@app.get("/health/ready")
def ready() -> JSONResponse:
    readiness = get_provider().readiness()
    response_status = status.HTTP_200_OK if readiness["ready"] else status.HTTP_503_SERVICE_UNAVAILABLE
    return JSONResponse(content=readiness, status_code=response_status)


@app.post("/v1/jobs", response_model=JobAccepted, status_code=status.HTTP_202_ACCEPTED)
def enqueue_job(request: CountingJobRequest) -> JobAccepted:
    # Re-delivery is safe: the Spring callback uses job ID + payload fingerprint
    # as its idempotency boundary.
    task = run_counting_job.apply_async(args=[request.model_dump(mode="json")], task_id=str(request.job_id))
    return JobAccepted(job_id=str(request.job_id), task_id=task.id)

