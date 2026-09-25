"""日报聚合与 CSV 导出（文档第 8 节 /report/daily 与 /report/daily.csv）。"""
from __future__ import annotations

from datetime import datetime

from .storage import Storage

CSV_COLUMNS = [
    "event_id", "request_id", "farm_id", "barn_id", "created_at", "captured_at",
    "status", "risk_level", "risk_code", "pig_count", "density",
    "quality_status", "merged_observation_count", "updated_at",
]


def _event_row(event: dict) -> list:
    state = event.get("state", {})
    quality = state.get("quality", {})
    return [
        event.get("event_id"), event.get("request_id"), event.get("farm_id"),
        event.get("barn_id"), event.get("created_at"), event.get("captured_at"),
        event.get("status"), event.get("risk", {}).get("level"), event.get("risk", {}).get("code"),
        state.get("pig_count"), state.get("density"), quality.get("status"),
        event.get("merged_observation_count", 0), event.get("updated_at"),
    ]


def _csv_cell(value) -> str:
    if value is None:
        return ""
    text = str(value)
    if any(ch in text for ch in (",", '"', "\n")):
        return '"' + text.replace('"', '""') + '"'
    return text


def daily_report(storage: Storage, farm_name: str, date: str | None = None) -> dict:
    date = date or datetime.now().astimezone().strftime("%Y-%m-%d")
    events, total = storage.list_events(date=date, limit=10000, offset=0)

    by_level: dict[str, int] = {}
    by_status: dict[str, int] = {}
    by_code: dict[str, int] = {}
    barns: dict[str, dict] = {}
    open_events: list[dict] = []

    for event in events:
        risk = event.get("risk", {})
        level = risk.get("level") or "none"
        code = risk.get("code") or "-"
        status = event.get("status", "open")
        by_level[level] = by_level.get(level, 0) + 1
        by_status[status] = by_status.get(status, 0) + 1
        by_code[code] = by_code.get(code, 0) + 1
        barn = barns.setdefault(event["barn_id"], {"events": 0, "alerts": 0, "open_alerts": 0})
        barn["events"] += 1
        if code != "-":
            barn["alerts"] += 1
            if status in ("open", "acknowledged"):
                barn["open_alerts"] += 1
                open_events.append(
                    {
                        "event_id": event["event_id"],
                        "barn_id": event["barn_id"],
                        "risk_level": level,
                        "risk_code": code,
                        "status": status,
                        "created_at": event["created_at"],
                        "last_observed_at": event.get("last_observed_at"),
                        "merged_observation_count": event.get("merged_observation_count", 0),
                    }
                )

    open_events.sort(key=lambda e: (e["risk_level"], e["created_at"]), reverse=True)
    return {
        "farm": farm_name,
        "date": date,
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "summary": {
            "events": total,
            "by_level": by_level,
            "by_status": by_status,
            "by_code": by_code,
            "barns_reporting": len(barns),
        },
        "barns": [
            {"barn_id": barn_id, **stats} for barn_id, stats in sorted(barns.items())
        ],
        "open_alerts": open_events,
        "event_ids": [e["event_id"] for e in events],
    }


def daily_report_csv(storage: Storage, date: str | None = None) -> str:
    date = date or datetime.now().astimezone().strftime("%Y-%m-%d")
    events, _ = storage.list_events(date=date, limit=10000, offset=0)
    lines = [",".join(CSV_COLUMNS)]
    lines.extend(",".join(_csv_cell(cell) for cell in _event_row(e)) for e in events)
    return "\r\n".join(lines) + "\r\n"
