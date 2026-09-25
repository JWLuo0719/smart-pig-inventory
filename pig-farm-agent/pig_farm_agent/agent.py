"""Agent 编排：校验输入 -> Detector -> 状态计算 -> 风险规则 -> 证据 -> 持久化。

对应文档第 7 节。Agent 不调用外部大语言模型；建议文本由规则模板生成。
关键行为：
- request_id 幂等：重复请求返回已存储结果，不产生重复事件（文档 1.1）。
- 冷却合并：同栏舍同代码在冷却窗口内的重复观测合并进未关闭事件，
  原始观测仍逐条保留（文档 5.2 / 6）。
- 自动恢复：连续 N 次观测回到正常区间后，系统自动 resolved 告警事件。
- 真实模式制品校验失败时 fail-closed：/health 报 degraded，分析返回
  MODEL_UNAVAILABLE。
"""
from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path
import json

from . import __version__
from .config import AgentConfig, load_config
from .detector import DetectionResult, Detector, ModelArtifactError, build_detector
from .evidence import EvidenceStore
from .models import (
    Event,
    ModelUnavailable,
    ValidationError,
    new_id,
    utc_now_iso,
    validate_id,
)
from .report import daily_report, daily_report_csv
from .risk import RiskEngine
from .state import compute_state
from .storage import Storage

ALLOWED_SOURCES = ("upload", "polling", "snapshot", "manual")


class PigFarmAgent:
    def __init__(self, config: AgentConfig | None = None):
        self.config = config or load_config()
        self._model_error: str | None = None
        try:
            self.detector, self.model_info = build_detector(self.config)
        except ModelArtifactError as exc:
            self.detector = None
            self._model_error = str(exc)
            self.model_info = {
                "mode": self.config.model_mode,
                "name": self.config.model_name,
                "version": self.config.model_version,
                "manifest_verified": False,
                "error": self._model_error,
            }
        self.storage = Storage(self.config.data_dir)
        self.evidence_store = EvidenceStore(self.config.data_dir)
        self.engine = RiskEngine(self.config.rules)

    # ---------- 分析闭环 ----------

    def analyze(self, request: dict) -> dict:
        request_id, farm_id, barn_id, captured_at, source, image, device_id = self._normalize(request)

        stored = self.storage.get_request_response(request_id)
        if stored is not None:
            return stored["response"]

        if self.detector is None:
            raise ModelUnavailable(self._model_error or "模型不可用")

        barn = self.config.barn(barn_id)
        history = self.storage.observation_history(barn_id, limit=16)
        detection = self._predict(image, request_id=request_id, barn_id=barn_id)
        state = compute_state(detection, barn, previous=history[0] if history else None)
        if device_id:
            # 来源可追溯：目录轮询/网关快照写入设备号（产品规划 §4.1）
            state = {**state, "source_device": device_id}
        assessment = self.engine.assess(state, history)

        if assessment["code"] is not None:
            merged = self._try_merge(
                barn_id=barn_id,
                code=assessment["code"],
                state=state,
                risk=assessment,
                request_id=request_id,
                captured_at=captured_at,
            )
            if merged is not None:
                return merged

        event_id = new_id("evt")
        evidence = self.evidence_store.save(
            event_id, detection, state, image=image, risk=assessment
        )
        created_at = utc_now_iso()
        event = Event(
            event_id=event_id,
            request_id=request_id,
            farm_id=farm_id,
            barn_id=barn_id,
            captured_at=captured_at,
            created_at=created_at,
            state=state,
            risk=assessment,
            evidence=evidence,
            suggested_actions=self.engine.actions_for(assessment["code"]),
            model={
                "name": detection.model_name,
                "version": detection.model_version,
                "postprocess": detection.postprocess,
                "score_mode": detection.score_mode,
            },
            human_confirmation_required=self.config.require_human_confirmation,
            status_history=[
                {"at": created_at, "from": None, "to": "open", "operator": "system", "note": "事件创建"}
            ],
        ).to_dict()
        self.storage.save_event(event)
        self.storage.save_observation(
            event_id=event_id, request_id=request_id, barn_id=barn_id,
            state=state, captured_at=captured_at,
        )
        response = {"event": event, "merged": False}
        self.storage.save_request_response(request_id, event_id, response)

        if assessment["code"] is None:
            self._auto_resolve(barn_id, state, history)
        return response

    def _normalize(self, request: dict) -> tuple[str, str, str, str, str, str | None, str | None]:
        if not isinstance(request, dict):
            raise ValidationError("请求体必须是 JSON 对象")
        request_id = validate_id(request.get("request_id") or request.get("client_request_id") or new_id("req"), "request_id")
        barn_id = request.get("barn_id") or request.get("barn") or "A01"
        validate_id(barn_id, "barn_id")
        farm_id = request.get("farm_id") or "demo"
        validate_id(farm_id, "farm_id")
        captured_at = request.get("captured_at")
        if captured_at:
            try:
                datetime.fromisoformat(str(captured_at))
            except ValueError as exc:
                raise ValidationError(f"captured_at 不是合法 ISO 时间: {captured_at!r}") from exc
        else:
            captured_at = utc_now_iso()
        source = request.get("source") or "upload"
        if source not in ALLOWED_SOURCES:
            raise ValidationError(f"source 非法，允许值: {', '.join(ALLOWED_SOURCES)}")
        device_id = request.get("device_id") or request.get("device")
        if device_id is not None:
            device_id = validate_id(str(device_id), "device_id")
        image = request.get("image_path")
        if image is not None:
            image = str(image)
            if not Path(image).exists():
                raise ValidationError(f"image_path 不存在: {image}")
        return request_id, str(farm_id), str(barn_id), str(captured_at), str(source), image, device_id

    def _predict(self, image: str | None, *, request_id: str, barn_id: str) -> DetectionResult:
        try:
            return self.detector.predict(image, request_id=request_id, barn_id=barn_id)
        except ModelArtifactError as exc:
            raise ModelUnavailable(str(exc)) from exc

    def _try_merge(self, *, barn_id: str, code: str, state: dict, risk: dict,
                   request_id: str, captured_at: str) -> dict | None:
        rule = self.config.rule(code)
        cooldown = rule.cooldown_seconds if rule else 3600.0
        since = (datetime.now().astimezone() - timedelta(seconds=cooldown)).isoformat(timespec="milliseconds")
        existing = self.storage.find_active_event(barn_id, code, since_iso=since)
        if existing is None:
            return None

        now = utc_now_iso()
        existing["state"] = state
        existing["risk"] = {
            **risk,
            "level": existing["risk"].get("level") or risk["level"],
        }
        existing["last_observed_at"] = now
        existing["updated_at"] = now
        existing["merged_observation_count"] = existing.get("merged_observation_count", 0) + 1
        existing["suggested_actions"] = self.engine.actions_for(code)
        self.storage.update_event(existing, action="observation_merged", operator="system",
                                  note=f"冷却窗口内观测合并 #{existing['merged_observation_count']}")
        observation_id = self.storage.save_observation(
            event_id=existing["event_id"], request_id=request_id, barn_id=barn_id,
            state=state, captured_at=captured_at,
        )
        response = {"event": existing, "merged": True, "observation_id": observation_id}
        self.storage.save_request_response(request_id, existing["event_id"], response)
        return response

    def _auto_resolve(self, barn_id: str, state: dict, history: list[dict]) -> None:
        codes = [r.code for r in self.engine.density_rules]
        for event in self.storage.open_alert_events(barn_id, codes):
            streak = self.engine.recovery_streak(state, history, event["risk"]["code"])
            if streak >= self.config.auto_resolve_observations:
                note = f"连续 {streak} 次观测恢复正常，系统自动关闭"
                self.storage.transition_event(
                    event["event_id"], "resolved", operator="system", note=note
                )

    # ---------- 查询与操作 ----------

    def get_event(self, event_id: str) -> dict:
        return self.storage.get_event(event_id)

    def get_request(self, request_id: str) -> dict | None:
        return self.storage.get_request_response(request_id)

    def list_events(self, *, barn_id: str | None = None, status: str | None = None,
                    date: str | None = None, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
        return self.storage.list_events(
            barn_id=barn_id, status=status, date=date, limit=limit, offset=offset
        )

    def transition(self, event_id: str, to_status: str, *, operator: str, note: str | None = None) -> dict:
        return self.storage.transition_event(event_id, to_status, operator=operator, note=note)

    def daily_report(self, date: str | None = None) -> dict:
        return daily_report(self.storage, self.config.farm_name, date)

    def daily_report_csv(self, date: str | None = None) -> str:
        return daily_report_csv(self.storage, date)

    def replay_summary(self, path: str | Path | None = None) -> dict:
        """回放门槛摘要（模型升级门槛，看板展示用）：基线信息 + 覆盖统计。"""
        from .replay import DEFAULT_BASELINE_PATH, summarize

        baseline_path = Path(path) if path else DEFAULT_BASELINE_PATH
        if not baseline_path.exists():
            return {
                "available": False,
                "baseline_path": str(baseline_path),
                "hint": "运行 python -m pig_farm_agent.replay --update-baseline 生成基线",
            }
        try:
            baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            return {"available": False, "baseline_path": str(baseline_path), "error": str(exc)}

        codes: dict[str, int] = {}
        qualities: dict[str, int] = {}
        for item in baseline.get("results", []):
            key = item.get("risk_code") or "none"
            codes[key] = codes.get(key, 0) + 1
            quality = item.get("quality_status") or "unknown"
            qualities[quality] = qualities.get(quality, 0) + 1
        counts = [r["detected_count"] for r in baseline.get("results", [])
                  if isinstance(r.get("detected_count"), int)]
        return {
            "available": True,
            "baseline_path": str(baseline_path),
            "model_name": baseline.get("model_name"),
            "model_version": baseline.get("model_version"),
            "model_mode": baseline.get("model_mode"),
            "mode": baseline.get("mode"),
            "image_count": baseline.get("image_count"),
            "generated_at": baseline.get("generated_at"),
            "timing": baseline.get("timing", {}),
            "risk_codes": codes,
            "quality_statuses": qualities,
            "count_range": [min(counts), max(counts)] if counts else None,
            "summary": summarize(baseline),
        }

    def health(self) -> dict:
        status = "ok" if self.detector is not None else "degraded"
        return {
            "status": status,
            "agent": "pig-farm-agent",
            "version": __version__,
            "model": self.model_info,
            "storage": self.storage.stats(),
            "config": self.config.snapshot(),
        }

    def close(self) -> None:
        self.storage.close()
