"""证据落盘：指标 JSON + 原图归档 + 标注图。

所有产物写入 data_dir/evidence/，事件 evidence 块记录相对路径
（如 "evidence/evt-xxx.json"），与文档 5.2 的契约一致。标注图依赖
Pillow（可选）：缺失时保留原图与指标 JSON，不阻塞分析主流程。
"""
from __future__ import annotations

from pathlib import Path
import json
import shutil

try:
    from PIL import Image, ImageDraw
    HAS_PIL = True
except ImportError:  # pragma: no cover - 部署环境可能不带 Pillow
    HAS_PIL = False

from .detector import DetectionResult
from .models import utc_now_iso

ALLOWED_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
# 可回放的证据产物后缀：归档/标注图片 + 指标 JSON（evidence 契约的一部分）。
# .db/.jsonl 等其余后缀一律拒绝，防止 /files/ 拖走整个事件库（检查报告 P0-5）。
ALLOWED_REPLAY_SUFFIXES = ALLOWED_IMAGE_SUFFIXES | {".json"}


class EvidenceStore:
    def __init__(self, data_dir: Path):
        self.root = Path(data_dir)
        self.evidence_dir = self.root / "evidence"
        self.evidence_dir.mkdir(parents=True, exist_ok=True)

    def save(
        self,
        event_id: str,
        detection: DetectionResult,
        state: dict,
        *,
        image: Path | bytes | None = None,
        image_name: str | None = None,
        risk: dict | None = None,
    ) -> dict:
        metrics_rel = f"evidence/{event_id}.json"
        metrics = {
            "event_id": event_id,
            "saved_at": utc_now_iso(),
            "detection": {
                "model_name": detection.model_name,
                "model_version": detection.model_version,
                "postprocess": detection.postprocess,
                "score_mode": detection.score_mode,
                "inference_ms": detection.inference_ms,
                "candidate_count": detection.candidate_count,
                "kept_count": detection.kept_count,
                "image_width": detection.image_width,
                "image_height": detection.image_height,
            },
            "boxes": detection.boxes,
            "scores": detection.scores,
            "state": state,
            "risk": risk or {},
        }
        (self.root / metrics_rel).write_text(
            json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8"
        )

        image_rel: str | None = None
        archived: Path | None = None
        if isinstance(image, (bytes, bytearray)):
            suffix = Path(image_name or "upload.jpg").suffix.lower()
            if suffix in ALLOWED_IMAGE_SUFFIXES:
                image_rel = f"evidence/{event_id}{suffix}"
                target = self.root / image_rel
                target.write_bytes(bytes(image))
                archived = target
        elif image is not None and Path(image).exists():
            src = Path(image)
            if src.suffix.lower() in ALLOWED_IMAGE_SUFFIXES:
                image_rel = f"evidence/{event_id}{src.suffix.lower()}"
                target = self.root / image_rel
                shutil.copyfile(src, target)
                archived = target

        annotated_rel: str | None = None
        if archived is not None and HAS_PIL and detection.boxes:
            annotated_rel = self._annotate(archived, event_id, detection)

        return {"image": image_rel, "metrics": metrics_rel, "annotated": annotated_rel}

    def resolve(self, rel_path: str) -> Path | None:
        """把事件里的相对证据路径解析为绝对路径（用于 HTTP 静态回放）。

        只允许回放 evidence/ 之下的证据产物：包含性校验对 evidence_dir（而非
        data_dir）做，后缀限定为图片与指标 JSON。agent.db、events.jsonl 之类
        的敏感文件即使位于 data_dir 内也不可经 /files/ 取回（检查报告 P0-5）。
        """
        candidate = (self.root / rel_path).resolve()
        try:
            rel = candidate.relative_to(self.evidence_dir.resolve())
        except ValueError:
            return None
        if rel == Path("."):
            return None
        if candidate.suffix.lower() not in ALLOWED_REPLAY_SUFFIXES:
            return None
        return candidate if candidate.exists() else None

    def _annotate(self, archived: Path, event_id: str, detection: DetectionResult) -> str | None:
        try:
            with Image.open(archived) as img:
                canvas = img.convert("RGB")
                scale_x = img.width / max(1, detection.image_width)
                scale_y = img.height / max(1, detection.image_height)
                draw = ImageDraw.Draw(canvas)
                for box, score in zip(detection.boxes, detection.scores):
                    x1, y1, x2, y2 = box
                    rect = [
                        x1 * scale_x, y1 * scale_y, x2 * scale_x, y2 * scale_y,
                    ]
                    draw.rectangle(rect, outline=(220, 38, 38), width=3)
                    draw.text((rect[0] + 2, max(0, rect[1] - 14)), f"{score:.2f}", fill=(220, 38, 38))
                rel = f"evidence/{event_id}_annotated.jpg"
                canvas.save(self.root / rel, "JPEG", quality=90)
                return rel
        except Exception:
            return None
