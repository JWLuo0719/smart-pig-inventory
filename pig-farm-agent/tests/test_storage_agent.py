from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from pig_farm_agent.models import InvalidTransition, ValidationError

from .helpers import make_agent, make_detection


class TestAnalyzeFlow(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        # 密度序列：38/45=0.844 超高阈值，30/45=0.667 正常
        self.agent = make_agent(
            self.tmp,
            [make_detection(38), make_detection(38), make_detection(38), make_detection(30), make_detection(30)],
        )

    def tearDown(self):
        self.agent.close()
        self._tmp.cleanup()

    def test_pending_then_fire_then_merge(self):
        first = self.agent.analyze({"request_id": "req-1", "barn_id": "A01"})
        self.assertFalse(first["merged"])
        self.assertEqual(first["event"]["risk"]["level"], "none")  # 1/2 次未确认

        second = self.agent.analyze({"request_id": "req-2", "barn_id": "A01"})
        self.assertEqual(second["event"]["risk"]["code"], "DENSITY_HIGH")
        self.assertEqual(second["event"]["risk"]["level"], "high")
        self.assertEqual(second["event"]["status"], "open")
        self.assertEqual(second["event"]["suggested_actions"][0], "15分钟内现场复核该栏舍")
        high_event_id = second["event"]["event_id"]

        third = self.agent.analyze({"request_id": "req-3", "barn_id": "A01"})
        self.assertTrue(third["merged"])
        self.assertEqual(third["event"]["event_id"], high_event_id)
        self.assertEqual(third["event"]["merged_observation_count"], 1)

        events, total = self.agent.list_events(barn_id="A01")
        self.assertEqual(total, 2)  # pending + 高风险事件；合并不新增
        observations = self.agent.storage.observation_history("A01")
        self.assertEqual(len(observations), 3)  # 原始观测全部保留

    def test_request_idempotency(self):
        detector = self.agent.detector
        first = self.agent.analyze({"request_id": "req-same", "barn_id": "A01"})
        again = self.agent.analyze({"request_id": "req-same", "barn_id": "A01"})
        self.assertEqual(first["event"]["event_id"], again["event"]["event_id"])
        self.assertEqual(len(detector.calls), 1)  # 幂等重试不重复推理

        stored = self.agent.get_request("req-same")
        self.assertEqual(stored["response"]["event"]["event_id"], first["event"]["event_id"])

    def test_auto_resolve_after_two_normals(self):
        self.agent.analyze({"request_id": "r1", "barn_id": "A01"})
        fired = self.agent.analyze({"request_id": "r2", "barn_id": "A01"})
        high_id = fired["event"]["event_id"]
        self.agent.analyze({"request_id": "r3", "barn_id": "A01"})  # 仍然超标：合并
        normal1 = self.agent.analyze({"request_id": "r4", "barn_id": "A01"})
        self.assertEqual(self.agent.get_event(high_id)["status"], "open")  # 恢复 1/2 次
        self.agent.analyze({"request_id": "r5", "barn_id": "A01"})
        resolved = self.agent.get_event(high_id)
        self.assertEqual(resolved["status"], "resolved")
        self.assertTrue(
            any(h["operator"] == "system" and "自动关闭" in (h["note"] or "") for h in resolved["status_history"])
        )
        self.assertEqual(normal1["event"]["risk"]["level"], "none")

    def test_transitions_and_audit(self):
        fired = self.agent.analyze({"request_id": "t1", "barn_id": "A01"})
        self.agent.analyze({"request_id": "t2", "barn_id": "A01"})
        event_id = fired["event"]["event_id"] if fired["event"]["risk"]["code"] else self.agent.list_events(status="open")[0][0]["event_id"]
        acked = self.agent.transition(event_id, "acknowledged", operator="vet-li", note="现场复核中")
        self.assertEqual(acked["status"], "acknowledged")
        resolved = self.agent.transition(event_id, "resolved", operator="vet-li", note="已分群")
        self.assertEqual(resolved["status"], "resolved")
        with self.assertRaises(InvalidTransition):
            self.agent.transition(event_id, "acknowledged", operator="vet-li")
        audit = self.agent.storage.audit_for_event(event_id)
        actions = [a["action"] for a in audit]
        self.assertIn("status_changed", actions)

    def test_unknown_barn_rejected(self):
        with self.assertRaises(ValidationError):
            self.agent.analyze({"request_id": "bad-1", "barn_id": "Z99"})

    def test_jsonl_mirror_written(self):
        self.agent.analyze({"request_id": "j1", "barn_id": "A01"})
        jsonl = self.tmp / "events.jsonl"
        self.assertTrue(jsonl.exists())
        lines = [json.loads(x) for x in jsonl.read_text(encoding="utf-8").splitlines() if x.strip()]
        self.assertTrue(any(record["action"] == "event_created" for record in lines))

    def test_evidence_metrics_persisted(self):
        result = self.agent.analyze({"request_id": "e1", "barn_id": "A01"})
        metrics_rel = result["event"]["evidence"]["metrics"]
        self.assertTrue(metrics_rel.startswith("evidence/"))
        metrics = json.loads((self.tmp / metrics_rel).read_text(encoding="utf-8"))
        self.assertEqual(metrics["event_id"], result["event"]["event_id"])
        self.assertIn("boxes", metrics)
        self.assertEqual(metrics["detection"]["model_name"], "DCR-SoftNMS-YOLOv13")


if __name__ == "__main__":
    unittest.main()
