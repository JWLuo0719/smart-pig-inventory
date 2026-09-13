from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any, Mapping


SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_BLOCKERS = {
    "license_approval",
    "authorized_business_gold_set",
    "owner_automatic_counting_approval",
}
DEFAULT_TOLERANCES = {
    "validation_mae_max_increase": 0.25,
    "validation_wape_max_increase": 0.01,
    "test_mae_max_increase": 0.25,
    "test_wape_max_increase": 0.01,
    "test_within_2_rate_max_drop": 0.03,
    "test_max_absolute_error_max_increase": 1,
    "steady_wall_p95_max_ratio": 1.5,
    "throughput_min_ratio": 0.67,
}


class GateError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exception:
        raise GateError(f"cannot read JSON {path.name}: {exception}") from exception
    if not isinstance(payload, dict):
        raise GateError(f"JSON root must be an object: {path.name}")
    return payload


def write_json(path: Path, payload: Mapping[str, Any], *, refuse_overwrite: bool = False) -> None:
    if refuse_overwrite and path.exists():
        raise GateError(f"refusing to overwrite immutable baseline: {path.name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exception:
        raise GateError(f"cannot hash {path.name}: {exception}") from exception
    return digest.hexdigest()


def canonical_sha256(payload: Mapping[str, Any]) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _mapping(payload: Mapping[str, Any], key: str) -> Mapping[str, Any]:
    value = payload.get(key)
    if not isinstance(value, Mapping):
        raise GateError(f"{key} must be an object")
    return value


def _string(payload: Mapping[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise GateError(f"{key} must be a non-empty string")
    return value.strip()


def _number(payload: Mapping[str, Any], key: str) -> float:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise GateError(f"{key} must be a finite number")
    return float(value)


def _integer(payload: Mapping[str, Any], key: str) -> int:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise GateError(f"{key} must be an integer")
    return value


def _validate_checksum(checksum: str, field: str) -> None:
    if not SHA256_PATTERN.fullmatch(checksum):
        raise GateError(f"{field} must be 64 lowercase hexadecimal characters")


def validate_regression_summary(summary: Mapping[str, Any]) -> None:
    if summary.get("schema_version") != 1:
        raise GateError("regression summary schema_version must be 1")
    threshold_selection = _mapping(summary, "threshold_selection")
    if threshold_selection.get("split") != "val":
        raise GateError("threshold selection must use the validation split")
    selected_threshold = _number(threshold_selection, "selected_threshold")
    if not 0 <= selected_threshold <= 1:
        raise GateError("selected threshold must be between 0 and 1")
    validation = _mapping(threshold_selection, "validation_result")
    held_out = _mapping(summary, "held_out_evaluation")
    if held_out.get("split") != "test":
        raise GateError("held-out evaluation must use the test split")
    if _number(held_out, "threshold") != selected_threshold:
        raise GateError("test threshold must equal the validation-selected threshold")
    test_result = _mapping(held_out, "result")
    if _number(validation, "threshold") != selected_threshold:
        raise GateError("validation result threshold must equal selected threshold")
    if _number(test_result, "threshold") != selected_threshold:
        raise GateError("test result threshold must equal selected threshold")
    for name, metrics in (("validation", validation), ("test", test_result)):
        if _integer(metrics, "images") <= 0:
            raise GateError(f"{name} image count must be positive")
        for key in ("mae", "wape", "within_2_rate", "max_absolute_error"):
            _number(metrics, key)
    latency = _mapping(held_out, "latency_ms")
    if _number(latency, "steady_wall_p95") <= 0:
        raise GateError("steady wall P95 must be positive")
    if _number(latency, "throughput_images_per_second") <= 0:
        raise GateError("throughput must be positive")
    model = _mapping(summary, "model")
    checksum = _string(model, "weight_sha256")
    _validate_checksum(checksum, "model.weight_sha256")
    _string(model, "weight_file")
    _integer(model, "image_size")
    _number(model, "iou_threshold")
    _mapping(summary, "runtime")


def build_manifest(
    summary: Mapping[str, Any],
    *,
    summary_sha256: str,
    weight_name: str,
    weight_size: int,
    weight_checksum: str,
    model_key: str,
    model_version: str,
    adapter_version: str,
) -> dict[str, Any]:
    validate_regression_summary(summary)
    summary_model = _mapping(summary, "model")
    summary_checksum = _string(summary_model, "weight_sha256")
    if summary_checksum != weight_checksum:
        raise GateError("weight checksum does not match the regression summary")
    if Path(_string(summary_model, "weight_file")).name != weight_name:
        raise GateError("weight file name does not match the regression summary")
    threshold_selection = _mapping(summary, "threshold_selection")
    held_out = _mapping(summary, "held_out_evaluation")
    identity = {
        "model_key": model_key,
        "model_version": model_version,
        "model_checksum": weight_checksum,
        "adapter_version": adapter_version,
    }
    return {
        "schema_version": 1,
        "release_kind": "research_candidate",
        "release_id": f"{model_key}:{model_version}@{weight_checksum[:12]}",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "model": identity,
        "artifact": {
            "file_name": weight_name,
            "size_bytes": weight_size,
            "sha256": weight_checksum,
        },
        "inference": {
            "selected_threshold": _number(threshold_selection, "selected_threshold"),
            "image_size": _integer(summary_model, "image_size"),
            "iou_threshold": _number(summary_model, "iou_threshold"),
        },
        "regression_evidence": {
            "summary_sha256": summary_sha256,
            "threshold_selection_split": "val",
            "held_out_evaluation_split": "test",
            "validation": dict(_mapping(threshold_selection, "validation_result")),
            "test": dict(_mapping(held_out, "result")),
            "latency_ms": dict(_mapping(held_out, "latency_ms")),
            "runtime": dict(_mapping(summary, "runtime")),
        },
        "safety": {
            "model_approved": False,
            "automatic_counting_enabled": False,
            "manual_review_required": True,
            "multiview_aggregation_enabled": False,
            "license_status": "pending",
            "business_gold_set_status": "pending",
            "owner_approval_status": "pending",
            "blockers": sorted(REQUIRED_BLOCKERS),
        },
    }


def validate_manifest(
    manifest: Mapping[str, Any],
    *,
    weights_path: Path | None = None,
    summary_path: Path | None = None,
) -> None:
    if manifest.get("schema_version") != 1:
        raise GateError("manifest schema_version must be 1")
    if manifest.get("release_kind") != "research_candidate":
        raise GateError("manifest release_kind must remain research_candidate")
    _string(manifest, "release_id")
    _string(manifest, "generated_at_utc")
    model = _mapping(manifest, "model")
    for key in ("model_key", "model_version", "adapter_version"):
        _string(model, key)
    model_checksum = _string(model, "model_checksum")
    _validate_checksum(model_checksum, "model.model_checksum")
    artifact = _mapping(manifest, "artifact")
    artifact_name = _string(artifact, "file_name")
    if artifact_name != Path(artifact_name).name:
        raise GateError("artifact.file_name must not contain a path")
    if _integer(artifact, "size_bytes") <= 0:
        raise GateError("artifact.size_bytes must be positive")
    artifact_checksum = _string(artifact, "sha256")
    _validate_checksum(artifact_checksum, "artifact.sha256")
    if artifact_checksum != model_checksum:
        raise GateError("artifact checksum must match model identity")
    inference = _mapping(manifest, "inference")
    if not 0 <= _number(inference, "selected_threshold") <= 1:
        raise GateError("inference threshold must be between 0 and 1")
    if _integer(inference, "image_size") <= 0:
        raise GateError("inference image size must be positive")
    if not 0 <= _number(inference, "iou_threshold") <= 1:
        raise GateError("inference IoU threshold must be between 0 and 1")
    evidence = _mapping(manifest, "regression_evidence")
    evidence_checksum = _string(evidence, "summary_sha256")
    _validate_checksum(evidence_checksum, "regression_evidence.summary_sha256")
    if evidence.get("threshold_selection_split") != "val" or evidence.get("held_out_evaluation_split") != "test":
        raise GateError("manifest must preserve validation selection and held-out test evaluation")
    _mapping(evidence, "validation")
    _mapping(evidence, "test")
    _mapping(evidence, "latency_ms")
    _mapping(evidence, "runtime")
    safety = _mapping(manifest, "safety")
    for key in ("model_approved", "automatic_counting_enabled", "multiview_aggregation_enabled"):
        if safety.get(key) is not False:
            raise GateError(f"safety.{key} must remain false for a research candidate")
    if safety.get("manual_review_required") is not True:
        raise GateError("safety.manual_review_required must remain true")
    for key in ("license_status", "business_gold_set_status", "owner_approval_status"):
        if safety.get(key) != "pending":
            raise GateError(f"safety.{key} must remain pending")
    blockers = safety.get("blockers")
    if not isinstance(blockers, list) or set(blockers) != REQUIRED_BLOCKERS:
        raise GateError("safety.blockers must list every deferred approval")
    if weights_path is not None:
        if weights_path.name != artifact_name:
            raise GateError("provided weight file name does not match manifest")
        if weights_path.stat().st_size != _integer(artifact, "size_bytes"):
            raise GateError("provided weight size does not match manifest")
        if file_sha256(weights_path) != artifact_checksum:
            raise GateError("provided weight checksum does not match manifest")
    if summary_path is not None:
        summary = load_json(summary_path)
        validate_regression_summary(summary)
        if file_sha256(summary_path) != evidence_checksum:
            raise GateError("provided regression summary checksum does not match manifest")
        summary_model = _mapping(summary, "model")
        if _string(summary_model, "weight_sha256") != model_checksum:
            raise GateError("regression summary model checksum does not match manifest")


def create_baseline(summary: Mapping[str, Any], *, summary_sha256: str) -> dict[str, Any]:
    validate_regression_summary(summary)
    threshold = _mapping(summary, "threshold_selection")
    held_out = _mapping(summary, "held_out_evaluation")
    model = _mapping(summary, "model")
    return {
        "schema_version": 1,
        "baseline_kind": "local_regression_baseline",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "immutable": True,
        "source_summary_sha256": summary_sha256,
        "model": {
            "weight_file": Path(_string(model, "weight_file")).name,
            "weight_sha256": _string(model, "weight_sha256"),
            "image_size": _integer(model, "image_size"),
            "iou_threshold": _number(model, "iou_threshold"),
        },
        "selected_threshold": _number(threshold, "selected_threshold"),
        "validation": _metric_snapshot(_mapping(threshold, "validation_result")),
        "test": _metric_snapshot(_mapping(held_out, "result")),
        "latency_ms": {
            "steady_wall_p95": _number(_mapping(held_out, "latency_ms"), "steady_wall_p95"),
            "throughput_images_per_second": _number(
                _mapping(held_out, "latency_ms"), "throughput_images_per_second"
            ),
        },
        "tolerances": dict(DEFAULT_TOLERANCES),
        "policy": "Never overwrite this file automatically. Promote a new versioned baseline explicitly.",
    }


def _metric_snapshot(metrics: Mapping[str, Any]) -> dict[str, float | int]:
    return {
        "images": _integer(metrics, "images"),
        "mae": _number(metrics, "mae"),
        "wape": _number(metrics, "wape"),
        "within_2_rate": _number(metrics, "within_2_rate"),
        "max_absolute_error": _number(metrics, "max_absolute_error"),
    }


def compare_to_baseline(
    summary: Mapping[str, Any],
    baseline: Mapping[str, Any],
    *,
    current_summary_sha256: str | None = None,
) -> dict[str, Any]:
    validate_regression_summary(summary)
    if baseline.get("schema_version") != 1 or baseline.get("baseline_kind") != "local_regression_baseline":
        raise GateError("unsupported regression baseline")
    if baseline.get("immutable") is not True:
        raise GateError("regression baseline must be immutable")
    current_model = _mapping(summary, "model")
    baseline_model = _mapping(baseline, "model")
    current_identity = {
        "weight_sha256": _string(current_model, "weight_sha256"),
        "image_size": _integer(current_model, "image_size"),
        "iou_threshold": _number(current_model, "iou_threshold"),
    }
    baseline_identity = {
        "weight_sha256": _string(baseline_model, "weight_sha256"),
        "image_size": _integer(baseline_model, "image_size"),
        "iou_threshold": _number(baseline_model, "iou_threshold"),
    }
    threshold = _mapping(summary, "threshold_selection")
    held_out = _mapping(summary, "held_out_evaluation")
    current_validation = _metric_snapshot(_mapping(threshold, "validation_result"))
    current_test = _metric_snapshot(_mapping(held_out, "result"))
    current_latency = _mapping(held_out, "latency_ms")
    baseline_validation = _mapping(baseline, "validation")
    baseline_test = _mapping(baseline, "test")
    baseline_latency = _mapping(baseline, "latency_ms")
    tolerances = _mapping(baseline, "tolerances")
    violations: list[dict[str, Any]] = []
    if current_identity != baseline_identity:
        violations.append({"code": "MODEL_IDENTITY_CHANGED", "baseline": baseline_identity, "current": current_identity})
    current_threshold = _number(threshold, "selected_threshold")
    baseline_threshold = _number(baseline, "selected_threshold")
    if current_threshold != baseline_threshold:
        violations.append(
            {"code": "SELECTED_THRESHOLD_CHANGED", "baseline": baseline_threshold, "current": current_threshold}
        )
    checks = [
        ("VALIDATION_MAE_DRIFT", _number(current_validation, "mae") - _number(baseline_validation, "mae"), _number(tolerances, "validation_mae_max_increase"), "max"),
        ("VALIDATION_WAPE_DRIFT", _number(current_validation, "wape") - _number(baseline_validation, "wape"), _number(tolerances, "validation_wape_max_increase"), "max"),
        ("TEST_MAE_DRIFT", _number(current_test, "mae") - _number(baseline_test, "mae"), _number(tolerances, "test_mae_max_increase"), "max"),
        ("TEST_WAPE_DRIFT", _number(current_test, "wape") - _number(baseline_test, "wape"), _number(tolerances, "test_wape_max_increase"), "max"),
        ("TEST_WITHIN_2_RATE_DROP", _number(baseline_test, "within_2_rate") - _number(current_test, "within_2_rate"), _number(tolerances, "test_within_2_rate_max_drop"), "max"),
        ("TEST_MAX_ERROR_DRIFT", _number(current_test, "max_absolute_error") - _number(baseline_test, "max_absolute_error"), _number(tolerances, "test_max_absolute_error_max_increase"), "max"),
    ]
    for code, delta, limit, _ in checks:
        if delta > limit:
            violations.append({"code": code, "delta": round(delta, 9), "limit": limit})
    current_p95 = _number(current_latency, "steady_wall_p95")
    baseline_p95 = _number(baseline_latency, "steady_wall_p95")
    p95_ratio = current_p95 / baseline_p95
    p95_limit = _number(tolerances, "steady_wall_p95_max_ratio")
    if p95_ratio > p95_limit:
        violations.append({"code": "STEADY_P95_REGRESSION", "ratio": round(p95_ratio, 9), "limit": p95_limit})
    current_throughput = _number(current_latency, "throughput_images_per_second")
    baseline_throughput = _number(baseline_latency, "throughput_images_per_second")
    throughput_ratio = current_throughput / baseline_throughput
    throughput_limit = _number(tolerances, "throughput_min_ratio")
    if throughput_ratio < throughput_limit:
        violations.append(
            {"code": "THROUGHPUT_REGRESSION", "ratio": round(throughput_ratio, 9), "limit": throughput_limit}
        )
    return {
        "schema_version": 1,
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "passed": not violations,
        "baseline_summary_sha256": _string(baseline, "source_summary_sha256"),
        "current_summary_sha256": current_summary_sha256 or canonical_sha256(summary),
        "ratios": {
            "steady_wall_p95": round(p95_ratio, 9),
            "throughput_images_per_second": round(throughput_ratio, 9),
        },
        "violations": violations,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build and verify research-only model release evidence.")
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build-manifest")
    build.add_argument("--summary", type=Path, required=True)
    build.add_argument("--weights", type=Path, required=True)
    build.add_argument("--expected-checksum", required=True)
    build.add_argument("--model-key", required=True)
    build.add_argument("--model-version", required=True)
    build.add_argument("--adapter-version", default="http-v1")
    build.add_argument("--output", type=Path, required=True)
    validate = commands.add_parser("validate-manifest")
    validate.add_argument("--manifest", type=Path, required=True)
    validate.add_argument("--weights", type=Path)
    validate.add_argument("--summary", type=Path)
    baseline = commands.add_parser("create-baseline")
    baseline.add_argument("--summary", type=Path, required=True)
    baseline.add_argument("--output", type=Path, required=True)
    compare = commands.add_parser("compare")
    compare.add_argument("--summary", type=Path, required=True)
    compare.add_argument("--baseline", type=Path, required=True)
    compare.add_argument("--output", type=Path)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "build-manifest":
            expected = args.expected_checksum.strip().lower()
            _validate_checksum(expected, "expected checksum")
            actual = file_sha256(args.weights)
            if actual != expected:
                raise GateError("weight checksum does not match expected checksum")
            summary = load_json(args.summary)
            manifest = build_manifest(
                summary,
                summary_sha256=file_sha256(args.summary),
                weight_name=args.weights.name,
                weight_size=args.weights.stat().st_size,
                weight_checksum=actual,
                model_key=args.model_key.strip(),
                model_version=args.model_version.strip(),
                adapter_version=args.adapter_version.strip(),
            )
            validate_manifest(manifest, weights_path=args.weights, summary_path=args.summary)
            write_json(args.output, manifest)
            print(json.dumps({"status": "valid", "manifest": str(args.output), "release_id": manifest["release_id"]}))
            return 0
        if args.command == "validate-manifest":
            manifest = load_json(args.manifest)
            validate_manifest(manifest, weights_path=args.weights, summary_path=args.summary)
            print(json.dumps({"status": "valid", "release_id": manifest["release_id"]}))
            return 0
        if args.command == "create-baseline":
            summary = load_json(args.summary)
            baseline = create_baseline(summary, summary_sha256=file_sha256(args.summary))
            write_json(args.output, baseline, refuse_overwrite=True)
            print(json.dumps({"status": "created", "baseline": str(args.output)}))
            return 0
        summary = load_json(args.summary)
        baseline = load_json(args.baseline)
        report = compare_to_baseline(summary, baseline, current_summary_sha256=file_sha256(args.summary))
        if args.output:
            write_json(args.output, report)
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report["passed"] else 2
    except (GateError, OSError) as exception:
        print(json.dumps({"status": "failed", "error": str(exception)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
