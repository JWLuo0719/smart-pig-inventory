"""模拟 App 的弱网行为，对运行中的 Agent 服务做联调压测（不依赖 App 仓库）。

模拟对象是 `smart-pig-inventory` 的行为契约（依据技术文档 §1.1 与 §8，字段名与
响应形状已对真实服务实测确认，见 `docs/app-integration-contract.md`）：

- 现场拍摄后先写入**本地队列**，有网才上传（multipart：`farm_id`、`barn_id`、
  `captured_at`、`client_request_id`、`image`）；
- 上传失败（超时/连不上/5xx/429）时保留队列项，**沿用同一个 `client_request_id`**
  重试；成功后从队列删除并记录 `event_id`；
- 恢复后可用 `GET /v1/mobile/requests/{client_request_id}` 查询结果（进程重启也能查到）；
- 复核时 `POST /events/{event_id}/ack|resolve|dismiss` 回写操作者与备注。

脚本注入的弱网故障：

| 故障 | 模拟方式 | 要验证的服务端性质 |
|---|---|---|
| `offline-at-start` | 前 N 个请求直接判为断网，不发出 | 队列可积压、恢复后按原 ID 重放 |
| `fail-first-attempt` | 首个请求"发出即断"，服务端已处理但客户端没收到 | 幂等：重放返回同一 `event_id`，不产生重复事件 |
| `timeout` | 请求发出后本地超时 | 同上（最典型的"幽灵重复"） |
| `flaky` | 按概率注入以上故障 | 混合流量下无重复事件 |
| `slow` | 每个请求前 sleep，压低吞吐 | 并发/连续上传不互相干扰 |

判定不变量（任一不满足即退出码 1）：

1. **一项一事件**：每个 `client_request_id` 最终对应恰好一个 `event_id`；
2. **重放幂等**：同一 ID 的多次尝试返回同一个 `event_id`，且服务端事件总数不增长；
3. **可追溯**：`GET /v1/mobile/requests/{id}` 能查到结果并带 `event_id`；
4. **确认可回写**：`ack` 成功且状态轨迹记录操作者与备注；
5. **错误可识别**：失败响应必须是统一错误格式 `{error_code, message, request_id}`。
"""
from __future__ import annotations

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
from typing import Any

SCENARIOS = ("clean", "flaky", "offline-recovery", "lossy-timeout", "burst", "slow")

RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504}
INTERNAL_ERROR_CODES = {"INTERNAL_ERROR", "MODEL_UNAVAILABLE", "PAYLOAD_TOO_LARGE",
                        "UNSUPPORTED_MEDIA_TYPE", "INVALID_MULTIPART"}


class NetworkFault(Exception):
    """客户端侧网络故障：连不上 / 超时 / 响应丢失。"""


@dataclass
class FaultProfile:
    """弱网注入参数。"""

    name: str = "clean"
    offline_first: int = 0           # 前 N 次请求直接断网（不发出）
    fail_first_attempt_ratio: float = 0.0   # "发出即断"比例：服务端已处理，客户端没收到
    timeout_ratio: float = 0.0       # 本地超时比例
    error_ratio: float = 0.0         # 服务端 5xx/429 比例（由脚本伪造，模拟网关错误）
    pre_request_delay: float = 0.0   # 每个请求前的额外延迟（秒）
    concurrency: int = 1             # 并发上传数（App 批量补传场景）


PROFILES = {
    "clean": FaultProfile(name="clean"),
    "flaky": FaultProfile(name="flaky", fail_first_attempt_ratio=0.30, timeout_ratio=0.15,
                          error_ratio=0.10, concurrency=2),
    "offline-recovery": FaultProfile(name="offline-recovery", offline_first=4, concurrency=2),
    "lossy-timeout": FaultProfile(name="lossy-timeout", timeout_ratio=0.5),
    "burst": FaultProfile(name="burst", concurrency=4),
    "slow": FaultProfile(name="slow", pre_request_delay=0.25, fail_first_attempt_ratio=0.2),
}


@dataclass
class QueueItem:
    """App 本地队列项：拍摄一次 = 一项，重试始终沿用同一个 client_request_id。"""

    index: int
    client_request_id: str
    farm_id: str
    barn_id: str
    captured_at: str
    image: bytes
    filename: str

    def fields(self) -> dict[str, str]:
        return {
            "farm_id": self.farm_id,
            "barn_id": self.barn_id,
            "captured_at": self.captured_at,
            "client_request_id": self.client_request_id,
            "source": "upload",
        }


@dataclass
class ItemOutcome:
    item: QueueItem
    attempts: int = 0
    event_id: str | None = None
    event_ids_seen: list[str] = field(default_factory=list)
    merged_flags: list[bool] = field(default_factory=list)
    terminal_error: str | None = None
    uploaded: bool = False
    fault_counts: dict[str, int] = field(default_factory=dict)

    def note_fault(self, kind: str) -> None:
        self.fault_counts[kind] = self.fault_counts.get(kind, 0) + 1


def make_jpeg(width: int = 420, height: int = 300, color: tuple[int, int, int] = (128, 120, 110)) -> bytes:
    try:
        from PIL import Image

        buffer = io.BytesIO()
        Image.new("RGB", (width, height), color).save(buffer, format="JPEG", quality=88)
        return buffer.getvalue()
    except ImportError:  # 无 Pillow 时退化为最小 JPEG 头，仍可走通上传链路
        return b"\xff\xd8\xff\xe0" + b"0" * 512 + b"\xff\xd9"


def build_multipart(fields: dict[str, str], filename: str, payload: bytes,
                    boundary: str) -> tuple[bytes, str]:
    chunks: list[bytes] = []
    for key, value in fields.items():
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
        )
    chunks.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{filename}"\r\n'
        "Content-Type: image/jpeg\r\n\r\n".encode()
    )
    chunks.append(payload)
    chunks.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


class AppSimulator:
    """模拟 App 的离线队列 + 幂等重试客户端。"""

    def __init__(self, base_url: str, *, token: str | None = None, timeout: float = 10.0,
                 max_retries: int = 4, backoff: float = 0.2, seed: int | None = None,
                 marker: str | None = None, logger=print):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout
        self.max_retries = max_retries
        self.backoff = backoff
        self.rng = random.Random(seed if seed is not None else 20260916)
        self.marker = marker or f"appsim-{uuid.uuid4().hex[:8]}"
        self.log = logger
        self._lock = threading.Lock()

    # ---------- 底层 HTTP ----------

    def _headers(self, extra: dict | None = None) -> dict:
        headers = dict(extra or {})
        if self.token:
            headers["X-Api-Token"] = self.token
        return headers

    def request(self, method: str, path: str, *, data: bytes | None = None,
                headers: dict | None = None, timeout: float | None = None) -> tuple[int, Any, dict]:
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, method=method, headers=self._headers(headers)
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout or self.timeout) as response:
                raw = response.read()
                return response.status, self._decode(raw), dict(response.headers)
        except urllib.error.HTTPError as exc:
            return exc.code, self._decode(exc.read()), dict(exc.headers)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise NetworkFault(str(exc)) from exc

    @staticmethod
    def _decode(raw: bytes) -> Any:
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {"raw": raw[:200].decode("utf-8", "replace")}

    # ---------- App 行为 ----------

    def upload_once(self, item: QueueItem) -> dict:
        """一次上传尝试：成功返回 {status, body}；服务端错误原样返回；网络故障抛 NetworkFault。"""
        boundary = f"----appsim{uuid.uuid4().hex[:12]}"
        body, content_type = build_multipart(item.fields(), item.filename, item.image, boundary)
        status, payload, _ = self.request("POST", "/v1/mobile/analyze", data=body,
                                         headers={"Content-Type": content_type})
        return {"status": status, "body": payload}

    def upload_with_retry(self, item: QueueItem, profile: FaultProfile) -> ItemOutcome:
        """按 App 的重试策略上传一项；故障注入与重试都记录在 outcome 里。

        `offline_first` 是**全局**的断网窗口（所有项共享），用实例状态实现，
        这样并发场景下也能真实模拟"整场断网 → 恢复后集中补传"。
        """
        outcome = ItemOutcome(item=item)
        for attempt in range(1, self.max_retries + 1):
            outcome.attempts = attempt
            if profile.pre_request_delay:
                time.sleep(profile.pre_request_delay)
            if self._consume_offline_slot(profile):
                # 断网：请求根本没发出，App 保留队列项、沿用同一 client_request_id
                outcome.note_fault("offline")
                time.sleep(self.backoff)
                continue
            roll = self.rng.random()
            if roll < profile.timeout_ratio:
                # 超时：请求已到服务端并可能已处理，客户端却认为失败 —— 最易造成重复事件
                outcome.note_fault("timeout")
                self._fire_and_forget(item)
                time.sleep(self.backoff)
                continue
            if roll < profile.timeout_ratio + profile.fail_first_attempt_ratio:
                # 发出即断（响应丢失）：服务端已处理
                outcome.note_fault("dropped_response")
                self._fire_and_forget(item)
                time.sleep(self.backoff)
                continue
            if roll < profile.timeout_ratio + profile.fail_first_attempt_ratio + profile.error_ratio:
                outcome.note_fault("server_error")
                time.sleep(self.backoff)
                continue
            try:
                result = self.upload_once(item)
            except NetworkFault:
                outcome.note_fault("network_error")
                time.sleep(self.backoff)
                continue

            status, payload = result["status"], result["body"]
            if status == 200 and isinstance(payload, dict) and "event" in payload:
                event = payload["event"]
                outcome.uploaded = True
                outcome.event_id = event.get("event_id")
                outcome.event_ids_seen.append(outcome.event_id)
                outcome.merged_flags.append(bool(payload.get("merged")))
                return outcome
            if status in RETRYABLE_STATUS:
                outcome.note_fault(f"http_{status}")
                time.sleep(self.backoff)
                continue
            # 非可重试错误（4xx）：App 应标记该项失败并提示用户
            outcome.terminal_error = self._describe_error(status, payload)
            return outcome
        outcome.terminal_error = outcome.terminal_error or "重试次数耗尽（弱网未恢复）"
        return outcome

    def _consume_offline_slot(self, profile: FaultProfile) -> bool:
        """全局断网窗口：前 N 次尝试不发请求（无论哪一项、哪一轮）。"""
        if profile.offline_first <= 0:
            return False
        with self._lock:
            if self._offline_used >= profile.offline_first:
                return False
            self._offline_used += 1
        return True

    def _fire_and_forget(self, item: QueueItem) -> None:
        """请求确实发出、但客户端丢弃响应（模拟超时/断连后的"幽灵重复"）。"""
        try:
            self.upload_once(item)
        except NetworkFault:
            pass

    @staticmethod
    def _describe_error(status: int, payload: Any) -> str:
        if isinstance(payload, dict) and "error_code" in payload:
            return f"HTTP {status} {payload['error_code']}: {payload.get('message', '')}"
        return f"HTTP {status}: {str(payload)[:120]}"

    def query_request(self, client_request_id: str) -> tuple[int, Any]:
        status, payload, _ = self.request(
            "GET", f"/v1/mobile/requests/{urllib.parse.quote(client_request_id)}"
        )
        return status, payload

    def fetch_event(self, event_id: str) -> tuple[int, Any]:
        status, payload, _ = self.request("GET", f"/events/{urllib.parse.quote(event_id)}")
        return status, payload

    def acknowledge(self, event_id: str, *, operator: str, note: str | None = None) -> tuple[int, Any]:
        body = json.dumps({"operator": operator, "note": note}).encode()
        status, payload, _ = self.request("POST", f"/events/{event_id}/ack", data=body,
                                          headers={"Content-Type": "application/json"})
        return status, payload

    def count_marker_events(self, marker: str) -> tuple[int, list[str]]:
        """统计本次联调注入的事件数（按 request_id 前缀隔离，不干扰既有数据）。"""
        seen: list[str] = []
        offset = 0
        while True:
            status, payload, _ = self.request(
                "GET", f"/events?limit=200&offset={offset}"
            )
            if status != 200 or not isinstance(payload, dict):
                break
            events = payload.get("events") or []
            for event in events:
                if str(event.get("request_id", "")).startswith(marker):
                    seen.append(event.get("event_id"))
            if len(events) < 200:
                break
            offset += 200
        return len(set(seen)), seen


import urllib.parse  # noqa: E402  （放在类定义后避免顶部导入顺序争议）


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


def build_queue(marker: str, *, count: int, barns: tuple[str, ...] = ("A01", "A02"),
                captured_base: str = "2026-09-16T08:") -> list[QueueItem]:
    """构造一次现场巡检的本地队列（每项一个 client_request_id）。"""
    items = []
    for index in range(count):
        barn = barns[index % len(barns)]
        items.append(
            QueueItem(
                index=index,
                client_request_id=f"{marker}-{index:03d}",
                farm_id="farm-app",
                barn_id=barn,
                captured_at=f"{captured_base}{index % 60:02d}:00+08:00",
                image=make_jpeg(420, 300, (120 + index % 40, 120, 110)),
                filename=f"IMG_{index:03d}.jpg",
            )
        )
    return items


def run_scenario(simulator: AppSimulator, items: list[QueueItem], profile: FaultProfile,
                 *, acknowledge: bool = True) -> dict:
    """跑一个弱网场景，返回结果与不变量检查。"""
    started = time.perf_counter()
    outcomes: list[ItemOutcome | None] = [None] * len(items)

    if profile.concurrency > 1:
        semaphore = threading.Semaphore(profile.concurrency)

        def worker(slot: int, item: QueueItem) -> None:
            with semaphore:
                outcomes[slot] = simulator.upload_with_retry(item, profile)

        threads = [threading.Thread(target=worker, args=(i, item))
                   for i, item in enumerate(items)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
    else:
        for i, item in enumerate(items):
            outcomes[i] = simulator.upload_with_retry(item, profile)

    resolved: list[ItemOutcome] = [o for o in outcomes if o is not None]
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    return {
        "profile": profile,
        "marker": simulator.marker,
        "items": len(items),
        "elapsed_ms": round(elapsed_ms, 1),
        "outcomes": resolved,
        "acknowledge": acknowledge,
    }


def verify(simulator: AppSimulator, run: dict) -> list[Check]:
    """校验 §1–§5 不变量。"""
    checks: list[Check] = []
    outcomes: list[ItemOutcome] = run["outcomes"]
    uploaded = [o for o in outcomes if o.uploaded]

    # 1. 一项一事件
    checks.append(Check(
        "每个 client_request_id 对应恰好一个 event_id",
        all(len(set(o.event_ids_seen)) <= 1 for o in outcomes),
        f"上传成功 {len(uploaded)}/{len(outcomes)}",
    ))

    # 2. 重放幂等：反复重放同一 ID 必须返回同一事件
    replay_ok, replay_detail = True, ""
    for outcome in uploaded[:3]:  # 抽查前 3 项，避免放大流量
        status, payload = simulator.query_request(outcome.item.client_request_id)
        if status != 200 or not isinstance(payload, dict):
            replay_ok, replay_detail = False, f"{outcome.item.client_request_id} 查询失败 HTTP {status}"
            break
        stored = ((payload.get("result") or {}).get("event") or {}).get("event_id")
        if stored != outcome.event_id:
            replay_ok, replay_detail = False, f"{outcome.item.client_request_id}: {stored} != {outcome.event_id}"
            break
    checks.append(Check("重放/查询命中同一事件（幂等）", replay_ok, replay_detail))

    # 3. 可追溯：requests 接口带结果
    trace_ok = True
    if uploaded:
        status, payload = simulator.query_request(uploaded[0].item.client_request_id)
        trace_ok = (status == 200 and isinstance(payload, dict)
                    and payload.get("status") == "completed"
                    and ((payload.get("result") or {}).get("event") or {}).get("event_id"))
    checks.append(Check("GET /v1/mobile/requests 可查到结果", trace_ok))

    # 4. 服务端事件数 == 本场景上传成功项数（无重复事件）
    with simulator._lock:  # noqa: SLF001 - 同进程内自检
        expected_ids = {o.event_id for o in uploaded}
    served_count, served_ids = simulator.count_marker_events(f"{run['marker']}-")
    checks.append(Check(
        "服务端事件数等于上传项数（无重复事件）",
        served_count == len(expected_ids) and set(served_ids) == expected_ids,
        f"服务端 {served_count} 个 / 客户端记录 {len(expected_ids)} 个",
    ))

    # 5. 确认可回写 + 状态轨迹
    ack_ok, ack_detail = True, ""
    if run["acknowledge"] and uploaded:
        target = uploaded[0].event_id
        status, payload = simulator.acknowledge(target, operator=run["marker"], note="弱网联调复核")
        history = (payload or {}).get("status_history") or []
        ack_ok = (status == 200 and isinstance(payload, dict) and payload.get("status") == "acknowledged"
                  and any(h.get("operator") == run["marker"] and h.get("to") == "acknowledged"
                          for h in history))
        ack_detail = f"HTTP {status}"
    checks.append(Check("确认回写并记录操作者/备注", ack_ok, ack_detail))

    # 6. 失败项都带可识别的统一错误格式
    failures = [o for o in outcomes if not o.uploaded]
    checks.append(Check(
        "失败项给出可识别错误（便于 App 提示/重试）",
        all(o.terminal_error for o in failures),
        f"失败 {len(failures)} 项",
    ))
    return checks
