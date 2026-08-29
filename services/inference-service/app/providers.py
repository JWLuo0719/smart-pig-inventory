from __future__ import annotations

from abc import ABC, abstractmethod
import os
from time import perf_counter

import httpx

from .schemas import CountingJobRequest, CountingJobResult


class CountingProvider(ABC):
    key: str

    @abstractmethod
    def count(self, request: CountingJobRequest) -> CountingJobResult:
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


class HttpYoloCountingProvider(CountingProvider):
    """Adapter for a separately deployed, approved model service.

    The product repository intentionally contains neither Ultralytics code nor
    model weights. The external service must accept CountingJobRequest JSON and
    return CountingJobResult JSON over this versioned boundary.
    """

    key = "http-yolo"

    def __init__(self, endpoint: str) -> None:
        self._endpoint = endpoint

    def count(self, request: CountingJobRequest) -> CountingJobResult:
        started = perf_counter()
        response = httpx.post(
            self._endpoint,
            json=request.model_dump(mode="json"),
            timeout=httpx.Timeout(120.0, connect=10.0),
        )
        response.raise_for_status()
        result = CountingJobResult.model_validate(response.json())
        return result.model_copy(
            update={
                "inference_source": self.key,
                "latency_ms": max(result.latency_ms, round((perf_counter() - started) * 1000)),
            }
        )


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
    if provider_key == "research-http-yolo" and os.getenv("MODEL_RESEARCH_ENABLED", "false").strip().lower() == "true":
        if endpoint:
            return ResearchHttpYoloCountingProvider(endpoint)
    if provider_key == "http-yolo" and os.getenv("MODEL_APPROVED", "false").strip().lower() == "true":
        if endpoint:
            return HttpYoloCountingProvider(endpoint)
    # Provider selection remains closed by default. A model adapter is enabled
    # only after license, checksum and gold-set regression review.
    return UnavailableCountingProvider()
