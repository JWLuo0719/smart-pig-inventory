"""状态与趋势计算：把 DetectionResult 转成事件 state 块。"""
from __future__ import annotations

from .config import BarnConfig
from .detector import DetectionResult


def compute_state(
    detection: DetectionResult,
    barn: BarnConfig,
    previous: dict | None = None,
) -> dict:
    """pig_count 来自保留框数；密度按栏舍容量折算；trend 对比上一次观测。

    previous 是 observations 表里同栏舍最近一条记录的 payload（dict），
    由 storage.latest_observation 提供，首条观测时为 None。
    """
    count = detection.kept_count
    density: float | None = None
    if barn.capacity and barn.capacity > 0:
        density = round(min(1.0, count / barn.capacity), 4)

    trend = None
    if previous:
        prev_state = previous.get("state", {})
        prev_count = prev_state.get("pig_count")
        if isinstance(prev_count, int):
            trend = {
                "count_delta": count - prev_count,
                "previous_count": prev_count,
                "previous_captured_at": previous.get("captured_at"),
                "previous_created_at": previous.get("created_at"),
            }

    return {
        "pig_count": count,
        "density": density,
        "quality": {"status": detection.quality_status, "coverage": detection.coverage},
        "trend": trend,
    }


def quality_ok(state: dict, min_coverage: float | None) -> bool:
    """质量门：状态非 usable 或覆盖率不足都视为低质量（文档第 6 节）。"""
    quality = state.get("quality", {})
    if quality.get("status") != "usable":
        return False
    coverage = quality.get("coverage")
    if min_coverage is not None and coverage is not None and coverage < min_coverage:
        return False
    return True
