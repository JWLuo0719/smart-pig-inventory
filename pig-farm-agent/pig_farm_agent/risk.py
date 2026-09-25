"""风险引擎：可解释规则 + 连续帧确认 + 冷却口径。

V1 不训练新的行为模型。规则、阈值、连续帧数与冷却时间全部来自
config.json；评估结果携带实际阈值写入事件，保证可复盘（文档第 6 节）。
"""
from __future__ import annotations

from .config import RiskRule
from .models import RISK_ORDER
from .state import quality_ok


def _trailing_streak(history: list[dict], predicate) -> int:
    """history 为新到旧排列；从最新一条往前数连续满足谓词的条数。"""
    streak = 0
    for item in history:
        if predicate(item):
            streak += 1
        else:
            break
    return streak


def _obs_density(item: dict) -> float | None:
    value = item.get("state", {}).get("density")
    return float(value) if isinstance(value, (int, float)) else None


class RiskEngine:
    def __init__(self, rules: list[RiskRule]):
        self.rules = sorted(
            (r for r in rules if r.enabled),
            key=lambda r: RISK_ORDER.get(r.level, 0),
            reverse=True,
        )
        self.density_rules = [r for r in self.rules if r.metric == "density"]
        self.quality_rule = next((r for r in self.rules if r.metric == "quality"), None)

    def assess(self, state: dict, history: list[dict]) -> dict:
        """输出 risk 块。history 是同栏舍更早的观测（新到旧），不含当前。"""
        # 1. 质量门优先：输入不足时给出 DATA_QUALITY_LOW，不产生密度类高风险结论。
        if self.quality_rule is not None:
            rule = self.quality_rule
            if not quality_ok(state, rule.min_coverage):
                coverage = state.get("quality", {}).get("coverage")
                confidence = 0.7
                if rule.min_coverage is not None and isinstance(coverage, (int, float)):
                    confidence = min(0.99, 0.6 + (rule.min_coverage - coverage) * 1.5)
                return {
                    "level": rule.level,
                    "code": rule.code,
                    "confidence": round(confidence, 2),
                    "thresholds": {
                        "quality_status_required": "usable",
                        "min_coverage": rule.min_coverage,
                    },
                    "consecutive_breaches": 1,
                    "note": "输入质量不足，已抑制密度类风险结论",
                }

        # 2. 密度规则：按严重级别从高到低评估，需满足连续观测确认。
        density = state.get("density")
        if not isinstance(density, (int, float)):
            return {
                "level": "none",
                "code": None,
                "confidence": 0.0,
                "thresholds": {},
                "consecutive_breaches": 0,
                "note": "缺少密度数据（栏舍容量未配置）",
            }

        for rule in self.density_rules:
            if rule.threshold is None or density < rule.threshold:
                continue
            streak = 1 + _trailing_streak(
                history, lambda item: (d := _obs_density(item)) is not None and d >= rule.threshold
            )
            if streak >= rule.confirm_observations:
                confidence = min(0.99, 0.6 + (density - rule.threshold) * 1.5)
                return {
                    "level": rule.level,
                    "code": rule.code,
                    "confidence": round(confidence, 2),
                    "thresholds": {
                        "density": rule.threshold,
                        "confirm_observations": rule.confirm_observations,
                        "cooldown_minutes": rule.cooldown_minutes,
                    },
                    "consecutive_breaches": streak,
                    "note": f"密度 {density:.2f} 连续 {streak} 次超过阈值 {rule.threshold}",
                }
            # 已越过高阈值但未满足连续确认：不再检查更低级别的规则。
            return {
                "level": "none",
                "code": None,
                "confidence": 0.0,
                "thresholds": {"density": rule.threshold, "confirm_observations": rule.confirm_observations},
                "consecutive_breaches": streak,
                "note": f"密度超标 {streak}/{rule.confirm_observations} 次，待连续确认",
            }

        return {
            "level": "none",
            "code": None,
            "confidence": 0.0,
            "thresholds": {r.code: r.threshold for r in self.density_rules},
            "consecutive_breaches": 0,
            "note": "密度处于正常区间",
        }

    def recovery_streak(self, state: dict, history: list[dict], code: str) -> int:
        """自动恢复判定：连续多少次观测（含当前）低于指定规则的阈值。"""
        rule = next((r for r in self.density_rules if r.code == code), None)
        if rule is None or rule.threshold is None:
            return 0
        density = state.get("density")
        if not isinstance(density, (int, float)) or density >= rule.threshold:
            return 0
        return 1 + _trailing_streak(
            history,
            lambda item: (d := _obs_density(item)) is not None and d < rule.threshold,
        )

    def actions_for(self, code: str | None) -> list[str]:
        """建议动作由规则模板生成，不调用外部大模型（文档第 7 节）。"""
        if code is None:
            return ["保持常规巡检"]
        rule = next((r for r in self.rules if r.code == code), None)
        if rule is None or not rule.actions:
            return ["复核该栏舍状态"]
        return list(rule.actions)
