"""视频抽帧计数的聚合与门禁测试。

抽帧与跟踪在外部 Runner 完成，这里只验证产品侧不会把"没有轨迹身份的逐帧检测"
当成数量，也不会把单帧噪声算成猪。
"""

import json
from pathlib import Path
from uuid import uuid4

import pytest

from app.providers import (
    CountingProvider,
    UnavailableCountingProvider,
    VideoTrackCountingProvider,
    get_provider,
    video_counting_enabled,
)
from app.schemas import CountingJobRequest, CountingJobResult, Detection, MediaReference, ModelIdentity
from app.video import aggregate_tracks


def detection(asset_id, track_id=None, frame_index=None, bbox=(0.4, 0.4, 0.6, 0.6)) -> Detection:
    return Detection(
        asset_id=asset_id,
        bbox=bbox,
        confidence=0.9,
        class_id=0,
        track_id=track_id,
        frame_index=frame_index,
    )


def video_request() -> CountingJobRequest:
    return CountingJobRequest(
        job_id=uuid4(),
        correlation_id="video-counting",
        organization_id=uuid4(),
        capture_set_id=uuid4(),
        capture_kind="video",
        media=[
            MediaReference(
                asset_id=uuid4(),
                view_position="video",
                object_uri="s3://pig-inventory/pen.mp4",
                sha256="a" * 64,
            )
        ],
        requested_model=ModelIdentity(
            model_key="pig-yolov13",
            version="v3-aligned",
            checksum="f" * 64,
            adapter_version="http-v1",
        ),
    )


class _StubCountingProvider(CountingProvider):
    key = "stub"

    def __init__(self, result: CountingJobResult) -> None:
        self._result = result

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        return self._result

    def readiness(self) -> dict[str, object]:
        return {"ready": True, "provider": self.key, "counting_available": True}


def _runner_result(
    request: CountingJobRequest,
    detections: list[Detection],
    *,
    status: str = "succeeded",
) -> CountingJobResult:
    return CountingJobResult(
        status=status,
        count=len(detections) if status == "succeeded" else None,
        detections=detections,
        warnings=[],
        model_key=request.requested_model.model_key,
        model_version=request.requested_model.version,
        model_checksum=request.requested_model.checksum,
        adapter_version=request.requested_model.adapter_version,
        inference_source="runner",
        latency_ms=9,
    )


# --- 契约 ---------------------------------------------------------------------


def test_detection_contract_declares_track_identity_and_frame_index() -> None:
    schema_path = Path(__file__).parents[3] / "contracts" / "inference-result.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    properties = schema["properties"]["detections"]["items"]["properties"]

    assert set(properties) == {"asset_id", "bbox", "confidence", "class_id", "track_id", "frame_index"}
    assert properties["track_id"]["maxLength"] == 64
    assert properties["frame_index"]["minimum"] == 0


# --- 聚合内核 -----------------------------------------------------------------


def test_same_track_seen_in_many_frames_counts_once() -> None:
    asset_id = uuid4()
    detections = [detection(asset_id, "pig-1", index) for index in range(5)]

    outcome = aggregate_tracks(detections)

    assert outcome.count == 1
    assert len(outcome.kept) == 5


def test_distinct_tracks_count_separately() -> None:
    asset_id = uuid4()
    detections = [
        detection(asset_id, "pig-1", 0),
        detection(asset_id, "pig-1", 1),
        detection(asset_id, "pig-2", 0),
        detection(asset_id, "pig-2", 1),
        detection(asset_id, "pig-3", 1),
    ]

    outcome = aggregate_tracks(detections)

    assert outcome.count == 3


def test_detections_without_a_track_identity_never_become_a_count() -> None:
    asset_id = uuid4()
    detections = [detection(asset_id, "pig-1", 0), detection(asset_id, None, 0)]

    outcome = aggregate_tracks(detections)

    assert outcome.count is None
    assert len(outcome.kept) == 2  # 证据保留，供人工复核
    assert any("track identity" in warning for warning in outcome.warnings)


def test_an_empty_video_result_is_not_reported_as_zero_pigs() -> None:
    outcome = aggregate_tracks([])

    assert outcome.count is None
    assert any("no detections" in warning for warning in outcome.warnings)


def test_min_observations_filters_single_frame_tracks() -> None:
    asset_id = uuid4()
    detections = [
        detection(asset_id, "pig-1", 0),
        detection(asset_id, "pig-1", 1),
        detection(asset_id, "pig-2", 1),
    ]

    outcome = aggregate_tracks(detections, min_observations=2)

    assert outcome.count == 1
    assert outcome.dropped_track_ids == ("pig-2",)
    assert any("fewer than 2 frame" in warning for warning in outcome.warnings)


def test_min_observations_must_be_positive() -> None:
    with pytest.raises(ValueError):
        aggregate_tracks([], min_observations=0)


# --- Provider -----------------------------------------------------------------


def test_video_provider_counts_distinct_tracks() -> None:
    request = video_request()
    detections = [detection(request.media[0].asset_id, "pig-1", index) for index in range(3)]
    provider = VideoTrackCountingProvider(_StubCountingProvider(_runner_result(request, detections)))

    result = provider.count(request)

    assert result.status == "succeeded"
    assert result.count == 1
    assert result.inference_source == "video-track-count"


def test_video_provider_fails_closed_when_the_runner_returns_no_tracks() -> None:
    request = video_request()
    detections = [detection(request.media[0].asset_id, None, 0)]
    provider = VideoTrackCountingProvider(_StubCountingProvider(_runner_result(request, detections)))

    result = provider.count(request)

    assert result.status == "review_required"
    assert result.count is None
    assert len(result.detections) == 1


def test_video_provider_keeps_the_research_provider_review_only() -> None:
    request = video_request()
    detections = [detection(request.media[0].asset_id, "pig-1", 0)]
    provider = VideoTrackCountingProvider(
        _StubCountingProvider(_runner_result(request, detections, status="review_required"))
    )

    result = provider.count(request)

    assert result.status == "review_required"
    assert result.count is None


def test_video_provider_delegates_non_video_requests() -> None:
    request = video_request()
    single = request.model_copy(update={"capture_kind": "single"})
    provider = VideoTrackCountingProvider(UnavailableCountingProvider())

    result = provider.count(single)

    assert result.inference_source == "unavailable"


def test_video_counting_requires_an_explicit_enablement_flag(monkeypatch) -> None:
    monkeypatch.setenv("COUNTING_PROVIDER", "video-track-count")
    monkeypatch.delenv("VIDEO_COUNTING_ENABLED", raising=False)

    assert video_counting_enabled() is False
    assert isinstance(get_provider(), UnavailableCountingProvider)


def test_video_counting_never_fabricates_a_count_without_an_approved_model(monkeypatch) -> None:
    monkeypatch.setenv("COUNTING_PROVIDER", "video-track-count")
    monkeypatch.setenv("VIDEO_COUNTING_ENABLED", "true")
    monkeypatch.delenv("MODEL_APPROVED", raising=False)
    monkeypatch.delenv("MODEL_RESEARCH_ENABLED", raising=False)

    provider = get_provider()

    assert isinstance(provider, VideoTrackCountingProvider)
    result = provider.count(video_request())
    assert result.status == "review_required"
    assert result.count is None


def test_video_task_bypasses_the_provider_until_counting_is_enabled(monkeypatch) -> None:
    """默认关闭时，任务仍然直接走人工证据分支，不调用任何 Provider。"""

    from app import tasks

    request = video_request()

    def explode() -> CountingProvider:
        raise AssertionError("video evidence must not reach the counting provider while counting is disabled")

    monkeypatch.delenv("VIDEO_COUNTING_ENABLED", raising=False)
    monkeypatch.setattr(tasks, "get_provider", explode)
    monkeypatch.setattr(tasks, "deliver_result", lambda job_id, result: None)

    outcome = tasks.run_counting_job.run(request.model_dump(mode="json"))

    assert outcome["status"] == "review_required"
    assert outcome["count"] is None
    assert outcome["inference_source"] == "manual-video-evidence"
