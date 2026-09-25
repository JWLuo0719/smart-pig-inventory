"""三图（左/中/右）跨图同一头猪的去重内核。

现场用左/中/右三张照片覆盖一个栏舍，相邻两张照片在视野边缘存在重叠，同一头猪
可能同时出现在两张照片里。仓库不变量明确要求：在经验证的去重 Provider 存在前，
禁止把左/中/右结果直接相加（``AGENTS.md``、PRD 3.4.5、AC-08）。本模块就是该
Provider 的内核，并且刻意做成"显式、可配置、默认关闭"：

* 只使用检测框的几何信息，不引入未经验证的模型或权重；
* 必须显式提供相邻视图的重叠比例（``MULTIVIEW_VIEW_OVERLAP``），否则 Provider
  会失败关闭（``review_required`` 且数量为空），不会退化成简单相加；
* 只合并"落在相邻视图重叠带内、纵向位置与高度一致"的检测框，并保留每一次合并的
  双方框与代价，作为可复核的证据；
* 结果始终只是候选值，绝不自动成为已确认盘点数量。

已知边界：图像存在透视、猪只姿态变化、人工估计的重叠带不准时，仍可能漏配或误配。
因此重叠比例与三个容差都必须由现场标定给出，并且只在三张视图齐全时生效。
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import NamedTuple

from .geometry import bbox_center
from .schemas import Detection

VIEW_ORDER = ("left", "center", "right")

_LEFT_BAND = "left"
_RIGHT_BAND = "right"


@dataclass(frozen=True)
class MultiViewCalibration:
    """相邻视图重叠带的现场标定参数。

    ``overlap`` 是相邻两张照片在水平方向重叠的比例（占整幅宽度），必须由现场
    标定或拍摄规范确定；它没有安全的默认值，因此没有配置时调用方必须失败关闭。
    """

    overlap: float
    center_tolerance: float = 0.08
    height_tolerance: float = 0.35
    max_cost: float = 1.0

    def __post_init__(self) -> None:
        if not math.isfinite(self.overlap) or not 0 < self.overlap <= 0.5:
            raise ValueError("Multi-view overlap must be a fraction within (0, 0.5]")
        if not math.isfinite(self.center_tolerance) or not 0 < self.center_tolerance <= 0.5:
            raise ValueError("Multi-view center tolerance must be a fraction within (0, 0.5]")
        if not math.isfinite(self.height_tolerance) or not 0 < self.height_tolerance <= 1:
            raise ValueError("Multi-view height tolerance must be a fraction within (0, 1]")
        if not math.isfinite(self.max_cost) or not 0 < self.max_cost <= 2:
            raise ValueError("Multi-view match cost ceiling must be within (0, 2]")


class DuplicateDecision(NamedTuple):
    """一次跨图合并的证据：留下哪个框、去掉哪个框、匹配代价。"""

    kept_view: str
    removed_view: str
    kept_bbox: tuple[float, float, float, float]
    removed_bbox: tuple[float, float, float, float]
    cost: float


class DedupOutcome(NamedTuple):
    kept: tuple[Detection, ...]
    duplicates: tuple[DuplicateDecision, ...]
    warnings: tuple[str, ...]


class _BandEntry(NamedTuple):
    index: int
    center_x: float
    center_y: float
    height: float


def deduplicate_views(
    detections_by_view: Mapping[str, Sequence[Detection]],
    calibration: MultiViewCalibration,
) -> DedupOutcome:
    """合并相邻视图重叠带内重复出现的同一头猪。

    ``detections_by_view`` 缺少某个视图或该视图没有检测框都按"空"处理；是否允许
    缺视图由调用方（Provider）判定，本函数只负责几何合并。
    """

    removed_keys: set[tuple[str, int]] = set()
    duplicates: list[DuplicateDecision] = []

    for kept_view, removed_view in (("left", "center"), ("center", "right")):
        kept_entries = _overlap_band(
            detections_by_view.get(kept_view, ()), side=_RIGHT_BAND, overlap=calibration.overlap
        )
        removed_entries = _overlap_band(
            detections_by_view.get(removed_view, ()), side=_LEFT_BAND, overlap=calibration.overlap
        )
        removed_entries = [entry for entry in removed_entries if (removed_view, entry.index) not in removed_keys]
        kept_entries = [entry for entry in kept_entries if (kept_view, entry.index) not in removed_keys]
        detections = detections_by_view.get(kept_view, ())
        removed_detections = detections_by_view.get(removed_view, ())

        for kept_index, removed_index, cost in _match_bands(kept_entries, removed_entries, calibration):
            removed_keys.add((removed_view, removed_index))
            duplicates.append(
                DuplicateDecision(
                    kept_view=kept_view,
                    removed_view=removed_view,
                    kept_bbox=tuple(detections[kept_index].bbox),
                    removed_bbox=tuple(removed_detections[removed_index].bbox),
                    cost=cost,
                )
            )

    kept = tuple(
        detection
        for view in VIEW_ORDER
        for index, detection in enumerate(detections_by_view.get(view, ()))
        if (view, index) not in removed_keys
    )

    warnings: list[str] = []
    if duplicates:
        warnings.append(
            f"Removed {len(duplicates)} cross-view duplicate detection(s) inside the configured "
            f"{calibration.overlap:.0%} view overlap"
        )
    warnings.append(
        "Multi-view detections were merged with configured overlap calibration; "
        "the aggregated count remains a review candidate"
    )
    return DedupOutcome(kept=kept, duplicates=tuple(duplicates), warnings=tuple(warnings))


def _overlap_band(
    detections: Sequence[Detection],
    *,
    side: str,
    overlap: float,
) -> list[_BandEntry]:
    """取出落在相邻视图重叠带内（右视图左缘 / 左视图右缘）的检测框。"""

    entries: list[_BandEntry] = []
    for index, detection in enumerate(detections):
        center_x, center_y = bbox_center(detection.bbox)
        if side == _RIGHT_BAND and center_x < 1 - overlap:
            continue
        if side == _LEFT_BAND and center_x > overlap:
            continue
        entries.append(
            _BandEntry(
                index=index,
                center_x=center_x,
                center_y=center_y,
                height=detection.bbox[3] - detection.bbox[1],
            )
        )
    return entries


def _match_bands(
    kept_entries: Sequence[_BandEntry],
    removed_entries: Sequence[_BandEntry],
    calibration: MultiViewCalibration,
) -> list[tuple[int, int, float]]:
    """在重叠带内做一对一贪心匹配，代价越小越先配对。"""

    candidates: list[tuple[float, int, int]] = []
    for kept in kept_entries:
        for removed in removed_entries:
            vertical_gap = abs(kept.center_y - removed.center_y)
            if vertical_gap > calibration.center_tolerance:
                continue
            scale_gap = abs(kept.height - removed.height) / max(kept.height, removed.height, 1e-9)
            if scale_gap > calibration.height_tolerance:
                continue
            cost = vertical_gap / calibration.center_tolerance + scale_gap / calibration.height_tolerance
            if cost > calibration.max_cost:
                continue
            candidates.append((cost, kept.index, removed.index))

    candidates.sort()
    matched_kept: set[int] = set()
    matched_removed: set[int] = set()
    matches: list[tuple[int, int, float]] = []
    for cost, kept_index, removed_index in candidates:
        if kept_index in matched_kept or removed_index in matched_removed:
            continue
        matched_kept.add(kept_index)
        matched_removed.add(removed_index)
        matches.append((kept_index, removed_index, cost))
    return matches
