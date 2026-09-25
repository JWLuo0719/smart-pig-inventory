"""环境变量与 config.json 解析。

优先级：显式参数 > 环境变量 > config.json > 内置默认值。
支持的环境变量（文档第 9 节）：
  PIG_AGENT_CONFIG      配置文件路径
  PIG_AGENT_MODEL_DIR   模型制品目录（覆盖 config.model.artifacts）
  PIG_AGENT_DATA_DIR    数据目录（SQLite、证据、JSONL）
  PIG_AGENT_WEIGHTS     真实模式权重文件（覆盖制品目录内的 model.pt）
  PIG_AGENT_HOST/PORT   服务监听地址
  PIG_AGENT_LOG_LEVEL   日志级别（DEBUG/INFO/WARNING/ERROR）
  PIG_AGENT_API_TOKEN   写操作令牌（局域网部署时保护确认/关闭接口）
  PIG_AGENT_POLLING_DEVICE  目录轮询的摄像头/设备号（写入事件来源）
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import json
import os

from .models import RISK_LEVELS, ValidationError

PROJECT_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_CAPACITY = 45
DEFAULT_UPLOAD_MAX_BYTES = 10 * 1024 * 1024
DEFAULT_UPLOAD_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")


class ConfigError(RuntimeError):
    pass


@dataclass(frozen=True)
class BarnConfig:
    barn_id: str
    capacity: int


@dataclass(frozen=True)
class RiskRule:
    code: str
    level: str
    metric: str  # density 或 quality
    enabled: bool = True
    threshold: float | None = None
    min_coverage: float | None = None
    confirm_observations: int = 2
    cooldown_minutes: int = 60
    actions: tuple[str, ...] = ()

    @property
    def cooldown_seconds(self) -> float:
        return float(self.cooldown_minutes) * 60.0


@dataclass
class AgentConfig:
    config_path: Path
    farm_name: str
    barns: dict[str, BarnConfig]
    model_mode: str
    model_name: str
    model_version: str
    model_dir: Path | None
    weights: str | None
    rules: list[RiskRule]
    auto_resolve_observations: int
    require_human_confirmation: bool
    upload_max_bytes: int
    upload_extensions: tuple[str, ...]
    data_dir: Path
    host: str
    port: int
    log_level: str
    polling_enabled: bool = False
    polling_watch_dir: Path | None = None
    polling_interval: float = 30.0
    polling_device_id: str | None = None
    api_token: str | None = None

    def barn(self, barn_id: str) -> BarnConfig:
        barn = self.barns.get(barn_id)
        if barn is None:
            known = ", ".join(sorted(self.barns))
            raise ValidationError(f"未知栏舍 {barn_id!r}，已配置: {known}")
        return barn

    def rule(self, code: str) -> RiskRule | None:
        return next((r for r in self.rules if r.code == code), None)

    @property
    def writes_protected(self) -> bool:
        """是否启用写操作令牌校验（局域网部署时建议开启）。"""
        return bool(self.api_token)

    def snapshot(self) -> dict:
        """健康检查用的只读摘要（不包含令牌明文）。"""
        return {
            "farm": self.farm_name,
            "barns": sorted(self.barns),
            "model_mode": self.model_mode,
            "data_dir": str(self.data_dir),
            "writes_protected": self.writes_protected,
            "polling": {
                "enabled": self.polling_enabled,
                "watch_dir": str(self.polling_watch_dir) if self.polling_watch_dir else None,
                "interval_seconds": self.polling_interval,
                "device_id": self.polling_device_id,
            },
            "rules": [
                {
                    "code": r.code,
                    "level": r.level,
                    "threshold": r.threshold,
                    "min_coverage": r.min_coverage,
                    "confirm_observations": r.confirm_observations,
                    "cooldown_minutes": r.cooldown_minutes,
                }
                for r in self.rules
            ],
        }


def _default_rule_dicts(density_alert: float) -> list[dict]:
    return [
        {
            "code": "DENSITY_HIGH",
            "level": "high",
            "metric": "density",
            "threshold": density_alert,
            "confirm_observations": 2,
            "cooldown_minutes": 60,
            "actions": [
                "15分钟内现场复核该栏舍",
                "检查通风与饮水设备",
                "必要时分群降低密度",
            ],
        },
        {
            "code": "DENSITY_WATCH",
            "level": "medium",
            "metric": "density",
            "threshold": 0.68,
            "confirm_observations": 2,
            "cooldown_minutes": 30,
            "actions": ["安排本班次巡检", "观察采食和饮水情况"],
        },
        {
            "code": "DATA_QUALITY_LOW",
            "level": "medium",
            "metric": "quality",
            "min_coverage": 0.80,
            "actions": ["重新拍摄或更换摄像头快照", "检查镜头污损、光照与遮挡"],
        },
    ]


def _parse_barns(raw) -> dict[str, BarnConfig]:
    barns: dict[str, BarnConfig] = {}
    if isinstance(raw, dict):
        items = raw.items()
        for barn_id, spec in items:
            capacity = spec.get("capacity", DEFAULT_CAPACITY) if isinstance(spec, dict) else spec
            barns[str(barn_id)] = BarnConfig(str(barn_id), int(capacity))
    elif isinstance(raw, list):
        for barn_id in raw:
            barns[str(barn_id)] = BarnConfig(str(barn_id), DEFAULT_CAPACITY)
    else:
        raise ConfigError("farm.barns 必须是字典或列表")
    if not barns:
        raise ConfigError("farm.barns 不能为空")
    return barns


def _parse_rules(raw: list | None, density_alert: float) -> list[RiskRule]:
    rules = []
    seen: set[str] = set()
    for item in raw if raw is not None else _default_rule_dicts(density_alert):
        code = str(item["code"])
        if code in seen:
            raise ConfigError(f"重复的风险规则代码: {code}")
        seen.add(code)
        level = str(item.get("level", "medium"))
        if level not in RISK_LEVELS or level == "none":
            raise ConfigError(f"规则 {code} 的 level 非法: {level}")
        metric = str(item.get("metric", "density"))
        if metric not in ("density", "quality"):
            raise ConfigError(f"规则 {code} 的 metric 非法: {metric}")
        rules.append(
            RiskRule(
                code=code,
                level=level,
                metric=metric,
                enabled=bool(item.get("enabled", True)),
                threshold=(
                    float(item["threshold"])
                    if item.get("threshold") is not None and metric == "density"
                    else None
                ),
                min_coverage=(
                    float(item.get("min_coverage", item.get("threshold")))
                    if metric == "quality"
                    else None
                ),
                confirm_observations=max(1, int(item.get("confirm_observations", 2))),
                cooldown_minutes=max(0, int(item.get("cooldown_minutes", 60))),
                actions=tuple(item.get("actions") or ()),
            )
        )
    return rules


def load_config(
    path: str | Path | None = None,
    *,
    data_dir: str | Path | None = None,
    host: str | None = None,
    port: int | None = None,
    log_level: str | None = None,
    model_dir: str | Path | None = None,
    use_env: bool = True,
) -> AgentConfig:
    config_path = Path(path or os.getenv("PIG_AGENT_CONFIG") or PROJECT_ROOT / "config.json")
    raw: dict = {}
    if config_path.exists():
        raw = json.loads(config_path.read_text(encoding="utf-8-sig"))

    farm = raw.get("farm", {})
    model = raw.get("model", {})
    agent = raw.get("agent", {})

    env = os.environ if use_env else {}
    density_alert = float(farm.get("density_alert", 0.82))

    artifacts = model.get("artifacts", "model_artifacts/dcr-softnms-yolov13-v1")
    resolved_model_dir = (
        Path(model_dir or env.get("PIG_AGENT_MODEL_DIR") or (PROJECT_ROOT / artifacts))
        if (model.get("mode", "mock") == "real" or env.get("PIG_AGENT_MODEL_DIR") or model_dir)
        else None
    )
    if resolved_model_dir is not None:
        resolved_model_dir = Path(resolved_model_dir)

    resolved_data_dir = Path(data_dir or env.get("PIG_AGENT_DATA_DIR") or PROJECT_ROOT / "data")
    upload = agent.get("upload", {})
    polling = agent.get("polling", {})
    polling_watch = polling.get("watch_dir")
    polling_watch_dir = Path(polling_watch) if polling_watch else resolved_data_dir / "polling"
    polling_device = env.get("PIG_AGENT_POLLING_DEVICE") or polling.get("device_id")
    api_token = env.get("PIG_AGENT_API_TOKEN") or agent.get("api_token")

    return AgentConfig(
        config_path=config_path,
        farm_name=str(farm.get("name", "示范猪场")),
        barns=_parse_barns(farm.get("barns", ["A01", "A02"])),
        model_mode=str(model.get("mode", "mock")),
        model_name=str(model.get("name", "DCR-SoftNMS-YOLOv13")),
        model_version=str(model.get("version", "v1")),
        model_dir=resolved_model_dir,
        weights=env.get("PIG_AGENT_WEIGHTS") or model.get("weights"),
        rules=_parse_rules(agent.get("risk_rules"), density_alert),
        auto_resolve_observations=max(1, int(agent.get("auto_resolve", {}).get("confirm_observations", 2))),
        require_human_confirmation=bool(agent.get("require_human_confirmation", True)),
        upload_max_bytes=int(upload.get("max_bytes", DEFAULT_UPLOAD_MAX_BYTES)),
        upload_extensions=tuple(
            ext.lower() if ext.startswith(".") else f".{ext.lower()}"
            for ext in upload.get("allowed_extensions", DEFAULT_UPLOAD_EXTENSIONS)
        ),
        data_dir=resolved_data_dir,
        host=str(host or env.get("PIG_AGENT_HOST", "127.0.0.1")),
        port=int(port or env.get("PIG_AGENT_PORT", "8787")),
        log_level=str(log_level or env.get("PIG_AGENT_LOG_LEVEL", "INFO")).upper(),
        polling_enabled=bool(polling.get("enabled", False)),
        polling_watch_dir=polling_watch_dir,
        polling_interval=max(5.0, float(polling.get("interval_seconds", 30))),
        polling_device_id=str(polling_device) if polling_device else None,
        api_token=str(api_token) if api_token else None,
    )
