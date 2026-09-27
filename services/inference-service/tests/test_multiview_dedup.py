"""跨图去重与栏舍归属判定的单元测试。

这两块是"三图同猪不重复"和"邻栏不计入本栏"的算法内核，不依赖网络或模型，
因此可以直接做确定性的边界测试。
"""

import json
from pathlib import Path
from uuid import uuid4

import pytest

from app.geometry import (
    MAX_EXCLUSIONS,
    ROI_KEYS,
    PenRoi,
    Region,
    RegionError,
    bbox_center,
    containment_ratio,
    parse_pen_roi,
    parse_region,
)
from app.multiview import MultiViewCalibration, deduplicate_views
from app.schemas import Detection


def test_roi_extension_matches_the_versioned_contract() -> None:
    """契约先行：Python 解析的字段集合必须与版本化 schema 完全一致。"""

    schema_path = Path(__file__).parents[3] / "contracts" / "inference-job.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    roi = schema["properties"]["media"]["items"]["properties"]["roi"]

    assert roi["additionalProperties"] is False
    assert set(roi["properties"]) == set(ROI_KEYS)
    assert roi["properties"]["exclusions"]["maxItems"] == MAX_EXCLUSIONS
    assert schema["$defs"]["normalizedRect"]["required"] == ["x", "y", "width", "height"]


def detection(bbox: tuple[float, float, float, float], asset_id=None) -> Detection:
    return Detection(
        asset_id=asset_id or uuid4(),
        bbox=bbox,
        confidence=0.9,
        class_id=0,
    )


# --- 区域解析与归属判定 -------------------------------------------------------


def test_parse_pen_roi_defaults_to_the_whole_image() -> None:
    assert parse_pen_roi(None) is None


def test_parse_pen_roi_keeps_the_legacy_center_point_behaviour() -> None:
    roi = parse_pen_roi({"x": 0.2, "y": 0.2, "width": 0.4, "height": 0.4})

    assert roi == PenRoi(include=Region(0.2, 0.2, 0.4, 0.4), exclusions=(), min_containment=0.0)
    # 历史口径：闭区间以框中心点判定。
    assert roi.admits((0.2, 0.2, 0.3, 0.3)) is True
    assert roi.admits((0.59, 0.59, 0.61, 0.61)) is True
    assert roi.admits((0.61, 0.61, 0.63, 0.63)) is False


def test_parse_pen_roi_reads_exclusion_regions_and_min_containment() -> None:
    roi = parse_pen_roi(
        {
            "x": 0.0,
            "y": 0.0,
            "width": 1.0,
            "height": 1.0,
            "exclusions": [{"x": 0.8, "y": 0.0, "width": 0.2, "height": 1.0}],
            "minContainment": 0.6,
        }
    )

    assert roi is not None
    assert roi.exclusions == (Region(0.8, 0.0, 0.2, 1.0),)
    assert roi.min_containment == 0.6


def test_neighbour_pen_exclusion_removes_a_detection_inside_it() -> None:
    """需求第 7 条：隔壁栏舍的猪不能计入本栏舍。"""

    roi = parse_pen_roi(
        {
            "x": 0.0,
            "y": 0.0,
            "width": 1.0,
            "height": 1.0,
            "exclusions": [
                {"x": 0.75, "y": 0.0, "width": 0.25, "height": 1.0},
                {"x": 0.0, "y": 0.0, "width": 0.25, "height": 1.0},
            ],
        }
    )

    assert roi is not None
    assert roi.admits((0.30, 0.40, 0.50, 0.60)) is True       # 本栏中间，计入
    assert roi.admits((0.80, 0.40, 0.95, 0.60)) is False      # 右侧邻栏，剔除
    assert roi.admits((0.05, 0.40, 0.20, 0.60)) is False      # 左侧邻栏，剔除


def test_min_containment_rejects_a_pig_that_is_mostly_in_the_neighbour_pen() -> None:
    roi = parse_pen_roi(
        {"x": 0.0, "y": 0.0, "width": 0.5, "height": 1.0, "minContainment": 0.6}
    )

    assert roi is not None
    # 中心点仍在有效区内（历史口径会放行），但只有 1/3 的框面积落在本栏。
    mostly_outside = (0.40, 0.40, 0.70, 0.60)
    assert 0.0 < containment_ratio(mostly_outside, roi.include) < 0.6
    assert roi.admits(mostly_outside) is False
    assert roi.admits((0.10, 0.40, 0.40, 0.60)) is True


def test_containment_ratio_ignores_degenerate_boxes() -> None:
    region = Region(0.0, 0.0, 0.5, 0.5)

    assert containment_ratio((0.2, 0.2, 0.2, 0.2), region) == 0.0
    assert containment_ratio((0.0, 0.0, 0.5, 0.5), region) == pytest.approx(1.0)
    assert containment_ratio((-1.0, -1.0, 5.0, 5.0), region) == pytest.approx(0.25 / 36.0)


@pytest.mark.parametrize(
    "raw",
    [
        {"x": 0.1, "y": 0.1, "width": 0.2},                                        # 缺字段
        {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2, "label": "pen"},         # 多余字段
        {"x": -0.1, "y": 0.1, "width": 0.2, "height": 0.2},                        # 越界
        {"x": 0.9, "y": 0.1, "width": 0.2, "height": 0.2},                         # x+width>1
        {"x": 0.1, "y": 0.1, "width": 0.0, "height": 0.2},                         # 非正宽度
        {"x": "0.1", "y": 0.1, "width": 0.2, "height": 0.2},                       # 非数值
    ],
)
def test_parse_region_fails_closed_on_contract_violations(raw) -> None:
    with pytest.raises(RegionError):
        parse_region(raw, label="roi")


def test_parse_pen_roi_rejects_unbounded_exclusions_and_bad_thresholds() -> None:
    too_many = [{"x": 0.0, "y": 0.0, "width": 0.1, "height": 0.1}] * (MAX_EXCLUSIONS + 1)

    with pytest.raises(RegionError):
        parse_pen_roi({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0, "exclusions": too_many})
    with pytest.raises(RegionError):
        parse_pen_roi({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0, "exclusions": "none"})
    with pytest.raises(RegionError):
        parse_pen_roi({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0, "minContainment": 1.5})
    with pytest.raises(RegionError):
        parse_pen_roi({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0, "minContainment": "high"})
    with pytest.raises(RegionError):
        parse_pen_roi({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0, "unknown": 1})


def test_bbox_center_uses_the_box_middle() -> None:
    assert bbox_center((0.1, 0.2, 0.3, 0.6)) == pytest.approx((0.2, 0.4))


# --- 三图跨图去重 -------------------------------------------------------------


def test_calibration_requires_a_real_overlap_fraction() -> None:
    assert MultiViewCalibration(overlap=0.2).overlap == 0.2

    for invalid in (0.0, -0.1, 0.51, float("nan")):
        with pytest.raises(ValueError):
            MultiViewCalibration(overlap=invalid)
    with pytest.raises(ValueError):
        MultiViewCalibration(overlap=0.2, center_tolerance=0.0)
    with pytest.raises(ValueError):
        MultiViewCalibration(overlap=0.2, height_tolerance=1.5)
    with pytest.raises(ValueError):
        MultiViewCalibration(overlap=0.2, max_cost=3.0)


def test_pig_seen_in_two_overlapping_views_is_counted_once() -> None:
    calibration = MultiViewCalibration(overlap=0.2)
    # 同一头猪：位于左图右缘（中心 0.95）与中图左缘（中心 0.05），高度一致。
    left = [detection((0.90, 0.30, 1.00, 0.50))]
    center = [detection((0.00, 0.30, 0.10, 0.50))]
    right: list[Detection] = []

    outcome = deduplicate_views({"left": left, "center": center, "right": right}, calibration)

    assert len(outcome.kept) == 1
    assert outcome.kept[0].bbox == (0.90, 0.30, 1.00, 0.50)
    assert len(outcome.duplicates) == 1
    assert outcome.duplicates[0].kept_view == "left"
    assert outcome.duplicates[0].removed_view == "center"
    assert outcome.duplicates[0].cost == pytest.approx(0.0)


def test_two_pigs_stay_two_pigs_across_three_views() -> None:
    """左/中/右各一头不同的猪，既不能相加成三头，也不能被误合并。"""

    calibration = MultiViewCalibration(overlap=0.2)
    left = [detection((0.40, 0.30, 0.50, 0.50))]
    center = [detection((0.45, 0.30, 0.55, 0.50))]
    right = [detection((0.80, 0.30, 0.90, 0.50))]

    outcome = deduplicate_views({"left": left, "center": center, "right": right}, calibration)

    assert len(outcome.kept) == 3
    assert outcome.duplicates == ()


def test_detections_in_the_overlap_band_with_different_height_are_kept() -> None:
    calibration = MultiViewCalibration(overlap=0.2)
    left = [detection((0.90, 0.30, 1.00, 0.60))]
    center = [detection((0.00, 0.30, 0.10, 0.38))]  # 明显更小，判定为不同的猪

    outcome = deduplicate_views({"left": left, "center": center, "right": []}, calibration)

    assert len(outcome.kept) == 2
    assert outcome.duplicates == ()


def test_vertical_offset_beyond_tolerance_is_not_merged() -> None:
    calibration = MultiViewCalibration(overlap=0.2)
    left = [detection((0.90, 0.10, 1.00, 0.30))]
    center = [detection((0.00, 0.60, 0.10, 0.80))]

    outcome = deduplicate_views({"left": left, "center": center, "right": []}, calibration)

    assert len(outcome.kept) == 2


def test_matching_is_one_to_one_across_the_overlap_band() -> None:
    calibration = MultiViewCalibration(overlap=0.2)
    # 左图重叠带有两头猪，中图重叠带只有一头：只能合并一头。
    left = [detection((0.90, 0.30, 1.00, 0.50)), detection((0.90, 0.60, 1.00, 0.80))]
    center = [detection((0.00, 0.30, 0.10, 0.50))]

    outcome = deduplicate_views({"left": left, "center": center, "right": []}, calibration)

    assert len(outcome.kept) == 2
    assert len(outcome.duplicates) == 1


def test_center_view_can_pair_with_both_neighbours() -> None:
    calibration = MultiViewCalibration(overlap=0.2)
    left = [detection((0.90, 0.30, 1.00, 0.50))]
    center = [detection((0.00, 0.30, 0.10, 0.50)), detection((0.90, 0.30, 1.00, 0.50))]
    right = [detection((0.00, 0.30, 0.10, 0.50))]

    outcome = deduplicate_views({"left": left, "center": center, "right": right}, calibration)

    # 一头猪出现在左+中，另一头出现在中+右：合计两头。
    assert len(outcome.kept) == 2
    assert {decision.removed_view for decision in outcome.duplicates} == {"center", "right"}


def test_dedup_warnings_state_the_aggregation_basis() -> None:
    calibration = MultiViewCalibration(overlap=0.25)
    left = [detection((0.80, 0.30, 1.00, 0.50))]
    center = [detection((0.00, 0.30, 0.20, 0.50))]

    outcome = deduplicate_views({"left": left, "center": center, "right": []}, calibration)

    assert any("cross-view duplicate" in warning for warning in outcome.warnings)
    assert any("review candidate" in warning for warning in outcome.warnings)


def test_missing_views_are_treated_as_empty_for_geometry_only() -> None:
    calibration = MultiViewCalibration(overlap=0.2)

    outcome = deduplicate_views({}, calibration)

    assert outcome.kept == ()
    assert outcome.duplicates == ()
