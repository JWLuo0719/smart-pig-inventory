import json
from pathlib import Path
from uuid import uuid4

from app.celery_app import celery_app
from app.providers import UnavailableCountingProvider
from app.schemas import CountingJobRequest, MediaReference, ModelIdentity


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
    assert set(result.model_dump(mode="json")) == set(result_schema["required"])


def test_worker_registers_counting_task() -> None:
    celery_app.loader.import_default_modules()
    assert "inference.count" in celery_app.tasks
