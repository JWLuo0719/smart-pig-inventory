from __future__ import annotations

from abc import ABC, abstractmethod
from time import perf_counter

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


def get_provider() -> CountingProvider:
    # Provider selection remains closed by default. A model adapter is enabled
    # only after license, checksum and gold-set regression review.
    return UnavailableCountingProvider()
