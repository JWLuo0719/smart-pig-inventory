from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from pig_farm_agent.config import ConfigError, load_config
from pig_farm_agent.models import ValidationError

from .helpers import PROJECT_ROOT


class TestConfigDefaults(unittest.TestCase):
    def test_missing_file_uses_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = load_config(Path(tmp) / "missing.json", data_dir=tmp, use_env=False)
            self.assertEqual(config.model_mode, "mock")
            self.assertEqual(sorted(config.barns), ["A01", "A02"])
            self.assertEqual(config.barns["A01"].capacity, 45)
            codes = {r.code for r in config.rules}
            self.assertEqual(codes, {"DENSITY_HIGH", "DENSITY_WATCH", "DATA_QUALITY_LOW"})

    def test_repo_config_loads(self):
        config = load_config(PROJECT_ROOT / "config.json", data_dir=tempfile.gettempdir(), use_env=False)
        self.assertEqual(config.farm_name, "示范猪场")
        high = config.rule("DENSITY_HIGH")
        self.assertEqual(high.threshold, 0.82)
        self.assertEqual(high.confirm_observations, 2)
        self.assertEqual(high.cooldown_minutes, 60)
        self.assertEqual(config.rule("DATA_QUALITY_LOW").min_coverage, 0.8)

    def test_barn_list_backward_compatible(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"farm": {"barns": ["B01"]}}), encoding="utf-8")
            config = load_config(path, data_dir=tmp, use_env=False)
            self.assertEqual(config.barns["B01"].capacity, 45)

    def test_unknown_barn_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = load_config(Path(tmp) / "missing.json", data_dir=tmp, use_env=False)
            with self.assertRaises(ValidationError):
                config.barn("NOPE")

    def test_invalid_rule_level_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(
                json.dumps({"agent": {"risk_rules": [{"code": "X", "level": "extreme", "metric": "density"}]}}),
                encoding="utf-8",
            )
            with self.assertRaises(ConfigError):
                load_config(path, data_dir=tmp, use_env=False)


class TestEnvOverrides(unittest.TestCase):
    def test_env_data_dir_and_port(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.dict(
                os.environ,
                {"PIG_AGENT_DATA_DIR": tmp, "PIG_AGENT_PORT": "9999", "PIG_AGENT_LOG_LEVEL": "debug"},
            ):
                config = load_config(PROJECT_ROOT / "config.json")
                self.assertEqual(Path(config.data_dir), Path(tmp))
                self.assertEqual(config.port, 9999)
                self.assertEqual(config.log_level, "DEBUG")


if __name__ == "__main__":
    unittest.main()
