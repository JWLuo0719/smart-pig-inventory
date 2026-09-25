from __future__ import annotations

import unittest

import numpy as np

from pig_farm_agent.model_runtime.scoring import (
    P_OVER_S_MAX,
    P_OVER_S_MIN,
    apply_score_multipliers,
    fuse_scores,
    probability_to_p_over_s_multiplier,
    quality_constrained_scores,
)


class TestScoring(unittest.TestCase):
    def test_p_over_s_multiplier_clipping(self):
        scores = np.array([0.5, 0.001, 0.5, 0.9], dtype=np.float32)
        probs = np.array([0.25, 0.9, 0.5, 0.5], dtype=np.float32)
        multiplier = probability_to_p_over_s_multiplier(scores, probs)
        # p/s: 0.5, 900(截断为5), 1.0, 0.556
        self.assertAlmostEqual(float(multiplier[0]), 0.5, places=5)
        self.assertAlmostEqual(float(multiplier[1]), P_OVER_S_MAX, places=5)
        self.assertAlmostEqual(float(multiplier[2]), 1.0, places=5)
        self.assertAlmostEqual(float(multiplier[3]), 0.5 / 0.9, places=4)

    def test_p_over_s_shape_mismatch_raises(self):
        with self.assertRaises(ValueError):
            probability_to_p_over_s_multiplier(np.ones(3, dtype=np.float32), np.ones(4, dtype=np.float32))

    def test_fuse_scores_modes(self):
        s = np.array([0.8, 0.2], dtype=np.float32)
        p = np.array([0.4, 0.9], dtype=np.float32)
        replaced = fuse_scores(s, p, mode="replace_p")
        np.testing.assert_allclose(replaced, p, rtol=1e-6)
        fused_b0 = fuse_scores(s, p, mode="fusion", beta=0.0)
        np.testing.assert_allclose(fused_b0, s, rtol=1e-5)
        fused_b1 = fuse_scores(s, p, mode="fusion", beta=1.0)
        np.testing.assert_allclose(fused_b1, p, rtol=1e-5)
        with self.assertRaises(ValueError):
            fuse_scores(s, p, mode="unknown")

    def test_quality_constrained_scores_bounded(self):
        rng = np.random.default_rng(42)
        # 比值保持在 p/s 截断区间内时，结果等于 s^0.75 * p
        s = rng.uniform(0.2, 1.0, 512).astype(np.float32)
        p = rng.uniform(0.3, 0.9, 512).astype(np.float32)
        out = quality_constrained_scores(s, p, score_power=0.75)
        self.assertTrue(np.all(out >= 0.0) and np.all(out <= 1.0))
        expected = np.clip(np.power(s, 0.75) * p, 0.0, 1.0)
        np.testing.assert_allclose(out, expected, rtol=1e-4)

    def test_quality_constrained_scores_extreme_ratio_clipped(self):
        s = np.array([0.001, 0.5], dtype=np.float32)
        p = np.array([1.0, 1.0], dtype=np.float32)
        out = quality_constrained_scores(s, p, score_power=0.75)
        self.assertTrue(np.all(out >= 0.0) and np.all(out <= 1.0))
        self.assertLess(float(out[0]), 1.0)

    def test_apply_score_multipliers(self):
        # scores 与 row_idx 对齐：local 下标对应 row_idx 中的行号
        scores = np.array([0.5, 0.5], dtype=np.float32)
        out = apply_score_multipliers(scores, np.array([0, 2]), {0: 2.0, 2: 10.0})
        self.assertAlmostEqual(float(out[0]), 1.0, places=6)  # 0.5*2
        self.assertAlmostEqual(float(out[1]), 1.0, places=6)  # 0.5*10 截断到 1


if __name__ == "__main__":
    unittest.main()
