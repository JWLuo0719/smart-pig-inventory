"""自证弱网重放脚本：用 mock 上游验证故障注入与不变量检查都真的生效。

这些测试回答的是"脚本本身可信吗"——不是"App 后端合规吗"。上游是
`tools/fake_upstream.py` 的最小合同实现（不是 smart-pig-inventory 的真实 Spring 后端）。
"""
from __future__ import annotations

import json
import threading
import unittest
import unittest.mock
import uuid
from http.server import ThreadingHTTPServer

from tools import fake_upstream
from tools.app_contract_sim import (
    PROFILES,
    Asset,
    CapturePackage,
    ContractClient,
    FaultProfile,
    NetworkFault,
    PackageSynchronizer,
    client_backoff,
    is_implemented,
    jpeg_bytes,
    probe_contract,
    verify,
)


def new_package(index: int = 0, assets: int = 1) -> CapturePackage:
    positions = ("single", "left", "center", "right")
    return CapturePackage(
        client_package_id=str(uuid.uuid4()),
        organization_id=str(uuid.uuid4()),
        pen_id=str(uuid.uuid4()),
        business_date="2026-09-16",
        capture_kind="single" if assets == 1 else "left_center_right",
        assets=[
            Asset(
                asset_id=str(uuid.uuid4()),
                data=jpeg_bytes(index * 10 + view),
                # 单图用 single；三视图按左/中/右（不能出现两个 single，服务端方向唯一性会拒）
                view_position="single" if assets == 1 else positions[min(view + 1, 3)],
                original_name=f"IMG_{index:03d}_{view}.jpg",
            )
            for view in range(assets)
        ],
    )


class UpstreamTestBase(unittest.TestCase):
    break_resume = False

    @classmethod
    def setUpClass(cls):
        cls.server, cls.state = fake_upstream.create_server(
            "127.0.0.1", 0, break_resume=cls.break_resume)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def client(self, token: str = "test-token") -> ContractClient:
        return ContractClient(self.base, access_token=token)

    def sync(self, package: CapturePackage, profile: FaultProfile, client=None):
        client = client or self.client()
        synchronizer = PackageSynchronizer(client, profile, logger=lambda *_: None)
        outcome = synchronizer.sync(package)
        return client, outcome, verify(package, outcome, client)


class TestHappyPath(UpstreamTestBase):
    def test_clean_sync_satisfies_all_invariants(self):
        package = new_package()
        _client, outcome, checks = self.sync(package, PROFILES["clean"])
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertTrue(package.session_id and package.inference_job_id)
        self.assertEqual(outcome.blob_uploads, 1)
        self.assertTrue(all(c["ok"] for c in checks), [c for c in checks if not c["ok"]])

    def test_three_view_package(self):
        package = new_package(assets=3)
        _client, outcome, checks = self.sync(package, PROFILES["clean"])
        self.assertTrue(outcome.synced)
        self.assertEqual(outcome.blob_uploads, 3)
        self.assertEqual([a.view_position for a in package.assets],
                         ["left", "center", "right"])
        self.assertTrue(all(c["ok"] for c in checks))


class TestIdempotency(UpstreamTestBase):
    def test_create_package_replay_returns_same_id(self):
        client = self.client()
        package = new_package()
        first = client.create_package(package)
        self.assertEqual(first[0], 201)
        package.server_package_id = first[1]["id"]
        replay = client.create_package(package)
        self.assertEqual(replay[0], 200)
        self.assertEqual(replay[1]["id"], package.server_package_id)
        self.assertEqual(replay[1]["state"], "awaiting_blobs")

    def test_commit_replay_returns_same_session_and_job(self):
        client = self.client()
        package = new_package()
        _c, outcome, _checks = self.sync(package, PROFILES["clean"], client)
        self.assertTrue(outcome.synced)
        status, payload, _ = client.commit(package)
        self.assertEqual(status, 200)
        self.assertEqual(payload["sessionId"], package.session_id)
        self.assertEqual(payload["inferenceJobId"], package.inference_job_id)

    def test_blob_replay_is_200_not_second_copy(self):
        client = self.client()
        package = new_package()
        status, payload, _ = client.create_package(package)
        package.server_package_id = payload["id"]
        first = client.put_blob(package, package.assets[0])
        again = client.put_blob(package, package.assets[0])
        self.assertEqual(first[0], 201)
        self.assertEqual(again[0], 200)

    def test_same_asset_id_different_content_conflicts(self):
        client = self.client()
        package = new_package()
        _status, payload, _ = client.create_package(package)
        package.server_package_id = payload["id"]
        client.put_blob(package, package.assets[0])
        tampered = Asset(asset_id=package.assets[0].asset_id, data=jpeg_bytes(999))
        status, body, _ = client.put_blob(package, tampered)
        self.assertEqual(status, 409)
        self.assertEqual(body["status"], 409)

    def test_blob_hash_mismatch_rejected(self):
        client = self.client()
        package = new_package()
        _status, payload, _ = client.create_package(package)
        package.server_package_id = payload["id"]
        asset = package.assets[0]
        with unittest.mock.patch.object(Asset, "sha256", new_callable=unittest.mock.PropertyMock,
                                        return_value="0" * 64):
            status, body, _ = client.put_blob(package, asset)
        self.assertEqual(status, 422, body)


class TestWeakNetwork(UpstreamTestBase):
    def test_offline_window_then_recovery(self):
        package = new_package()
        _client, outcome, checks = self.sync(package, PROFILES["offline-recovery"])
        self.assertGreater(outcome.faults.get("offline", 0), 0, "断网故障未被注入")
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertTrue(all(c["ok"] for c in checks), [c for c in checks if not c["ok"]])

    def test_dropped_responses_and_timeouts_do_not_duplicate(self):
        package = new_package()
        _client, outcome, checks = self.sync(package, PROFILES["flaky"])
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertTrue(all(c["ok"] for c in checks), [c for c in checks if not c["ok"]])
        self.assertTrue(outcome.faults, "flaky 场景应至少注入一次故障")
        # "发出即断"的调用服务端已经处理：客户端仍必须只拿到一个包
        self.assertIsNotNone(package.server_package_id)

    def test_token_expiry_replay_same_idempotency_key(self):
        package = new_package()
        _client, outcome, checks = self.sync(package, PROFILES["token-expiry"])
        self.assertGreater(outcome.faults.get("token_expired", 0), 0, "401 未被注入")
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertTrue(all(c["ok"] for c in checks), [c for c in checks if not c["ok"]])

    def test_timeout_after_server_processed_still_single_package(self):
        """响应丢失后重放：服务端只应有一个包（幂等键生效）。"""
        package = new_package()
        profile = FaultProfile(name="dropped", fail_calls=1, retry_delay=0.02)
        client, outcome, _checks = self.sync(package, profile)
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertEqual(outcome.faults.get("connection_lost"), 1)
        # 注入的失败发生在客户端，因此第一次真正成功的 create-package 才是建包
        self.assertTrue(outcome.created_package)
        self.assertEqual(outcome.blob_uploads, 1)
        # 再整包重放一次（模拟进程重启后的恢复）：必须命中同一个包与同一个任务
        server_package_id = package.server_package_id
        session_id = package.session_id
        synchronizer = PackageSynchronizer(client, FaultProfile(name="clean"),
                                           logger=lambda *_: None)
        again = synchronizer.sync(package)
        self.assertTrue(again.synced)
        self.assertEqual(package.server_package_id, server_package_id, "不应新建第二个包")
        self.assertEqual(package.session_id, session_id, "不应新建第二个盘点会话")
        self.assertEqual(again.blob_uploads, 0, "重放时 blob 已存在，不应再新建")
        self.assertEqual(again.blob_resends, 0, "重放时 existingAssets 应让它跳过上传")
        self.assertEqual(again.blob_skipped, 1)

    def test_partial_resume_skips_existing_asset(self):
        """中途断网后恢复：已上传的 blob 必须被 existingAssets 跳过。"""
        package = new_package(assets=3)
        profile = FaultProfile(
            name="partial-resume",
            fail_after_step=f"blob-{package.assets[0].asset_id[:8]}",
            retry_delay=0.02, max_attempts=5)
        _client, outcome, checks = self.sync(package, profile)
        self.assertEqual(outcome.faults.get("connection_lost"), 1, "应恰好断网一次")
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        self.assertEqual(outcome.blob_uploads, 3, "恢复后只补缺失的 blob，不重复上传")
        self.assertEqual(outcome.blob_skipped, 2, "已存在的两张 blob 应被跳过")
        self.assertEqual(outcome.blob_resends, 0, "服务端回报已有的 blob 不应重发")
        self.assertTrue(all(c["ok"] for c in checks), [c for c in checks if not c["ok"]])

    def test_client_backoff_matches_app_policy(self):
        import random

        rng = random.Random(1)
        self.assertGreaterEqual(client_backoff(1, rng), 30)
        self.assertLessEqual(client_backoff(8, rng), 15 * 60 + 1)
        self.assertLessEqual(client_backoff(99, rng), 15 * 60 + 1)

    def test_blocked_on_4xx_without_retry(self):
        """4xx（除 401）应判定为被拒，不再重试。"""
        client = self.client()
        package = new_package()
        package.server_package_id = str(uuid.uuid4())   # 不存在的包 → 404
        synchronizer = PackageSynchronizer(
            client, FaultProfile(name="clean", max_attempts=3), logger=lambda *_: None)
        outcome = synchronizer.sync(package)
        self.assertFalse(outcome.synced)
        self.assertIn("404", outcome.blocked_reason or "")


class TestBrokenUpstreamDetected(UpstreamTestBase):
    """故意让上游忽略 existingAssets，确认检查项真的能抓到重复上传。"""

    break_resume = True

    def test_resume_violation_is_caught(self):
        package = new_package(assets=3)
        profile = FaultProfile(
            name="partial-resume",
            fail_after_step=f"blob-{package.assets[0].asset_id[:8]}",
            retry_delay=0.02, max_attempts=5)
        _client, outcome, checks = self.sync(package, profile)
        self.assertTrue(outcome.synced, outcome.blocked_reason)
        # 该上游不回报 existingAssets（blob_skipped 恒为 0），恢复后必然重复上传：
        # blob1（attempt 1 已建但服务端没回报）与 blob2（断网前已发出）各重复一次
        self.assertEqual(outcome.blob_skipped, 0)
        self.assertGreaterEqual(outcome.blob_uploads, 3)
        self.assertEqual(outcome.blob_resends, 2, "两张已上传的 blob 被重发")
        # 上游从不回报 existingAssets，因此 I3（"回报了却重传"）按定义通过；
        # 真正抓到这类浪费的是 I8（同一次同步内每张图最多 PUT 一次）
        i8 = next(c for c in checks if c["id"] == "I8")
        self.assertFalse(i8["ok"], "重复上传必须被 I8 抓到")


class TestContractProbe(UpstreamTestBase):
    def test_probe_reports_all_endpoints_implemented(self):
        findings = probe_contract(self.client())
        self.assertEqual(len(findings), 5)
        self.assertTrue(all(item["implemented"] for item in findings),
                        [item for item in findings if not item["implemented"]])
        self.assertTrue(all(item["problem_json"] for item in findings),
                        "错误响应应为 application/problem+json")

    def test_probe_detects_missing_route(self):
        client = ContractClient("http://127.0.0.1:9", access_token="t", timeout=0.5)
        findings = probe_contract(client)
        self.assertTrue(all(not item["implemented"] for item in findings))

    def test_is_implemented_thresholds(self):
        for status in (200, 201, 401, 422, 409):
            self.assertTrue(is_implemented(status), status)
        for status in (None, 404, 405, 501):
            self.assertFalse(is_implemented(status), status)


class TestUnreachableTarget(unittest.TestCase):
    def test_network_fault_raised(self):
        client = ContractClient("http://127.0.0.1:9", access_token="t", timeout=0.5)
        with self.assertRaises(NetworkFault):
            client.get_package(str(uuid.uuid4()))


if __name__ == "__main__":
    unittest.main()
