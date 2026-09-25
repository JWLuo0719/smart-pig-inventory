"""SQLite 事件存储 + JSONL 镜像。

主存为 SQLite（事件、观测、审计、请求幂等表）；每次事件写入/更新同步
追加 JSONL 快照到 data/events.jsonl，作为故障恢复与导出格式（文档第 9 节）。
所有操作通过 threading.Lock 串行化，适配多线程 HTTP 服务。
"""
from __future__ import annotations

from pathlib import Path
import json
import sqlite3
import threading

from .models import EventNotFound, ensure_transition, new_id, utc_now_iso

_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    request_id TEXT UNIQUE,
    barn_id TEXT NOT NULL,
    risk_code TEXT,
    risk_level TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_observed_at TEXT NOT NULL,
    payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_barn ON events(barn_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE TABLE IF NOT EXISTS observations (
    observation_id TEXT PRIMARY KEY,
    event_id TEXT,
    request_id TEXT UNIQUE,
    barn_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    pig_count INTEGER,
    density REAL,
    quality_status TEXT,
    payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_obs_barn ON observations(barn_id, created_at DESC);
CREATE TABLE IF NOT EXISTS audit_log (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL,
    action TEXT NOT NULL,
    from_status TEXT,
    to_status TEXT,
    operator TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS analyze_requests (
    request_id TEXT PRIMARY KEY,
    event_id TEXT,
    response TEXT NOT NULL,
    created_at TEXT NOT NULL
);
"""


class Storage:
    def __init__(self, data_dir: Path):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.data_dir / "agent.db"
        self.jsonl_path = self.data_dir / "events.jsonl"
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.executescript(_SCHEMA)
            self._conn.commit()

    # ---------- 底层 ----------

    def _append_jsonl(self, action: str, payload: dict) -> None:
        record = {"recorded_at": utc_now_iso(), "action": action, "event": payload}
        with self.jsonl_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    @staticmethod
    def _row_to_event(row: sqlite3.Row) -> dict:
        return json.loads(row["payload"])

    # ---------- 事件 ----------

    def save_event(self, event: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO events (event_id, request_id, barn_id, risk_code, risk_level,"
                " status, created_at, last_observed_at, payload) VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    event["event_id"], event["request_id"], event["barn_id"],
                    event["risk"].get("code"), event["risk"]["level"], event["status"],
                    event["created_at"], event["last_observed_at"],
                    json.dumps(event, ensure_ascii=False),
                ),
            )
            self._conn.commit()
        self._append_jsonl("event_created", event)

    def get_event(self, event_id: str) -> dict:
        with self._lock:
            row = self._conn.execute("SELECT * FROM events WHERE event_id = ?", (event_id,)).fetchone()
        if row is None:
            raise EventNotFound(f"事件不存在: {event_id}")
        return self._row_to_event(row)

    def update_event(self, event: dict, *, action: str, operator: str, note: str | None = None,
                     from_status: str | None = None) -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE events SET status = ?, risk_code = ?, last_observed_at = ?, payload = ?"
                " WHERE event_id = ?",
                (
                    event["status"], event["risk"].get("code"), event["last_observed_at"],
                    json.dumps(event, ensure_ascii=False), event["event_id"],
                ),
            )
            self._conn.execute(
                "INSERT INTO audit_log (event_id, action, from_status, to_status, operator, note, created_at)"
                " VALUES (?,?,?,?,?,?,?)",
                (event["event_id"], action, from_status, event["status"], operator, note, event["updated_at"]),
            )
            self._conn.commit()
        self._append_jsonl(f"event_{action}", event)

    def transition_event(self, event_id: str, to_status: str, *, operator: str, note: str | None) -> dict:
        with self._lock:
            row = self._conn.execute("SELECT * FROM events WHERE event_id = ?", (event_id,)).fetchone()
            if row is None:
                raise EventNotFound(f"事件不存在: {event_id}")
            event = self._row_to_event(row)
            ensure_transition(event["status"], to_status)
            from_status = event["status"]
            now = utc_now_iso()
            event.setdefault("status_history", []).append(
                {"at": now, "from": from_status, "to": to_status, "operator": operator, "note": note}
            )
            event["status"] = to_status
            event["updated_at"] = now
            self.update_event(event, action="status_changed", operator=operator, note=note,
                              from_status=from_status)
            return event

    def list_events(self, *, barn_id: str | None = None, status: str | None = None,
                    date: str | None = None, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
        clauses, params = [], []
        if barn_id:
            clauses.append("barn_id = ?"); params.append(barn_id)
        if status:
            clauses.append("status = ?"); params.append(status)
        if date:
            clauses.append("substr(created_at, 1, 10) = ?"); params.append(date)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        with self._lock:
            total = self._conn.execute(
                f"SELECT COUNT(*) FROM events {where}", params
            ).fetchone()[0]
            rows = self._conn.execute(
                f"SELECT * FROM events {where} ORDER BY created_at DESC LIMIT ? OFFSET ?",
                [*params, int(limit), int(offset)],
            ).fetchall()
        return [self._row_to_event(r) for r in rows], int(total)

    def find_active_event(self, barn_id: str, risk_code: str, *, since_iso: str) -> dict | None:
        """冷却合并查询：同栏舍同代码、未关闭且在冷却窗口内的事件。"""
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM events WHERE barn_id = ? AND risk_code = ?"
                " AND status IN ('open','acknowledged') AND last_observed_at >= ?"
                " ORDER BY created_at DESC LIMIT 1",
                (barn_id, risk_code, since_iso),
            ).fetchone()
        return self._row_to_event(row) if row else None

    def open_alert_events(self, barn_id: str, codes: list[str]) -> list[dict]:
        placeholders = ",".join("?" * len(codes))
        with self._lock:
            rows = self._conn.execute(
                f"SELECT * FROM events WHERE barn_id = ? AND risk_code IN ({placeholders})"
                " AND status IN ('open','acknowledged') ORDER BY created_at DESC",
                (barn_id, *codes),
            ).fetchall()
        return [self._row_to_event(r) for r in rows]

    # ---------- 观测 ----------

    def save_observation(self, *, event_id: str | None, request_id: str, barn_id: str,
                         state: dict, captured_at: str) -> str:
        quality = state.get("quality", {})
        observation = {
            "observation_id": new_id("obs"),
            "event_id": event_id,
            "request_id": request_id,
            "barn_id": barn_id,
            "captured_at": captured_at,
            "created_at": utc_now_iso(),
            "state": state,
        }
        with self._lock:
            self._conn.execute(
                "INSERT INTO observations (observation_id, event_id, request_id, barn_id,"
                " created_at, pig_count, density, quality_status, payload)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    observation["observation_id"], event_id, request_id, barn_id,
                    observation["created_at"], state.get("pig_count"), state.get("density"),
                    quality.get("status"), json.dumps(observation, ensure_ascii=False),
                ),
            )
            self._conn.commit()
        return observation["observation_id"]

    def latest_observation(self, barn_id: str) -> dict | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT payload FROM observations WHERE barn_id = ?"
                " ORDER BY created_at DESC, rowid DESC LIMIT 1",
                (barn_id,),
            ).fetchone()
        return json.loads(row["payload"]) if row else None

    def observation_history(self, barn_id: str, limit: int = 10) -> list[dict]:
        """新到旧排列，供连续帧确认与恢复判定使用。"""
        with self._lock:
            rows = self._conn.execute(
                "SELECT payload FROM observations WHERE barn_id = ?"
                " ORDER BY created_at DESC, rowid DESC LIMIT ?",
                (barn_id, int(limit)),
            ).fetchall()
        return [json.loads(r["payload"]) for r in rows]

    # ---------- 请求幂等 ----------

    def save_request_response(self, request_id: str, event_id: str | None, response: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT OR IGNORE INTO analyze_requests (request_id, event_id, response, created_at)"
                " VALUES (?,?,?,?)",
                (request_id, event_id, json.dumps(response, ensure_ascii=False), utc_now_iso()),
            )
            self._conn.commit()

    def get_request_response(self, request_id: str) -> dict | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT response, created_at FROM analyze_requests WHERE request_id = ?",
                (request_id,),
            ).fetchone()
        if row is None:
            return None
        return {"request_id": request_id, "created_at": row["created_at"], "response": json.loads(row["response"])}

    # ---------- 统计 ----------

    def stats(self) -> dict:
        with self._lock:
            events = self._conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
            observations = self._conn.execute("SELECT COUNT(*) FROM observations").fetchone()[0]
            open_events = self._conn.execute(
                "SELECT COUNT(*) FROM events WHERE status IN ('open','acknowledged')"
            ).fetchone()[0]
        return {
            "ok": True,
            "database": str(self.db_path),
            "events": int(events),
            "observations": int(observations),
            "open_events": int(open_events),
        }

    def audit_for_event(self, event_id: str) -> list[dict]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT action, from_status, to_status, operator, note, created_at"
                " FROM audit_log WHERE event_id = ? ORDER BY seq",
                (event_id,),
            ).fetchall()
        return [dict(r) for r in rows]

    def close(self) -> None:
        with self._lock:
            self._conn.close()
