from copy import deepcopy
from pathlib import Path
import runpy

import pytest


MODULE = runpy.run_path(str(Path(__file__).parents[3] / "scripts" / "model_release_gate.py"))
GateError = MODULE["GateError"]
build_manifest = MODULE["build_manifest"]
compare_to_baseline = MODULE["compare_to_baseline"]
create_baseline = MODULE["create_baseline"]
validate_manifest = MODULE["validate_manifest"]
validate_regression_summary = MODULE["validate_regression_summary"]


def summary() -> dict:
    metrics = {
        "threshold": 0.6,
        "images": 10,
        "expected_total": 100,
        "predicted_total": 99,
        "mae": 0.5,
        "rmse": 0.7,
        "bias": -0.1,
        "wape": 0.03,
        "exact_rate": 0.6,
        "within_2_rate": 0.95,
        "max_absolute_error": 3,
    }
    return {
        "schema_version": 1,
        "threshold_selection": {
            "split": "val",
            "selected_threshold": 0.6,
            "validation_result": deepcopy(metrics),
        },
        "held_out_evaluation": {
            "split": "test",
            "threshold": 0.6,
            "result": deepcopy(metrics),
            "latency_ms": {"steady_wall_p95": 50.0, "throughput_images_per_second": 15.0},
        },
        "model": {
            "weight_file": "best.pt",
            "weight_sha256": "a" * 64,
            "image_size": 640,
            "iou_threshold": 0.7,
        },
        "runtime": {"python": "3.13", "torch": "test", "ultralytics": "test"},
    }


def manifest() -> dict:
    payload = summary()
    return build_manifest(
        payload,
        summary_sha256="b" * 64,
        weight_name="best.pt",
        weight_size=123,
        weight_checksum="a" * 64,
        model_key="pig-yolov13-research",
        model_version="candidate-v1",
        adapter_version="http-v1",
    )


def test_summary_rejects_test_split_threshold_selection() -> None:
    payload = summary()
    payload["threshold_selection"]["split"] = "test"

    with pytest.raises(GateError, match="validation split"):
        validate_regression_summary(payload)


def test_manifest_is_research_only_and_contains_no_artifact_path() -> None:
    payload = manifest()

    validate_manifest(payload)

    assert payload["artifact"]["file_name"] == "best.pt"
    assert payload["safety"]["model_approved"] is False
    assert payload["safety"]["automatic_counting_enabled"] is False
    assert payload["safety"]["manual_review_required"] is True


def test_manifest_rejects_approval_or_missing_blocker() -> None:
    payload = manifest()
    payload["safety"]["model_approved"] = True

    with pytest.raises(GateError, match="model_approved"):
        validate_manifest(payload)

    payload = manifest()
    payload["safety"]["blockers"].pop()
    with pytest.raises(GateError, match="every deferred approval"):
        validate_manifest(payload)


def test_manifest_rejects_artifact_path_or_checksum_mismatch() -> None:
    payload = manifest()
    payload["artifact"]["file_name"] = "external/best.pt"

    with pytest.raises(GateError, match="must not contain a path"):
        validate_manifest(payload)

    payload = manifest()
    payload["artifact"]["sha256"] = "c" * 64
    with pytest.raises(GateError, match="must match model identity"):
        validate_manifest(payload)


def test_same_summary_passes_immutable_baseline_comparison() -> None:
    payload = summary()
    baseline = create_baseline(payload, summary_sha256="d" * 64)

    report = compare_to_baseline(payload, baseline)

    assert report["passed"] is True
    assert report["violations"] == []


def test_metric_drift_and_model_change_fail_gate() -> None:
    payload = summary()
    baseline = create_baseline(payload, summary_sha256="d" * 64)
    changed = deepcopy(payload)
    changed["model"]["weight_sha256"] = "e" * 64
    changed["held_out_evaluation"]["result"]["mae"] = 0.8
    changed["held_out_evaluation"]["latency_ms"]["steady_wall_p95"] = 80.0

    report = compare_to_baseline(changed, baseline)

    assert report["passed"] is False
    codes = {violation["code"] for violation in report["violations"]}
    assert codes == {"MODEL_IDENTITY_CHANGED", "TEST_MAE_DRIFT", "STEADY_P95_REGRESSION"}
