"""Validate synthetic tool boundaries; this does not execute an AI agent."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tmp" / "contract-test-deps"))
from jsonschema import Draft202012Validator, FormatChecker  # noqa: E402


class AssistantToolContractsTest(unittest.TestCase):
    def test_schema_and_synthetic_fixtures(self):
        folder = ROOT / "contracts" / "assistant-tools"
        schema = json.loads((folder / "v1.schema.json").read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        samples = json.loads((folder / "synthetic-fixtures.json").read_text(encoding="utf-8"))
        self.assertTrue(samples["syntheticOnly"])
        for fixture in samples["fixtures"]:
            with self.subTest(fixture=fixture["name"]):
                self.assertEqual(validator.is_valid(fixture["payload"]), fixture["valid"])

    def test_only_three_read_tools_are_exposed(self):
        schema = json.loads((ROOT / "contracts/assistant-tools/v1.schema.json").read_text(encoding="utf-8"))
        tools = {item["properties"]["tool"]["const"] for item in schema["$defs"].values()}
        self.assertEqual(tools, {"get_day_overview", "get_pen_history", "inspect_session"})


if __name__ == "__main__":
    unittest.main()
