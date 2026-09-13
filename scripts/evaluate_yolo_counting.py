#!/usr/bin/env python3
"""Evaluate an external YOLO weight as a read-only pig-counting candidate.

The script does not copy or modify images, labels, model source, or weights.
Its default report path is ignored by Git. Results are research evidence only;
they must not be used to enable production counting automatically.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import statistics
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from time import perf_counter
from typing import Iterable, Sequence

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class ImageEvaluation:
    image: str
    expected_count: int
    confidences: tuple[float, ...]
    wall_latency_ms: float
    model_latency_ms: float


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_thresholds(raw_value: str) -> tuple[float, ...]:
    try:
        thresholds = tuple(sorted({float(value.strip()) for value in raw_value.split(",") if value.strip()}))
    except ValueError as exception:
        raise ValueError("thresholds must be comma-separated numbers") from exception
    if not thresholds or any(not math.isfinite(value) or value < 0 or value > 1 for value in thresholds):
        raise ValueError("thresholds must contain finite values between 0 and 1")
    return thresholds


def count_yolo_labels(label_path: Path, class_id: int) -> int:
    if not label_path.is_file():
        raise ValueError(f"missing label for image: {label_path.name}")
    count = 0
    for line_number, raw_line in enumerate(label_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw_line.strip():
            continue
        parts = raw_line.split()
        if len(parts) != 5:
            raise ValueError(f"invalid YOLO label columns in {label_path.name}:{line_number}")
        try:
            label_class = int(parts[0])
            coordinates = tuple(float(value) for value in parts[1:])
        except ValueError as exception:
            raise ValueError(f"invalid YOLO label value in {label_path.name}:{line_number}") from exception
        if any(not math.isfinite(value) or value < 0 or value > 1 for value in coordinates):
            raise ValueError(f"invalid YOLO label range in {label_path.name}:{line_number}")
        if label_class < 0:
            raise ValueError(f"negative class id in {label_path}:{line_number}")
        if label_class == class_id:
            count += 1
    return count


def percentile(values: Sequence[float], quantile: float) -> float:
    if not values:
        raise ValueError("cannot calculate a percentile for an empty sequence")
    ordered = sorted(values)
    position = (len(ordered) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def summarize_threshold(records: Sequence[ImageEvaluation], threshold: float) -> dict[str, object]:
    expected = [record.expected_count for record in records]
    predicted = [sum(confidence >= threshold for confidence in record.confidences) for record in records]
    errors = [prediction - truth for prediction, truth in zip(predicted, expected, strict=True)]
    absolute_errors = [abs(error) for error in errors]
    squared_errors = [error * error for error in errors]
    expected_total = sum(expected)
    return {
        "threshold": threshold,
        "images": len(records),
        "expected_total": expected_total,
        "predicted_total": sum(predicted),
        "mae": round(statistics.fmean(absolute_errors), 6),
        "rmse": round(math.sqrt(statistics.fmean(squared_errors)), 6),
        "bias": round(statistics.fmean(errors), 6),
        "wape": round(sum(absolute_errors) / expected_total, 6) if expected_total else None,
        "exact_rate": round(sum(error == 0 for error in errors) / len(errors), 6),
        "within_2_rate": round(sum(error <= 2 for error in absolute_errors) / len(errors), 6),
        "max_absolute_error": max(absolute_errors),
    }


def build_report(
    records: Sequence[ImageEvaluation],
    thresholds: Sequence[float],
    *,
    split: str,
    class_id: int,
    weight_name: str,
    weight_checksum: str,
    image_size: int,
    device: str,
    iou_threshold: float,
) -> dict[str, object]:
    if not records:
        raise ValueError("no image evaluations were produced")
    metrics = [summarize_threshold(records, threshold) for threshold in thresholds]
    best = min(metrics, key=lambda item: (float(item["mae"]), abs(float(item["bias"])), float(item["threshold"])))
    wall_latencies = [record.wall_latency_ms for record in records]
    model_latencies = [record.model_latency_ms for record in records]
    steady_wall_latencies = wall_latencies[1:] or wall_latencies
    steady_model_latencies = model_latencies[1:] or model_latencies
    total_wall_seconds = sum(wall_latencies) / 1000
    return {
        "schema_version": 1,
        "created_at_utc": datetime.now(UTC).isoformat(),
        "policy": "Read-only research evaluation; not a production approval or automatic-counting authorization.",
        "scope": {"split": split, "images": len(records), "class_id": class_id},
        "model": {
            "weight_file": weight_name,
            "weight_sha256": weight_checksum,
            "image_size": image_size,
            "device": device,
            "iou_threshold": iou_threshold,
            "inference_floor_confidence": min(thresholds),
        },
        "runtime": {"python": platform.python_version(), "platform": platform.platform()},
        "latency_ms": {
            "cold_first_wall": round(wall_latencies[0], 3),
            "wall_mean": round(statistics.fmean(wall_latencies), 3),
            "wall_p50": round(percentile(wall_latencies, 0.5), 3),
            "wall_p95": round(percentile(wall_latencies, 0.95), 3),
            "steady_wall_mean": round(statistics.fmean(steady_wall_latencies), 3),
            "steady_wall_p50": round(percentile(steady_wall_latencies, 0.5), 3),
            "steady_wall_p95": round(percentile(steady_wall_latencies, 0.95), 3),
            "model_mean": round(statistics.fmean(model_latencies), 3),
            "model_p50": round(percentile(model_latencies, 0.5), 3),
            "model_p95": round(percentile(model_latencies, 0.95), 3),
            "steady_model_mean": round(statistics.fmean(steady_model_latencies), 3),
            "throughput_images_per_second": round(len(records) / total_wall_seconds, 6) if total_wall_seconds else None,
        },
        "metrics_by_threshold": metrics,
        "lowest_mae_observed_in_split": best,
        "limitations": [
            "Threshold selection on this dataset must not be treated as production calibration.",
            "A narrow count distribution cannot establish empty-pen, low-count, occlusion, blur, lighting, or device generalization.",
            "The product-side MinIO, ROI, callback, and review path requires separate end-to-end verification.",
        ],
        "per_image": [
            {
                "image": record.image,
                "expected_count": record.expected_count,
                "candidate_counts": {
                    f"{threshold:.6g}": sum(confidence >= threshold for confidence in record.confidences)
                    for threshold in thresholds
                },
                "wall_latency_ms": round(record.wall_latency_ms, 3),
                "model_latency_ms": round(record.model_latency_ms, 3),
            }
            for record in records
        ],
    }


def discover_images(dataset_root: Path, split: str) -> list[Path]:
    image_directory = dataset_root / split / "images"
    if not image_directory.is_dir():
        raise ValueError(f"missing image directory for split: {split}")
    return sorted(
        (path for path in image_directory.rglob("*") if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES),
        key=lambda path: path.as_posix(),
    )


def evaluate_images(
    model: object,
    image_paths: Iterable[Path],
    *,
    dataset_root: Path,
    split: str,
    class_id: int,
    image_size: int,
    minimum_confidence: float,
    iou_threshold: float,
    device: str,
) -> list[ImageEvaluation]:
    image_directory = dataset_root / split / "images"
    label_directory = dataset_root / split / "labels"
    records: list[ImageEvaluation] = []
    paths = list(image_paths)
    for index, image_path in enumerate(paths, start=1):
        relative = image_path.relative_to(image_directory)
        label_path = (label_directory / relative).with_suffix(".txt")
        expected_count = count_yolo_labels(label_path, class_id)
        started = perf_counter()
        results = model.predict(
            source=str(image_path),
            imgsz=image_size,
            conf=minimum_confidence,
            iou=iou_threshold,
            device=device,
            verbose=False,
        )
        wall_latency_ms = (perf_counter() - started) * 1000
        result = results[0]
        boxes = getattr(result, "boxes", None)
        confidences: list[float] = []
        if boxes is not None and len(boxes) > 0:
            confidence_values = boxes.conf.cpu().tolist()
            class_values = boxes.cls.cpu().tolist()
            confidences = [
                float(confidence)
                for confidence, predicted_class in zip(confidence_values, class_values, strict=True)
                if int(predicted_class) == class_id
            ]
        speed = getattr(result, "speed", {}) or {}
        model_latency_ms = sum(float(speed.get(stage, 0.0)) for stage in ("preprocess", "inference", "postprocess"))
        records.append(
            ImageEvaluation(
                image=relative.as_posix(),
                expected_count=expected_count,
                confidences=tuple(confidences),
                wall_latency_ms=wall_latency_ms,
                model_latency_ms=model_latency_ms,
            )
        )
        if index == 1 or index % 10 == 0 or index == len(paths):
            print(f"[INFO] evaluated {index}/{len(paths)} images", flush=True)
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-root", required=True, type=Path, help="Read-only YOLO dataset root")
    parser.add_argument("--runner-repo", required=True, type=Path, help="External YOLOv13 source root")
    parser.add_argument("--weights", required=True, type=Path, help="External model weights")
    parser.add_argument("--expected-checksum", help="Optional sha256 or sha256:<digest>; mismatch fails closed")
    parser.add_argument("--split", default="test", choices=("train", "val", "test"))
    parser.add_argument("--thresholds", default="0.25,0.40,0.50,0.60,0.65,0.70")
    parser.add_argument("--class-id", type=int, default=0)
    parser.add_argument("--image-size", type=int, default=640)
    parser.add_argument("--iou-threshold", type=float, default=0.7)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--max-images", type=int, help="Optional local smoke limit; omit for a full split")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test-assets/generated/yolo-counting-regression.json"),
        help="Local report path; default is Git-ignored",
    )
    args = parser.parse_args()

    dataset_root = args.dataset_root.resolve()
    runner_repo = args.runner_repo.resolve()
    weights = args.weights.resolve()
    if not dataset_root.is_dir():
        parser.error("dataset root does not exist")
    if not runner_repo.is_dir():
        parser.error("runner repository does not exist")
    if not weights.is_file():
        parser.error("weights file does not exist")
    if args.max_images is not None and args.max_images < 1:
        parser.error("max-images must be positive")
    if args.image_size < 32:
        parser.error("image-size must be at least 32")
    if not 0 <= args.iou_threshold <= 1:
        parser.error("iou-threshold must be between 0 and 1")

    try:
        thresholds = parse_thresholds(args.thresholds)
    except ValueError as exception:
        parser.error(str(exception))
    weight_checksum = sha256_file(weights)
    if args.expected_checksum:
        expected_checksum = args.expected_checksum.removeprefix("sha256:").strip().lower()
        if expected_checksum != weight_checksum:
            parser.error("weight checksum does not match expected-checksum")

    image_paths = discover_images(dataset_root, args.split)
    if args.max_images is not None:
        image_paths = image_paths[: args.max_images]
    if not image_paths:
        parser.error("no images found")

    sys.path.insert(0, str(runner_repo))
    import torch
    import ultralytics
    from ultralytics import YOLO

    model = YOLO(str(weights))
    records = evaluate_images(
        model,
        image_paths,
        dataset_root=dataset_root,
        split=args.split,
        class_id=args.class_id,
        image_size=args.image_size,
        minimum_confidence=min(thresholds),
        iou_threshold=args.iou_threshold,
        device=args.device,
    )
    report = build_report(
        records,
        thresholds,
        split=args.split,
        class_id=args.class_id,
        weight_name=weights.name,
        weight_checksum=weight_checksum,
        image_size=args.image_size,
        device=args.device,
        iou_threshold=args.iou_threshold,
    )
    report["runtime"].update({"torch": torch.__version__, "ultralytics": ultralytics.__version__})
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "output": str(output),
        "images": len(records),
        "lowest_mae_observed_in_split": report["lowest_mae_observed_in_split"],
        "latency_ms": report["latency_ms"],
    }
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
