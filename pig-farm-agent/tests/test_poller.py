from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from pig_farm_agent.poller import (
    DirectoryPoller,
    build_poller,
    request_id_for,
    snapshot_time_from_name,
)

from .helpers import make_agent, make_detection


class TestSnapshotTimeParsing(unittest.TestCase):
    def test_common_camera_naming(self):
        for name in (
            "20260916_083000.jpg",
            "barn-A01-20260916-083000.jpg",
            "cam1_20260916_083000_snap.jpg",
            "2026-09-16T08:30:00.jpg",
            "20260916083000.jpg",
        ):
            with self.subTest(name=name):
                parsed = snapshot_time_from_name(name)
                self.assertIsNotNone(parsed, name)
                self.assertTrue(parsed.startswith("2026-09-16T08:30:00"), parsed)

    def test_date_only_and_unparsable(self):
        self.assertTrue(snapshot_time_from_name("2026-09-16.jpg").startswith("2026-09-16T00:00:00"))
        self.assertIsNone(snapshot_time_from_name("snapshot-latest.jpg"))

    def test_invalid_calendar_value_falls_through(self):
        self.assertIsNone(snapshot_time_from_name("20261345_999999.jpg"))


class TestDirectoryPoller(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.watch = self.tmp / "polling"
        self.agent = make_agent(self.tmp, [make_detection(38) for _ in range(20)])
        self.poller = DirectoryPoller(self.agent, self.watch, interval_seconds=5)

    def tearDown(self):
        self.agent.close()
        self._tmp.cleanup()

    def _drop_image(self, barn: str = "A01", name: str = "snap1.jpg",
                    payload: bytes = b"\xff\xd8\xff\xe0FAKE") -> Path:
        barn_dir = self.watch / barn
        barn_dir.mkdir(parents=True, exist_ok=True)
        path = barn_dir / name
        path.write_bytes(payload)
        return path

    def _poll_settled(self) -> list[dict]:
        """第一轮登记文件指纹，第二轮文件稳定后才处理（避免读到半张图）。"""
        self.poller.poll_once()
        return self.poller.poll_once()

    def test_new_image_analyzed_and_archived(self):
        image = self._drop_image()
        responses = self._poll_settled()
        self.assertEqual(len(responses), 1)
        event = responses[0]["event"]
        self.assertEqual(event["barn_id"], "A01")
        self.assertTrue(event["request_id"].startswith("poll-"))
        self.assertEqual(event["state"]["pig_count"], 38)
        # 文件移入 _processed，原图归档进证据
        self.assertFalse(image.exists())
        processed = list((self.watch / "_processed" / "A01").glob("*.jpg"))
        self.assertEqual(len(processed), 1)
        self.assertTrue(event["evidence"]["image"].endswith(".jpg"))

    def test_unstable_file_deferred_until_settled(self):
        """文件在写入过程中（大小变化）不会被处理，写完后的下一轮才分析。"""
        image = self._drop_image()
        poller = DirectoryPoller(self.agent, self.watch, interval_seconds=5, settle_scans=1)
        self.assertEqual(poller.poll_once(), [])            # 首次扫描只登记指纹
        self.assertTrue(image.exists())                     # 未被处理
        with image.open("ab") as handle:                    # 模拟摄像头继续写入
            handle.write(b"PART2")
        self.assertEqual(poller.poll_once(), [])            # 指纹变了，继续等待
        self.assertTrue(image.exists())
        self.assertEqual(len(poller.poll_once()), 1)        # 稳定后处理
        self.assertFalse(image.exists())

    def test_settle_scans_zero_processes_immediately(self):
        """定时任务一次性扫描场景：不做稳定等待，直接处理。"""
        image = self._drop_image()
        poller = DirectoryPoller(self.agent, self.watch, interval_seconds=5, settle_scans=0)
        self.assertEqual(len(poller.poll_once()), 1)
        self.assertFalse(image.exists())

    def test_growing_file_not_processed(self):
        image = self._drop_image()
        self.poller.poll_once()
        image.write_bytes(b"\xff\xd8\xff\xe0FAKE" + b"MORE")  # 摄像头仍在写入
        self.assertEqual(self.poller.poll_once(), [])
        self.assertTrue(image.exists())
        self.assertEqual(len(self.poller.poll_once()), 1)

    def test_idempotent_across_cycles(self):
        self._drop_image()
        first = self._poll_settled()
        second = self.poller.poll_once()  # 文件已移走，不再重复分析
        self.assertEqual(len(first), 1)
        self.assertEqual(second, [])
        _, total = self.agent.list_events(barn_id="A01")
        self.assertEqual(total, 1)

    def test_same_bytes_again_is_idempotent_by_fingerprint(self):
        image = self._drop_image()
        request_id = request_id_for(image)
        self._poll_settled()
        # 完全相同的快照再次出现时 mtime 不同 → 指纹不同，属于新观测
        again = self._drop_image(name="snap1.jpg")
        self.assertNotEqual(request_id_for(again), request_id)

    def test_source_device_and_captured_at_recorded(self):
        sidecar = {
            "device_id": "cam-A01-03",
            "captured_at": "2026-09-16T08:30:00+08:00",
        }
        image = self._drop_image(name="20260916_083000.jpg")
        image.with_suffix(".json").write_text(json.dumps(sidecar), encoding="utf-8")
        responses = self._poll_settled()
        self.assertEqual(len(responses), 1)
        event = responses[0]["event"]
        self.assertEqual(event["captured_at"], "2026-09-16T08:30:00+08:00")  # 侧车优先
        self.assertEqual(event["state"]["source_device"], "cam-A01-03")
        # 侧车随图片一起归档，便于事后追溯
        self.assertTrue(list((self.watch / "_processed" / "A01").glob("*.json")))

    def test_captured_at_from_filename_without_sidecar(self):
        self._drop_image(name="cam1_20260916_083000.jpg")
        responses = self._poll_settled()
        self.assertTrue(responses[0]["event"]["captured_at"].startswith("2026-09-16T08:30:00"))

    def test_device_id_falls_back_to_config_then_barn(self):
        self._drop_image()
        responses = self._poll_settled()
        self.assertEqual(responses[0]["event"]["state"]["source_device"], "barn-A01")

        self.agent.config.polling_device_id = "edge-host-1"
        poller = DirectoryPoller(self.agent, self.watch, interval_seconds=5)
        poller.poll_once()
        self._drop_image(name="snap2.jpg")
        poller.poll_once()
        responses = poller.poll_once()
        self.assertEqual(responses[0]["event"]["state"]["source_device"], "edge-host-1")

    def test_unknown_barn_skipped(self):
        self._drop_image(barn="Z99", name="snap.jpg")
        self._poll_settled()
        self.assertTrue((self.watch / "Z99" / "snap.jpg").exists())

    def test_failed_analysis_isolated(self):
        image = self._drop_image()
        self.poller.poll_once()  # 登记指纹
        original_analyze = self.agent.analyze
        self.agent.analyze = lambda req: (_ for _ in ()).throw(RuntimeError("boom"))
        responses = self.poller.poll_once()
        self.assertEqual(responses, [])
        self.assertFalse(image.exists())
        failed = list((self.watch / "_failed" / "A01").glob("*.jpg"))
        self.assertEqual(len(failed), 1)
        self.agent.analyze = original_analyze

    def test_rejected_request_isolated(self):
        image = self._drop_image()
        self.poller.poll_once()
        original_analyze = self.agent.analyze
        from pig_farm_agent.models import ValidationError

        self.agent.analyze = lambda req: (_ for _ in ()).throw(ValidationError("坏请求"))
        self.assertEqual(self.poller.poll_once(), [])
        self.assertTrue(list((self.watch / "_failed" / "A01").glob("*.jpg")))
        self.agent.analyze = original_analyze

    def test_archive_keeps_duplicate_names(self):
        for _ in range(2):
            self._drop_image(name="same-name.jpg", payload=b"\xff\xd8\xff\xe0" + bytes([len(str(_))]))
            self._poll_settled()
        archived = sorted(p.name for p in (self.watch / "_processed" / "A01").glob("*.jpg"))
        self.assertEqual(len(archived), 2)
        self.assertEqual(len(set(archived)), 2)  # 不覆盖同名快照

    def test_build_poller_creates_watch_dir(self):
        poller = build_poller(self.agent.config, self.agent)
        self.assertTrue(poller.watch_dir.exists())
        self.assertEqual(poller.watch_dir, self.agent.config.polling_watch_dir)


if __name__ == "__main__":
    unittest.main()
