import json
import logging
import os
from pathlib import Path
from uuid import UUID

import httpx
from pydantic import ValidationError

from .celery_app import celery_app
from .callback import PermanentCallbackError, TransientCallbackError, deliver_result
from .providers import get_provider, video_counting_enabled
from .schemas import CountingJobRequest, CountingJobResult

logger = logging.getLogger(__name__)

# 死信目录：容器内可写路径兜底；可用 DEAD_LETTER_DIR 挂载到宿主机持久卷。
DEFAULT_DEAD_LETTER_DIR = "/tmp/pig-inference-dead-letter"


@celery_app.task(name="inference.count", bind=True, max_retries=3)
def run_counting_job(self, payload: dict) -> dict:
    request = CountingJobRequest.model_validate(payload)
    try:
        if request.capture_kind == "video" and not video_counting_enabled():
            # 默认路径：视频只作为人工复核证据，不产生任何自动数量。
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
    except PermanentCallbackError as exception:
        # 永久失败不再向上抛：炸穿 Celery 任务会让终态永久丢失且没有死信可查。
        _write_dead_letter(request.job_id, result, exception)
    except Exception as exception:  # 兜底：意外异常同样落死信，避免静默炸穿 worker。
        _write_dead_letter(request.job_id, result, exception)
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


def _write_dead_letter(job_id: UUID, result: CountingJobResult, exception: Exception) -> None:
    """把无法投递的终态结果写入死信目录，供人工补偿投递。

    死信文件包含完整 result payload 与失败原因；写盘失败只记日志，不再向上抛。
    """

    reason = f"{type(exception).__name__}: {exception}"
    dead_letter_dir = Path(os.getenv("DEAD_LETTER_DIR", DEFAULT_DEAD_LETTER_DIR))
    dead_letter_path = dead_letter_dir / f"{job_id}.json"
    record = {
        "job_id": str(job_id),
        "failure_reason": reason,
        "result": result.model_dump(mode="json"),
    }
    logger.error(
        "result callback delivery failed permanently; terminal result archived to dead letter",
        extra={"job_id": str(job_id), "failure_reason": reason, "dead_letter_path": str(dead_letter_path)},
    )
    try:
        dead_letter_dir.mkdir(parents=True, exist_ok=True)
        dead_letter_path.write_text(
            json.dumps(record, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError:
        logger.exception("dead letter write failed for job %s", job_id)

