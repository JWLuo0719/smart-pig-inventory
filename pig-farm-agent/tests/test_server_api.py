from __future__ import annotations

import json
import threading
import unittest
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from pig_farm_agent.server import create_server

from .helpers import make_agent, make_detection


def http(method: str, url: str, body: bytes | None = None, headers: dict | None = None):
    request = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), dict(exc.headers)


class ServerTestBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import tempfile

        cls._tmp = tempfile.TemporaryDirectory()
        cls.tmp = Path(cls._tmp.name)
        cls.agent = make_agent(cls.tmp, [make_detection(38) for _ in range(20)])
        cls.agent.config.log_level = "ERROR"
        cls.server, _, _ = create_server(cls.agent, "127.0.0.1", 0)
        cls.port = cls.server.server_address[1]
        cls.base = f"http://127.0.0.1:{cls.port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.agent.close()
        cls._tmp.cleanup()

    def url(self, path: str) -> str:
        return f"{self.base}{path}"

    @staticmethod
    def unique(prefix: str) -> str:
        """各测试共享同一 Agent（因此共享幂等表），request_id 必须唯一。"""
        return f"{prefix}-{uuid.uuid4().hex[:10]}"


class TestHealthAndAnalyze(ServerTestBase):
    def test_health(self):
        status, body, _ = http("GET", self.url("/health"))
        payload = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")
        for key in ("model", "storage", "config"):
            self.assertIn(key, payload)
        self.assertTrue(payload["storage"]["ok"])

    def test_dashboard_index_served(self):
        status, body, headers = http("GET", self.url("/"))
        self.assertEqual(status, 200)
        self.assertIn("text/html", headers.get("Content-Type", ""))
        text = body.decode("utf-8")
        self.assertIn("猪场智能运营看板", text)
        self.assertIn("/v1/mobile/analyze", text)  # 上传逻辑存在

    def test_get_single_event(self):
        _, raw, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"barn_id": "A01"}).encode(), {"Content-Type": "application/json"},
        )
        event_id = json.loads(raw)["event"]["event_id"]
        status, raw, _ = http("GET", self.url(f"/events/{event_id}"))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["event_id"], event_id)
        status, raw, _ = http("GET", self.url("/events/evt-missing"))
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(raw)["error_code"], "EVENT_NOT_FOUND")

    def test_analyze_json_contract(self):
        status, body, _ = http(
            "POST",
            self.url("/analyze"),
            json.dumps({"request_id": "api-1", "farm_id": "farm-demo", "barn_id": "A01"}).encode(),
            {"Content-Type": "application/json"},
        )
        payload = json.loads(body)
        self.assertEqual(status, 200)
        event = payload["event"]
        for key in ("event_id", "request_id", "farm_id", "barn_id", "captured_at",
                    "state", "risk", "evidence", "suggested_actions", "status", "model"):
            self.assertIn(key, event)
        self.assertEqual(event["request_id"], "api-1")
        self.assertIsInstance(event["state"]["pig_count"], int)
        self.assertIn(event["model"]["name"], "DCR-SoftNMS-YOLOv13")

    def test_analyze_idempotent(self):
        request_id = self.unique("dup")
        _, first, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"client_request_id": request_id, "barn_id": "A01"}).encode(),
            {"Content-Type": "application/json"},
        )
        _, second, _ = http(
            "POST", self.url("/v1/mobile/analyze"),
            json.dumps({"client_request_id": request_id, "barn_id": "A01"}).encode(),
            {"Content-Type": "application/json"},
        )
        self.assertEqual(
            json.loads(first)["event"]["event_id"], json.loads(second)["event"]["event_id"]
        )

    def test_invalid_json(self):
        status, body, _ = http(
            "POST", self.url("/analyze"), b"{not json", {"Content-Type": "application/json"}
        )
        payload = json.loads(body)
        self.assertEqual(status, 400)
        self.assertEqual(payload["error_code"], "INVALID_JSON")
        self.assertIn("request_id", payload)

    def test_unknown_barn(self):
        status, body, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"barn_id": "Z99"}).encode(), {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(json.loads(body)["error_code"], "VALIDATION_ERROR")

    def test_not_found_route(self):
        status, body, _ = http("GET", self.url("/nope"))
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(body)["error_code"], "NOT_FOUND")


class TestMobileFlow(ServerTestBase):
    def test_multipart_upload(self):
        boundary = "----pigagenttest"
        request_id = self.unique("mp")
        parts = []
        for name, value in [
            ("farm_id", "farm-m"),
            ("barn_id", "A02"),
            ("client_request_id", request_id),
            ("captured_at", "2026-09-16T08:30:00+08:00"),
        ]:
            parts.append(
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
            )
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
            "Content-Type: image/jpeg\r\n\r\n"
        )
        body = "".join(parts).encode() + b"\xff\xd8\xff\xe0FAKEJPEGDATA" + f"\r\n--{boundary}--\r\n".encode()
        status, raw, _ = http(
            "POST", self.url("/v1/mobile/analyze"), body,
            {"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        payload = json.loads(raw)
        self.assertEqual(status, 200)
        self.assertEqual(payload["event"]["request_id"], request_id)
        self.assertEqual(payload["event"]["barn_id"], "A02")
        self.assertEqual(payload["event"]["captured_at"], "2026-09-16T08:30:00+08:00")
        self.assertTrue(payload["event"]["evidence"]["image"].endswith(".jpg"))
        # 上传文件落盘到 inbox（文件名使用 HTTP 请求 ID 而非 client_request_id）
        inbox = list((self.tmp / "inbox" / "farm-m" / "A02").glob("*.jpg"))
        self.assertEqual(len(inbox), 1)

    def test_unsupported_extension(self):
        boundary = "----pigagenttest"
        body = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"barn_id\"\r\n\r\nA01\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"notes.txt\"\r\n"
            "Content-Type: text/plain\r\n\r\nhello\r\n"
            f"--{boundary}--\r\n"
        ).encode()
        status, raw, _ = http(
            "POST", self.url("/v1/mobile/analyze"), body,
            {"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        self.assertEqual(status, 415)
        self.assertEqual(json.loads(raw)["error_code"], "UNSUPPORTED_MEDIA_TYPE")

    def test_request_query_and_miss(self):
        request_id = self.unique("query")
        http(
            "POST", self.url("/analyze"),
            json.dumps({"client_request_id": request_id, "barn_id": "A01"}).encode(),
            {"Content-Type": "application/json"},
        )
        status, raw, _ = http("GET", self.url(f"/v1/mobile/requests/{request_id}"))
        payload = json.loads(raw)
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "completed")
        self.assertIn("event", payload["result"])

        status, raw, _ = http("GET", self.url("/v1/mobile/requests/never-seen"))
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(raw)["error_code"], "REQUEST_NOT_FOUND")


class TestModelReplayEndpoint(ServerTestBase):
    def test_replay_gate_summary(self):
        status, raw, _ = http("GET", self.url("/model/replay"))
        payload = json.loads(raw)
        self.assertEqual(status, 200)
        self.assertTrue(payload["available"], payload)
        self.assertGreater(payload["image_count"], 0)
        self.assertIn("DENSITY_HIGH", payload["risk_codes"])
        self.assertIn("DATA_QUALITY_LOW", payload["risk_codes"])
        # 摘要面向看板展示：模型版本、图片数、计数区间与耗时口径齐全
        self.assertIn("模型", payload["summary"])
        self.assertIn("计数", payload["summary"])
        self.assertIn("耗时", payload["summary"])
        self.assertEqual(len(payload["count_range"]), 2)
        self.assertIn("mean_ms", payload["timing"])


class TestWriteToken(unittest.TestCase):
    """写保护：启用 PIG_AGENT_API_TOKEN 后 POST 需要令牌，读取保持开放。"""

    @classmethod
    def setUpClass(cls):
        import tempfile

        cls._tmp = tempfile.TemporaryDirectory()
        cls.agent = make_agent(Path(cls._tmp.name), [make_detection(30) for _ in range(10)])
        cls.agent.config.log_level = "ERROR"
        cls.agent.config.api_token = "s3cret-token"
        cls.server, _, _ = create_server(cls.agent, "127.0.0.1", 0)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.agent.close()
        cls._tmp.cleanup()

    def test_health_is_open_and_reports_protection(self):
        status, raw, _ = http("GET", f"{self.base}/health")
        self.assertEqual(status, 200)
        self.assertTrue(json.loads(raw)["config"]["writes_protected"])

    def test_write_without_token_rejected(self):
        status, raw, _ = http("POST", f"{self.base}/analyze", b"{}",
                              {"Content-Type": "application/json"})
        payload = json.loads(raw)
        self.assertEqual(status, 401)
        self.assertEqual(payload["error_code"], "UNAUTHORIZED")
        self.assertIn("request_id", payload)

    def test_write_with_wrong_token_rejected(self):
        status, _, _ = http("POST", f"{self.base}/analyze", b"{}",
                            {"Content-Type": "application/json", "X-Api-Token": "wrong"})
        self.assertEqual(status, 401)

    def test_write_with_token_accepted(self):
        request_id = f"tok-{uuid.uuid4().hex[:8]}"
        body = json.dumps({"client_request_id": request_id, "barn_id": "A01"}).encode()
        status, raw, _ = http("POST", f"{self.base}/analyze", body,
                              {"Content-Type": "application/json", "X-Api-Token": "s3cret-token"})
        self.assertEqual(status, 200, raw)
        self.assertEqual(json.loads(raw)["event"]["request_id"], request_id)

        status, _, _ = http("POST", f"{self.base}/events/{json.loads(raw)['event']['event_id']}/ack",
                            b"{}", {"Content-Type": "application/json"})
        self.assertEqual(status, 401)
        status, _, _ = http("POST", f"{self.base}/events/{json.loads(raw)['event']['event_id']}/ack",
                            b"{}", {"Content-Type": "application/json", "X-Api-Token": "s3cret-token"})
        self.assertEqual(status, 200)


class TestEventsAndReports(ServerTestBase):
    def test_list_events_filter_and_pagination(self):
        http("POST", self.url("/analyze"), json.dumps({"barn_id": "A01"}).encode(),
             {"Content-Type": "application/json"})
        status, raw, _ = http("GET", self.url("/events?barn_id=A01&limit=1&offset=0"))
        payload = json.loads(raw)
        self.assertEqual(status, 200)
        self.assertLessEqual(len(payload["events"]), 1)
        self.assertGreaterEqual(payload["total"], 1)
        self.assertEqual(payload["limit"], 1)

        status, raw, _ = http("GET", self.url("/events?status=bogus"))
        self.assertEqual(status, 400)

    def test_ack_resolve_flow(self):
        _, raw, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"barn_id": "A01"}).encode(), {"Content-Type": "application/json"},
        )
        event_id = json.loads(raw)["event"]["event_id"]
        status, raw, _ = http(
            "POST", self.url(f"/events/{event_id}/ack"),
            json.dumps({"operator": "vet-wang", "note": "已到场"}).encode(),
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["status"], "acknowledged")

        status, raw, _ = http(
            "POST", self.url(f"/events/{event_id}/resolve"), b"{}",
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["status"], "resolved")

        # resolved 后不允许再 ack
        status, raw, _ = http(
            "POST", self.url(f"/events/{event_id}/ack"), b"{}",
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 409)
        self.assertEqual(json.loads(raw)["error_code"], "INVALID_TRANSITION")

    def test_event_action_not_found(self):
        status, raw, _ = http("POST", self.url("/events/evt-missing/ack"), b"{}",
                              {"Content-Type": "application/json"})
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(raw)["error_code"], "EVENT_NOT_FOUND")

    def test_daily_report_and_csv(self):
        http("POST", self.url("/analyze"), json.dumps({"barn_id": "A01"}).encode(),
             {"Content-Type": "application/json"})
        status, raw, _ = http("GET", self.url("/report/daily"))
        payload = json.loads(raw)
        self.assertEqual(status, 200)
        for key in ("farm", "date", "summary", "barns", "open_alerts", "event_ids"):
            self.assertIn(key, payload)
        self.assertGreaterEqual(payload["summary"]["events"], 1)

        status, raw, _ = http("GET", self.url("/report/daily.csv"))
        text = raw.decode("utf-8-sig")
        self.assertEqual(status, 200)
        self.assertTrue(text.startswith("event_id,request_id,farm_id,barn_id"))
        lines = [line for line in text.splitlines() if line.strip()]
        self.assertGreaterEqual(len(lines), 2)

    def test_evidence_serving(self):
        _, raw, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"barn_id": "A01"}).encode(), {"Content-Type": "application/json"},
        )
        metrics_rel = json.loads(raw)["event"]["evidence"]["metrics"]
        status, raw, headers = http("GET", self.url(f"/files/{metrics_rel}"))
        self.assertEqual(status, 200)
        self.assertIn("application/json", headers.get("Content-Type", ""))

        status, _, _ = http("GET", self.url("/files/..%2Fagent.db"))
        self.assertIn(status, (404, 400))


if __name__ == "__main__":
    unittest.main()
