"""模拟上游业务后端的最小实现（按 App 4 步上传合同），用于自证弱网重放脚本。

它只服务一个目的：**在没有 Docker / Spring / 真机的情况下验证 `app_contract_sim`
本身是对的**——即故障注入确实发生了、幂等与续传语义确实被检查到了。它不是产品
代码，也不冒充 smart-pig-inventory 的真实后端（真实后端是 Spring + MySQL + MinIO）。

支持：create-package（幂等 + existingAssets）、get-package、put-blob（SHA-256 校验 +
同标识不同内容 409）、put-manifest（ROI/哈希校验）、commit（幂等返回同一 session/job）。
"无此路由"返回独立错误码 `NoRoute`，使契约探针能区分"路由缺失"与"资源缺失"。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

SHA256_PATTERN = re.compile(r"^[a-f0-9]{64}$")

STATE_LOCK = threading.RLock()
PACKAGES: dict[str, dict] = {}          # server package id -> record
BY_CLIENT_ID: dict[str, str] = {}       # client package id -> server package id
IDEMPOTENCY: dict[str, str] = {}        # idempotency key -> server package id


class UpstreamState:
    def __init__(self, break_resume: bool = False):
        self.break_resume = break_resume


def problem(status: int, title: str, detail: str = "", code: str = "") -> tuple[int, bytes, str]:
    body = {
        "type": "about:blank",
        "title": title,
        "status": status,
        "detail": detail,
        "code": code or title,
        "correlationId": uuid.uuid4().hex[:12],
    }
    return status, json.dumps(body, ensure_ascii=False).encode(), "application/problem+json"


def no_route(path: str) -> tuple[int, bytes, str]:
    """"无此路由"必须与"资源不存在"可区分，否则契约探针无法判定端点是否实现。"""
    return problem(404, "NoRoute", f"未知路径 {path}", "NoRoute")


def not_found(detail: str) -> tuple[int, bytes, str]:
    return problem(404, "NotFound", detail, "NotFound")


def make_handler(state: UpstreamState):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_args):
            pass

        # ---------- 工具 ----------

        def _send(self, status: int, payload: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _json(self, status: int, payload) -> None:
            self._send(status, json.dumps(payload, ensure_ascii=False).encode(),
                       "application/json")

        def _read(self) -> bytes:
            length = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(length) if length else b""

        def _authorized(self) -> bool:
            return (self.headers.get("Authorization") or "").startswith("Bearer ")

        def _idempotency_key(self) -> str | None:
            return self.headers.get("X-Idempotency-Key")

        def _reject_unauthorized(self) -> None:
            status, body, ctype = problem(401, "Unauthorized", "缺少 Bearer 令牌", "Unauthorized")
            self._send(status, body, ctype)

        # ---------- 路由 ----------

        def do_POST(self):
            path = urlparse(self.path).path
            if path == "/api/v1/auth/login":
                return self._json(200, {
                    "accessToken": "sim-token-" + uuid.uuid4().hex[:12],
                    "refreshToken": uuid.uuid4().hex * 2,
                    "tokenType": "Bearer",
                    "accessTokenExpiresAt": "2026-12-31T00:00:00+08:00",
                    "refreshTokenExpiresAt": "2027-01-31T00:00:00+08:00",
                })
            if not self._authorized():
                return self._reject_unauthorized()
            if path == "/api/v1/upload-packages":
                return self._create_package()
            match = re.match(r"^/api/v1/upload-packages/([\w-]+)/commit$", path)
            if match:
                return self._commit(match.group(1))
            status, body, ctype = no_route(path)
            return self._send(status, body, ctype)

        def do_PUT(self):
            path = urlparse(self.path).path
            if not self._authorized():
                return self._reject_unauthorized()
            blob = re.match(r"^/api/v1/upload-packages/([\w-]+)/blobs/([\w-]+)$", path)
            if blob:
                return self._put_blob(blob.group(1), blob.group(2))
            manifest = re.match(r"^/api/v1/upload-packages/([\w-]+)/manifest$", path)
            if manifest:
                return self._put_manifest(manifest.group(1))
            status, body, ctype = no_route(path)
            return self._send(status, body, ctype)

        def do_GET(self):
            path = urlparse(self.path).path
            if not self._authorized():
                return self._reject_unauthorized()
            match = re.match(r"^/api/v1/upload-packages/([\w-]+)$", path)
            if match:
                with STATE_LOCK:
                    record = PACKAGES.get(match.group(1))
                if record is None:
                    status, body, ctype = not_found("采集包不存在")
                    return self._send(status, body, ctype)
                return self._json(200, {
                    "id": record["id"],
                    "clientPackageId": record["clientPackageId"],
                    "state": record["state"],
                    # --break-resume 时故意不回报已存在的 blob，用来验证脚本能抓到重复上传
                    "existingAssets": ([] if state.break_resume
                                       else sorted(record["blobs"].keys())),
                })
            status, body, ctype = no_route(path)
            return self._send(status, body, ctype)

        # ---------- 合同实现 ----------

        def _create_package(self):
            key = self._idempotency_key()
            if not key:
                status, body, ctype = problem(422, "ValidationError",
                                              "缺少 X-Idempotency-Key", "ValidationError")
                return self._send(status, body, ctype)
            try:
                body = json.loads(self._read().decode("utf-8"))
            except Exception:
                status, payload, ctype = problem(422, "ValidationError",
                                                 "请求体不是 JSON", "ValidationError")
                return self._send(status, payload, ctype)
            for field in ("clientPackageId", "organizationId", "penId",
                          "businessDate", "captureKind"):
                if field not in body:
                    status, payload, ctype = problem(
                        422, "ValidationError", f"缺少字段 {field}", "ValidationError")
                    return self._send(status, payload, ctype)
            with STATE_LOCK:
                existing_id = BY_CLIENT_ID.get(body["clientPackageId"]) or IDEMPOTENCY.get(key)
                if existing_id and existing_id in PACKAGES:
                    record = PACKAGES[existing_id]
                    return self._json(200, {            # 重放：200 + existingAssets
                        "id": record["id"],
                        "clientPackageId": record["clientPackageId"],
                        "state": record["state"],
                        "existingAssets": sorted(record["blobs"].keys()),
                    })
                package_id = str(uuid.uuid4())
                PACKAGES[package_id] = {
                    "id": package_id,
                    "clientPackageId": body["clientPackageId"],
                    "state": "awaiting_blobs",
                    "blobs": {},
                    "manifest": None,
                    "commit": None,
                }
                BY_CLIENT_ID[body["clientPackageId"]] = package_id
                IDEMPOTENCY[key] = package_id
            return self._json(201, {                        # 新建：201
                "id": package_id,
                "clientPackageId": body["clientPackageId"],
                "state": "awaiting_blobs",
                "existingAssets": [],
            })

        def _put_blob(self, package_id: str, asset_id: str):
            digest_header = self.headers.get("X-Content-SHA256") or ""
            if not SHA256_PATTERN.match(digest_header):
                status, payload, ctype = problem(422, "ValidationError",
                                                 "X-Content-SHA256 格式非法", "ValidationError")
                return self._send(status, payload, ctype)
            data = self._read()
            actual = hashlib.sha256(data).hexdigest()
            if actual != digest_header:
                status, payload, ctype = problem(422, "ValidationError",
                                                 "内容与声明哈希不一致", "ValidationError")
                return self._send(status, payload, ctype)
            with STATE_LOCK:
                record = PACKAGES.get(package_id)
                if record is None:
                    status, payload, ctype = not_found("采集包不存在")
                    return self._send(status, payload, ctype)
                previous = record["blobs"].get(asset_id)
                if previous is not None and previous != actual:
                    # 同一标识、不同内容 → 409（组织范围精确重复拦截）
                    status, payload, ctype = problem(409, "Conflict",
                                                     "同一 assetId 内容不一致", "Conflict")
                    return self._send(status, payload, ctype)
                if previous == actual:
                    return self._json(200, {"assetId": asset_id, "state": "exists"})
                record["blobs"][asset_id] = actual
                if record["state"] == "awaiting_blobs":
                    record["state"] = "awaiting_manifest"
            return self._json(201, {"assetId": asset_id, "state": "stored"})

        def _put_manifest(self, package_id: str):
            try:
                manifest = json.loads(self._read().decode("utf-8"))
            except Exception:
                status, payload, ctype = problem(422, "ValidationError",
                                                 "清单不是 JSON", "ValidationError")
                return self._send(status, payload, ctype)
            assets = manifest.get("assets") or []
            if not assets:
                status, payload, ctype = problem(422, "ValidationError",
                                                 "清单缺少 assets", "ValidationError")
                return self._send(status, payload, ctype)
            with STATE_LOCK:
                record = PACKAGES.get(package_id)
                if record is None:
                    status, payload, ctype = not_found("采集包不存在")
                    return self._send(status, payload, ctype)
                for asset in assets:
                    roi = asset.get("roi")
                    if roi and (roi["x"] + roi["width"] > 1 or roi["y"] + roi["height"] > 1):
                        status, payload, ctype = problem(422, "ValidationError",
                                                         "ROI 越界", "ValidationError")
                        return self._send(status, payload, ctype)
                    if asset["assetId"] not in record["blobs"]:
                        status, payload, ctype = problem(
                            422, "ValidationError",
                            f"blob 未上传: {asset['assetId']}", "ValidationError")
                        return self._send(status, payload, ctype)
                    if record["blobs"][asset["assetId"]] != asset["sha256"]:
                        status, payload, ctype = problem(
                            422, "ValidationError", "清单哈希与已存 blob 不一致", "ValidationError")
                        return self._send(status, payload, ctype)
                if record["manifest"] is not None:
                    return self._json(200, {"state": record["state"]})   # 幂等重放
                record["manifest"] = manifest
                record["state"] = "ready_to_commit"
            return self._json(201, {"state": "ready_to_commit"})

        def _commit(self, package_id: str):
            key = self._idempotency_key()
            with STATE_LOCK:
                record = PACKAGES.get(package_id)
                if record is None:
                    status, payload, ctype = not_found("采集包不存在")
                    return self._send(status, payload, ctype)
                if record["manifest"] is None:
                    status, payload, ctype = problem(422, "ValidationError",
                                                     "清单未提交", "ValidationError")
                    return self._send(status, payload, ctype)
                if record["commit"] is not None:
                    return self._json(200, record["commit"])             # 重放：200 同一任务
                result = {
                    "packageId": package_id,
                    "sessionId": str(uuid.uuid4()),
                    "inferenceJobId": str(uuid.uuid4()),
                    "status": "submitted",
                }
                record["commit"] = result
                record["state"] = "committed"
                record["idempotencyKey"] = key
            return self._json(201, result)

    return Handler


def create_server(host: str = "127.0.0.1", port: int = 0,
                  break_resume: bool = False) -> tuple[ThreadingHTTPServer, UpstreamState]:
    state = UpstreamState(break_resume=break_resume)
    server = ThreadingHTTPServer((host, port), make_handler(state))
    return server, state


def main() -> None:
    parser = argparse.ArgumentParser(description="模拟上游业务后端（App 4 步上传合同）")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--break-resume", action="store_true",
                        help="故意忽略 existingAssets（用于验证 I3 能抓到重复上传）")
    args = parser.parse_args()
    server, _ = create_server(args.host, args.port, break_resume=args.break_resume)
    print(f"上游模拟服务已启动：http://{args.host}:{args.port}/api/v1 "
          f"(break_resume={args.break_resume})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
