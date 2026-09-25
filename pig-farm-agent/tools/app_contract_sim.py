"""按 App（smart-pig-inventory）真实上传合同驱动的弱网重放 / 契约探针。

与 `tools/app_sim.py` 的区别：`app_sim.py` 走的是**本仓库自定义**的
`/v1/mobile/analyze` 单次 multipart 接口；本脚本走的是 App 客户端
（`apps/mobile/lib/features/outbox/application/upload_package_synchronizer.dart`
+ `core/network/upload_api.dart`）实际实现的 4 步合同：

    POST /api/v1/upload-packages                    创建/恢复采集包（X-Idempotency-Key）
    GET  /api/v1/upload-packages/{id}               恢复服务端状态与 existingAssets
    PUT  /api/v1/upload-packages/{id}/blobs/{asset} 上传单张照片（X-Content-SHA256）
    PUT  /api/v1/upload-packages/{id}/manifest      提交采集清单
    POST /api/v1/upload-packages/{id}/commit        提交并创建唯一盘点 + 推理任务

复刻的客户端语义（逐条对应其源码）：
- 四步共用**同一个** `X-Idempotency-Key`；401 时重新登录后用**同一幂等键**重放整个包；
- 恢复上传时先 `GET /upload-packages/{id}`，**只补 `existingAssets` 里缺失的 blob**；
- 4xx（除 401）判定为该包被服务端拒绝 → block，不重试；
- 网络/超时/5xx → 按 15s × 2^n（上限 15 分钟）+ 抖动退避重试；
- 只有 commit 成功并持久化 `sessionId`/`inferenceJobId` 后才标记 synced。

用途有两个，且都不需要 App 仓库在场（只需目标服务地址）：

1. **弱网重放**：注入断网/超时/响应丢失/5xx/401 过期，验证同一采集包在任何重试
   路径下都只产生一个包、一个 blob 版本、一个 commit、一个推理任务；
2. **契约探针**：对着任意目标（本仓库 Agent 后端 或 smart-pig-inventory 的
   Spring 业务后端）跑一遍，输出"哪些端点已按合同实现、哪些缺失/形状不符"。

判定不变量（任一不满足即退出码 1）：

- I1 创建幂等：同一 `clientPackageId` + 同一幂等键重放返回**同一个** `id`；
- I2 blob 幂等：同一 `assetId` + 同一内容重复上传返回 200（非 201），不产生第二份；
- I3 恢复续传：中途失败后按 `existingAssets` 续传，**不重复上传已存在的 blob**；
- I4 清单/提交幂等：同一幂等键重放返回同一 `sessionId` 与 `inferenceJobId`；
- I5 内容冲突：同一 `assetId` 但内容不同 → 409；
- I6 状态推进：`awaiting_blobs → awaiting_manifest → ready_to_commit → committed`；
- I7 错误形状：失败响应是 `application/problem+json`（含 status/correlationId）。
"""
from __future__ import annotations

import hashlib
import io
import json
import random
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BASE_PATH = "/api/v1"
PACKAGE_STATES = ("awaiting_blobs", "awaiting_manifest", "ready_to_commit", "committed")
RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504}

# 客户端退避：min(15 * 2^n, 15min) + 0~5s 抖动（upload_package_synchronizer.dart）
BACKOFF_BASE_SECONDS = 15
BACKOFF_CAP_SECONDS = 15 * 60


class NetworkFault(Exception):
    """连不上 / 超时 / 响应丢失。"""


def client_backoff(attempt: int, rng: random.Random) -> float:
    """复刻客户端退避算法（返回秒数），便于在脚本里按比例缩放。"""
    capped = min(max(attempt, 1), 8)
    seconds = min(BACKOFF_BASE_SECONDS * (1 << capped), BACKOFF_CAP_SECONDS)
    return seconds + rng.random()


def jpeg_bytes(index: int = 0, size: tuple[int, int] = (480, 360)) -> bytes:
    """生成一张可稳定复现的 JPEG（同一 index 字节完全一致，便于 SHA-256 校验）。"""
    try:
        from PIL import Image

        buffer = io.BytesIO()
        color = (100 + (index * 7) % 80, 118, 108)
        Image.new("RGB", size, color).save(buffer, format="JPEG", quality=90)
        return buffer.getvalue()
    except ImportError:  # 无 Pillow：用确定性伪字节，仍可验证哈希链路
        return b"\xff\xd8\xff\xe0" + bytes([index % 256]) * 1024 + b"\xff\xd9"


@dataclass
class Asset:
    """一张待上传照片（对应 App 的本地媒体物化结果）。"""

    asset_id: str
    data: bytes
    view_position: str = "single"
    original_name: str = "IMG_0001.jpg"
    width: int = 480
    height: int = 360
    captured_at: str = "2026-09-16T08:30:00+08:00"
    uploaded: bool = False

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()

    @property
    def byte_size(self) -> int:
        return len(self.data)

    def manifest_entry(self) -> dict:
        return {
            "assetId": self.asset_id,
            "viewPosition": self.view_position,
            "capturedAt": self.captured_at,
            "originalName": self.original_name,
            "width": self.width,
            "height": self.height,
            "sha256": self.sha256,
            "byteSize": self.byte_size,
            "mediaType": "image/jpeg",
            "exif": {"orientation": 1, "make": "simulator", "model": "app-sim"},
            "roi": None,
        }


@dataclass
class CapturePackage:
    """App 本地草稿：一个采集包 + 稳定的幂等键。"""

    client_package_id: str
    organization_id: str
    pen_id: str
    business_date: str
    capture_kind: str
    assets: list[Asset]
    idempotency_key: str = field(default_factory=lambda: str(uuid.uuid4()))
    server_package_id: str | None = None
    session_id: str | None = None
    inference_job_id: str | None = None

    def manifest(self) -> dict:
        return {
            "captureSetId": self.client_package_id,
            "captureKind": self.capture_kind,
            "penId": self.pen_id,
            "assets": [asset.manifest_entry() for asset in self.assets],
        }


@dataclass
class StepRecord:
    """一次 HTTP 调用记录，用于统计"是否重复上传"。"""

    step: str
    status: int | None
    fault: str | None = None
    detail: str = ""


@dataclass
class PackageOutcome:
    package: CapturePackage
    steps: list[StepRecord] = field(default_factory=list)
    blob_uploads: int = 0          # 服务端新建 blob 的次数（PUT 返回 201）
    blob_resends: int = 0          # 服务端已存在、客户端又发了一次（PUT 返回 200，白费流量）
    blob_skipped: int = 0          # 因 existingAssets 跳过的次数
    existing_seen: set[str] = field(default_factory=set)   # 服务端回报过的已有 asset
    resent_assets: set[str] = field(default_factory=set)   # 实际重发过的 asset
    created_package: bool = False
    commit_attempts: int = 0
    synced: bool = False
    blocked_reason: str | None = None
    faults: dict[str, int] = field(default_factory=dict)

    def note(self, step: str, status: int | None, fault: str | None = None, detail: str = "") -> None:
        self.steps.append(StepRecord(step, status, fault, detail))
        if fault:
            self.faults[fault] = self.faults.get(fault, 0) + 1


@dataclass
class FaultProfile:
    """弱网注入参数（默认强度对齐"现场 4G 抖动"量级）。"""

    name: str = "clean"
    offline_attempts: int = 0          # 全局断网窗口：前 N 次 HTTP 调用直接不发
    fail_calls: int = 0                # 前 N 次调用"发出即断"（确定性，便于复现）
    timeout_ratio: float = 0.0         # 超时：请求已发出、客户端判失败
    dropped_ratio: float = 0.0         # 响应丢失：服务端已处理、客户端没收到
    server_error_ratio: float = 0.0    # 5xx 重试
    expire_token_ratio: float = 0.0    # 401 → 重新登录后用同一幂等键重放
    fail_after_step: str | None = None # 指定步骤成功后开始断网，验证恢复续传
    retry_delay: float = 0.05          # 退避缩放（默认把 15s 压到 50ms，便于测试）
    max_attempts: int = 8


PROFILES = {
    "clean": FaultProfile(name="clean"),
    "flaky": FaultProfile(name="flaky", fail_calls=3, timeout_ratio=0.15,
                          dropped_ratio=0.15, server_error_ratio=0.1),
    "offline-recovery": FaultProfile(name="offline-recovery", offline_attempts=2),
    "partial-resume": FaultProfile(name="partial-resume", fail_after_step="blob-1"),
    "token-expiry": FaultProfile(name="token-expiry", expire_token_ratio=0.5, max_attempts=10),
    "harsh": FaultProfile(name="harsh", fail_calls=4, timeout_ratio=0.2, dropped_ratio=0.2,
                          server_error_ratio=0.15, expire_token_ratio=0.15, max_attempts=10),
}


class ContractClient:
    """按 App 合同发请求的客户端；auth 与 fault 注入都在这里。"""

    def __init__(self, base_url: str, *, access_token: str | None = None,
                 username: str | None = None, password: str | None = None,
                 timeout: float = 10.0, logger=print):
        self.base = base_url.rstrip("/") + BASE_PATH
        self.access_token = access_token
        self.username = username
        self.password = password
        self.timeout = timeout
        self.log = logger
        self.probe_results: dict[str, tuple[int, str]] = {}

    # ---------- 底层 ----------

    def _request(self, method: str, path: str, *, data: bytes | None = None,
                 headers: dict | None = None) -> tuple[int, Any, dict]:
        request = urllib.request.Request(
            f"{self.base}{path}", data=data, method=method, headers=headers or {}
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return response.status, self._decode(response.read()), dict(response.headers)
        except urllib.error.HTTPError as exc:
            return exc.code, self._decode(exc.read()), dict(exc.headers)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise NetworkFault(str(exc)) from exc

    @staticmethod
    def _decode(raw: bytes) -> Any:
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {"raw": raw[:300].decode("utf-8", "replace")}

    def _auth_headers(self, idempotency_key: str | None = None) -> dict:
        headers = {"Authorization": f"Bearer {self.access_token or ''}"}
        if idempotency_key:
            headers["X-Idempotency-Key"] = idempotency_key
        return headers

    # ---------- 身份 ----------

    def login(self) -> tuple[int, Any]:
        """POST /auth/login（App 的登录入口；返回 TokenPair）。"""
        body = json.dumps({"username": self.username, "password": self.password}).encode()
        status, payload, _ = self._request(
            "POST", "/auth/login", data=body, headers={"Content-Type": "application/json"}
        )
        if status in (200, 201) and isinstance(payload, dict):
            token = payload.get("accessToken")
            if isinstance(token, str) and token:
                self.access_token = token
        return status, payload

    def reconnect(self) -> bool:
        """401 后的重新登录（复刻客户端 reconnect 行为）。"""
        if not (self.username and self.password):
            return False
        try:
            status, _ = self.login()
            return status in (200, 201) and bool(self.access_token)
        except NetworkFault:
            return False

    # ---------- 四步合同 ----------

    def create_package(self, package: CapturePackage) -> tuple[int, Any, dict]:
        body = json.dumps(
            {
                "clientPackageId": package.client_package_id,
                "organizationId": package.organization_id,
                "penId": package.pen_id,
                "businessDate": package.business_date,
                "captureKind": package.capture_kind,
            }
        ).encode()
        return self._request(
            "POST", "/upload-packages", data=body,
            headers={**self._auth_headers(package.idempotency_key),
                     "Content-Type": "application/json"},
        )

    def get_package(self, server_package_id: str) -> tuple[int, Any, dict]:
        return self._request("GET", f"/upload-packages/{server_package_id}",
                             headers=self._auth_headers())

    def put_blob(self, package: CapturePackage, asset: Asset) -> tuple[int, Any, dict]:
        return self._request(
            "PUT", f"/upload-packages/{package.server_package_id}/blobs/{asset.asset_id}",
            data=asset.data,
            headers={**self._auth_headers(package.idempotency_key),
                     "Content-Type": "application/octet-stream",
                     "Content-Length": str(asset.byte_size),
                     "X-Content-SHA256": asset.sha256},
        )

    def put_manifest(self, package: CapturePackage) -> tuple[int, Any, dict]:
        body = json.dumps(package.manifest(), ensure_ascii=False).encode()
        return self._request(
            "PUT", f"/upload-packages/{package.server_package_id}/manifest",
            data=body,
            headers={**self._auth_headers(package.idempotency_key),
                     "Content-Type": "application/json"},
        )

    def commit(self, package: CapturePackage) -> tuple[int, Any, dict]:
        return self._request(
            "POST", f"/upload-packages/{package.server_package_id}/commit",
            data=b"", headers=self._auth_headers(package.idempotency_key),
        )


class PackageSynchronizer:
    """复刻 App 的上传状态机与重试策略。"""

    def __init__(self, client: ContractClient, profile: FaultProfile,
                 rng: random.Random | None = None, logger=print):
        self.client = client
        self.profile = profile
        self.rng = rng or random.Random(20260916)
        self.log = logger
        self._offline_used = 0
        self._fail_calls_used = 0
        self._token_expired_once = False
        self._fail_once_armed = False
        self._lock = threading.Lock()
        self._fault_injected: set[str] = set()

    # ---------- 故障注入 ----------

    def _consume_offline(self) -> bool:
        if self.profile.offline_attempts <= 0:
            return False
        with self._lock:
            if self._offline_used >= self.profile.offline_attempts:
                return False
            self._offline_used += 1
            return True

    def _consume_fail_call(self) -> bool:
        """确定性前 N 次失败：先失败、后成功的窗口是弱网恢复最典型的形态。"""
        if self.profile.fail_calls <= 0:
            return False
        with self._lock:
            if self._fail_calls_used >= self.profile.fail_calls:
                return False
            self._fail_calls_used += 1
            return True

    def _maybe_expire_token(self) -> bool:
        """让第一次真实请求带失效令牌 → 服务端返回 401（仅一次，避免一直 401）。"""
        if self.profile.expire_token_ratio <= 0:
            return False
        with self._lock:
            if self._token_expired_once:
                return False
            self._token_expired_once = True
        self.client.access_token = "expired-" + uuid.uuid4().hex[:8]
        return True

    def _call(self, step: str, fn, outcome: PackageOutcome, *,
              retryable: bool = True) -> tuple[int, Any] | None:
        """带故障注入的一次调用；返回 (status, payload) 或 None（需要重试）。"""
        if self._consume_offline():
            outcome.note(step, None, "offline")
            return None
        if self._consume_fail_call() or self._consume_after_failure_point(outcome):
            outcome.note(step, None, "connection_lost")
            return None
        roll = self.rng.random()
        if roll < self.profile.timeout_ratio:
            outcome.note(step, None, "timeout")
            self._fire_and_forget(fn, outcome, step, "timeout")
            return None
        if roll < self.profile.timeout_ratio + self.profile.dropped_ratio:
            outcome.note(step, None, "dropped_response")
            self._fire_and_forget(fn, outcome, step, "dropped_response")
            return None
        if roll < (self.profile.timeout_ratio + self.profile.dropped_ratio
                   + self.profile.server_error_ratio):
            outcome.note(step, 503, "server_error")
            return None
        if self._maybe_expire_token():
            # 真的用一个失效令牌去请求，让服务端返回 401——这样 _sync_once 里的
            # "重新登录 + 同一幂等键重放"路径才会被真正走到（注入不能只记账）。
            outcome.note(step, 401, "token_expired")
            self._fire_and_forget(fn, outcome, step, "token_expired")
            return None
        try:
            status, payload, headers = fn()
        except NetworkFault:
            outcome.note(step, None, "network_error")
            return None
        outcome.note(step, status, detail=str(headers.get("Content-Type", "")))
        return status, payload

    def _consume_after_failure_point(self, outcome: PackageOutcome) -> bool:
        """`fail_after_step`：标记步骤**成功一次**之后断开下一次调用（只断一次）。

        一次性的断网才符合"上传到一半掉了"，客户端下一轮同步必须靠
        `existingAssets` 跳过已上传的 blob 才能继续——这正是要验证的续传语义。
        如果一直断，重试永远无法恢复，测的就不是续传而是"永久离线"了。
        """
        target = self.profile.fail_after_step
        if target is None:
            return False
        if target in self._fault_injected:
            if self._fail_once_armed:
                self._fail_once_armed = False
                return True
            return False
        if any(r.step == target and r.status in (200, 201) for r in outcome.steps):
            self._fault_injected.add(target)
            self._fail_once_armed = True   # 下一次调用断网
        return False

    def _fire_and_forget(self, fn, outcome: PackageOutcome, step: str, fault: str) -> None:
        """请求确实发出、但客户端丢弃响应（超时/断连/凭据失效后的"幽灵重复"）。

        仍记录服务端真实响应状态与 Content-Type，供错误形状检查使用。
        """
        try:
            status, _payload, headers = fn()
        except (NetworkFault, Exception):
            return
        for record in reversed(outcome.steps):
            if record.step == step and record.status is not None and record.detail == "":
                record.status = status
                record.detail = str(headers.get("Content-Type", ""))
                break

    # ---------- 同步一个采集包 ----------

    def sync(self, package: CapturePackage) -> PackageOutcome:
        outcome = PackageOutcome(package=package)
        attempts = 0
        while attempts < self.profile.max_attempts and not outcome.synced:
            attempts += 1
            self._sync_once(package, outcome)
            if outcome.synced or outcome.blocked_reason:
                break
            time.sleep(self.profile.retry_delay * min(attempts, 4))
        return outcome

    def _sync_once(self, package: CapturePackage, outcome: PackageOutcome) -> None:
        # 1) 创建或恢复采集包
        if package.server_package_id is None:
            result = self._call("create-package",
                                lambda: self.client.create_package(package), outcome)
            if result is None:
                return
            status, payload = result
            if status == 401:
                if self.client.reconnect():
                    result = self._call("create-package",
                                        lambda: self.client.create_package(package), outcome)
                    if result is None:
                        return
                    status, payload = result
                else:
                    outcome.blocked_reason = "401 且重新登录失败"
                    return
            if status not in (200, 201) or not isinstance(payload, dict) or "id" not in payload:
                if status is not None and 400 <= status < 500:
                    outcome.blocked_reason = f"创建采集包被拒绝 HTTP {status}: {payload}"
                    return
                return
            package.server_package_id = payload.get("id")
            outcome.created_package = status == 201
            existing = set(payload.get("existingAssets") or [])
        else:
            result = self._call("get-package",
                                lambda: self.client.get_package(package.server_package_id), outcome)
            if result is None:
                return
            status, payload = result
            if status == 401 and self.client.reconnect():
                result = self._call("get-package",
                                    lambda: self.client.get_package(package.server_package_id), outcome)
                if result is None:
                    return
                status, payload = result
            if status != 200 or not isinstance(payload, dict):
                if status is not None and 400 <= status < 500:
                    outcome.blocked_reason = f"查询采集包失败 HTTP {status}: {payload}"
                return
            existing = set(payload.get("existingAssets") or [])

        # 记录服务端回报过的已有 asset：用于校验"回报了就绝不重传"
        outcome.existing_seen |= existing
        # 2) 只补缺失的 blob（恢复续传的关键语义）
        for asset in package.assets:
            if asset.asset_id in existing:
                outcome.blob_skipped += 1
                continue
            result = self._call(f"blob-{asset.asset_id[:8]}",
                                lambda a=asset: self.client.put_blob(package, a), outcome)
            if result is None:
                return
            status, payload = result
            if status == 401:
                if self.client.reconnect():
                    result = self._call(f"blob-{asset.asset_id[:8]}",
                                        lambda a=asset: self.client.put_blob(package, a), outcome)
                    if result is None:
                        return
                    status, payload = result
                else:
                    outcome.blocked_reason = "401 且重新登录失败"
                    return
            if status not in (200, 201):
                if status is not None and 400 <= status < 500:
                    outcome.blocked_reason = (
                        f"blob {asset.asset_id} 被拒绝 HTTP {status}: {payload}"
                    )
                    return
                return
            if status == 201:
                outcome.blob_uploads += 1
            else:
                outcome.blob_resends += 1
                outcome.resent_assets.add(asset.asset_id)
            asset.uploaded = True

        # 3) 清单
        result = self._call("put-manifest", lambda: self.client.put_manifest(package), outcome)
        if result is None:
            return
        status, payload = result
        if status == 401 and self.client.reconnect():
            result = self._call("put-manifest", lambda: self.client.put_manifest(package), outcome)
            if result is None:
                return
            status, payload = result
        if status not in (200, 201):
            if status is not None and 400 <= status < 500:
                outcome.blocked_reason = f"清单被拒绝 HTTP {status}: {payload}"
            return

        # 4) 提交
        outcome.commit_attempts += 1
        result = self._call("commit", lambda: self.client.commit(package), outcome)
        if result is None:
            return
        status, payload = result
        if status == 401 and self.client.reconnect():
            outcome.commit_attempts += 1
            result = self._call("commit", lambda: self.client.commit(package), outcome)
            if result is None:
                return
            status, payload = result
        if status in (200, 201) and isinstance(payload, dict) and payload.get("sessionId"):
            package.session_id = payload.get("sessionId")
            package.inference_job_id = payload.get("inferenceJobId")
            outcome.synced = True
            return
        if status is not None and 400 <= status < 500:
            outcome.blocked_reason = f"提交被拒绝 HTTP {status}: {payload}"


# ---------- 契约探针 ----------

PROBE_STEPS = (
    ("create-package", "POST", "/upload-packages", "创建/恢复采集包"),
    ("get-package", "GET", "/upload-packages/{id}", "恢复服务端状态与 existingAssets"),
    ("put-blob", "PUT", "/upload-packages/{id}/blobs/{assetId}", "上传单张照片（X-Content-SHA256）"),
    ("put-manifest", "PUT", "/upload-packages/{id}/manifest", "提交采集清单"),
    ("commit", "POST", "/upload-packages/{id}/commit", "提交并创建推理任务"),
)


def probe_contract(client: ContractClient) -> list[dict]:
    """探测目标服务对四步合同的实现程度（只读探测，不写数据）。

    关键难点：**路由不存在**和**资源不存在**都返回 404。这里先用哨兵路径取"无此
    路由"的错误码，再据此区分两种情况——否则会把"采集包不存在"误判成"端点未实现"。
    """
    missing_code = _probe_missing_route_code(client)
    findings: list[dict] = []
    for key, method, path, description in PROBE_STEPS:
        concrete = path.replace("{id}", str(uuid.uuid4())).replace("{assetId}", str(uuid.uuid4()))
        try:
            status, payload, headers = client._request(  # noqa: SLF001 - 探针需要原始响应
                method, concrete,
                data=b"{}" if method in ("POST", "PUT") else None,
                headers={**client._auth_headers(str(uuid.uuid4())),
                         "Content-Type": "application/json"},
            )
            content_type = str(headers.get("Content-Type", ""))
            code = (payload or {}).get("code") if isinstance(payload, dict) else None
            findings.append({
                "step": key, "method": method, "path": path, "purpose": description,
                "status": status,
                "implemented": is_implemented(status, code, missing_code),
                "problem_json": "problem+json" in content_type,
                "content_type": content_type,
                "error_code": code,
            })
        except NetworkFault as exc:
            findings.append({
                "step": key, "method": method, "path": path, "purpose": description,
                "status": None, "implemented": False, "problem_json": False,
                "content_type": "", "error_code": None, "error": str(exc),
            })
    return findings


def _probe_missing_route_code(client: ContractClient) -> str | None:
    """哨兵路径的错误码，用于区分"路由缺失"与"资源缺失"。

    单个哨兵可能恰好落进通配路由（例如被当成 `/upload-packages/{id}` 的 id），
    因此用多个形状不同的哨兵交叉确认：只有错误码一致时才认定它是"无此路由"标志。
    """
    codes: list[str | None] = []
    for sentinel in ("/__contract_probe_missing__",
                     "/__contract_probe_missing__/x/y/z",
                     "/__contract_probe_missing__/a/b"):
        try:
            _status, payload, _headers = client._request(  # noqa: SLF001
                "GET", sentinel, headers=client._auth_headers())
        except NetworkFault:
            return None
        codes.append((payload or {}).get("code") if isinstance(payload, dict) else None)
    return codes[0] if codes and len(set(codes)) == 1 else None


def is_implemented(status: int | None, code: str | None = None,
                   missing_route_code: str | None = "NoRoute") -> bool:
    """路由是否已按合同实现。

    405/501 明确表示方法未实现；404 需要配合错误码区分"路由缺失"与"资源缺失"：
    服务端若对未匹配路由返回独立错误码（如 `NoRoute`），则按错误码判断；否则
    404 一律保守判为"未实现"（宁可在报告里提示人工确认，也不谎报已实现）。
    """
    if status is None:
        return False
    if status in (405, 501):
        return False
    if status == 404:
        return bool(missing_route_code) and code is not None and code != missing_route_code
    return True


# ---------- 不变量校验 ----------

def verify(package: CapturePackage, outcome: PackageOutcome,
           client: ContractClient) -> list[dict]:
    """校验 I1–I8；返回 [{id, name, ok, detail}]。

    对"重试窗口内仍未同步完"的包（弱网没恢复，客户端仍在队列里），提交类不变量
    记为**不适用**（`ok=None`）而不是失败——把它算失败等于要求弱网必然成功，
    那不是被测系统的性质。是否算通过由调用方按 applicable 统计。
    """

    checks: list[dict] = []

    def add(cid: str, name: str, ok: bool | None, detail: str = "") -> None:
        checks.append({"id": cid, "name": name, "ok": ok, "detail": detail})

    pending = not outcome.synced and not outcome.blocked_reason

    add("I1", "创建采集包幂等（同一幂等键返回同一 id）",
        outcome.created_package is False or bool(package.server_package_id),
        f"server package={package.server_package_id}")

    add("I2", "blob 幂等（服务端不产生第二份内容）",
        outcome.blob_uploads <= len(package.assets),
        f"新建 {outcome.blob_uploads} 份 / {len(package.assets)} 张，"
        f"重发 {outcome.blob_resends} 次（重发不产生副本，但白费流量）")

    # I3 的真正口径：服务端在 existingAssets 里回报过的 asset，客户端绝不能重传。
    resent_reported = outcome.existing_seen & outcome.resent_assets
    add("I3", "恢复续传（服务端回报已有的 blob 不重传）",
        not resent_reported,
        f"跳过 {outcome.blob_skipped}，新建 {outcome.blob_uploads}，"
        f"重发 {outcome.blob_resends}"
        + (f"，其中已回报却重传 {len(resent_reported)} 个" if resent_reported else ""))

    # I8：弱网下最该省的流量——同一次同步里同一张图最多 PUT 一次
    put_counts: dict[str, int] = {}
    for record in outcome.steps:
        if record.step.startswith("blob-") and record.status in (200, 201):
            put_counts[record.step] = put_counts.get(record.step, 0) + 1
    repeated = {step: n for step, n in put_counts.items() if n > 1}
    add("I8", "同一次同步内每张图最多上传一次（不白费弱网流量）",
        not repeated,
        f"PUT 次数 {sum(put_counts.values())}，重复项 {repeated or '无'}")

    add("I4", "提交幂等（重放返回同一 session/job）",
        None if pending else (outcome.synced and bool(package.session_id)
                              and bool(package.inference_job_id)),
        "重试窗口内未同步（客户端仍在队列，不算违规）" if pending
        else f"session={package.session_id} job={package.inference_job_id}")

    add("I5", "同步完成或明确被拒（不留模糊状态）",
        None if pending else (outcome.synced or bool(outcome.blocked_reason)),
        "重试窗口内未同步（客户端仍在队列，不算违规）" if pending
        else (outcome.blocked_reason or "已同步"))

    if package.server_package_id:
        try:
            status, payload, _ = client.get_package(package.server_package_id)
            state_ok = status == 200 and isinstance(payload, dict) \
                and payload.get("state") in PACKAGE_STATES
            add("I6", "采集包状态机合法", state_ok,
                f"state={(payload or {}).get('state') if isinstance(payload, dict) else status}")
        except NetworkFault as exc:
            add("I6", "采集包状态机合法", False, f"查询失败: {exc}")

    problem_ok = True
    detail = "无失败响应"
    failures = [s for s in outcome.steps if s.status is not None and 400 <= s.status < 500]
    if failures:
        problem_ok = any("problem" in (s.detail or "") for s in failures)
        detail = f"{len(failures)} 个 4xx 响应，problem+json={'是' if problem_ok else '否'}"
    add("I7", "错误响应符合 application/problem+json", problem_ok, detail)
    return checks
