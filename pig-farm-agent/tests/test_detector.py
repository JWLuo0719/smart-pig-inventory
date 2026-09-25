from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from pig_farm_agent.detector import (
    ModelArtifactError,
    MockDetector,
    _linear_soft_nms_numpy,
    load_manifest,
)

from .helpers import PROJECT_ROOT

ARTIFACT_DIR = PROJECT_ROOT / "model_artifacts" / "dcr-softnms-yolov13-v1"


class TestManifestValidation(unittest.TestCase):
    def test_valid_repo_artifact(self):
        manifest = load_manifest(ARTIFACT_DIR)
        self.assertEqual(manifest["model_name"], "DCR-SoftNMS-YOLOv13")
        self.assertEqual(manifest["model_version"], "v1")

    def _write_manifest(self, tmp: Path, payload) -> Path:
        (tmp / "manifest.json").write_text(json.dumps(payload), encoding="utf-8")
        return tmp

    def test_missing_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ModelArtifactError):
                load_manifest(Path(tmp))

    def test_missing_field(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._write_manifest(Path(tmp), {"model_name": "x"})
            with self.assertRaises(ModelArtifactError):
                load_manifest(Path(tmp))

    def test_missing_artifact_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._write_manifest(
                Path(tmp),
                {"model_name": "x", "model_version": "1", "files": [{"path": "model.pt"}]},
            )
            with self.assertRaises(ModelArtifactError):
                load_manifest(Path(tmp))

    def test_checksum_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_manifest(
                root,
                {
                    "model_name": "x",
                    "model_version": "1",
                    "files": [{"path": "model.pt", "sha256": "0" * 64}],
                },
            )
            (root / "model.pt").write_bytes(b"weights")
            with self.assertRaises(ModelArtifactError):
                load_manifest(root)


class TestMockDetector(unittest.TestCase):
    def test_deterministic_for_same_request(self):
        detector = MockDetector()
        first = detector.predict(None, request_id="req-a", barn_id="A01")
        second = detector.predict(None, request_id="req-a", barn_id="A01")
        self.assertEqual(first.boxes, second.boxes)
        self.assertEqual(first.quality_status, second.quality_status)
        self.assertEqual(first.kept_count, second.kept_count)
        self.assertGreaterEqual(first.kept_count, 18)
        self.assertLessEqual(first.kept_count, 44)
        self.assertEqual(len(first.scores), first.kept_count)

    def test_variation_across_requests(self):
        detector = MockDetector()
        counts = {
            detector.predict(None, request_id=f"req-{i}", barn_id="A01").kept_count for i in range(20)
        }
        self.assertGreater(len(counts), 1)

    def test_contract_fields(self):
        result = MockDetector().predict(None, request_id="req-x", barn_id="A01")
        for field in ("inference_ms", "candidate_count", "quality_status", "coverage",
                      "image_width", "image_height", "model_name", "model_version", "postprocess"):
            self.assertTrue(hasattr(result, field))
        self.assertGreaterEqual(result.candidate_count, result.kept_count)


class TestLinearSoftNms(unittest.TestCase):
    def test_overlapping_boxes_decayed(self):
        boxes = [[0, 0, 100, 100], [5, 5, 105, 105], [300, 300, 400, 400]]
        scores = [0.9, 0.8, 0.7]
        keep, kept = _linear_soft_nms_numpy(
            boxes, scores, iou_thres=0.4, score_floor=0.001, max_det=300
        )
        self.assertEqual(len(keep), 3)
        # 与最高分框高度重叠的候选被线性衰减，排序跌到最后；不重叠框保持原分
        self.assertEqual(keep, [0, 2, 1])
        self.assertAlmostEqual(kept[0], 0.9)
        self.assertAlmostEqual(kept[1], 0.7)
        iou_pair = 9025 / 10975  # (100-5)^2 / (2*100^2 - 9025)
        self.assertAlmostEqual(kept[2], 0.8 * (1 - iou_pair), places=5)

    def test_empty_input(self):
        self.assertEqual(_linear_soft_nms_numpy([], [], iou_thres=0.4, score_floor=0.001, max_det=10), ([], []))

    def test_max_det_cap(self):
        boxes = [[float(i), 0, float(i) + 10, 10] for i in range(10)]
        scores = [0.9 - i * 0.01 for i in range(10)]
        keep, _ = _linear_soft_nms_numpy(boxes, scores, iou_thres=0.4, score_floor=0.001, max_det=3)
        self.assertEqual(len(keep), 3)


if __name__ == "__main__":
    unittest.main()
