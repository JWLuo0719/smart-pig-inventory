from pathlib import Path
import runpy

import pytest


MODULE = runpy.run_path(str(Path(__file__).parents[3] / "scripts" / "evaluate_yolo_counting.py"))
ImageEvaluation = MODULE["ImageEvaluation"]
build_report = MODULE["build_report"]
count_yolo_labels = MODULE["count_yolo_labels"]
parse_thresholds = MODULE["parse_thresholds"]
summarize_threshold = MODULE["summarize_threshold"]


def test_threshold_metrics_are_recalculated_without_rerunning_inference() -> None:
    records = [
        ImageEvaluation("one.jpg", 2, (0.9, 0.6, 0.4), 10.0, 8.0),
        ImageEvaluation("two.jpg", 1, (0.8,), 20.0, 18.0),
    ]

    at_half = summarize_threshold(records, 0.5)
    at_seven_tenths = summarize_threshold(records, 0.7)

    assert at_half["predicted_total"] == 3
    assert at_half["mae"] == 0
    assert at_half["wape"] == 0
    assert at_seven_tenths["predicted_total"] == 2
    assert at_seven_tenths["mae"] == 0.5
    assert at_seven_tenths["bias"] == -0.5


def test_report_selects_lowest_mae_then_lowest_bias_and_threshold() -> None:
    records = [ImageEvaluation("one.jpg", 1, (0.9, 0.6), 10.0, 8.0)]

    report = build_report(
        records,
        (0.5, 0.7),
        split="test",
        class_id=0,
        weight_name="best.pt",
        weight_checksum="a" * 64,
        image_size=640,
        device="cpu",
        iou_threshold=0.7,
    )

    assert report["lowest_mae_observed_in_split"]["threshold"] == 0.7
    assert report["latency_ms"]["cold_first_wall"] == 10.0
    assert report["latency_ms"]["wall_p95"] == 10.0
    assert report["latency_ms"]["steady_wall_mean"] == 10.0
    assert report["per_image"][0]["candidate_counts"] == {"0.5": 2, "0.7": 1}


def test_label_parser_counts_only_requested_class_and_rejects_bad_rows(tmp_path: Path) -> None:
    label = tmp_path / "sample.txt"
    label.write_text("0 0.5 0.5 0.1 0.1\n1 0.4 0.4 0.2 0.2\n", encoding="utf-8")

    assert count_yolo_labels(label, 0) == 1

    label.write_text("0 1.5 0.5 0.1 0.1\n", encoding="utf-8")
    with pytest.raises(ValueError, match="range"):
        count_yolo_labels(label, 0)

    label.write_text("-1 0.5 0.5 0.1 0.1\n", encoding="utf-8")
    with pytest.raises(ValueError, match="negative class id"):
        count_yolo_labels(label, 0)


def test_threshold_parser_deduplicates_and_validates() -> None:
    assert parse_thresholds("0.6,0.25,0.6") == (0.25, 0.6)
    with pytest.raises(ValueError, match="between 0 and 1"):
        parse_thresholds("1.1")
