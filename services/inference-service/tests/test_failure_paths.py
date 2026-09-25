import json
from uuid import uuid4

import httpx
import pytest

from app.callback import PermanentCallbackError, TransientCallbackError, deliver_result
from app.main import enqueue_job
from app.schemas import CountingJobRequest, CountingJobResult
from app.tasks import classify_provider_failure, run_counting_job


def counting_payload() -> dict[str, object]:
    return {
        "job_id": str(uuid4()),
        "correlation_id": "provider-failure-test",
        "organization_id": str(uuid4()),
        "capture_set_id": str(uuid4()),
        "capture_kind": "single",
        "media": [
            {
                "asset_id": str(uuid4()),
                "view_position": "single",
                "object_uri": "s3://pig-inventory/test.jpg",
                "sha256": "a" * 64,
                "roi": None,
            }
        ],
        "requested_model": {
            "model_key": "pig-yolov13-research",
            "version": "v3-aligned-baseline-182e",
            "checksum": "sha256:" + "b" * 64,
            "adapter_version": "http-v1",
        },
    }


def failed_result() -> CountingJobResult:
    return CountingJobResult(
        status="failed",
        count=None,
        warnings=["Provider failed"],
        model_key="pig-yolov13-research",
        model_version="v3-aligned-baseline-182e",
        model_checksum="sha256:" + "b" * 64,
        adapter_version="http-v1",
        inference_source="provider-error",
        latency_ms=0,
        failure_code="PROVIDER_ERROR",
        failure_message="timeout",
    )


def test_video_evidence_bypasses_image_provider_and_keeps_count_unknown(monkeypatch):
    payload = counting_payload()
    payload["capture_kind"] = "video"
    payload["media"][0]["view_position"] = "video"
    payload["media"][0]["object_uri"] = "s3://pig-inventory/synthetic.mp4"
    delivered = []
    def forbidden_provider():
        raise AssertionError("Video must never be sent to the image counting provider")
    monkeypatch.setattr("app.tasks.get_provider", forbidden_provider)
    monkeypatch.setattr("app.tasks.deliver_result", lambda job_id, result: delivered.append(result))
    output = run_counting_job.run(payload)
    assert output["status"] == "review_required"
    assert output["count"] is None
    assert output["detections"] == []
    assert output["inference_source"] == "manual-video-evidence"
    assert len(delivered) == 1


def test_worker_converts_provider_timeout_to_auditable_terminal_failure(monkeypatch) -> None:
    delivered: dict[str, object] = {}

    class TimeoutProvider:
        def count(self, request):
            raise httpx.ReadTimeout("runner timed out")

    def capture_delivery(job_id, result) -> None:
        delivered["job_id"] = job_id
        delivered["result"] = result

    monkeypatch.setattr("app.tasks.get_provider", lambda: TimeoutProvider())
    monkeypatch.setattr("app.tasks.deliver_result", capture_delivery)

    payload = counting_payload()
    output = run_counting_job.run(payload)

    assert output["status"] == "failed"
    assert output["count"] is None
    assert output["failure_code"] == "PROVIDER_TIMEOUT"
    assert output["failure_message"] == "Counting provider timed out before returning a result"
    assert delivered["result"].status == "failed"
    assert str(delivered["job_id"]) == payload["job_id"]


def test_administrative_retry_is_a_distinct_job_with_the_same_evidence_and_model(monkeypatch) -> None:
    queued: list[tuple[dict[str, object], str]] = []

    class Task:
        def __init__(self, task_id: str) -> None:
            self.id = task_id

    def fake_apply_async(*, args, task_id):
        queued.append((args[0], task_id))
        return Task(task_id)

    monkeypatch.setattr("app.main.run_counting_job.apply_async", fake_apply_async)
    original_payload = counting_payload()
    retry_payload = {**original_payload, "job_id": str(uuid4()), "correlation_id": "admin-retry"}

    original = enqueue_job(CountingJobRequest.model_validate(original_payload))
    retry = enqueue_job(CountingJobRequest.model_validate(retry_payload))

    assert original.job_id != retry.job_id
    assert [task_id for _, task_id in queued] == [original.job_id, retry.job_id]
    assert queued[0][0]["capture_set_id"] == queued[1][0]["capture_set_id"]
    assert queued[0][0]["media"] == queued[1][0]["media"]
    assert queued[0][0]["requested_model"] == queued[1][0]["requested_model"]


@pytest.mark.parametrize("status_code", [429, 500, 503])
def test_callback_treats_retryable_http_status_as_transient(monkeypatch, status_code: int) -> None:
    class Response:
        text = "temporary callback failure"

        def __init__(self) -> None:
            self.status_code = status_code

    monkeypatch.setenv("INFERENCE_CALLBACK_TOKEN", "test-callback-token")
    monkeypatch.setattr("app.callback.httpx.put", lambda *args, **kwargs: Response())

    with pytest.raises(TransientCallbackError, match=str(status_code)):
        deliver_result(uuid4(), failed_result())


def test_callback_treats_network_error_as_transient(monkeypatch) -> None:
    def raise_timeout(*args, **kwargs):
        request = httpx.Request("PUT", "http://business-api/result")
        raise httpx.ReadTimeout("callback timed out", request=request)

    monkeypatch.setenv("INFERENCE_CALLBACK_TOKEN", "test-callback-token")
    monkeypatch.setattr("app.callback.httpx.put", raise_timeout)

    with pytest.raises(TransientCallbackError, match="callback timed out"):
        deliver_result(uuid4(), failed_result())


@pytest.mark.parametrize("status_code", [401, 403, 422])
def test_callback_treats_client_rejection_as_permanent(monkeypatch, status_code: int) -> None:
    class Response:
        text = "invalid callback payload"

        def __init__(self) -> None:
            self.status_code = status_code

    monkeypatch.setenv("INFERENCE_CALLBACK_TOKEN", "test-callback-token")
    monkeypatch.setattr("app.callback.httpx.put", lambda *args, **kwargs: Response())

    with pytest.raises(PermanentCallbackError, match=str(status_code)):
        deliver_result(uuid4(), failed_result())


@pytest.mark.parametrize("status_code", [200, 204])
def test_callback_sends_service_key_and_stable_job_id_without_user_jwt(monkeypatch, status_code: int) -> None:
    job_id = uuid4()
    observed = []
    monkeypatch.setenv("INFERENCE_CALLBACK_TOKEN", "synthetic-callback-service-only")
    monkeypatch.setenv("BUSINESS_API_BASE_URL", "http://business-api:8080")

    def send(url, *, headers, json, timeout):
        observed.append((url, headers, json))
        return httpx.Response(status_code)

    monkeypatch.setattr("app.callback.httpx.put", send)
    deliver_result(job_id, failed_result())
    deliver_result(job_id, failed_result())
    assert len(observed) == 2
    for url, headers, payload in observed:
        assert url == f"http://business-api:8080/api/v1/inference-jobs/{job_id}/result"
        assert headers == {
            "X-Idempotency-Key": str(job_id),
            "X-Inference-Service-Key": "synthetic-callback-service-only",
        }
        assert payload["count"] is None


def test_provider_failure_classification_is_structured_and_sanitized() -> None:
    request = httpx.Request("POST", "http://runner.internal/v1/count?token=secret")
    response = httpx.Response(503, request=request)

    assert classify_provider_failure(httpx.ConnectError("secret host failed", request=request)) == (
        "PROVIDER_UNAVAILABLE",
        "Counting provider could not be reached",
    )
    assert classify_provider_failure(httpx.HTTPStatusError("secret body", request=request, response=response)) == (
        "PROVIDER_HTTP_STATUS",
        "Counting provider returned HTTP 503",
    )
    assert classify_provider_failure(ValueError("secret contract detail")) == (
        "PROVIDER_CONTRACT_ERROR",
        "Counting provider response failed product safety validation",
    )


# --- 空令牌 fail-closed 与死信兜底（回调投递不再炸穿 Celery 任务） -----------------


def test_空令牌拒发(monkeypatch) -> None:
    """空 INFERENCE_CALLBACK_TOKEN 必须 fail-closed 拒发：省略头照发只会换来业务侧 401。"""

    monkeypatch.delenv("INFERENCE_CALLBACK_TOKEN", raising=False)
    sent: list[object] = []
    monkeypatch.setattr("app.callback.httpx.put", lambda *args, **kwargs: sent.append(kwargs))

    with pytest.raises(PermanentCallbackError, match="INFERENCE_CALLBACK_TOKEN"):
        deliver_result(uuid4(), failed_result())

    assert sent == []


def test_permanent_error落死信且任务不抛(monkeypatch, tmp_path) -> None:
    """永久投递失败不再炸穿任务：终态结果（含 provider failed）写入死信目录。"""

    class TimeoutProvider:
        def count(self, request):
            raise httpx.ReadTimeout("runner timed out")

    def raise_permanent(job_id, result) -> None:
        raise PermanentCallbackError("callback returned 401: invalid service key")

    monkeypatch.setenv("DEAD_LETTER_DIR", str(tmp_path))
    monkeypatch.setattr("app.tasks.get_provider", lambda: TimeoutProvider())
    monkeypatch.setattr("app.tasks.deliver_result", raise_permanent)

    payload = counting_payload()
    output = run_counting_job.run(payload)

    assert output["status"] == "failed"
    assert output["failure_code"] == "PROVIDER_TIMEOUT"
    dead_letters = list(tmp_path.glob("*.json"))
    assert len(dead_letters) == 1
    record = json.loads(dead_letters[0].read_text(encoding="utf-8"))
    assert record["job_id"] == payload["job_id"]
    assert "callback returned 401" in record["failure_reason"]
    assert record["result"]["status"] == "failed"
    assert record["result"]["failure_code"] == "PROVIDER_TIMEOUT"
    assert record["result"]["failure_message"] == "Counting provider timed out before returning a result"


def test_异常兜底落死信(monkeypatch, tmp_path) -> None:
    """投递路径的意外异常同样落死信并打日志，避免静默炸穿 worker。"""

    def explode(job_id, result) -> None:
        raise RuntimeError("unexpected delivery bug")

    monkeypatch.setenv("DEAD_LETTER_DIR", str(tmp_path))
    monkeypatch.delenv("COUNTING_PROVIDER", raising=False)
    monkeypatch.delenv("MODEL_APPROVED", raising=False)
    monkeypatch.delenv("MODEL_RESEARCH_ENABLED", raising=False)
    monkeypatch.setattr("app.tasks.deliver_result", explode)

    payload = counting_payload()
    output = run_counting_job.run(payload)

    assert output["status"] == "review_required"
    dead_letters = list(tmp_path.glob("*.json"))
    assert len(dead_letters) == 1
    record = json.loads(dead_letters[0].read_text(encoding="utf-8"))
    assert record["job_id"] == payload["job_id"]
    assert "unexpected delivery bug" in record["failure_reason"]
    assert record["result"]["status"] == "review_required"
    assert record["result"]["count"] is None
