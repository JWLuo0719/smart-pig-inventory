"""视频抽帧计数的产品侧聚合内核。

架构边界：抽帧、逐帧检测与跨帧跟踪都在产品仓库之外的 Runner 中完成
（``AGENTS.md``：模型研究仓库保持独立，产品代码只通过版本化 Provider 契约通信）。
本模块只负责把 Runner 返回的、带 ``track_id`` 的逐帧检测聚合成"这一栏有多少头猪"，
并保证任何无法证明跨帧身份的情况都失败关闭。

计数口径：一栏猪的数量 = 不同 ``track_id`` 的个数；同一头猪出现在多少帧里都只算一头。

失败关闭规则：

* 任一检测框缺少 ``track_id`` → 无法证明跨帧身份，不产生数量（保留检测框作证据）；
* 完全没有检测框 → 可能是空栏，也可能是抽帧失败，交人工判断，不产生数量；
* 观测帧数少于阈值的轨迹按配置丢弃，并在 ``warnings`` 中说明，避免把单帧噪声算成猪。

视频证据在合同上不允许携带 ROI（``ManifestAsset``），因此本模块不做区域过滤。
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Sequence
from typing import NamedTuple

from .schemas import Detection


class TrackOutcome(NamedTuple):
    count: int | None
    kept: tuple[Detection, ...]
    dropped_track_ids: tuple[str, ...]
    warnings: tuple[str, ...]


def aggregate_tracks(
    detections: Sequence[Detection],
    *,
    min_observations: int = 1,
) -> TrackOutcome:
    """把逐帧检测聚合成去重后的猪只数量。"""

    if min_observations < 1:
        raise ValueError("Video track minimum observations must be at least 1")
    if not detections:
        return TrackOutcome(
            count=None,
            kept=(),
            dropped_track_ids=(),
            warnings=(
                "Video evidence produced no detections at all; no count is produced",
            ),
        )
    if any(not detection.track_id for detection in detections):
        return TrackOutcome(
            count=None,
            kept=tuple(detections),
            dropped_track_ids=(),
            warnings=(
                "Video counting requires a track identity for every detection; "
                "the runner did not provide one, so detections stay as evidence without a count",
            ),
        )

    observations = Counter(detection.track_id for detection in detections)
    dropped = tuple(sorted(track for track, seen in observations.items() if seen < min_observations))
    kept = tuple(detection for detection in detections if detection.track_id not in dropped)

    warnings: list[str] = []
    if dropped:
        warnings.append(
            f"Dropped {len(dropped)} video track(s) observed in fewer than {min_observations} frame(s)"
        )
    warnings.append("Video count is the number of distinct tracked pigs and remains a review candidate")
    return TrackOutcome(
        count=len({detection.track_id for detection in kept}),
        kept=kept,
        dropped_track_ids=dropped,
        warnings=tuple(warnings),
    )
