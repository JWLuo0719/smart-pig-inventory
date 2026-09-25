from __future__ import annotations

from abc import ABC, abstractmethod
import math
import os
from time import perf_counter
from urllib.parse import urlsplit, urlunsplit

import httpx

from .geometry import PenRoi, parse_pen_roi
from .multiview import VIEW_ORDER, MultiViewCalibration, deduplicate_views
from .schemas import CountingJobRequest, CountingJobResult, Detection
from .video import aggregate_tracks


class CountingProvider(ABC):
    key: str

    @abstractmethod
    def count(self, request: CountingJobRequest) -> CountingJobResult:
        raise NotImplementedError

    @abstractmethod
    def readiness(self) -> dict[str, object]:
        raise NotImplementedError


class UnavailableCountingProvider(CountingProvider):
    key = "unavailable"

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        started = perf_counter()
        return CountingJobResult(
            status="review_required",
            count=None,
            warnings=["No validated counting provider is configured"],
            model_key=request.requested_model.model_key,
            model_version=request.requested_model.version,
            model_checksum=request.requested_model.checksum,
            adapter_version=request.requested_model.adapter_version,
            inference_source=self.key,
            latency_ms=round((perf_counter() - started) * 1000),
        )

    def readiness(self) -> dict[str, object]:
        return {
            "ready": True,
            "provider": self.key,
            "counting_available": False,
            "reason_code": "NO_VALIDATED_PROVIDER",
        }


class HttpYoloCountingProvider(CountingProvider):
    """Adapter for a separately deployed, approved model service.

    The product repository intentionally contains neither Ultralytics code nor
    model weights. The external service must accept CountingJobRequest JSON and
    return CountingJobResult JSON over this versioned boundary.
    """

    key = "http-yolo"

    def __init__(
        self,
        endpoint: str,
        timeout_seconds: float | None = None,
        connect_timeout_seconds: float | None = None,
        readiness_endpoint: str | None = None,
        expected_identity: tuple[str, str, str, str] | None = None,
    ) -> None:
        self._endpoint = endpoint
        total_timeout = (
            _positive_number("timeout_seconds", timeout_seconds)
            if timeout_seconds is not None
            else _positive_environment_float("YOLO_HTTP_TIMEOUT_SECONDS", 120.0)
        )
        connect_timeout = (
            _positive_number("connect_timeout_seconds", connect_timeout_seconds)
            if connect_timeout_seconds is not None
            else _positive_environment_float("YOLO_HTTP_CONNECT_TIMEOUT_SECONDS", 10.0)
        )
        self._timeout = httpx.Timeout(total_timeout, connect=connect_timeout)
        self._readiness_timeout = httpx.Timeout(min(total_timeout, 10.0), connect=min(connect_timeout, 5.0))
        configured_readiness_endpoint = os.getenv("YOLO_HTTP_READY_ENDPOINT", "").strip()
        self._readiness_endpoint = readiness_endpoint or configured_readiness_endpoint or _default_readiness_endpoint(endpoint)
        self._expected_identity = expected_identity

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        started = perf_counter()
        response = httpx.post(
            self._endpoint,
            json=request.model_dump(mode="json"),
            headers=_runner_service_headers(),
            timeout=self._timeout,
        )
        response.raise_for_status()
        result = CountingJobResult.model_validate(response.json())
        normalized = _normalize_runner_result(request, result)
        return normalized.model_copy(
            update={
                "inference_source": self.key,
                "latency_ms": max(normalized.latency_ms, round((perf_counter() - started) * 1000)),
            }
        )

    def readiness(self) -> dict[str, object]:
        try:
            response = httpx.get(
                self._readiness_endpoint,
                headers=_runner_service_headers(),
                timeout=self._readiness_timeout,
            )
            if response.status_code != 200:
                return _not_ready(self.key, "RUNNER_NOT_READY")
            payload = response.json()
        except httpx.RequestError:
            return _not_ready(self.key, "RUNNER_UNREACHABLE")
        except (TypeError, ValueError):
            return _not_ready(self.key, "RUNNER_INVALID_READINESS")
        if not isinstance(payload, dict) or payload.get("ready") is not True:
            return _not_ready(self.key, "RUNNER_NOT_READY")
        if self._expected_identity is not None:
            actual_identity = (
                payload.get("model_key"),
                payload.get("model_version"),
                payload.get("model_checksum"),
                payload.get("adapter_version"),
            )
            if actual_identity != self._expected_identity:
                return _not_ready(self.key, "RUNNER_IDENTITY_MISMATCH")
        return {
            "ready": True,
            "provider": self.key,
            "counting_available": True,
            "model_key": payload.get("model_key"),
            "model_version": payload.get("model_version"),
            "model_checksum": payload.get("model_checksum"),
            "adapter_version": payload.get("adapter_version"),
        }


class ResearchHttpYoloCountingProvider(HttpYoloCountingProvider):
    """Adapter for an isolated research model service.

    Research detections are evidence for a reviewer, never an automatic pig
    inventory count. This lets a third-party model be exercised end to end
    without granting it the production approval gate.
    """

    key = "research-http-yolo"

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        result = super().count(request)
        if result.status == "failed":
            return result

        return result.model_copy(
            update={
                "status": "review_required",
                "count": None,
                "warnings": [
                    "Research model output: automatic counting is disabled pending domain validation",
                    *result.warnings,
                ],
            }
        )


class MultiViewDeduplicatingProvider(CountingProvider):
    """左/中/右三图跨图去重 Provider。

    它包装一个既有的图像 Provider：内层仍然负责逐张图的检测与逐图 ROI 过滤，本层
    只做一件事——在三个视图齐全、且现场已标定相邻视图重叠比例时，把重叠带内重复
    出现的同一头猪合并，从而不必把左/中/右简单相加。

    失败关闭规则（任一条不满足都不聚合，数量留空）：

    * 未配置重叠标定；
    * 三张视图不齐全或方向不是左/中/右；
    * 内层 Provider 处于研究模式（内层本身已强制复核）时只合并检测框，数量仍为空。
    """

    key = "multi-view-dedup"

    def __init__(self, inner: CountingProvider, calibration: MultiViewCalibration | None) -> None:
        self._inner = inner
        self._calibration = calibration

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        started = perf_counter()
        if request.capture_kind != "left_center_right":
            # 单图与视频不涉及跨图合并，沿用内层 Provider 的判定。
            return self._inner.count(request)

        result = self._inner.count(request)
        if result.status == "failed":
            return result

        elapsed_ms = round((perf_counter() - started) * 1000)
        if self._calibration is None:
            return self._review_required(
                result,
                "Multi-view overlap calibration is not configured; "
                "left, center and right detections are not aggregated",
                elapsed_ms,
            )
        if len(request.media) != len(VIEW_ORDER) or {
            media.view_position for media in request.media
        } != set(VIEW_ORDER):
            return self._review_required(
                result,
                "Multi-view de-duplication requires exactly one left, center and right view",
                elapsed_ms,
            )

        media_by_asset = {media.asset_id: media for media in request.media}
        detections_by_view: dict[str, list[Detection]] = {view: [] for view in VIEW_ORDER}
        for detection in result.detections:
            media = media_by_asset.get(detection.asset_id)
            if media is None:
                raise ValueError("Multi-view detection references an asset outside the counting request")
            detections_by_view[media.view_position].append(detection)

        outcome = deduplicate_views(detections_by_view, self._calibration)
        return result.model_copy(
            update={
                "count": len(outcome.kept) if result.status == "succeeded" else None,
                "detections": list(outcome.kept),
                "warnings": [*result.warnings, *outcome.warnings],
                "inference_source": self.key,
                "latency_ms": max(result.latency_ms, elapsed_ms),
            }
        )

    def readiness(self) -> dict[str, object]:
        payload = dict(self._inner.readiness())
        payload["provider"] = self.key
        payload["multi_view_dedup"] = self._calibration is not None
        if self._calibration is None:
            payload["multi_view_reason_code"] = "MULTIVIEW_CALIBRATION_MISSING"
        return payload

    def _review_required(
        self,
        result: CountingJobResult,
        message: str,
        elapsed_ms: int,
    ) -> CountingJobResult:
        return result.model_copy(
            update={
                "status": "review_required",
                "count": None,
                "warnings": [message, *result.warnings],
                "inference_source": self.key,
                "latency_ms": max(result.latency_ms, elapsed_ms),
            }
        )


class VideoTrackCountingProvider(CountingProvider):
    """视频抽帧计数 Provider：把 Runner 的逐帧轨迹聚合成去重后的猪只数量。

    抽帧与跨帧跟踪由产品仓库之外的 Runner 完成，本层只做聚合与门禁。失败关闭规则：
    任一检测框缺少轨迹标识、或完全没有检测框时，都不产生数量（`review_required`），
    仍然保留检测框作为人工复核证据。
    """

    key = "video-track-count"

    def __init__(self, inner: CountingProvider, min_observations: int = 1) -> None:
        self._inner = inner
        self._min_observations = min_observations

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        started = perf_counter()
        if request.capture_kind != "video":
            return self._inner.count(request)

        result = self._inner.count(request)
        if result.status == "failed":
            return result

        outcome = aggregate_tracks(result.detections, min_observations=self._min_observations)
        elapsed_ms = round((perf_counter() - started) * 1000)
        aggregated = result.status == "succeeded" and outcome.count is not None
        return result.model_copy(
            update={
                "status": "succeeded" if aggregated else "review_required",
                "count": outcome.count if aggregated else None,
                "detections": list(outcome.kept),
                "warnings": [*result.warnings, *outcome.warnings],
                "inference_source": self.key,
                "latency_ms": max(result.latency_ms, elapsed_ms),
            }
        )

    def readiness(self) -> dict[str, object]:
        payload = dict(self._inner.readiness())
        payload["provider"] = self.key
        payload["video_counting"] = True
        payload["video_min_track_observations"] = self._min_observations
        return payload


def video_counting_enabled() -> bool:
    """视频自动计数默认关闭；关闭时视频仍走人工证据流程。"""

    return _enabled("VIDEO_COUNTING_ENABLED")


def get_provider() -> CountingProvider:
    provider_key = os.getenv("COUNTING_PROVIDER", "unavailable").strip().lower()
    endpoint = os.getenv("YOLO_HTTP_ENDPOINT", "").strip()
    expected_identity = _configured_model_identity()
    if provider_key == "multi-view-dedup" and _enabled("MULTIVIEW_DEDUP_ENABLED"):
        # 跨图去重只是显式启用的包装层；内层能否真正计数仍由 MODEL_APPROVED /
        # MODEL_RESEARCH_ENABLED 门禁决定，未批准时内层保持 unavailable。
        return MultiViewDeduplicatingProvider(
            _image_provider(endpoint, expected_identity),
            _configured_multiview_calibration(),
        )
    if provider_key == "video-track-count" and video_counting_enabled():
        # 视频计数同样只是聚合层：抽帧与跟踪由外部 Runner 提供，模型门禁照旧生效。
        return VideoTrackCountingProvider(
            _image_provider(endpoint, expected_identity),
            _configured_video_min_observations(),
        )
    if provider_key == "research-http-yolo" and _enabled("MODEL_RESEARCH_ENABLED"):
        if endpoint:
            return ResearchHttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    if provider_key == "http-yolo" and _enabled("MODEL_APPROVED"):
        if endpoint:
            return HttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    # Provider selection remains closed by default. A model adapter is enabled
    # only after license, checksum and gold-set regression review.
    return UnavailableCountingProvider()


def _enabled(name: str) -> bool:
    return os.getenv(name, "false").strip().lower() == "true"


def _runner_service_headers() -> dict[str, str]:
    """可选共享令牌：配置 YOLO_HTTP_TOKEN 时给 Runner 请求附上 X-Runner-Service-Key（与 research_runner 同步）。

    未设置该环境变量时保持现状（不带此请求头），兼容未开启鉴权的 Runner 部署。
    """

    token = os.getenv("YOLO_HTTP_TOKEN", "").strip()
    if not token:
        return {}
    return {"X-Runner-Service-Key": token}


def _image_provider(endpoint: str, expected_identity: tuple[str, str, str, str]) -> CountingProvider:
    """按既有模型门禁挑选内层图像 Provider；未获批准时保持 unavailable。"""

    if endpoint and _enabled("MODEL_APPROVED"):
        return HttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    if endpoint and _enabled("MODEL_RESEARCH_ENABLED"):
        return ResearchHttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    return UnavailableCountingProvider()


def _configured_multiview_calibration() -> MultiViewCalibration | None:
    """读取相邻视图重叠带的现场标定；未配置重叠比例时返回 None 由 Provider 失败关闭。"""

    raw_overlap = os.getenv("MULTIVIEW_VIEW_OVERLAP", "").strip()
    if not raw_overlap:
        return None
    try:
        overlap = float(raw_overlap)
    except ValueError as exception:
        raise ValueError("MULTIVIEW_VIEW_OVERLAP must be a number within (0, 0.5]") from exception
    try:
        return MultiViewCalibration(
            overlap=overlap,
            center_tolerance=_optional_finite_float("MULTIVIEW_CENTER_TOLERANCE", 0.08),
            height_tolerance=_optional_finite_float("MULTIVIEW_HEIGHT_TOLERANCE", 0.35),
            max_cost=_optional_finite_float("MULTIVIEW_MAX_COST", 1.0),
        )
    except ValueError as exception:
        raise ValueError(f"MULTIVIEW_VIEW_OVERLAP is not a usable overlap fraction: {exception}") from exception


def _optional_finite_float(name: str, default: float) -> float:
    raw_value = os.getenv(name, "").strip()
    if not raw_value:
        return default
    try:
        value = float(raw_value)
    except ValueError as exception:
        raise ValueError(f"{name} must be a finite number") from exception
    if not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number")
    return value


def _configured_video_min_observations() -> int:
    raw_value = os.getenv("VIDEO_MIN_TRACK_OBSERVATIONS", "").strip()
    if not raw_value:
        return 1
    try:
        value = int(raw_value)
    except ValueError as exception:
        raise ValueError("VIDEO_MIN_TRACK_OBSERVATIONS must be an integer of at least 1") from exception
    if value < 1:
        raise ValueError("VIDEO_MIN_TRACK_OBSERVATIONS must be an integer of at least 1")
    return value


def _configured_model_identity() -> tuple[str, str, str, str]:
    return (
        os.getenv("MODEL_KEY", "pending-license-review").strip(),
        os.getenv("MODEL_VERSION", "unverified").strip(),
        os.getenv("MODEL_CHECKSUM", "unverified").strip(),
        os.getenv("MODEL_ADAPTER_VERSION", "http-v1").strip(),
    )


def _default_readiness_endpoint(endpoint: str) -> str:
    parsed = urlsplit(endpoint)
    return urlunsplit((parsed.scheme, parsed.netloc, "/health/ready", "", ""))


def _not_ready(provider: str, reason_code: str) -> dict[str, object]:
    return {
        "ready": False,
        "provider": provider,
        "counting_available": False,
        "reason_code": reason_code,
    }


def _positive_environment_float(name: str, default: float) -> float:
    raw_value = os.getenv(name, str(default)).strip()
    try:
        value = float(raw_value)
    except ValueError as exception:
        raise ValueError(f"{name} must be a positive number") from exception
    return _positive_number(name, value)


def _positive_number(name: str, value: float) -> float:
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be a positive number")
    return value


def _normalize_runner_result(
    request: CountingJobRequest,
    result: CountingJobResult,
) -> CountingJobResult:
    expected = request.requested_model
    actual_identity = (
        result.model_key,
        result.model_version,
        result.model_checksum,
        result.adapter_version,
    )
    expected_identity = (
        expected.model_key,
        expected.version,
        expected.checksum,
        expected.adapter_version,
    )
    if actual_identity != expected_identity:
        raise ValueError("Runner result model identity does not match the requested model")

    media_by_asset_id = {media.asset_id: media for media in request.media}
    pen_roi_by_asset_id = {media.asset_id: parse_pen_roi(media.roi) for media in request.media}
    filtered_detections = []
    for detection in result.detections:
        media = media_by_asset_id.get(detection.asset_id)
        if media is None:
            raise ValueError("Runner result references an asset outside the counting request")
        _validate_normalized_bbox(detection.bbox)
        if _admits_detection(pen_roi_by_asset_id[media.asset_id], detection.bbox):
            filtered_detections.append(detection)

    warnings = list(result.warnings)
    normalized_count = result.count
    if result.status == "succeeded":
        normalized_count = len(filtered_detections)
        if result.count != normalized_count:
            warnings.append("Runner count was recalculated from validated detections and ROI")

    return result.model_copy(
        update={
            "count": normalized_count,
            "detections": filtered_detections,
            "warnings": warnings,
        }
    )


def _validate_normalized_bbox(bbox: tuple[float, float, float, float]) -> None:
    x1, y1, x2, y2 = bbox
    if not all(math.isfinite(value) for value in bbox):
        raise ValueError("Runner detection bounding boxes must contain finite values")
    if not (0 <= x1 <= x2 <= 1 and 0 <= y1 <= y2 <= 1):
        raise ValueError("Runner detection bounding boxes must use normalized xyxy coordinates")


def _admits_detection(roi: PenRoi | None, bbox: tuple[float, float, float, float]) -> bool:
    """没有 ROI 时整幅图像都算本栏；否则按有效区、排除区与最小包含比例判定。

    判定细节集中在 ``app.geometry``，本函数只表达"缺省即整图"这一历史口径。
    """

    return roi is None or roi.admits(bbox)
