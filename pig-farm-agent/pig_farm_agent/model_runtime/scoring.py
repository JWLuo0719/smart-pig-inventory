"""Score fusion for DCR-SoftNMS: how p_correct becomes the final score.

Record-40/41 variants:
  replace_p : final_score = p_correct                      (pure replacement ablation)
  fusion    : final_score = score^(1-b) * p_correct^b      (b in [0, 1])
  multiplier: final_score = score * score_multiplier       (frozen headline when
              score_multiplier = clip(p_correct / max(score, .001), .05, 5.0))
  quality_product: final_score = score^alpha * p_correct  (V3-C conservative)
"""
from __future__ import annotations

import numpy as np


P_OVER_S_MIN = 0.05
P_OVER_S_MAX = 5.0


def probability_to_p_over_s_multiplier(
    scores: np.ndarray,
    probabilities: np.ndarray,
    *,
    score_floor: float = 1e-3,
    min_multiplier: float = P_OVER_S_MIN,
    max_multiplier: float = P_OVER_S_MAX,
) -> np.ndarray:
    """Convert correctness probabilities to the frozen ``p/s`` multiplier.

    Keeping this conversion in one place prevents train-time cache generation
    and evaluation from silently using different clipping semantics.
    """
    s = np.asarray(scores, dtype=np.float32)
    p = np.asarray(probabilities, dtype=np.float32)
    if s.shape != p.shape:
        raise ValueError(f"scores and probabilities must have the same shape: {s.shape} != {p.shape}")
    if not np.isfinite(s).all() or not np.isfinite(p).all():
        raise ValueError("scores and probabilities must contain only finite values")
    multiplier = p / np.maximum(s, float(score_floor))
    return np.clip(multiplier, float(min_multiplier), float(max_multiplier)).astype(np.float32)


def probability_to_score_multiplier(
    probabilities: np.ndarray,
    *,
    center: float,
    strength: float,
    min_multiplier: float,
    max_multiplier: float,
) -> np.ndarray:
    probs = np.asarray(probabilities, dtype=np.float32)
    center_value = float(np.clip(center, 1e-6, 1.0 - 1e-6))
    scale = max(center_value, 1.0 - center_value)
    multipliers = 1.0 + float(strength) * ((probs - center_value) / scale)
    return np.clip(multipliers, float(min_multiplier), float(max_multiplier)).astype(np.float32)


def fuse_scores(
    scores: np.ndarray,
    p_correct: np.ndarray,
    *,
    mode: str = "replace_p",
    beta: float = 0.0,
) -> np.ndarray:
    """Combine original scores with correctness probabilities."""
    s = np.asarray(scores, dtype=np.float32)
    p = np.asarray(p_correct, dtype=np.float32)
    if mode == "replace_p":
        return p.copy()
    if mode == "fusion":
        b = float(np.clip(beta, 0.0, 1.0))
        s = np.clip(s, 1e-6, 1.0)
        p = np.clip(p, 1e-6, 1.0)
        return (np.power(s, 1.0 - b) * np.power(p, b)).astype(np.float32)
    raise ValueError(f"unknown score mode: {mode}")


def quality_constrained_scores(
    scores: np.ndarray,
    p_correct: np.ndarray,
    *,
    score_power: float = 0.75,
) -> np.ndarray:
    """Retain detector confidence while applying a bounded quality penalty.

    The frozen V3-B replacement uses ``p_correct`` alone.  This conservative
    V3-C variant keeps the original confidence as a reliability prior and
    applies the learned quality signal with a fixed exponent selected on Val.
    The same p/s clip as V3-B is applied after the product so low-score
    candidates cannot be promoted without bound.
    """
    s = np.clip(np.asarray(scores, dtype=np.float32), 0.0, 1.0)
    p = np.clip(np.asarray(p_correct, dtype=np.float32), 0.0, 1.0)
    if s.shape != p.shape:
        raise ValueError(f"scores and p_correct must have the same shape: {s.shape} != {p.shape}")
    if not np.isfinite(s).all() or not np.isfinite(p).all():
        raise ValueError("scores and p_correct must contain only finite values")
    exponent = max(0.0, float(score_power))
    quality_score = np.clip(np.power(s, exponent) * p, 0.0, 1.0)
    multiplier = probability_to_p_over_s_multiplier(s, quality_score)
    return np.clip(s * multiplier, 0.0, 1.0).astype(np.float32)


def apply_score_multipliers(
    scores: np.ndarray,
    row_idx: np.ndarray,
    multipliers: dict[int, float],
) -> np.ndarray:
    """Multiply candidate scores by a {row_idx: multiplier} map, clipped to [0, 1]."""
    out = np.asarray(scores, dtype=np.float32).copy()
    for local, row in enumerate(np.asarray(row_idx, dtype=np.int64).tolist()):
        m = multipliers.get(int(row))
        if m is not None:
            out[local] = float(np.clip(out[local] * float(m), 0.0, 1.0))
    return out
