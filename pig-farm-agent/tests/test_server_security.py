"""回归：image_path 越界摄入与 /files/ 越权回放（检查报告 S7 / P0-5）。

- image_path 必须 resolve 到 data_dir 之下，否则 400 VALIDATION_ERROR；
- /files/ 只回放 evidence/ 之下的图片与指标 JSON，agent.db / events.jsonl
  以及 .db/.jsonl 等后缀一律拒绝。
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from pig_farm_agent.evidence import ALLOWED_REPLAY_SUFFIXES, EvidenceStore

from .test_server_api import ServerTestBase, http


class TestImagePathContainment(ServerTestBase):
    """image_path 越界拒绝：resolve 后必须位于 data_dir 之下。"""

    def test_image_path_outside_data_dir_rejected(self):
        outside_dir = Path(tempfile.mkdtemp())
        outside = outside_dir / "secret.jpg"
        outside.write_bytes(b"\xff\xd8\xff\xe0FAKESECRET")
        for value in (
            str(outside),  # 绝对路径：宿主机任意可读文件
            str(outside_dir),  # data_dir 之外的目录
            "../outside/secret.jpg",
            str(self.tmp.parent / "escape.jpg"),
        ):
            status, raw, _ = http(
                "POST", self.url("/analyze"),
                json.dumps({"client_request_id": self.unique("esc"), "barn_id": "A01",
                            "image_path": value}).encode(),
                {"Content-Type": "application/json"},
            )
            payload = json.loads(raw)
            self.assertEqual(status, 400, (value, raw))
            self.assertEqual(payload["error_code"], "VALIDATION_ERROR", value)

    def test_image_path_inside_data_dir_accepted(self):
        inbox = self.tmp / "inbox" / "demo" / "A01"
        inbox.mkdir(parents=True, exist_ok=True)
        image = inbox / "inside.jpg"
        image.write_bytes(b"\xff\xd8\xff\xe0INSIDE")
        status, raw, _ = http(
            "POST", self.url("/analyze"),
            json.dumps({"client_request_id": self.unique("ok"), "barn_id": "A01",
                        "image_path": str(image)}).encode(),
            {"Content-Type": "application/json"},
        )
        payload = json.loads(raw)
        self.assertEqual(status, 200, raw)
        self.assertTrue(payload["event"]["evidence"]["image"].endswith(".jpg"))


class TestFilesReplayScope(ServerTestBase):
    """/files/ 只回放 evidence/ 下的证据产物（图片 + 指标 JSON）。"""

    def test_files_cannot_reach_data_dir_root_files(self):
        # 先落一个事件：agent.db / events.jsonl 都在 data_dir 根下，修复前可直接下载
        http("POST", self.url("/analyze"), json.dumps({"barn_id": "A01"}).encode(),
             {"Content-Type": "application/json"})
        self.assertTrue((self.tmp / "agent.db").exists())
        self.assertTrue((self.tmp / "events.jsonl").exists())
        for rel in (
            "agent.db",
            "events.jsonl",
            "..%2Fagent.db",
            "evidence/../agent.db",
            "evidence/..%2Fevents.jsonl",
        ):
            status, raw, _ = http("GET", self.url(f"/files/{rel}"))
            self.assertIn(status, (404, 400), (rel, raw))
            self.assertNotIn(b"SQLite format", raw)
            self.assertNotIn(b"recorded_at", raw)

    def test_files_rejects_non_evidence_suffixes(self):
        evidence_dir = self.tmp / "evidence"
        evidence_dir.mkdir(parents=True, exist_ok=True)
        (evidence_dir / "dump.db").write_bytes(b"SQLite format 3\x00")
        (evidence_dir / "rows.jsonl").write_text('{"a": 1}', encoding="utf-8")
        for rel in ("evidence/dump.db", "evidence/rows.jsonl"):
            status, raw, _ = http("GET", self.url(f"/files/{rel}"))
            self.assertEqual(status, 404, (rel, raw))

    def test_files_still_serves_evidence_image_and_metrics(self):
        evidence_dir = self.tmp / "evidence"
        evidence_dir.mkdir(parents=True, exist_ok=True)
        (evidence_dir / "evt-demo.jpg").write_bytes(b"\xff\xd8\xff\xe0FAKEJPEG")
        (evidence_dir / "evt-demo.json").write_text("{}", encoding="utf-8")
        status, _, headers = http("GET", self.url("/files/evidence/evt-demo.jpg"))
        self.assertEqual(status, 200)
        self.assertIn("image/jpeg", headers.get("Content-Type", ""))
        status, _, headers = http("GET", self.url("/files/evidence/evt-demo.json"))
        self.assertEqual(status, 200)
        self.assertIn("application/json", headers.get("Content-Type", ""))


class TestEvidenceResolveScope(unittest.TestCase):
    """EvidenceStore.resolve：包含性校验收窄到 evidence/，后缀限定证据产物。"""

    def test_resolve_only_replays_evidence_products(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = EvidenceStore(Path(tmp))
            (store.evidence_dir / "evt-1.json").write_text("{}", encoding="utf-8")
            (store.evidence_dir / "evt-1.jpg").write_bytes(b"\xff\xd8")
            (store.evidence_dir / "evt-1_annotated.jpg").write_bytes(b"\xff\xd8")
            (store.evidence_dir / "evil.db").write_bytes(b"SQLite format 3")
            (store.evidence_dir / "evil.jsonl").write_text("{}", encoding="utf-8")
            (store.root / "agent.db").write_bytes(b"SQLite format 3")
            (store.root / "events.jsonl").write_text("{}", encoding="utf-8")

            self.assertIsNotNone(store.resolve("evidence/evt-1.json"))
            self.assertIsNotNone(store.resolve("evidence/evt-1.jpg"))
            self.assertIsNotNone(store.resolve("evidence/evt-1_annotated.jpg"))
            self.assertIsNone(store.resolve("agent.db"))
            self.assertIsNone(store.resolve("events.jsonl"))
            self.assertIsNone(store.resolve("evidence/evil.db"))
            self.assertIsNone(store.resolve("evidence/evil.jsonl"))
            self.assertIsNone(store.resolve("evidence/../agent.db"))
            self.assertIsNone(store.resolve("../agent.db"))
            self.assertIsNone(store.resolve("evidence"))
            self.assertIsNone(store.resolve("evidence/missing.jpg"))

    def test_replay_allowlist_keeps_images_and_metrics_json(self):
        # 指标 JSON 是 evidence 契约产物（文档 5.2），必须保留；.db/.jsonl 之类拒绝
        self.assertIn(".json", ALLOWED_REPLAY_SUFFIXES)
        for suffix in (".db", ".jsonl", ".sqlite", ".py", ".log"):
            self.assertNotIn(suffix, ALLOWED_REPLAY_SUFFIXES)


if __name__ == "__main__":
    unittest.main()
