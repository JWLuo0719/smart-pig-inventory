"""回归：research_runner 的 job_id 路径穿越、工作目录越界与可选服务密钥。

对应检查报告的 /count 工作目录穿越（job_id 拼路径 → finally 的 rmtree 递删宿主目录）
与 P1-4（Runner 无鉴权）。HTTP 用例走 FastAPI TestClient 真实路由；
工作目录用例直接驱动 _new_workdir / _cleanup_workdir / _assert_inside_tmp。
"""
from __future__ import annotations

import os
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from fastapi.testclient import TestClient

from research_runner import app as runner_app


def count_payload(job_id: str) -> dict:
    """最小 CountingJobRequest：media 为空即可走通契约（不触发 MinIO 拉取）。"""
    return {
        "job_id": job_id,
        "correlation_id": "corr-test",
        "organization_id": "org-test",
        "capture_set_id": "cap-test",
        "capture_kind": "single",
        "media": [],
        "requested_model": {
            "model_key": "DCR-SoftNMS-YOLOv13",
            "version": "test-v1",
            "checksum": "0" * 64,
            "adapter_version": "research-runner-1",
        },
    }


class TestJobIdPathTraversal(unittest.TestCase):
    """job_id 白名单：非法 ID 一律契约形 failed，且 rmtree 不得越出 RUNNER_TMP。"""

    def setUp(self):
        self.client = TestClient(runner_app.app)
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)
        self.sandbox = self.base / "runner-tmp"
        self.sandbox.mkdir()
        self.victim = self.base / "victim"
        self.victim.mkdir()
        self.sentinel = self.victim / "keep.txt"
        self.sentinel.write_text("sentinel", encoding="utf-8")
        self._env = unittest.mock.patch.dict(os.environ, {"RUNNER_TMP": str(self.sandbox)})
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()

    def test_traversal_job_id_rejected_and_host_dirs_survive(self):
        for job_id in (
            "../../../victim-x",  # 老实现取前 8 字符拼目录名，../ 即可越出 RUNNER_TMP
            "a/../../../victim",
            "..",
            "job/../x",
            "x" * 65,
            "",
            "a b",
            "中文id",
        ):
            response = self.client.post("/count", json=count_payload(job_id))
            payload = response.json()
            self.assertEqual(response.status_code, 200, job_id)  # 契约形 failed，不是 5xx
            self.assertEqual(payload["status"], "failed", job_id)
            self.assertIsNone(payload["count"], job_id)
            self.assertTrue(
                any("invalid job_id" in w for w in payload["warnings"]), (job_id, payload)
            )
        self.assertTrue(self.sentinel.exists(), "rmtree 不得递删 RUNNER_TMP 之外的目录")
        self.assertEqual(self.sentinel.read_text(encoding="utf-8"), "sentinel")
        self.assertEqual(list(self.sandbox.iterdir()), [], "非法 job_id 不应创建任何工作目录")

    def test_valid_job_id_passes_and_cleans_workdir(self):
        response = self.client.post("/count", json=count_payload("job-ok_1-A"))
        payload = response.json()
        self.assertEqual(response.status_code, 200, payload)
        self.assertEqual(payload["status"], "succeeded")
        self.assertEqual(payload["count"], 0)
        self.assertEqual(list(self.sandbox.iterdir()), [], "工作目录用完即删")


class TestWorkdirSandbox(unittest.TestCase):
    """工作目录生命周期：服务端命名、断言位于 RUNNER_TMP 之下、rmtree 不越界。"""

    def test_new_workdir_is_server_generated_inside_runner_tmp(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "runner-tmp"
            with unittest.mock.patch.dict(os.environ, {"RUNNER_TMP": str(sandbox)}):
                workdir = runner_app._new_workdir()
                self.assertTrue(workdir.name.startswith("job-"))
                self.assertEqual(workdir.parent, sandbox.resolve())
                self.assertTrue(workdir.is_dir())
                runner_app._cleanup_workdir(workdir)
                self.assertFalse(workdir.exists())

    def test_cleanup_refuses_to_delete_outside_runner_tmp(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            sandbox = base / "runner-tmp"
            sandbox.mkdir()
            outside = base / "outside"
            outside.mkdir()
            keep = outside / "keep.txt"
            keep.write_text("sentinel", encoding="utf-8")
            with unittest.mock.patch.dict(os.environ, {"RUNNER_TMP": str(sandbox)}):
                runner_app._cleanup_workdir(outside)  # 越界：拒绝删除
                self.assertTrue(keep.exists())
                runner_app._cleanup_workdir(sandbox)  # 沙箱根本身：同样拒绝
                self.assertTrue(keep.exists())
                with self.assertRaises(ValueError):
                    runner_app._assert_inside_tmp(outside, sandbox)
                with self.assertRaises(ValueError):
                    runner_app._assert_inside_tmp(sandbox, sandbox)
                inside = runner_app._assert_inside_tmp(sandbox / "job-x", sandbox)
                self.assertEqual(inside, (sandbox / "job-x").resolve())


class TestRunnerServiceKey(unittest.TestCase):
    """RUNNER_API_TOKEN 两种模式：未设置保持开放，设置后要求 X-Runner-Service-Key。"""

    def setUp(self):
        self.client = TestClient(runner_app.app)

    def test_token_unset_keeps_endpoints_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            with unittest.mock.patch.dict(os.environ, {"RUNNER_TMP": tmp}) as env:
                env.pop(runner_app.RUNNER_TOKEN_ENV, None)  # 默认关闭：向后兼容既有部署
                ready = self.client.get("/ready")
                self.assertEqual(ready.status_code, 200)
                self.assertIs(ready.json()["ready"], True)
                count = self.client.post("/count", json=count_payload("job-open-1"))
                self.assertEqual(count.status_code, 200)
                self.assertEqual(count.json()["status"], "succeeded")

    def test_token_set_requires_matching_service_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            with unittest.mock.patch.dict(
                os.environ, {"RUNNER_TMP": tmp, runner_app.RUNNER_TOKEN_ENV: "s3cret"}
            ):
                bad_headers = ({}, {runner_app.RUNNER_KEY_HEADER: "wrong"})
                for path in ("/ready", "/health/ready"):
                    for headers in bad_headers:
                        response = self.client.get(path, headers=headers)
                        self.assertEqual(response.status_code, 401, (path, headers))
                        self.assertIs(response.json()["ready"], False)
                for headers in bad_headers:
                    response = self.client.post(
                        "/count", json=count_payload("job-tok-1"), headers=headers
                    )
                    self.assertEqual(response.status_code, 401, headers)
                    payload = response.json()
                    self.assertEqual(payload["status"], "failed")  # 契约形 401
                    self.assertIsNone(payload["count"])
                    self.assertIn("unauthorized", payload["warnings"][0])

                ok = {runner_app.RUNNER_KEY_HEADER: "s3cret"}
                for path in ("/ready", "/health/ready"):
                    response = self.client.get(path, headers=ok)
                    self.assertEqual(response.status_code, 200, path)
                    self.assertIs(response.json()["ready"], True)
                response = self.client.post("/count", json=count_payload("job-tok-2"), headers=ok)
                self.assertEqual(response.status_code, 200, response.json())
                self.assertEqual(response.json()["status"], "succeeded")


if __name__ == "__main__":
    unittest.main()
