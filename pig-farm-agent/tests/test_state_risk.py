from __future__ import annotations

import unittest

from pig_farm_agent.config import BarnConfig, load_config
from pig_farm_agent.risk import RiskEngine
from pig_farm_agent.state import compute_state, quality_ok

from .helpers import PROJECT_ROOT, make_detection

BARN = BarnConfig("A01", 45)


def obs(density: float, **kwargs) -> dict:
    base = {
        "state": {
            "pig_count": int(density * 45),
            "density": density,
            "quality": {"status": "usable", "coverage": 0.95},
            "trend": None,
        }
    }
    base["state"]["quality"].update(kwargs)
    return base


def state_of(density: float, count: int | None = None, quality: str = "usable", coverage=0.95) -> dict:
    return {
        "pig_count": count if count is not None else int(density * 45),
        "density": density,
        "quality": {"status": quality, "coverage": coverage},
        "trend": None,
    }


class TestComputeState(unittest.TestCase):
    def test_density_and_count(self):
        result = compute_state(make_detection(38), BARN)
        self.assertEqual(result["pig_count"], 38)
        self.assertAlmostEqual(result["density"], round(38 / 45, 4))
        self.assertEqual(result["quality"]["status"], "usable")

    def test_density_clamped(self):
        result = compute_state(make_detection(60), BARN)
        self.assertEqual(result["density"], 1.0)

    def test_trend_against_previous(self):
        previous = {"captured_at": "t0", "created_at": "t0", "state": {"pig_count": 30}}
        result = compute_state(make_detection(38), BARN, previous=previous)
        self.assertEqual(result["trend"]["count_delta"], 8)
        self.assertEqual(result["trend"]["previous_count"], 30)

    def test_first_observation_has_no_trend(self):
        self.assertIsNone(compute_state(make_detection(38), BARN)["trend"])


class TestQualityGate(unittest.TestCase):
    def test_status_and_coverage(self):
        self.assertTrue(quality_ok(state_of(0.5), 0.8))
        self.assertFalse(quality_ok(state_of(0.5, quality="blurry"), 0.8))
        self.assertFalse(quality_ok(state_of(0.5, coverage=0.5), 0.8))
        self.assertTrue(quality_ok(state_of(0.5, coverage=None), 0.8))


class TestRiskEngine(unittest.TestCase):
    def setUp(self):
        config = load_config(PROJECT_ROOT / "config.json", use_env=False)
        self.engine = RiskEngine(config.rules)

    def test_boundary_at_threshold_fires(self):
        # 0.82 恰好等于阈值：>= 判定成立
        result = self.engine.assess(state_of(0.82), [obs(0.9)])
        self.assertEqual(result["code"], "DENSITY_HIGH")
        self.assertEqual(result["level"], "high")
        self.assertEqual(result["consecutive_breaches"], 2)
        self.assertEqual(result["thresholds"]["density"], 0.82)

    def test_single_breach_pends(self):
        result = self.engine.assess(state_of(0.9), [obs(0.5)])
        self.assertIsNone(result["code"])
        self.assertEqual(result["level"], "none")
        self.assertIn("待连续确认", result["note"])

    def test_broken_streak_resets(self):
        # history 为新到旧：上一次观测正常，当前超标只有 1 次，不生成告警
        result = self.engine.assess(state_of(0.9), [obs(0.5), obs(0.9)])
        self.assertIsNone(result["code"])

    def test_watch_level(self):
        result = self.engine.assess(state_of(0.7), [obs(0.7)])
        self.assertEqual(result["code"], "DENSITY_WATCH")
        self.assertEqual(result["level"], "medium")

    def test_high_takes_precedence_over_watch(self):
        result = self.engine.assess(state_of(0.9), [obs(0.85)])
        self.assertEqual(result["code"], "DENSITY_HIGH")

    def test_quality_low_suppresses_density(self):
        result = self.engine.assess(state_of(0.95, quality="blurry"), [obs(0.9)])
        self.assertEqual(result["code"], "DATA_QUALITY_LOW")
        self.assertIn("抑制", result["note"])

    def test_low_coverage_quality(self):
        result = self.engine.assess(state_of(0.5, coverage=0.6), [])
        self.assertEqual(result["code"], "DATA_QUALITY_LOW")
        self.assertEqual(result["thresholds"]["min_coverage"], 0.8)

    def test_normal_state(self):
        result = self.engine.assess(state_of(0.5), [obs(0.5)])
        self.assertIsNone(result["code"])
        self.assertEqual(result["note"], "密度处于正常区间")

    def test_recovery_streak(self):
        state = state_of(0.5)
        self.assertEqual(self.engine.recovery_streak(state, [obs(0.6)], "DENSITY_HIGH"), 2)
        self.assertEqual(self.engine.recovery_streak(state, [obs(0.9)], "DENSITY_HIGH"), 1)
        self.assertEqual(self.engine.recovery_streak(state_of(0.9), [obs(0.5)], "DENSITY_HIGH"), 0)

    def test_actions_from_templates(self):
        self.assertEqual(self.engine.actions_for(None), ["保持常规巡检"])
        actions = self.engine.actions_for("DENSITY_HIGH")
        self.assertTrue(any("复核" in a for a in actions))


if __name__ == "__main__":
    unittest.main()
