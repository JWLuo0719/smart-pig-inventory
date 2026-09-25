from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from pig_farm_agent.replay import (
    DEFAULT_BASELINE_PATH,
    DEFAULT_IMAGES_DIR,
    barn_for,
    collect_images,
    compare,
    main as replay_main,
    run_replay,
    summarize,
)

from .helpers import make_agent


def _copy_fixtures(target: Path, names: list[str] | None = None) -> Path:
    """把仓库夹具复制到临时目录，便于在隔离目录里做破坏性实验。"""
    target.mkdir(parents=True, exist_ok=True)
    for image in collect_images(DEFAULT_IMAGES_DIR):
        if names is None or image.name in names:
            shutil.copyfile(image, target / image.name)
    return target


class TestFixtureHelpers(unittest.TestCase):
    def test_barn_parsed_from_filename(self):
        self.assertEqual(barn_for(Path("barn-A01-03.jpg"), "A01"), "A01")
        self.assertEqual(barn_for(Path("barn-B12-01c.jpg"), "A01"), "B12")
        self.assertEqual(barn_for(Path("A02_20260916_083000.jpg"), "A01"), "A02")
        self.assertEqual(barn_for(Path("plain.jpg"), "A07"), "A07")

    def test_collect_images_sorted_and_filtered(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("b.jpg", "a.jpg", "notes.txt"):
                (root / name).write_text("x", encoding="utf-8")
            self.assertEqual([p.name for p in collect_images(root)], ["a.jpg", "b.jpg"])

    def test_missing_dir_raises(self):
        with self.assertRaises(FileNotFoundError):
            collect_images(Path("no-such-dir"))


class TestReplayRun(unittest.TestCase):
    """对仓库自带的固定夹具跑全链路回放（mock 模式）。"""

    @classmethod
    def setUpClass(cls):
        cls.agent = make_agent(Path(tempfile.mkdtemp(prefix="pig-replay-test-")))
        cls.result = run_replay(cls.agent.config, DEFAULT_IMAGES_DIR, mode="agent")
        cls.baseline = json.loads(DEFAULT_BASELINE_PATH.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        cls.agent.close()

    def test_full_pipeline_results_are_recorded(self):
        self.assertEqual(self.result["image_count"], len(collect_images(DEFAULT_IMAGES_DIR)))
        self.assertEqual(self.result["mode"], "agent")
        for item in self.result["results"]:
            self.assertIsInstance(item["detected_count"], int)
            self.assertIsInstance(item["candidate_count"], int)
            self.assertGreaterEqual(item["candidate_count"], item["detected_count"])
            self.assertIn(item["quality_status"], ("usable", "blurry", "degraded", "unreadable"))
            self.assertTrue(item["evidence_complete"], item["file"])
            self.assertGreaterEqual(item["event_ms"], 0)

    def test_fixtures_cover_every_risk_path(self):
        codes = {r["risk_code"] for r in self.result["results"]}
        self.assertIn(None, codes)                    # 正常区间
        self.assertIn("DENSITY_WATCH", codes)         # 中风险密度
        self.assertIn("DENSITY_HIGH", codes)          # 高风险密度（连续帧确认）
        self.assertIn("DATA_QUALITY_LOW", codes)      # 质量门
        self.assertGreaterEqual(sum(1 for r in self.result["results"] if r["merged"]), 1,
                                "夹具应覆盖冷却合并通路")

    def test_baseline_matches_current_repository_state(self):
        """基线必须与仓库当前配置/夹具一致，否则门槛失效。"""
        diffs = compare(self.baseline, self.result)
        self.assertEqual(diffs, [], f"基线漂移: {diffs}")

    def test_replay_is_deterministic(self):
        """同名同内容图片在两个数据目录下结果一致（种子不含完整路径）。"""
        first = run_replay(self.agent.config, DEFAULT_IMAGES_DIR, mode="agent")
        second = run_replay(self.agent.config, DEFAULT_IMAGES_DIR, mode="agent")
        keys = ("file", "barn_id", "detected_count", "candidate_count",
                "quality_status", "density", "risk_level", "risk_code", "merged")
        self.assertEqual([{k: r[k] for k in keys} for r in first["results"]],
                         [{k: r[k] for k in keys} for r in second["results"]])

    def test_detector_mode_without_risk_fields(self):
        result = run_replay(self.agent.config, DEFAULT_IMAGES_DIR, mode="detector")
        self.assertEqual(result["mode"], "detector")
        self.assertTrue(all("risk_code" not in r for r in result["results"]))
        self.assertGreaterEqual(result["timing"]["mean_ms"], 0)

    def test_unknown_mode_raises(self):
        with self.assertRaises(ValueError):
            run_replay(self.agent.config, DEFAULT_IMAGES_DIR, mode="nope")

    def test_summarize_mentions_model_and_risk(self):
        text = summarize(self.result)
        self.assertIn("DCR-SoftNMS-YOLOv13", text)
        self.assertIn("DENSITY_HIGH", text)


class TestReplayGate(unittest.TestCase):
    """门槛判定：计数、质量、风险等级与夹具指纹的任何漂移都要拦下。"""

    @classmethod
    def setUpClass(cls):
        cls.agent = make_agent(Path(tempfile.mkdtemp(prefix="pig-replay-gate-")))
        cls.baseline = json.loads(DEFAULT_BASELINE_PATH.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        cls.agent.close()

    def _run_in_copy(self, mutate=None) -> dict:
        with tempfile.TemporaryDirectory(prefix="pig-replay-copy-") as tmp:
            images = _copy_fixtures(Path(tmp) / "images")
            if mutate:
                mutate(images)
            return run_replay(self.agent.config, images, mode="agent")

    def test_tampered_fixture_content_fails_gate(self):
        def append_byte(images: Path):
            target = sorted(images.glob("*.jpg"))[0]
            target.write_bytes(target.read_bytes() + b"x")

        current = self._run_in_copy(append_byte)
        diffs = compare(self.baseline, current)
        self.assertTrue(any("指纹" in d for d in diffs), diffs)
        self.assertTrue(any("计数" in d or "候选数" in d or "风险" in d for d in diffs), diffs)

    def test_missing_fixture_fails_gate(self):
        current = self._run_in_copy(lambda images: sorted(images.glob("*.jpg"))[0].unlink())
        diffs = compare(self.baseline, current)
        self.assertTrue(any("缺少图片结果" in d for d in diffs), diffs)

    def test_extra_fixture_fails_gate(self):
        def add_image(images: Path):
            shutil.copyfile(sorted(images.glob("*.jpg"))[0], images / "barn-A01-99.jpg")

        current = self._run_in_copy(add_image)
        diffs = compare(self.baseline, current)
        self.assertTrue(any("多出图片结果" in d for d in diffs), diffs)

    def test_model_version_change_fails_gate(self):
        current = json.loads(json.dumps(self.baseline))
        current["model_version"] = "v2"
        diffs = compare(self.baseline, current)
        self.assertTrue(any("模型版本不同" in d for d in diffs), diffs)

    def test_risk_change_blocks_by_default_and_can_be_allowed(self):
        current = json.loads(json.dumps(self.baseline))
        item = current["results"][0]
        item["risk_code"] = "DENSITY_HIGH" if item["risk_code"] != "DENSITY_HIGH" else None
        item["risk_level"] = "high" if item["risk_level"] != "high" else "none"
        self.assertTrue(any("风险等级" in d for d in compare(self.baseline, current)))
        self.assertEqual(compare(self.baseline, current, allow_risk_change=True), [])

    def test_quality_status_change_fails_gate(self):
        current = json.loads(json.dumps(self.baseline))
        current["results"][0]["quality_status"] = "blurry"
        self.assertTrue(any("质量状态" in d for d in compare(self.baseline, current)))

    def test_tolerance_applies_to_counts_only(self):
        current = json.loads(json.dumps(self.baseline))
        current["results"][0]["detected_count"] += 2
        current["results"][0]["candidate_count"] += 2
        self.assertTrue(compare(self.baseline, current))
        self.assertEqual(compare(self.baseline, current, tolerance=2), [])

    def test_mode_mismatch_fails_gate(self):
        current = json.loads(json.dumps(self.baseline))
        current["mode"] = "detector"
        self.assertTrue(any("回放模式不同" in d for d in compare(self.baseline, current)))


class TestReplayCli(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="pig-replay-cli-")
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def _args(self, baseline: Path, *extra: str) -> list[str]:
        return ["--images", str(DEFAULT_IMAGES_DIR), "--baseline", str(baseline),
                "--data-dir", str(self.tmp / "data"), *extra]

    def test_update_baseline_then_compare_passes(self):
        baseline = self.tmp / "baseline.json"
        self.assertEqual(replay_main(self._args(baseline, "--update-baseline")), 0)
        self.assertTrue(baseline.exists())
        self.assertEqual(replay_main(self._args(baseline)), 0)

    def test_compare_without_baseline_returns_2(self):
        self.assertEqual(replay_main(self._args(self.tmp / "nope.json")), 2)

    def test_strict_timing_gate_fails(self):
        baseline = self.tmp / "baseline.json"
        replay_main(self._args(baseline, "--update-baseline"))
        self.assertEqual(replay_main(self._args(baseline, "--max-ms", "0.001")), 1)


class TestCompareReportsRiskLevel(unittest.TestCase):
    """风险等级/代码差异必须逐项出现在差异清单里（文档第 10 节口径）。"""

    def test_compare_reports_risk_level_and_code(self):
        baseline = {
            "model_name": "M", "model_version": "v1", "mode": "agent",
            "fixtures": {"a.jpg": "abc"},
            "results": [{"file": "a.jpg", "detected_count": 30, "candidate_count": 33,
                         "quality_status": "usable", "risk_level": "high", "risk_code": "DENSITY_HIGH"}],
        }
        current = json.loads(json.dumps(baseline))
        current["results"][0].update({"risk_level": "medium", "risk_code": "DENSITY_WATCH"})
        diffs = compare(baseline, current)
        self.assertTrue(any("风险等级 high -> medium" in d for d in diffs), diffs)
        self.assertTrue(any("风险代码 DENSITY_HIGH -> DENSITY_WATCH" in d for d in diffs), diffs)


if __name__ == "__main__":
    unittest.main()
