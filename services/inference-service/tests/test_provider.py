import json
from pathlib import Path
from uuid import uuid4

from app.celery_app import celery_app
from app.callback import deliver_result
from app.providers import ResearchHttpYoloCountingProvider, UnavailableCountingProvider, get_provider
from app.schemas import CountingJobRequest, CountingJobResult, MediaReference, ModelIdentity


def test_unavailable_provider_never_fakes_a_count() -> None:
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="test-correlation",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[
            MediaReference(
                asset_id=uuid4(),
                view_position="single",
                object_uri="s3://pig-inventory/org/session/photo.jpg",
                sha256="0" * 64,
            )
        ],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="unverified",
            checksum="0" * 64,
            adapter_version="1",
        ),
    )

    result = UnavailableCountingProvider().count(request)

    assert result.status == "review_required"
    assert result.count is None
    assert result.detections == []


def test_request_serialization_matches_versioned_contract() -> None:
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="contract-check",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[
            MediaReference(
                asset_id=uuid4(),
                view_position="single",
                object_uri="s3://pig-inventory/photo.jpg",
                sha256="a" * 64,
            )
        ],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="0.0.0",
            checksum="b" * 64,
            adapter_version="1",
        ),
    )
    schema_path = Path(__file__).parents[3] / "contracts" / "inference-job.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))

    assert set(request.model_dump(mode="json")) == set(schema["required"])
    assert set(request.media[0].model_dump(mode="json")) == set(
        schema["properties"]["media"]["items"]["required"]
    ) | {"roi"}

    result = UnavailableCountingProvider().count(request)
    result_schema_path = Path(__file__).parents[3] / "contracts" / "inference-result.schema.json"
    result_schema = json.loads(result_schema_path.read_text(encoding="utf-8"))
    serialized_result = result.model_dump(mode="json")
    assert set(result_schema["required"]).issubset(serialized_result)
    assert set(serialized_result).issubset(result_schema["properties"])


def test_worker_registers_counting_task() -> None:
    celery_app.loader.import_default_modules()
    assert "inference.count" in celery_app.tasks


def test_research_provider_forces_manual_review(monkeypatch) -> None:
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="research-provider",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[MediaReference(asset_id=uuid4(), view_position="single", object_uri="s3://pig-inventory/photo.jpg", sha256="c" * 64)],
        requested_model=ModelIdentity(model_key="yolov13n-research", version="test", checksum="d" * 64, adapter_version="http-v1"),
    )

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return {
                "status": "succeeded",
                "count": 3,
                "detections": [],
                "warnings": [],
                "model_key": "yolov13n-research",
                "model_version": "test",
                "model_checksum": "d" * 64,
                "adapter_version": "http-v1",
                "inference_source": "runner",
                "latency_ms": 8,
            }

    monkeypatch.setattr("app.providers.httpx.post", lambda *args, **kwargs: Response())
    result = ResearchHttpYoloCountingProvider("http://runner/v1/count").count(request)

    assert result.status == "review_required"
    assert result.count is None
    assert result.inference_source == "research-http-yolo"
    assert result.warnings[0].startswith("Research model output")


def test_research_provider_requires_explicit_experiment_flag(monkeypatch) -> None:
    monkeypatch.setenv("COUNTING_PROVIDER", "research-http-yolo")
    monkeypatch.setenv("YOLO_HTTP_ENDPOINT", "http://runner/v1/count")
    monkeypatch.delenv("MODEL_RESEARCH_ENABLED", raising=False)

    assert isinstance(get_provider(), UnavailableCountingProvider)


def test_callback_uses_job_id_as_idempotency_key_and_contract_casing(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class Response:
        status_code = 204
        text = ""

    def fake_put(url: str, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return Response()

    monkeypatch.setattr("app.callback.httpx.put", fake_put)
    job_id = uuid4()
    result = CountingJobResult(
        status="review_required",
        count=None,
        warnings=["No validated provider"],
        model_key="pending-license-review",
        model_version="unverified",
        model_checksum="unverified",
        adapter_version="http-v1",
        inference_source="unavailable",
        latency_ms=0,
    )

    deliver_result(job_id, result)

    assert captured["url"].endswith(f"/api/v1/inference-jobs/{job_id}/result")
    assert captured["headers"] == {"X-Idempotency-Key": str(job_id)}
    payload = captured["json"]
    assert payload["modelKey"] == "pending-license-review"
    assert payload["latencyMs"] == 0
    assert "model_key" not in payload
