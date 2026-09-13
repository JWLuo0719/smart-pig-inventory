import json
from pathlib import Path
from uuid import uuid4

import httpx
import pytest

from app.celery_app import celery_app
from app.callback import deliver_result
from app.providers import HttpYoloCountingProvider, ResearchHttpYoloCountingProvider, UnavailableCountingProvider, get_provider
from app.schemas import CountingJobRequest, CountingJobResult, Detection, MediaReference, ModelIdentity


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


def test_approved_provider_recalculates_count_from_roi_filtered_detections(monkeypatch) -> None:
    asset_id = uuid4()
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="approved-provider-roi",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[MediaReference(
            asset_id=asset_id,
            view_position="single",
            object_uri="s3://pig-inventory/photo.jpg",
            sha256="e" * 64,
            roi={"x": 0.2, "y": 0.2, "width": 0.4, "height": 0.4},
        )],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="v3-aligned",
            checksum="f" * 64,
            adapter_version="http-v1",
        ),
    )

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return CountingJobResult(
                status="succeeded",
                count=2,
                detections=[
                    Detection(asset_id=asset_id, bbox=(0.25, 0.25, 0.35, 0.35), confidence=0.9, class_id=0),
                    Detection(asset_id=asset_id, bbox=(0.7, 0.7, 0.9, 0.9), confidence=0.8, class_id=0),
                ],
                model_key="pig-yolov13",
                model_version="v3-aligned",
                model_checksum="f" * 64,
                adapter_version="http-v1",
                inference_source="runner",
                latency_ms=10,
            ).model_dump(mode="json")

    monkeypatch.setattr("app.providers.httpx.post", lambda *args, **kwargs: Response())

    result = HttpYoloCountingProvider("http://runner/v1/count").count(request)

    assert result.status == "succeeded"
    assert result.count == 1
    assert len(result.detections) == 1
    assert result.detections[0].bbox == (0.25, 0.25, 0.35, 0.35)
    assert "recalculated" in result.warnings[-1]


def test_provider_rejects_a_runner_model_identity_mismatch(monkeypatch) -> None:
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="identity-mismatch",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[MediaReference(
            asset_id=uuid4(),
            view_position="single",
            object_uri="s3://pig-inventory/photo.jpg",
            sha256="1" * 64,
        )],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="v3-aligned",
            checksum="2" * 64,
            adapter_version="http-v1",
        ),
    )

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return {
                "status": "succeeded",
                "count": 0,
                "detections": [],
                "warnings": [],
                "model_key": "pig-yolov13",
                "model_version": "v3-aligned",
                "model_checksum": "wrong-checksum",
                "adapter_version": "http-v1",
                "inference_source": "runner",
                "latency_ms": 1,
            }

    monkeypatch.setattr("app.providers.httpx.post", lambda *args, **kwargs: Response())

    with pytest.raises(ValueError, match="model identity"):
        HttpYoloCountingProvider("http://runner/v1/count").count(request)


def test_provider_uses_configured_positive_http_timeouts(monkeypatch) -> None:
    asset_id = uuid4()
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="configured-timeout",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[MediaReference(
            asset_id=asset_id,
            view_position="single",
            object_uri="s3://pig-inventory/photo.jpg",
            sha256="5" * 64,
        )],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="v3-aligned",
            checksum="6" * 64,
            adapter_version="http-v1",
        ),
    )
    captured: dict[str, object] = {}

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return CountingJobResult(
                status="succeeded",
                count=0,
                detections=[],
                model_key="pig-yolov13",
                model_version="v3-aligned",
                model_checksum="6" * 64,
                adapter_version="http-v1",
                inference_source="runner",
                latency_ms=1,
            ).model_dump(mode="json")

    def fake_post(*args, **kwargs):
        captured["timeout"] = kwargs["timeout"]
        return Response()

    monkeypatch.setenv("YOLO_HTTP_TIMEOUT_SECONDS", "12.5")
    monkeypatch.setenv("YOLO_HTTP_CONNECT_TIMEOUT_SECONDS", "3")
    monkeypatch.setattr("app.providers.httpx.post", fake_post)

    HttpYoloCountingProvider("http://runner/v1/count").count(request)

    assert captured["timeout"].read == 12.5
    assert captured["timeout"].connect == 3.0


def test_provider_rejects_non_positive_http_timeout(monkeypatch) -> None:
    monkeypatch.setenv("YOLO_HTTP_TIMEOUT_SECONDS", "0")

    with pytest.raises(ValueError, match="positive number"):
        HttpYoloCountingProvider("http://runner/v1/count")


def test_http_provider_readiness_requires_matching_loaded_model(monkeypatch) -> None:
    expected_identity = ("pig-yolov13", "v3", "sha256:" + "a" * 64, "http-v1")

    class Response:
        status_code = 200

        def json(self) -> dict[str, object]:
            return {
                "ready": True,
                "model_key": "pig-yolov13",
                "model_version": "v3",
                "model_checksum": "sha256:" + "a" * 64,
                "adapter_version": "http-v1",
            }

    captured: dict[str, object] = {}

    def fake_get(url: str, **kwargs):
        captured["url"] = url
        captured["timeout"] = kwargs["timeout"]
        return Response()

    monkeypatch.setattr("app.providers.httpx.get", fake_get)
    provider = HttpYoloCountingProvider("http://runner:9000/v1/count", expected_identity=expected_identity)

    readiness = provider.readiness()

    assert readiness["ready"] is True
    assert readiness["counting_available"] is True
    assert captured["url"] == "http://runner:9000/health/ready"


def test_http_provider_readiness_fails_closed_for_identity_mismatch(monkeypatch) -> None:
    class Response:
        status_code = 200

        def json(self) -> dict[str, object]:
            return {
                "ready": True,
                "model_key": "wrong-model",
                "model_version": "v3",
                "model_checksum": "sha256:" + "a" * 64,
                "adapter_version": "http-v1",
            }

    monkeypatch.setattr("app.providers.httpx.get", lambda *args, **kwargs: Response())
    provider = HttpYoloCountingProvider(
        "http://runner/v1/count",
        expected_identity=("pig-yolov13", "v3", "sha256:" + "a" * 64, "http-v1"),
    )

    assert provider.readiness() == {
        "ready": False,
        "provider": "http-yolo",
        "counting_available": False,
        "reason_code": "RUNNER_IDENTITY_MISMATCH",
    }


def test_http_provider_readiness_reports_unreachable_without_leaking_endpoint(monkeypatch) -> None:
    request = httpx.Request("GET", "http://runner/health/ready")
    monkeypatch.setattr(
        "app.providers.httpx.get",
        lambda *args, **kwargs: (_ for _ in ()).throw(httpx.ConnectError("secret endpoint", request=request)),
    )

    readiness = HttpYoloCountingProvider("http://runner/v1/count").readiness()

    assert readiness["reason_code"] == "RUNNER_UNREACHABLE"
    assert "secret" not in str(readiness)


@pytest.mark.parametrize(
    ("references_requested_asset", "bbox", "expected_message"),
    [
        (False, (0.1, 0.1, 0.2, 0.2), "outside the counting request"),
        (True, (-0.1, 0.1, 0.2, 0.2), "normalized xyxy"),
    ],
)
def test_provider_rejects_unknown_assets_and_invalid_boxes(
    monkeypatch,
    references_requested_asset: bool,
    bbox: tuple[float, float, float, float],
    expected_message: str,
) -> None:
    asset_id = uuid4()
    request = CountingJobRequest(
        job_id=uuid4(),
        correlation_id="invalid-runner-detection",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="single",
        media=[MediaReference(
            asset_id=asset_id,
            view_position="single",
            object_uri="s3://pig-inventory/photo.jpg",
            sha256="3" * 64,
        )],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="v3-aligned",
            checksum="4" * 64,
            adapter_version="http-v1",
        ),
    )

    class Response:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, object]:
            return CountingJobResult(
                status="succeeded",
                count=1,
                detections=[Detection(
                    asset_id=asset_id if references_requested_asset else uuid4(),
                    bbox=bbox,
                    confidence=0.9,
                    class_id=0,
                )],
                model_key="pig-yolov13",
                model_version="v3-aligned",
                model_checksum="4" * 64,
                adapter_version="http-v1",
                inference_source="runner",
                latency_ms=1,
            ).model_dump(mode="json")

    monkeypatch.setattr("app.providers.httpx.post", lambda *args, **kwargs: Response())

    with pytest.raises(ValueError, match=expected_message):
        HttpYoloCountingProvider("http://runner/v1/count").count(request)


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
