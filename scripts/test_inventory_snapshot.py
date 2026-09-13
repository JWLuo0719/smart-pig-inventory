"""Archive and no-write guard tests; Docker calls are isolated from the host."""
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import inventory_snapshot as s


class SnapshotGuards(unittest.TestCase):
    def test_archive_rejects_escape_and_links(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "unsafe.tar.gz"
            for name, kind in [("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                               ("link", tarfile.SYMTYPE), ("device", tarfile.CHRTYPE)]:
                with tarfile.open(path, "w:gz") as out:
                    item = tarfile.TarInfo(name); item.type = kind
                    out.addfile(item, io.BytesIO(b""))
                with self.assertRaises(ValueError):
                    s.check_archive(path)

    def test_live_project_rejected_before_directory_created(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(s, "containers", return_value=[{"State": {"Running": True}}]):
            path = Path(folder) / "backup"
            with self.assertRaises(ValueError):
                s.backup("pig-inventory-test", path)
            self.assertFalse(path.exists())

    def test_restore_refuses_existing_volume_before_write(self):
        manifest = {"sourceProject": "pig-inventory-source"}
        with patch.object(s, "verify", return_value=manifest), patch.object(s, "containers", return_value=[]), \
                patch.object(s, "docker", return_value="pig-inventory-target_mysql_data") as call:
            with self.assertRaises(ValueError):
                s.restore(Path("unused"), "pig-inventory-target")
            call.assert_called_once_with("volume", "ls", "-q")

    def test_manifest_rejects_missing_volume_and_path_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            manifest = {"schemaVersion": 1, "mode": "all-services-stopped", "volumes": []}
            for entries in [[], [{"logical": key, "file": "../outside"} for key in s.VOLUMES]]:
                manifest["volumes"] = entries
                (path / "manifest.json").write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    s.verify(path)


if __name__ == "__main__":
    unittest.main()
