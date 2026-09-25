"""NMS family for the DCR-SoftNMS runtime: hard / Soft-NMS / adaptive / relation-aware.

Moved verbatim from the research execution tooling. ACTION_INDEX is defined locally
here (values identical to the research policy module) so that importing this module
no longer pulls in the whole expert-model family.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np
import torch

ACTION_NAMES = ("keep", "refine", "rescore", "protect", "suppress")
ACTION_INDEX = {name: i for i, name in enumerate(ACTION_NAMES)}


@dataclass(frozen=True)
class ChannelCoefficients:
    rho: torch.Tensor
    eta: torch.Tensor
    lam: torch.Tensor
    kappa: torch.Tensor


def channel_coefficients(action_probs: torch.Tensor, eps: float = 1e-6) -> ChannelCoefficients:
    pi_refine = action_probs[:, ACTION_INDEX["refine"]] + eps
    pi_keep = action_probs[:, ACTION_INDEX["keep"]] + eps
    rho = pi_refine / (pi_keep + pi_refine)
    pi_score = action_probs[:, [ACTION_INDEX["rescore"], ACTION_INDEX["protect"], ACTION_INDEX["suppress"]]]
    eta = pi_score / (pi_score.sum(dim=1, keepdim=True) + eps)
    lam = action_probs[:, ACTION_INDEX["protect"]]
    kappa = action_probs[:, ACTION_INDEX["suppress"]]
    return ChannelCoefficients(rho=rho, eta=eta, lam=lam, kappa=kappa)


def pairwise_thresholds(
    victim_indices: torch.Tensor,
    relation_probs: torch.Tensor,
    *,
    lam: torch.Tensor,
    kappa: torch.Tensor,
    tau_base: float = 0.70,
    tau_min: float = 0.30,
    tau_max: float = 0.90,
    p_max: float = 0.20,
    s_max: float = 0.20,
) -> torch.Tensor:
    victims = victim_indices.to(torch.long)
    probs = relation_probs.to(torch.float32)
    p_duplicate = probs[:, 0]
    p_neighbor = probs[:, 1]
    protect_margin = lam.to(torch.float32)[victims] * float(p_max) * p_neighbor
    suppress_margin = kappa.to(torch.float32)[victims] * float(s_max) * p_duplicate
    return (float(tau_base) + protect_margin - suppress_margin).clamp(float(tau_min), float(tau_max))


def full_relation_probs(n: int, default: Sequence[float] = (0.0, 0.0, 1.0)) -> torch.Tensor:
    probs = torch.zeros((int(n), int(n), 3), dtype=torch.float32)
    value = torch.tensor(list(default), dtype=torch.float32)
    probs[:, :] = value
    return probs


def box_iou_torch(a: torch.Tensor, b: torch.Tensor) -> torch.Tensor:
    aa = a.to(torch.float32)
    bb = b.to(torch.float32)
    tl = torch.maximum(aa[:, None, :2], bb[None, :, :2])
    br = torch.minimum(aa[:, None, 2:], bb[None, :, 2:])
    wh = (br - tl).clamp_min(0.0)
    inter = wh[:, :, 0] * wh[:, :, 1]
    area_a = (aa[:, 2] - aa[:, 0]).clamp_min(0.0) * (aa[:, 3] - aa[:, 1]).clamp_min(0.0)
    area_b = (bb[:, 2] - bb[:, 0]).clamp_min(0.0) * (bb[:, 3] - bb[:, 1]).clamp_min(0.0)
    return inter / (area_a[:, None] + area_b[None, :] - inter).clamp_min(1e-9)


def deterministic_order(scores: torch.Tensor, row_idx: torch.Tensor | None = None) -> list[int]:
    s = scores.detach().cpu().numpy()
    if row_idx is None:
        r = list(range(len(s)))
    else:
        r = row_idx.detach().cpu().numpy().tolist()
    return sorted(range(len(s)), key=lambda i: (-float(s[i]), int(r[i]), int(i)))


def soft_nms(
    boxes: torch.Tensor,
    scores: torch.Tensor,
    *,
    row_idx: torch.Tensor | None = None,
    method: str = "linear",
    iou_thres: float = 0.50,
    sigma: float = 0.50,
    score_floor: float = 0.001,
    max_det: int = 300,
) -> tuple[list[int], torch.Tensor, list[dict]]:
    """Linear/gaussian Soft-NMS with a vectorized CPU fast path.

    Semantics are bit-identical to the original per-victim loop (validated by
    tests/test_drra_core.py::test_soft_nms_vectorized_matches_reference):
    same champion tie-breaking (score desc, row_idx asc, index asc), same
    round-order decay application, same floor removal and event stream.
    Non-CPU tensors fall back to the reference loop.
    """
    b = boxes.to(torch.float32)
    final_scores = scores.to(torch.float32).clone()
    if method not in {"linear", "gaussian"}:
        raise ValueError(f"unknown soft_nms method: {method}")
    n = int(b.shape[0])
    if n == 0:
        return [], final_scores, []
    if not final_scores.is_cpu:
        return _soft_nms_reference(
            b, final_scores, row_idx=row_idx, method=method, iou_thres=iou_thres,
            sigma=sigma, score_floor=score_floor, max_det=max_det,
        )

    scores_np = final_scores.numpy()  # zero-copy view: torch and numpy share memory
    row_np = (
        row_idx.detach().cpu().numpy().astype(np.int64)
        if row_idx is not None
        else np.arange(n, dtype=np.int64)
    )
    alive = np.ones(n, dtype=bool)
    kept: list[int] = []
    events: list[dict] = []
    floor = float(score_floor)
    thres = float(iou_thres)
    n_alive = n
    while n_alive > 0 and len(kept) < int(max_det):
        cand = np.flatnonzero(alive)
        order = np.lexsort((cand, row_np[cand], -scores_np[cand].astype(np.float64)))
        champion = int(cand[order[0]])
        if float(scores_np[champion]) < floor:
            break
        alive[champion] = False
        n_alive -= 1
        kept.append(champion)
        rest = np.flatnonzero(alive)
        if rest.size == 0:
            break
        rest_t = torch.from_numpy(rest)
        ious_t = box_iou_torch(b[champion : champion + 1], b[rest_t])[0]
        ious = ious_t.numpy()
        if method == "linear":
            decay = np.where(ious > thres, np.float32(1.0) - ious, np.float32(1.0))
        else:
            decay = torch.exp(-(ious_t * ious_t) / float(sigma)).numpy()
        changed = np.flatnonzero(decay < np.float32(1.0))
        if changed.size:
            victims = rest[changed]
            old_scores = scores_np[victims].copy()
            scores_np[victims] = old_scores * decay[changed]
            new_scores = scores_np[victims]
            for j in range(changed.size):
                events.append(
                    {
                        "suppressor_index": champion,
                        "victim_index": int(victims[j]),
                        "reason": "soft_decay",
                        "suppression_iou": float(ious[changed[j]]),
                        "old_score": float(old_scores[j]),
                        "new_score": float(new_scores[j]),
                        "decay": float(decay[changed[j]]),
                    }
                )
            still_alive = new_scores >= floor
            alive[victims] = still_alive
            n_alive -= int((~still_alive).sum())
    return kept, final_scores, events


def _soft_nms_reference(
    b: torch.Tensor,
    final_scores: torch.Tensor,
    *,
    row_idx: torch.Tensor | None,
    method: str,
    iou_thres: float,
    sigma: float,
    score_floor: float,
    max_det: int,
) -> tuple[list[int], torch.Tensor, list[dict]]:
    row_cpu = row_idx.detach().cpu() if row_idx is not None else None
    remaining = set(range(int(b.shape[0])))
    kept: list[int] = []
    events: list[dict] = []
    while remaining and len(kept) < int(max_det):
        ordered = sorted(
            remaining,
            key=lambda i: (
                -float(final_scores[i].detach().cpu()),
                int(row_cpu[i]) if row_cpu is not None else int(i),
                int(i),
            ),
        )
        current = int(ordered[0])
        remaining.remove(current)
        if float(final_scores[current].detach().cpu()) < float(score_floor):
            break
        kept.append(current)
        if not remaining:
            continue
        rest = torch.tensor(sorted(remaining), dtype=torch.long, device=b.device)
        ious = box_iou_torch(b[current : current + 1], b[rest])[0]
        for local, victim in enumerate(rest.detach().cpu().tolist()):
            iou = float(ious[local].detach().cpu())
            old_score = float(final_scores[victim].detach().cpu())
            if method == "linear":
                decay = 1.0 - iou if iou > float(iou_thres) else 1.0
            else:
                decay = float(torch.exp(-(ious[local] * ious[local]) / float(sigma)).detach().cpu())
            if decay < 1.0:
                final_scores[victim] = final_scores[victim] * float(decay)
                events.append(
                    {
                        "suppressor_index": current,
                        "victim_index": int(victim),
                        "reason": "soft_decay",
                        "suppression_iou": iou,
                        "old_score": old_score,
                        "new_score": float(final_scores[victim].detach().cpu()),
                        "decay": float(decay),
                    }
                )
            if float(final_scores[victim].detach().cpu()) < float(score_floor):
                remaining.remove(int(victim))
    return kept, final_scores, events


def gated_soft_nms(
    boxes: torch.Tensor,
    scores: torch.Tensor,
    *,
    relation_probs: torch.Tensor,
    row_idx: torch.Tensor | None = None,
    method: str = "linear",
    iou_thres: float = 0.50,
    sigma: float = 0.50,
    score_floor: float = 0.001,
    max_det: int = 300,
    alpha_dup: float = 0.50,
    alpha_nei: float = 0.50,
    alpha_bg: float = 0.0,
    gamma_min: float = 0.50,
    gamma_max: float = 2.0,
) -> tuple[list[int], torch.Tensor, list[dict]]:
    b = boxes.to(torch.float32)
    final_scores = scores.to(torch.float32).clone()
    rel = relation_probs.to(torch.float32)
    if method not in {"linear", "gaussian"}:
        raise ValueError(f"unknown gated_soft_nms method: {method}")
    if rel.shape != (b.shape[0], b.shape[0], 3):
        raise ValueError(f"relation_probs must have shape ({b.shape[0]}, {b.shape[0]}, 3), got {tuple(rel.shape)}")

    remaining = set(range(int(b.shape[0])))
    kept: list[int] = []
    events: list[dict] = []
    row_cpu = row_idx.detach().cpu() if row_idx is not None else None
    while remaining and len(kept) < int(max_det):
        ordered = sorted(
            remaining,
            key=lambda i: (
                -float(final_scores[i].detach().cpu()),
                int(row_cpu[i]) if row_cpu is not None else int(i),
                int(i),
            ),
        )
        current = int(ordered[0])
        remaining.remove(current)
        if float(final_scores[current].detach().cpu()) < float(score_floor):
            break
        kept.append(current)
        if not remaining:
            continue

        rest = torch.tensor(sorted(remaining), dtype=torch.long, device=b.device)
        ious = box_iou_torch(b[current : current + 1], b[rest])[0]
        pair_rel = rel[current, rest]
        gamma = (
            1.0
            + float(alpha_dup) * pair_rel[:, 0]
            + float(alpha_bg) * pair_rel[:, 2]
            - float(alpha_nei) * pair_rel[:, 1]
        ).clamp(float(gamma_min), float(gamma_max))
        for local, victim in enumerate(rest.detach().cpu().tolist()):
            iou = float(ious[local].detach().cpu())
            old_score = float(final_scores[victim].detach().cpu())
            if method == "linear":
                base_decay = 1.0 - iou if iou > float(iou_thres) else 1.0
            else:
                base_decay = float(torch.exp(-(ious[local] * ious[local]) / float(sigma)).detach().cpu())
            decay = float(torch.pow(torch.tensor(base_decay, dtype=torch.float32), gamma[local]).detach().cpu())
            if decay < 1.0:
                final_scores[victim] = final_scores[victim] * decay
                probs = pair_rel[local].detach().cpu()
                events.append(
                    {
                        "suppressor_index": current,
                        "victim_index": int(victim),
                        "reason": "gated_soft_decay",
                        "suppression_iou": iou,
                        "old_score": old_score,
                        "new_score": float(final_scores[victim].detach().cpu()),
                        "base_decay": float(base_decay),
                        "decay": decay,
                        "gamma": float(gamma[local].detach().cpu()),
                        "p_duplicate": float(probs[0]),
                        "p_neighbor": float(probs[1]),
                        "p_background_conflict": float(probs[2]),
                    }
                )
            if float(final_scores[victim].detach().cpu()) < float(score_floor):
                remaining.remove(int(victim))
    return kept, final_scores, events


def adaptive_soft_nms(
    boxes: torch.Tensor,
    scores: torch.Tensor,
    *,
    relation_probs: torch.Tensor,
    row_idx: torch.Tensor | None = None,
    method: str = "linear",
    iou_thres: float = 0.40,
    sigma: float = 0.50,
    score_floor: float = 0.001,
    max_det: int = 300,
    density_iou_thres: float = 0.30,
    density_ref_count: float = 32.0,
    density_tau_gain: float = 0.10,
    neighbor_tau_gain: float = 0.12,
    duplicate_tau_gain: float = 0.20,
    background_tau_gain: float = 0.08,
    alpha_dup: float = 0.50,
    alpha_nei: float = 0.50,
    alpha_bg: float = 0.0,
    gamma_min: float = 0.50,
    gamma_max: float = 2.0,
) -> tuple[list[int], torch.Tensor, list[dict]]:
    """Relation- and density-conditioned Soft-NMS.

    The fixed Soft-NMS threshold treats every high-overlap pair identically.
    This variant raises the pair threshold for locally crowded/neighbor pairs
    and lowers it for duplicate/background-conflict pairs.  The same relation
    signal also controls the decay exponent, so a pair is protected or
    suppressed continuously instead of being hard-deleted.
    """
    b = boxes.to(torch.float32)
    final_scores = scores.to(torch.float32).clone()
    rel = relation_probs.to(torch.float32)
    if method not in {"linear", "gaussian"}:
        raise ValueError(f"unknown adaptive_soft_nms method: {method}")
    n = int(b.shape[0])
    if rel.shape != (n, n, 3):
        raise ValueError(f"relation_probs must have shape ({n}, {n}, 3), got {tuple(rel.shape)}")
    if n == 0:
        return [], final_scores, []
    if float(density_ref_count) <= 0.0:
        raise ValueError("density_ref_count must be positive")

    # Density is computed from the same candidate geometry available at
    # inference time. Log scaling prevents a large candidate pool from making
    # the adaptive threshold saturate for every image.
    pair_iou = box_iou_torch(b, b)
    density_count = (pair_iou >= float(density_iou_thres)).sum(dim=1).to(torch.float32) - 1.0
    density = (
        torch.log1p(density_count.clamp_min(0.0))
        / np.log1p(float(density_ref_count))
    ).clamp(0.0, 1.0)

    if b.is_cpu:
        # Keep the adaptive path close to the vectorized Soft-NMS path. The
        # pair-specific threshold and exponent are computed for all victims
        # in one pass; only event serialization remains scalar.
        pair_iou_np = pair_iou.numpy()
        rel_np = rel.numpy()
        scores_np = final_scores.numpy()
        density_np = density.numpy()
        row_np = (
            row_idx.detach().cpu().numpy().astype(np.int64)
            if row_idx is not None
            else np.arange(n, dtype=np.int64)
        )
        alive = np.ones(n, dtype=bool)
        kept: list[int] = []
        events: list[dict] = []
        n_alive = n
        floor = float(score_floor)
        while n_alive > 0 and len(kept) < int(max_det):
            cand = np.flatnonzero(alive)
            order = np.lexsort((cand, row_np[cand], -scores_np[cand].astype(np.float64)))
            champion = int(cand[order[0]])
            if float(scores_np[champion]) < floor:
                break
            alive[champion] = False
            n_alive -= 1
            kept.append(champion)
            rest = np.flatnonzero(alive)
            if rest.size == 0:
                break
            ious = pair_iou_np[champion, rest]
            pair_rel = rel_np[champion, rest]
            pair_density = np.maximum(density_np[champion], density_np[rest])
            thresholds = np.clip(
                float(iou_thres)
                + float(density_tau_gain) * pair_density
                + float(neighbor_tau_gain) * pair_rel[:, 1]
                - float(duplicate_tau_gain) * pair_rel[:, 0]
                - float(background_tau_gain) * pair_rel[:, 2],
                float(iou_thres) - 0.20,
                float(iou_thres) + 0.40,
            )
            gamma = np.clip(
                1.0
                + float(alpha_dup) * pair_rel[:, 0]
                + float(alpha_bg) * pair_rel[:, 2]
                - float(alpha_nei) * pair_rel[:, 1],
                float(gamma_min),
                float(gamma_max),
            )
            if method == "linear":
                base_decay = np.where(ious > thresholds, 1.0 - ious, 1.0).astype(np.float32)
            else:
                base_decay = np.exp(-(ious * ious) / float(sigma)).astype(np.float32)
            decay = np.power(base_decay, gamma).astype(np.float32)
            changed = np.flatnonzero(decay < np.float32(1.0))
            if changed.size:
                victims = rest[changed]
                old_scores = scores_np[victims].copy()
                scores_np[victims] = old_scores * decay[changed]
                new_scores = scores_np[victims]
                for j, victim in enumerate(victims.tolist()):
                    probs = pair_rel[changed[j]]
                    events.append(
                        {
                            "suppressor_index": champion,
                            "victim_index": int(victim),
                            "reason": "adaptive_soft_decay",
                            "suppression_iou": float(ious[changed[j]]),
                            "threshold": float(thresholds[changed[j]]),
                            "base_decay": float(base_decay[changed[j]]),
                            "decay": float(decay[changed[j]]),
                            "gamma": float(gamma[changed[j]]),
                            "pair_density": float(pair_density[changed[j]]),
                            "p_duplicate": float(probs[0]),
                            "p_neighbor": float(probs[1]),
                            "p_background_conflict": float(probs[2]),
                            "old_score": float(old_scores[j]),
                            "new_score": float(new_scores[j]),
                        }
                    )
                still_alive = new_scores >= floor
                alive[victims] = still_alive
                n_alive -= int((~still_alive).sum())
        return kept, final_scores, events

    remaining = set(range(n))
    kept: list[int] = []
    events: list[dict] = []
    row_cpu = row_idx.detach().cpu() if row_idx is not None else None
    while remaining and len(kept) < int(max_det):
        ordered = sorted(
            remaining,
            key=lambda i: (
                -float(final_scores[i].detach().cpu()),
                int(row_cpu[i]) if row_cpu is not None else int(i),
                int(i),
            ),
        )
        current = int(ordered[0])
        remaining.remove(current)
        if float(final_scores[current].detach().cpu()) < float(score_floor):
            break
        kept.append(current)
        if not remaining:
            continue

        rest = torch.tensor(sorted(remaining), dtype=torch.long, device=b.device)
        ious = pair_iou[current, rest]
        pair_rel = rel[current, rest]
        p_duplicate = pair_rel[:, 0]
        p_neighbor = pair_rel[:, 1]
        p_background = pair_rel[:, 2]
        pair_density = torch.maximum(density[current], density[rest])
        thresholds = (
            float(iou_thres)
            + float(density_tau_gain) * pair_density
            + float(neighbor_tau_gain) * p_neighbor
            - float(duplicate_tau_gain) * p_duplicate
            - float(background_tau_gain) * p_background
        ).clamp(float(iou_thres) - 0.20, float(iou_thres) + 0.40)
        gamma = (
            1.0
            + float(alpha_dup) * p_duplicate
            + float(alpha_bg) * p_background
            - float(alpha_nei) * p_neighbor
        ).clamp(float(gamma_min), float(gamma_max))

        for local, victim in enumerate(rest.detach().cpu().tolist()):
            iou = float(ious[local].detach().cpu())
            threshold = float(thresholds[local].detach().cpu())
            old_score = float(final_scores[victim].detach().cpu())
            if method == "linear":
                base_decay = 1.0 - iou if iou > threshold else 1.0
            else:
                base_decay = float(torch.exp(-(ious[local] * ious[local]) / float(sigma)).detach().cpu())
            decay = float(torch.pow(torch.tensor(base_decay, dtype=torch.float32), gamma[local]).detach().cpu())
            if decay < 1.0:
                final_scores[victim] = final_scores[victim] * decay
                probs = pair_rel[local].detach().cpu()
                events.append(
                    {
                        "suppressor_index": current,
                        "victim_index": int(victim),
                        "reason": "adaptive_soft_decay",
                        "suppression_iou": iou,
                        "threshold": threshold,
                        "base_decay": float(base_decay),
                        "decay": decay,
                        "gamma": float(gamma[local].detach().cpu()),
                        "pair_density": float(pair_density[local].detach().cpu()),
                        "p_duplicate": float(probs[0]),
                        "p_neighbor": float(probs[1]),
                        "p_background_conflict": float(probs[2]),
                    }
                )
            if float(final_scores[victim].detach().cpu()) < float(score_floor):
                remaining.remove(int(victim))
    return kept, final_scores, events


def relation_aware_nms(
    boxes: torch.Tensor,
    scores: torch.Tensor,
    *,
    lam: torch.Tensor,
    kappa: torch.Tensor,
    relation_probs: torch.Tensor,
    row_idx: torch.Tensor | None = None,
    tau_base: float = 0.70,
    tau_min: float = 0.30,
    tau_max: float = 0.90,
    p_max: float = 0.20,
    s_max: float = 0.20,
    max_det: int = 300,
) -> tuple[list[int], list[dict]]:
    b = boxes.to(torch.float32)
    score = scores.to(torch.float32)
    rel = relation_probs.to(torch.float32)
    if rel.shape != (b.shape[0], b.shape[0], 3):
        raise ValueError(f"relation_probs must have shape ({b.shape[0]}, {b.shape[0]}, 3), got {tuple(rel.shape)}")
    ordered = deterministic_order(score, row_idx=row_idx)
    active = torch.ones(len(ordered), dtype=torch.bool)
    kept: list[int] = []
    events: list[dict] = []
    for order_pos, cand_idx in enumerate(ordered):
        if not bool(active[order_pos]):
            continue
        if len(kept) >= int(max_det):
            for tail_pos in range(order_pos, len(ordered)):
                if bool(active[tail_pos]):
                    events.append({"victim_index": int(ordered[tail_pos]), "reason": "max_det"})
            break
        kept.append(int(cand_idx))
        rest_positions = [p for p in range(order_pos + 1, len(ordered)) if bool(active[p])]
        if not rest_positions:
            continue
        rest_idx = torch.tensor([ordered[p] for p in rest_positions], dtype=torch.long, device=b.device)
        ious = box_iou_torch(b[cand_idx : cand_idx + 1], b[rest_idx])[0]
        pair_rel = rel[int(cand_idx), rest_idx]
        thresholds = pairwise_thresholds(
            victim_indices=rest_idx.cpu(),
            relation_probs=pair_rel.cpu(),
            lam=lam.cpu(),
            kappa=kappa.cpu(),
            tau_base=tau_base,
            tau_min=tau_min,
            tau_max=tau_max,
            p_max=p_max,
            s_max=s_max,
        ).to(ious.device)
        for local, (pos, victim_idx) in enumerate(zip(rest_positions, rest_idx.detach().cpu().tolist())):
            if float(ious[local]) > float(thresholds[local]):
                active[pos] = False
                probs = pair_rel[local].detach().cpu()
                victim = torch.tensor([victim_idx], dtype=torch.long)
                protect_margin = float(lam.detach().cpu()[victim].item() * float(p_max) * probs[1].item())
                suppress_margin = float(kappa.detach().cpu()[victim].item() * float(s_max) * probs[0].item())
                events.append(
                    {
                        "suppressor_index": int(cand_idx),
                        "victim_index": int(victim_idx),
                        "reason": "iou",
                        "suppression_iou": float(ious[local].detach().cpu()),
                        "threshold": float(thresholds[local].detach().cpu()),
                        "protect_margin": protect_margin,
                        "suppress_margin": suppress_margin,
                    }
                )
    return kept, events
