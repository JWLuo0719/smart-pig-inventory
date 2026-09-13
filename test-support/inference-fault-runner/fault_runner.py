from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from threading import Lock
from time import sleep
from typing import Any


HOST = "0.0.0.0"
PORT = 9000
CONTROL_TOKEN = os.getenv("FAULT_CONTROL_TOKEN", "local-e2e-only")
MODEL_IDENTITY = {
    "model_key": os.getenv("MODEL_KEY", "pending-license-review"),
    "model_version": os.getenv("MODEL_VERSION", "unverified"),
    "model_checksum": os.getenv("MODEL_CHECKSUM", "unverified"),
    "adapter_version": os.getenv("MODEL_ADAPTER_VERSION", "http-v1"),
}
STATE: dict[str, Any] = {
    "mode": os.getenv("FAULT_INITIAL_MODE", "not_ready"),
    "delay_seconds": float(os.getenv("FAULT_DELAY_SECONDS", "5")),
    "model_identity": dict(MODEL_IDENTITY),
}
STATE_LOCK = Lock()


class Handler(BaseHTTPRequestHandler):
    server_version = "InferenceFaultRunner/1.0"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        if self.path == "/health/live":
            self._json(200, {"alive": True})
            return
        if self.path == "/health/ready":
            with STATE_LOCK:
                mode = STATE["mode"]
                model_identity = dict(STATE["model_identity"])
            if mode == "not_ready":
                self._json(503, {"ready": False, **model_identity})
            else:
                self._json(200, {"ready": True, **model_identity})
            return
        self._json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        if self.path == "/control":
            self._control()
            return
        if self.path == "/v1/count":
            self._count()
            return
        self._json(404, {"error": "not_found"})

    def _control(self) -> None:
        if self.headers.get("X-Fault-Control-Key") != CONTROL_TOKEN:
            self._json(403, {"error": "forbidden"})
            return
        body = self._read_json()
        mode = body.get("mode")
        if mode not in {"ready", "not_ready", "timeout"}:
            self._json(422, {"error": "invalid_mode"})
            return
        delay_seconds = float(body.get("delay_seconds", STATE["delay_seconds"]))
        if delay_seconds < 0 or delay_seconds > 60:
            self._json(422, {"error": "invalid_delay"})
            return
        model_identity = body.get("model_identity")
        if model_identity is not None:
            if not isinstance(model_identity, dict):
                self._json(422, {"error": "invalid_model_identity"})
                return
            required = {"model_key", "model_version", "model_checksum", "adapter_version"}
            if set(model_identity) != required or any(
                not isinstance(model_identity[key], str) or not model_identity[key].strip() for key in required
            ):
                self._json(422, {"error": "invalid_model_identity"})
                return
        with STATE_LOCK:
            STATE["mode"] = mode
            STATE["delay_seconds"] = delay_seconds
            if model_identity is not None:
                STATE["model_identity"] = dict(model_identity)
            active_identity = dict(STATE["model_identity"])
        self._json(200, {"mode": mode, "delay_seconds": delay_seconds, "model_identity": active_identity})

    def _count(self) -> None:
        with STATE_LOCK:
            mode = STATE["mode"]
            delay_seconds = STATE["delay_seconds"]
            model_identity = dict(STATE["model_identity"])
        if mode == "not_ready":
            self._json(503, {"error": "not_ready"})
            return
        if mode == "timeout":
            sleep(delay_seconds)
        request = self._read_json()
        media = request.get("media", [])
        detections = []
        if media:
            detections.append({
                "asset_id": media[0]["asset_id"],
                "bbox": [0.1, 0.1, 0.2, 0.2],
                "confidence": 0.9,
                "class_id": 0,
            })
        self._json(200, {
            "status": "review_required",
            "count": None,
            "detections": detections,
            "warnings": ["Deterministic fault-injection runner; manual review required"],
            **model_identity,
            "inference_source": "fault-runner",
            "latency_ms": round(delay_seconds * 1000) if mode == "timeout" else 1,
            "failure_code": None,
            "failure_message": None,
        })

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        content = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError):
            return


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
