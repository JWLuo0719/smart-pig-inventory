from __future__ import annotations

from abc import ABC, abstractmethod
import math
import os
from time import perf_counter
from urllib.parse import urlsplit, urlunsplit

import httpx

from .schemas import CountingJobRequest, CountingJobResult


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
            response = httpx.get(self._readiness_endpoint, timeout=self._readiness_timeout)
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


def get_provider() -> CountingProvider:
    provider_key = os.getenv("COUNTING_PROVIDER", "unavailable").strip().lower()
    endpoint = os.getenv("YOLO_HTTP_ENDPOINT", "").strip()
    expected_identity = _configured_model_identity()
    if provider_key == "research-http-yolo" and os.getenv("MODEL_RESEARCH_ENABLED", "false").strip().lower() == "true":
        if endpoint:
            return ResearchHttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    if provider_key == "http-yolo" and os.getenv("MODEL_APPROVED", "false").strip().lower() == "true":
        if endpoint:
            return HttpYoloCountingProvider(endpoint, expected_identity=expected_identity)
    # Provider selection remains closed by default. A model adapter is enabled
    # only after license, checksum and gold-set regression review.
    return UnavailableCountingProvider()


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
    filtered_detections = []
    for detection in result.detections:
        media = media_by_asset_id.get(detection.asset_id)
        if media is None:
            raise ValueError("Runner result references an asset outside the counting request")
        _validate_normalized_bbox(detection.bbox)
        if _center_is_inside_roi(detection.bbox, media.roi):
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


def _center_is_inside_roi(
    bbox: tuple[float, float, float, float],
    roi: dict[str, object] | None,
) -> bool:
    if roi is None:
        return True
    x = float(roi["x"])
    y = float(roi["y"])
    right = x + float(roi["width"])
    bottom = y + float(roi["height"])
    center_x = (bbox[0] + bbox[2]) / 2
    center_y = (bbox[1] + bbox[3]) / 2
    return x <= center_x <= right and y <= center_y <= bottom
