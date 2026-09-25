from __future__ import annotations

import unittest

from pig_farm_agent import models
from pig_farm_agent.models import (
    Event,
    EventNotFound,
    InvalidTransition,
    ValidationError,
    ensure_transition,
    new_event,
    new_id,
    validate_id,
)


class TestStateMachine(unittest.TestCase):
    def test_allowed_paths(self):
        ensure_transition("open", "acknowledged")
        ensure_transition("open", "resolved")
        ensure_transition("open", "dismissed")
        ensure_transition("acknowledged", "resolved")
        ensure_transition("acknowledged", "dismissed")

    def test_forbidden_paths(self):
        for current, target in [
            ("resolved", "open"),
            ("resolved", "acknowledged"),
            ("dismissed", "open"),
            ("acknowledged", "open"),
            ("bogus", "open"),
        ]:
            with self.assertRaises(InvalidTransition):
                ensure_transition(current, target)


class TestIds(unittest.TestCase):
    def test_new_id_format(self):
        value = new_id("evt")
        self.assertRegex(value, r"^evt-\d{14}-[0-9a-f]{6}$")

    def test_new_id_unique(self):
        self.assertNotEqual(new_id("req"), new_id("req"))

    def test_validate_id_rejects_bad_input(self):
        for bad in ("", "a b", "x" * 200, "a/b", "a;b"):
            with self.assertRaises(ValidationError):
                validate_id(bad, "request_id")
        self.assertEqual(validate_id("req-1", "request_id"), "req-1")


class TestEventContract(unittest.TestCase):
    def build_event(self) -> Event:
        return new_event(
            request_id="req-1",
            farm_id="farm-demo",
            barn_id="barn-a",
            captured_at="2026-09-16T08:30:00+08:00",
            state={"pig_count": 86, "density": 0.72,
                   "quality": {"status": "usable", "coverage": 0.94}, "trend": None},
            risk={"level": "medium", "code": "DENSITY_HIGH", "confidence": 0.83,
                  "thresholds": {"density": 0.82}},
            evidence={"image": "evidence/evt-x.jpg", "metrics": "evidence/evt-x.json"},
            suggested_actions=["复核饮水和通风状态"],
            model={"name": "DCR-SoftNMS-YOLOv13", "version": "v1"},
            human_confirmation_required=True,
        )

    def test_to_dict_matches_doc_section_5_2(self):
        payload = self.build_event().to_dict()
        expected_keys = [
            "event_id", "request_id", "farm_id", "barn_id", "captured_at",
            "state", "risk", "evidence", "suggested_actions", "status", "model",
        ]
        for key in expected_keys:
            self.assertIn(key, payload)
        self.assertEqual(payload["status"], "open")
        self.assertEqual(payload["state"]["pig_count"], 86)
        self.assertEqual(payload["risk"]["code"], "DENSITY_HIGH")
        self.assertEqual(payload["suggested_actions"], ["复核饮水和通风状态"])

    def test_round_trip(self):
        event = self.build_event()
        restored = Event.from_dict(event.to_dict())
        self.assertEqual(restored.to_dict(), event.to_dict())

    def test_record_transition_appends_history(self):
        event = self.build_event()
        event.record_transition("acknowledged", "vet-zhang", "已复核", "2026-09-16T09:00:00+08:00")
        self.assertEqual(event.status, "acknowledged")
        self.assertEqual(len(event.status_history), 2)
        self.assertEqual(event.status_history[-1]["operator"], "vet-zhang")
        with self.assertRaises(InvalidTransition):
            event.record_transition("open", "vet-zhang", None, "2026-09-16T09:01:00+08:00")


if __name__ == "__main__":
    unittest.main()
