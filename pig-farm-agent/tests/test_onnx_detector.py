from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np

from pig_farm_agent.detector import decode_onnx_output

try:
    import onnxruntime  # noqa: F401
    HAS_ORT = True
except ImportError:
    HAS_ORT = False

from .helpers import PROJECT_ROOT

ARTIFACT_DIR = PROJECT_ROOT / "model_artifacts" / "dcr-softnms-yolov13-v1"


class TestDecodeOnnxOutput(unittest.TestCase):
    def test_coordinate_restore(self):
        # 原图 1280x960 -> letterbox 到 640x640：scale=0.5，水平不填充，垂直 pad_y=80
        output = np.array([[[320.0], [320.0], [100.0], [50.0], [0.9]]], dtype=np.float32)  # (1,5,1)
        boxes, scores = decode_onnx_output(output, scale=0.5, pad_x=0.0, pad_y=80.0, conf_thres=0.25)
        self.assertEqual(len(boxes), 1)
        x1, y1, x2, y2 = boxes[0]
        self.assertAlmostEqual(x1, (320 - 50 - 0) / 0.5, places=1)
        self.assertAlmostEqual(y1, (320 - 25 - 80) / 0.5, places=1)
        self.assertAlmostEqual(x2, (320 + 50 - 0) / 0.5, places=1)
        self.assertAlmostEqual(y2, (320 + 25 - 80) / 0.5, places=1)
        self.assertAlmostEqual(scores[0], 0.9, places=3)

    def test_conf_threshold_filters(self):
        output = np.array(
            [[[100.0, 200.0], [100.0, 200.0], [40.0, 40.0], [40.0, 40.0], [0.9, 0.1]]],
            dtype=np.float32,
        )
        boxes, scores = decode_onnx_output(output, scale=1.0, pad_x=0.0, pad_y=0.0, conf_thres=0.25)
        self.assertEqual(len(boxes), 1)
        self.assertEqual(scores[0], 0.9)

    def test_empty_output(self):
        output = np.zeros((1, 5, 8400), dtype=np.float32)
        boxes, scores = decode_onnx_output(output, scale=1.0, pad_x=0.0, pad_y=0.0, conf_thres=0.25)
        self.assertEqual((boxes, scores), ([], []))


@unittest.skipUnless(HAS_ORT and (ARTIFACT_DIR / "model.onnx").exists(),
                     "需要 onnxruntime 与 ONNX 制品")
class TestOnnxDetectorIntegration(unittest.TestCase):
    def test_predict_on_synthetic_image(self):
        import tempfile

        from PIL import Image, ImageDraw

        from pig_farm_agent.detector import OnnxDetector, load_manifest

        with tempfile.TemporaryDirectory() as tmp:
            img = Image.new("RGB", (960, 720), (125, 115, 105))
            draw = ImageDraw.Draw(img)
            for i in range(6):
                draw.ellipse(
                    [60 + i * 140, 200 + (i % 2) * 160, 150 + i * 140, 290 + (i % 2) * 160],
                    fill=(85, 65, 55), outline=(55, 42, 36), width=3,
                )
            image_path = Path(tmp) / "barn.jpg"
            img.save(image_path, "JPEG", quality=92)

            detector = OnnxDetector(ARTIFACT_DIR, load_manifest(ARTIFACT_DIR))
            result = detector.predict(str(image_path), request_id="onnx-test-1", barn_id="A01")

            self.assertEqual(result.model_name, "DCR-SoftNMS-YOLOv13")
            self.assertEqual(result.postprocess, "onnx+linear-softnms")
            self.assertEqual((result.image_width, result.image_height), (960, 720))
            self.assertGreater(result.inference_ms, 0)
            self.assertLess(result.inference_ms, 20000)
            self.assertGreaterEqual(result.candidate_count, result.kept_count)
            self.assertIn(result.quality_status, ("usable", "blurry", "degraded", "unreadable"))


if __name__ == "__main__":
    unittest.main()
