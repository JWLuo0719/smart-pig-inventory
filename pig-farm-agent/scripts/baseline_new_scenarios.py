# -*- coding: utf-8 -*-
"""基线评测：现有 DCR-SoftNMS-YOLOv13 ONNX 在新场景数据集上的表现。

用法：/d/CondaEnvs/pig-agent/python.exe scripts/baseline_new_scenarios.py
输出：每张抽样图的检出数/置信度统计（JSON）+ 6 张带框可视化，供人工目检。
"""
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cv2

from pig_farm_agent.detector import OnnxDetector

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "model_artifacts" / "dcr-softnms-yolov13-v1"
DATASET = Path("D:/newdataset")
OUT = Path(r"C:\Users\Lenovo\AppData\Local\Temp\baseline_vis")
OUT.mkdir(parents=True, exist_ok=True)

BATCHES = {
    "0301": DATASET / "3月1日1-3栋大猪图片 (1)",
    "0302": DATASET / "3月2日1栋大猪图片(可以作为验证)",
}

manifest = json.loads((MODEL_DIR / "manifest.json").read_text(encoding="utf-8"))
detector = OnnxDetector(MODEL_DIR, manifest)

random.seed(42)
report = {"model": str(MODEL_DIR.name), "samples": []}
vis_targets = {}
for tag, folder in BATCHES.items():
    images = sorted([p for p in folder.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")])
    sample = random.sample(images, min(20, len(images)))
    for index, image_path in enumerate(sample):
        result = detector.predict(str(image_path), request_id=f"baseline-{tag}-{index}")
        scores = result.scores
        report["samples"].append({
            "batch": tag,
            "file": image_path.name,
            "count": result.kept_count,
            "mean_conf": round(sum(scores) / len(scores), 3) if scores else 0.0,
            "min_conf": round(min(scores), 3) if scores else 0.0,
        })
        if tag not in vis_targets:
            vis_targets[tag] = []
        if len(vis_targets[tag]) < 3 and index % 7 == 0:
            vis_targets[tag].append((image_path, result))

for tag, items in vis_targets.items():
    for order, (image_path, result) in enumerate(items):
        raw = __import__("numpy").fromfile(str(image_path), dtype="uint8")
        image = cv2.imdecode(raw, cv2.IMREAD_COLOR)
        for box, score in zip(result.boxes, result.scores):
            x1, y1, x2, y2 = [int(round(v)) for v in box]
            cv2.rectangle(image, (x1, y1), (x2, y2), (0, 160, 255), 3)
        target = OUT / f"{tag}_{order}_{result.kept_count}头_{image_path.stem[:16]}.jpg"
        scale = 1400 / max(image.shape[:2])
        if scale < 1:
            image = cv2.resize(image, None, fx=scale, fy=scale)
        cv2.imwrite(str(target), image)

counts = [s["count"] for s in report["samples"]]
report["summary"] = {
    "n": len(counts),
    "count_min": min(counts),
    "count_max": max(counts),
    "count_mean": round(sum(counts) / len(counts), 1),
    "zero_detection_images": sum(1 for c in counts if c == 0),
    "mean_conf_overall": round(sum(s["mean_conf"] for s in report["samples"]) / len(report["samples"]), 3),
}
(OUT / "baseline_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report["summary"], ensure_ascii=False))
for s in report["samples"]:
    print(s["batch"], s["file"][:30], "检出:", s["count"], "均置信:", s["mean_conf"])
