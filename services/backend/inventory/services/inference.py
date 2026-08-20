from dataclasses import dataclass, field
from pathlib import Path
from time import perf_counter
from typing import Protocol

import requests
from django.conf import settings


@dataclass(frozen=True)
class Detection:
    bbox: list[float]
    confidence: float
    class_id: int = 0
    class_name: str = "pig"


@dataclass(frozen=True)
class CountingResponse:
    raw_count: int
    detections: list[Detection] = field(default_factory=list)
    quality_flags: list[str] = field(default_factory=list)
    model_key: str = ""
    model_version: str = ""
    model_checksum: str = ""
    latency_ms: int = 0


class ProviderUnavailable(RuntimeError):
    pass


class CountingProvider(Protocol):
    key: str

    def count(self, files: list[Path]) -> CountingResponse: ...


def is_detection_inside_roi(detection: Detection, roi: dict) -> bool:
    """Keep detections in the operator-defined valid pen area.

    Empty ROI deliberately means "not configured" and preserves the model result.
    Supported wire forms are a normalized rect (`x`, `y`, `width`, `height`) and a
    normalized polygon (`points: [[x, y], ...]`). Coordinates are compared against
    the bounding-box center, which keeps the contract stable across model formats.
    """
    if not roi or not detection.bbox or len(detection.bbox) < 4:
        return True
    x1, y1, x2, y2 = detection.bbox[:4]
    x, y = (x1 + x2) / 2, (y1 + y2) / 2
    if roi.get("type") == "rect":
        return roi["x"] <= x <= roi["x"] + roi["width"] and roi["y"] <= y <= roi["y"] + roi["height"]
    points = roi.get("points", [])
    if len(points) < 3:
        return True
    inside = False
    previous = points[-1]
    for current in points:
        x1p, y1p = previous
        x2p, y2p = current
        intersects = ((y1p > y) != (y2p > y)) and (x < (x2p - x1p) * (y - y1p) / (y2p - y1p or 1e-12) + x1p)
        if intersects:
            inside = not inside
        previous = current
    return inside


class UnavailableCountingProvider:
    key = "unavailable"

    def count(self, files: list[Path]) -> CountingResponse:
        raise ProviderUnavailable("尚未配置经过验证的 YOLO 推理服务；任务必须人工复核。")


class HttpYoloCountingProvider:
    key = "http_yolo"

    def count(self, files: list[Path]) -> CountingResponse:
        if len(files) != 1:
            raise ProviderUnavailable("当前 HTTP YOLO 适配器只支持单图；三视图必须人工复核。")
        if not settings.YOLO_INFERENCE_URL:
            raise ProviderUnavailable("YOLO_INFERENCE_URL 未配置。")
        started = perf_counter()
        with files[0].open("rb") as image:
            response = requests.post(
                settings.YOLO_INFERENCE_URL,
                files={"image": (files[0].name, image, "image/jpeg")},
                timeout=90,
            )
        response.raise_for_status()
        payload = response.json()
        if not payload.get("success", True):
            raise ProviderUnavailable(payload.get("detail", "YOLO 服务未返回成功结果。"))
        detections = [
            Detection(
                bbox=item.get("bbox", []),
                confidence=float(item.get("confidence", 0)),
                class_id=int(item.get("class_id", 0)),
                class_name=item.get("class_name", "pig"),
            )
            for item in payload.get("detections", [])
        ]
        return CountingResponse(
            raw_count=int(payload.get("num_detections", len(detections))),
            detections=detections,
            model_key=payload.get("model_used", "yolov13"),
            model_version=payload.get("model_version", "unversioned"),
            latency_ms=round((perf_counter() - started) * 1000),
        )


def get_counting_provider() -> CountingProvider:
    if settings.COUNTING_PROVIDER == HttpYoloCountingProvider.key:
        return HttpYoloCountingProvider()
    return UnavailableCountingProvider()
