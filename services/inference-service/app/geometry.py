"""归一化区域解析与"这一头猪是否属于本栏"的判定。

本模块是纯函数实现：不依赖网络、模型、数据库或 Web 框架，便于独立测试。
契约来源：``contracts/openapi.yaml`` 的 ``Roi``/``RoiRegion`` 与
``contracts/inference-job.schema.json`` 中 ``media[].roi``。

判定口径按优先级依次为：

1. 检测框中心点必须落在有效区内（历史口径，保持向后兼容）；
2. 中心点落在任一排除区（邻栏、料槽、走道等）内时不计入本栏；
3. 配置了 ``minContainment`` 时，检测框与有效区的交叠面积占比必须达到阈值，
   用于排除"半身在邻栏"的目标。

任何与契约不符的 ROI 结构都会抛出 :class:`RegionError`。它继承 ``ValueError``，
因此会被 ``app.tasks.classify_provider_failure`` 归类为 ``PROVIDER_CONTRACT_ERROR``，
以失败关闭（fail-closed）而不是按"没有 ROI"静默放行。
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from typing import Any, NamedTuple

MAX_EXCLUSIONS = 8

_RECT_KEYS = ("x", "y", "width", "height")

# ``roi`` 允许出现的字段，与 contracts/inference-job.schema.json 的 roi.properties 一一对应。
ROI_KEYS = frozenset({*_RECT_KEYS, "exclusions", "minContainment"})


class RegionError(ValueError):
    """ROI 结构与版本化契约不符。"""


class Region(NamedTuple):
    """归一化 xywh 矩形（原点在左上角，取值 0..1）。"""

    x: float
    y: float
    width: float
    height: float

    @property
    def right(self) -> float:
        return self.x + self.width

    @property
    def bottom(self) -> float:
        return self.y + self.height

    @property
    def area(self) -> float:
        return self.width * self.height

    def contains_point(self, point_x: float, point_y: float) -> bool:
        """闭区间判定，与既往"框中心点落入有效区"的口径完全一致。"""

        return self.x <= point_x <= self.right and self.y <= point_y <= self.bottom


class PenRoi(NamedTuple):
    """一个栏舍在单张图像上的归属规则：有效区 + 排除区 + 最小包含比例。"""

    include: Region
    exclusions: tuple[Region, ...] = ()
    min_containment: float = 0.0

    def admits(self, bbox: Sequence[float]) -> bool:
        """判断一个归一化 xyxy 检测框是否计入本栏。"""

        center_x, center_y = bbox_center(bbox)
        if not self.include.contains_point(center_x, center_y):
            return False
        if any(region.contains_point(center_x, center_y) for region in self.exclusions):
            return False
        if self.min_containment > 0 and containment_ratio(bbox, self.include) < self.min_containment:
            return False
        return True


def bbox_center(bbox: Sequence[float]) -> tuple[float, float]:
    return ((bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2)


def intersection_area(bbox: Sequence[float], region: Region) -> float:
    """归一化 xyxy 检测框与归一化 xywh 区域的交叠面积。"""

    left = max(bbox[0], region.x)
    top = max(bbox[1], region.y)
    right = min(bbox[2], region.right)
    bottom = min(bbox[3], region.bottom)
    if right <= left or bottom <= top:
        return 0.0
    return (right - left) * (bottom - top)


def containment_ratio(bbox: Sequence[float], region: Region) -> float:
    """检测框落在指定区域内的面积占检测框自身面积的比例（0..1）。"""

    box_area = max(0.0, bbox[2] - bbox[0]) * max(0.0, bbox[3] - bbox[1])
    if box_area <= 0:
        return 0.0
    return intersection_area(bbox, region) / box_area


def parse_region(raw: Any, *, label: str) -> Region:
    """严格解析一个归一化矩形；任何越界、缺字段或多余字段都视为契约错误。"""

    if not isinstance(raw, Mapping):
        raise RegionError(f"{label} must be an object")
    unknown = sorted(set(raw) - set(_RECT_KEYS))
    if unknown:
        raise RegionError(f"{label} contains a field that is not in the contract: {', '.join(unknown)}")
    missing = [key for key in _RECT_KEYS if key not in raw]
    if missing:
        raise RegionError(f"{label} is missing required field(s): {', '.join(missing)}")

    coordinates: dict[str, float] = {}
    for key in _RECT_KEYS:
        value = raw[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise RegionError(f"{label}.{key} must be a finite number")
        coordinates[key] = float(value)

    region = Region(**coordinates)
    if (
        region.x < 0
        or region.y < 0
        or region.width <= 0
        or region.height <= 0
        or region.right > 1
        or region.bottom > 1
    ):
        raise RegionError(f"{label} must stay inside normalized image bounds")
    return region


def parse_pen_roi(raw: Any) -> PenRoi | None:
    """把 ``media[].roi`` 解析成归属规则；``None`` 表示整张图像都算本栏。"""

    if raw is None:
        return None
    if not isinstance(raw, Mapping):
        raise RegionError("roi must be an object or null")
    unknown = sorted(set(raw) - ROI_KEYS)
    if unknown:
        raise RegionError(f"roi contains a field that is not in the contract: {', '.join(unknown)}")

    include = parse_region({key: raw[key] for key in _RECT_KEYS if key in raw}, label="roi")

    raw_exclusions = raw.get("exclusions")
    if raw_exclusions is None:
        raw_exclusions = ()
    if isinstance(raw_exclusions, (str, bytes)) or not isinstance(raw_exclusions, (list, tuple)):
        raise RegionError("roi.exclusions must be an array")
    if len(raw_exclusions) > MAX_EXCLUSIONS:
        raise RegionError(f"roi.exclusions must not contain more than {MAX_EXCLUSIONS} regions")
    exclusions = tuple(
        parse_region(item, label=f"roi.exclusions[{index}]") for index, item in enumerate(raw_exclusions)
    )

    raw_min_containment = raw.get("minContainment")
    if raw_min_containment is None:
        raw_min_containment = 0.0
    if (
        isinstance(raw_min_containment, bool)
        or not isinstance(raw_min_containment, (int, float))
        or not math.isfinite(float(raw_min_containment))
    ):
        raise RegionError("roi.minContainment must be a finite number")
    min_containment = float(raw_min_containment)
    if not 0 <= min_containment <= 1:
        raise RegionError("roi.minContainment must be within 0..1")

    return PenRoi(include=include, exclusions=exclusions, min_containment=min_containment)
