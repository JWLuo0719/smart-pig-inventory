# -*- coding: utf-8 -*-
"""预标注：用现有 DCR-SoftNMS-YOLOv13 ONNX 为新场景数据集生成 YOLO 预标注。

输出 D:/newdataset/prelabel/：
  labels/0301、labels/0302   每图一个 YOLO txt（class cx cy w h，归一化）
  classes.txt                类别表（单类 pig）
  prelabel_stats.csv         每图检出数/最低置信度（供人工按图排优先级）
  data.yaml                  ultralytics 训练配置（0301=train 池，0302=val）

阈值取 0.15（低于产品 0.25）：预标注宁可多给候选框让人删，避免整头漏检。
"""
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import numpy as np
import cv2

from pig_farm_agent.detector import OnnxDetector

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "model_artifacts" / "dcr-softnms-yolov13-v1"
DATASET = Path("D:/newdataset")
OUT = Path("D:/newdataset/prelabel")
CONF = 0.15

BATCHES = {
    "0301": (DATASET / "3月1日1-3栋大猪图片 (1)", "train"),
    "0302": (DATASET / "3月2日1栋大猪图片(可以作为验证)", "val"),
}

manifest = json.loads((MODEL_DIR / "manifest.json").read_text(encoding="utf-8"))
detector = OnnxDetector(MODEL_DIR, manifest, conf_thres=CONF)

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "classes.txt").write_text("pig\n", encoding="utf-8")
stats_rows = []
done = 0
for tag, (folder, split) in BATCHES.items():
    labels_dir = OUT / "labels" / tag
    labels_dir.mkdir(parents=True, exist_ok=True)
    images = sorted(p for p in folder.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    for index, image_path in enumerate(images):
        try:
            result = detector.predict(str(image_path), request_id=f"prelabel-{tag}-{index}")
        except Exception as exc:  # 坏图跳过并记录，不中断整批
            stats_rows.append({"batch": tag, "file": image_path.name, "count": -1,
                               "min_conf": "", "error": str(exc)[:120]})
            continue
        width, height = result.image_width, result.image_height
        lines = []
        for box in result.boxes:
            x1 = min(max(box[0], 0.0), width)
            y1 = min(max(box[1], 0.0), height)
            x2 = min(max(box[2], 0.0), width)
            y2 = min(max(box[3], 0.0), height)
            if x2 - x1 < 2 or y2 - y1 < 2:
                continue
            cx, cy = (x1 + x2) / 2 / width, (y1 + y2) / 2 / height
            bw, bh = (x2 - x1) / width, (y2 - y1) / height
            lines.append(f"0 {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}")
        (labels_dir / f"{image_path.stem}.txt").write_text("\n".join(lines) + ("\n" if lines else ""),
                                                           encoding="utf-8")
        stats_rows.append({"batch": tag, "file": image_path.name, "count": len(lines),
                           "min_conf": round(min(result.scores), 3) if result.scores else 0.0,
                           "error": ""})
        done += 1
        if done % 40 == 0:
            print(f"进度 {done} 张", flush=True)

with (OUT / "prelabel_stats.csv").open("w", newline="", encoding="utf-8-sig") as handle:
    writer = csv.DictWriter(handle, fieldnames=["batch", "file", "count", "min_conf", "error"])
    writer.writeheader()
    writer.writerows(stats_rows)

(OUT / "data.yaml").write_text(
    f"path: D:/newdataset/prelabel\n"
    f"train: images/train\n"
    f"val: images/val\n"
    f"names:\n  0: pig\n", encoding="utf-8")

(OUT / "README.md").write_text("""# 预标注使用说明（给标注同学）

这些 txt 是旧模型自动打的"草稿框"，**必须人工修正后才能用于训练**，重点三类：

1. **补漏**：离镜头近的大猪、栏杆后面的猪经常整头漏掉——逐头核对，缺的画上；
2. **删误检**：空地板、栏杆上偶尔有假框——直接删；
3. **贴齐**：框只需贴住猪的身体边界，贴边猪的框贴到图片边缘即可。

## 工具（二选一）
- X-AnyLabeling：打开文件 -> 导入 YOLO 标签，选 prelabel/classes.txt 和 images 目录
- labelImg：打开目录选图片目录，"Change Save Dir" 到对应 labels 目录，格式选 YOLO

## 目录
- images/0301（训练池）、images/0302（验证集，按批次隔离，勿混）
- 标注保存在 labels/0301、labels/0302，与图片同名 .txt

## 训练目录
确认标注完成后，把图片复制/链接到 images/train 与 images/val（与 labels 同名对应），
data.yaml 已按此写好。
""", encoding="utf-8")

counts = [row["count"] for row in stats_rows if row["count"] >= 0]
print(json.dumps({
    "完成": done, "失败": sum(1 for r in stats_rows if r["error"]),
    "检出数_最小": min(counts), "检出数_最大": max(counts),
    "检出数_均值": round(sum(counts) / len(counts), 1),
    "输出目录": str(OUT),
}, ensure_ascii=False))
