"""数据契约：Observation、Evidence、Alert/Event、Action 与事件状态机。

对应《第一代产品技术开发文档》第 5 节。事件 JSON 的字段顺序与文档 5.2
的示例保持一致，新增字段（updated_at、status_history 等）追加在后面，
便于 App 与看板向前兼容。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import re
import secrets
import time

RISK_LEVELS = ("none", "low", "medium", "high")
RISK_ORDER = {name: i for i, name in enumerate(RISK_LEVELS)}
EVENT_STATUSES = ("open", "acknowledged", "resolved", "dismissed")

# 事件状态机：open -> acknowledged -> resolved，也允许 open -> dismissed。
ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "open": {"acknowledged", "resolved", "dismissed"},
    "acknowledged": {"resolved", "dismissed"},
    "resolved": set(),
    "dismissed": set(),
}


class DomainError(RuntimeError):
    """领域层可预期错误，携带机器可读的错误码。"""

    error_code = "DOMAIN_ERROR"
    http_status = 400

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class EventNotFound(DomainError):
    error_code = "EVENT_NOT_FOUND"
    http_status = 404


class InvalidTransition(DomainError):
    error_code = "INVALID_TRANSITION"
    http_status = 409


class ValidationError(DomainError):
    error_code = "VALIDATION_ERROR"
    http_status = 400


class ModelUnavailable(DomainError):
    error_code = "MODEL_UNAVAILABLE"
    http_status = 503


def ensure_transition(current: str, target: str) -> None:
    if current not in ALLOWED_TRANSITIONS:
        raise InvalidTransition(f"未知事件状态: {current}")
    if target not in ALLOWED_TRANSITIONS[current]:
        raise InvalidTransition(f"不允许的状态转换: {current} -> {target}")


def utc_now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="milliseconds")


def new_id(prefix: str) -> str:
    stamp = time.strftime("%Y%m%d%H%M%S")
    return f"{prefix}-{stamp}-{secrets.token_hex(3)}"


_ID_PATTERN = re.compile(r"^[\w.:@-]{1,128}$")


def validate_id(value: str, field_name: str) -> str:
    if not isinstance(value, str) or not _ID_PATTERN.match(value):
        raise ValidationError(f"{field_name} 含非法字符或超长: {value!r}")
    return value


@dataclass
class Quality:
    status: str = "usable"
    coverage: float | None = None

    def to_dict(self) -> dict:
        return {"status": self.status, "coverage": self.coverage}


@dataclass
class Observation:
    """一次栏舍观测的状态块，写入事件 state 字段。"""

    barn_id: str
    pig_count: int
    density: float | None
    quality: Quality = field(default_factory=Quality)
    trend: dict | None = None

    def to_dict(self) -> dict:
        return {
            "pig_count": self.pig_count,
            "density": self.density,
            "quality": self.quality.to_dict(),
            "trend": self.trend,
        }


@dataclass
class RiskAssessment:
    """风险引擎输出，写入事件 risk 字段。"""

    level: str = "none"
    code: str | None = None
    confidence: float = 0.0
    thresholds: dict = field(default_factory=dict)
    consecutive_breaches: int = 0
    note: str = ""

    @property
    def fires_event(self) -> bool:
        return self.code is not None

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "code": self.code,
            "confidence": round(float(self.confidence), 2),
            "thresholds": self.thresholds,
            "consecutive_breaches": self.consecutive_breaches,
            "note": self.note,
        }


@dataclass
class Evidence:
    image: str | None = None
    metrics: str | None = None
    annotated: str | None = None

    def to_dict(self) -> dict:
        return {"image": self.image, "metrics": self.metrics, "annotated": self.annotated}


@dataclass
class Event:
    """猪群状态事件。to_dict() 输出与文档 5.2 的契约一致。"""

    event_id: str
    request_id: str
    farm_id: str
    barn_id: str
    captured_at: str
    created_at: str
    state: dict
    risk: dict
    evidence: dict
    suggested_actions: list[str]
    status: str = "open"
    model: dict = field(default_factory=dict)
    human_confirmation_required: bool = True
    updated_at: str = ""
    last_observed_at: str = ""
    merged_observation_count: int = 0
    status_history: list[dict] = field(default_factory=list)

    def __post_init__(self):
        if not self.updated_at:
            self.updated_at = self.created_at
        if not self.last_observed_at:
            self.last_observed_at = self.created_at

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "request_id": self.request_id,
            "farm_id": self.farm_id,
            "barn_id": self.barn_id,
            "captured_at": self.captured_at,
            "state": self.state,
            "risk": self.risk,
            "evidence": self.evidence,
            "suggested_actions": self.suggested_actions,
            "status": self.status,
            "model": self.model,
            "human_confirmation_required": self.human_confirmation_required,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "last_observed_at": self.last_observed_at,
            "merged_observation_count": self.merged_observation_count,
            "status_history": list(self.status_history),
        }

    @classmethod
    def from_dict(cls, payload: dict) -> "Event":
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in payload.items() if k in known})

    def record_transition(self, to_status: str, operator: str, note: str | None, at: str) -> None:
        ensure_transition(self.status, to_status)
        self.status_history.append(
            {
                "at": at,
                "from": self.status,
                "to": to_status,
                "operator": operator,
                "note": note,
            }
        )
        self.status = to_status
        self.updated_at = at


def new_event(
    *,
    request_id: str,
    farm_id: str,
    barn_id: str,
    captured_at: str,
    state: dict,
    risk: dict,
    evidence: dict,
    suggested_actions: list[str],
    model: dict,
    human_confirmation_required: bool,
) -> Event:
    now = utc_now_iso()
    return Event(
        event_id=new_id("evt"),
        request_id=request_id,
        farm_id=farm_id,
        barn_id=barn_id,
        captured_at=captured_at,
        created_at=now,
        state=state,
        risk=risk,
        evidence=evidence,
        suggested_actions=suggested_actions,
        model=model,
        human_confirmation_required=human_confirmation_required,
        status_history=[
            {"at": now, "from": None, "to": "open", "operator": "system", "note": "事件创建"}
        ],
    )
