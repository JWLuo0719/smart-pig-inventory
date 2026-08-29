from __future__ import annotations

from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field


class ModelIdentity(BaseModel):
    model_key: str
    version: str
    checksum: str
    adapter_version: str


class MediaReference(BaseModel):
    asset_id: UUID
    view_position: Literal["single", "left", "center", "right"]
    object_uri: str
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    roi: dict[str, Any] | None = None


class CountingJobRequest(BaseModel):
    job_id: UUID
    correlation_id: str
    organization_id: UUID
    capture_set_id: UUID
    capture_kind: Literal["single", "left_center_right"]
    media: list[MediaReference]
    requested_model: ModelIdentity


class Detection(BaseModel):
    asset_id: UUID
    bbox: tuple[float, float, float, float]
    confidence: float = Field(ge=0, le=1)
    class_id: int


class CountingJobResult(BaseModel):
    status: Literal["succeeded", "review_required", "failed"]
    count: int | None = Field(default=None, ge=0)
    detections: list[Detection] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    model_key: str
    model_version: str
    model_checksum: str
    adapter_version: str
    inference_source: str
    latency_ms: int = Field(ge=0)
    failure_code: str | None = Field(default=None, max_length=128)
    failure_message: str | None = Field(default=None, max_length=1000)
