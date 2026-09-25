"""零依赖 HTTP API（标准库实现，文档第 8 节）。

端点：
  GET  /                                 最小 Web 看板（单文件静态页）
  GET  /health                           服务、模型制品与存储状态
  POST /analyze                          JSON 元数据或 multipart 图片
  POST /v1/mobile/analyze                App multipart 上传（client_request_id 幂等）
  GET  /events?barn_id=&status=&date=    分页查询事件
  GET  /events/{event_id}                单事件详情（看板/App 用）
  GET  /v1/mobile/requests/{request_id}  App 查询任务状态与结果
  POST /events/{id}/ack|resolve|dismiss  人工确认 / 关闭 / 驳回
  GET  /report/daily?date=               日报 JSON
  GET  /report/daily.csv?date=           日报 CSV 导出
  GET  /files/{path}                     证据文件回放（仅 evidence/ 下的图片与指标 JSON）
  GET  /model/replay                     回放门槛摘要（模型升级门槛）

统一错误格式：{"error_code": "...", "message": "...", "request_id": "..."}。

写保护：设置 PIG_AGENT_API_TOKEN（或 config.agent.api_token）后，所有 POST
需要携带 `X-Api-Token` 头，否则返回 401 UNAUTHORIZED；读取接口保持开放，
便于局域网部署时在边缘主机上放行只读看板。
"""
from __future__ import annotations

from email.parser import BytesParser
from email.policy import default as email_default_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
import hmac
import json
import re
import sys
import threading
import time
import traceback
import uuid

from .agent import PigFarmAgent
from .config import AgentConfig, load_config
from .models import DomainError, EVENT_STATUSES

JSON_BODY_LIMIT = 1024 * 1024
LOG_LEVELS = {"DEBUG": 10, "INFO": 20, "WARNING": 30, "ERROR": 40}
INDEX_HTML = Path(__file__).resolve().parent / "static" / "index.html"


class ApiError(Exception):
    def __init__(self, status: int, error_code: str, message: str, request_id: str | None = None):
        super().__init__(message)
        self.status = status
        self.error_code = error_code
        self.message = message
        self.request_id = request_id


class StructLogger:
    def __init__(self, level: str = "INFO", stream=None):
        self.threshold = LOG_LEVELS.get(level.upper(), 20)
        self.stream = stream or sys.stdout

    def log(self, level: str, message: str, **fields) -> None:
        if LOG_LEVELS.get(level.upper(), 20) < self.threshold:
            return
        record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "level": level.upper(), "msg": message, **fields}
        self.stream.write(json.dumps(record, ensure_ascii=False) + "\n")
        self.stream.flush()

    def info(self, message: str, **fields) -> None:
        self.log("info", message, **fields)

    def error(self, message: str, **fields) -> None:
        self.log("error", message, **fields)


def parse_multipart(content_type: str, body: bytes) -> tuple[dict[str, str], tuple[str, bytes] | None]:
    """用标准库 email 解析 multipart/form-data，返回 (字段, (文件名, 数据))。"""
    try:
        raw = b"Content-Type: " + content_type.encode("latin-1") + b"\r\n\r\n" + body
        message = BytesParser(policy=email_default_policy).parsebytes(raw)
        parts = list(message.iter_parts())
    except Exception as exc:
        raise ApiError(400, "INVALID_MULTIPART", f"multipart 解析失败: {exc}") from exc
    if not parts:
        raise ApiError(400, "INVALID_MULTIPART", "multipart 请求不包含任何部分")

    fields: dict[str, str] = {}
    file_part: tuple[str, bytes] | None = None
    for part in parts:
        name = part.get_param("name", header="content-disposition")
        if name is None:
            continue
        payload = part.get_payload(decode=True) or b""
        filename = part.get_filename()
        if filename:
            file_part = (filename, payload)
        else:
            fields[str(name)] = payload.decode("utf-8", "replace").strip()
    return fields, file_part


CONTENT_TYPES = {
    ".json": "application/json",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}


def make_handler(agent: PigFarmAgent, logger: StructLogger):
    config: AgentConfig = agent.config

    class Handler(BaseHTTPRequestHandler):
        server_version = "pig-farm-agent/1.0"
        protocol_version = "HTTP/1.1"

        # ---------- 基础工具 ----------

        def send_json(self, payload, status: int = 200, request_id: str | None = None) -> None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            if request_id:
                self.send_header("X-Request-Id", request_id)
            self.end_headers()
            self.wfile.write(data)

        def send_error_json(self, status: int, error_code: str, message: str,
                            request_id: str | None = None) -> None:
            self.send_json({"error_code": error_code, "message": message, "request_id": request_id}, status, request_id)

        def send_bytes(self, data: bytes, content_type: str) -> None:
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def read_body(self, limit: int) -> bytes:
            length = int(self.headers.get("Content-Length") or 0)
            if length > limit:
                # 未消费的请求体会破坏 keep-alive 连接，直接关闭连接
                self.close_connection = True
                raise ApiError(413, "PAYLOAD_TOO_LARGE", f"请求体超过限制 {limit} 字节")
            return self.rfile.read(length) if length else b""

        def parse_json_body(self) -> dict:
            raw = self.read_body(max(JSON_BODY_LIMIT, config.upload_max_bytes))
            if not raw:
                return {}
            try:
                body = json.loads(raw.decode("utf-8"))
            except Exception as exc:
                raise ApiError(400, "INVALID_JSON", f"JSON 解析失败: {exc}") from exc
            if not isinstance(body, dict):
                raise ApiError(400, "INVALID_JSON", "请求体必须是 JSON 对象")
            return body

        def save_upload(self, filename: str, data: bytes, farm_id: str, barn_id: str,
                        request_id: str) -> Path:
            if len(data) > config.upload_max_bytes:
                raise ApiError(413, "PAYLOAD_TOO_LARGE", f"文件超过限制 {config.upload_max_bytes} 字节")
            suffix = Path(filename).suffix.lower()
            if suffix not in config.upload_extensions:
                raise ApiError(415, "UNSUPPORTED_MEDIA_TYPE",
                               f"不支持的文件类型 {suffix or '(无后缀)'}，允许: {', '.join(config.upload_extensions)}")
            inbox = config.data_dir / "inbox" / re.sub(r"[^\w.-]", "_", farm_id) / re.sub(r"[^\w.-]", "_", barn_id)
            inbox.mkdir(parents=True, exist_ok=True)
            target = inbox / f"{time.strftime('%Y%m%dT%H%M%S')}_{request_id}{suffix}"
            target.write_bytes(data)
            return target

        def safe_image_path(self, image_path: str | None, request_id: str) -> str | None:
            """image_path 越界拒绝：resolve 后必须严格位于 data_dir 之下。

            请求体里的 image_path 会进入检测与证据归档，若不限定落点，
            调用方可把宿主机任意可读文件拉进证据库（检查报告 S7）。
            """
            if not image_path:
                return None
            resolved = Path(image_path).resolve()
            try:
                rel = resolved.relative_to(config.data_dir.resolve())
            except ValueError:
                raise ApiError(400, "VALIDATION_ERROR",
                               f"image_path 越出 data_dir 范围: {image_path}", request_id)
            if rel == Path("."):
                raise ApiError(400, "VALIDATION_ERROR",
                               f"image_path 必须指向 data_dir 之下的文件: {image_path}", request_id)
            return str(resolved)

        # ---------- 路由 ----------

        def do_GET(self):
            self._dispatch("GET")

        def do_POST(self):
            self._dispatch("POST")

        def _dispatch(self, method: str) -> None:
            started = time.perf_counter()
            parsed = urlparse(self.path)
            path = unquote(parsed.path)
            query = parse_qs(parsed.query)
            request_id = self.headers.get("X-Request-Id") or f"req-{uuid.uuid4().hex[:12]}"
            status = 500
            try:
                if method == "POST":
                    self._require_token(request_id)
                handler = self._route(method, path)
                if handler is None:
                    raise ApiError(404, "NOT_FOUND", f"路径不存在: {method} {path}")
                handler(request_id, query)
                status = 200
            except ApiError as exc:
                status = exc.status
                self.send_error_json(exc.status, exc.error_code, exc.message, exc.request_id or request_id)
            except DomainError as exc:
                status = exc.http_status
                self.send_error_json(exc.http_status, exc.error_code, exc.message, request_id)
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception as exc:
                status = 500
                logger.error("unhandled_exception", error=str(exc), path=path,
                             traceback=traceback.format_exc())
                try:
                    self.send_error_json(500, "INTERNAL_ERROR", "服务内部错误", request_id)
                except Exception:
                    pass
            finally:
                logger.info(
                    "access", method=method, path=path, status=status,
                    request_id=request_id,
                    duration_ms=round((time.perf_counter() - started) * 1000, 1),
                )

        def _require_token(self, request_id: str) -> None:
            """写操作令牌校验（未配置令牌时保持开放，兼容单机/内网默认部署）。

            通过 agent.config 读取令牌，便于运行期调整或测试注入。
            """
            active = agent.config
            if not active.writes_protected:
                return
            provided = self.headers.get("X-Api-Token") or ""
            if not hmac.compare_digest(provided, str(active.api_token)):
                raise ApiError(401, "UNAUTHORIZED",
                               "写操作需要有效的 X-Api-Token（见 PIG_AGENT_API_TOKEN）",
                               request_id)

        def _route(self, method: str, path: str):
            routes: list[tuple[str, object]] = []
            if method == "GET":
                routes = [
                    (r"^/$", self._get_index),
                    (r"^/health$", self._get_health),
                    (r"^/events$", self._get_events),
                    (r"^/events/([\w.:@-]+)$", self._get_event),
                    (r"^/report/daily$", self._get_report_daily),
                    (r"^/report/daily\.csv$", self._get_report_csv),
                    (r"^/model/replay$", self._get_model_replay),
                    (r"^/v1/mobile/requests/([\w.:@-]+)$", self._get_mobile_request),
                    (r"^/files/([\w./-]+)$", self._get_file),
                ]
            else:
                routes = [
                    (r"^/analyze$", self._post_analyze),
                    (r"^/v1/mobile/analyze$", self._post_analyze),
                    (r"^/events/([\w.:@-]+)/(ack|resolve|dismiss)$", self._post_event_action),
                ]
            for pattern, handler in routes:
                match = re.match(pattern, path)
                if match:
                    return lambda rid, q, h=handler, m=match: h(rid, q, *m.groups())
            return None

        # ---------- GET 处理 ----------

        def _get_index(self, request_id: str, query: dict) -> None:
            """最小 Web 看板（单文件、零依赖）。"""
            if not INDEX_HTML.exists():
                raise ApiError(404, "NOT_FOUND", "看板页面缺失", request_id)
            self.send_bytes(INDEX_HTML.read_bytes(), "text/html; charset=utf-8")

        def _get_health(self, request_id: str, query: dict) -> None:
            self.send_json(agent.health(), 200, request_id)

        def _get_events(self, request_id: str, query: dict) -> None:
            barn_id = (query.get("barn_id") or [None])[0]
            status = (query.get("status") or [None])[0]
            if status is not None and status not in EVENT_STATUSES:
                raise ApiError(400, "VALIDATION_ERROR",
                               f"status 非法，允许值: {', '.join(EVENT_STATUSES)}", request_id)
            date = (query.get("date") or [None])[0]
            if date is not None and not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
                raise ApiError(400, "VALIDATION_ERROR", "date 必须是 YYYY-MM-DD", request_id)
            try:
                limit = min(200, max(1, int((query.get("limit") or ["50"])[0])))
                offset = max(0, int((query.get("offset") or ["0"])[0]))
            except ValueError:
                raise ApiError(400, "VALIDATION_ERROR", "limit/offset 必须是整数", request_id)
            events, total = agent.list_events(
                barn_id=barn_id, status=status, date=date, limit=limit, offset=offset
            )
            self.send_json({"events": events, "total": total, "limit": limit, "offset": offset}, 200, request_id)

        def _get_event(self, request_id: str, query: dict, event_id: str) -> None:
            self.send_json(agent.get_event(event_id), 200, request_id)

        def _get_mobile_request(self, request_id: str, query: dict, target_request_id: str) -> None:
            stored = agent.get_request(target_request_id)
            if stored is None:
                raise ApiError(404, "REQUEST_NOT_FOUND", f"请求不存在: {target_request_id}", request_id)
            self.send_json(
                {
                    "request_id": target_request_id,
                    "status": "completed",
                    "created_at": stored["created_at"],
                    "result": stored["response"],
                },
                200,
                request_id,
            )

        def _get_report_daily(self, request_id: str, query: dict) -> None:
            date = (query.get("date") or [None])[0]
            self.send_json(agent.daily_report(date), 200, request_id)

        def _get_report_csv(self, request_id: str, query: dict) -> None:
            date = (query.get("date") or [None])[0]
            data = agent.daily_report_csv(date).encode("utf-8-sig")
            self.send_response(200)
            self.send_header("Content-Type", "text/csv; charset=utf-8")
            self.send_header("Content-Disposition", 'attachment; filename="daily_report.csv"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _get_model_replay(self, request_id: str, query: dict) -> None:
            """回放门槛摘要：模型升级前必须通过的固定图片集对比（文档第 10 节）。"""
            self.send_json(agent.replay_summary(), 200, request_id)

        def _get_file(self, request_id: str, query: dict, rel: str) -> None:
            """回放事件 evidence 块中的相对路径（如 evidence/evt-x.json）。"""
            path = agent.evidence_store.resolve(rel)
            if path is None:
                raise ApiError(404, "EVIDENCE_NOT_FOUND", f"证据文件不存在: {rel}", request_id)
            self.send_bytes(
                path.read_bytes(),
                CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream"),
            )

        # ---------- POST 处理 ----------

        def _post_analyze(self, request_id: str, query: dict) -> None:
            content_type = (self.headers.get("Content-Type") or "").lower()
            if content_type.startswith("multipart/"):
                fields, file_part = parse_multipart(
                    self.headers.get("Content-Type"),
                    self.read_body(config.upload_max_bytes + 64 * 1024),
                )
                image_path = None
                if file_part is not None:
                    filename, data = file_part
                    barn = re.sub(r"[^\w.-]", "_", fields.get("barn_id", "A01"))
                    farm = re.sub(r"[^\w.-]", "_", fields.get("farm_id", "demo"))
                    image_path = self.save_upload(filename, data, farm, barn, request_id)
                payload = {
                    "request_id": fields.get("client_request_id") or fields.get("request_id") or request_id,
                    "farm_id": fields.get("farm_id", "demo"),
                    "barn_id": fields.get("barn_id", "A01"),
                    "captured_at": fields.get("captured_at"),
                    "source": fields.get("source", "upload"),
                    "image_path": self.safe_image_path(
                        str(image_path) if image_path else fields.get("image_path"), request_id
                    ),
                }
            else:
                body = self.parse_json_body()
                payload = {
                    "request_id": body.get("client_request_id") or body.get("request_id") or request_id,
                    "farm_id": body.get("farm_id", "demo"),
                    "barn_id": body.get("barn_id", body.get("barn", "A01")),
                    "captured_at": body.get("captured_at"),
                    "source": body.get("source", "upload"),
                    "image_path": self.safe_image_path(body.get("image_path"), request_id),
                }
            result = agent.analyze(payload)
            self.send_json(result, 200, request_id)

        def _post_event_action(self, request_id: str, query: dict, event_id: str, action: str) -> None:
            body = self.parse_json_body()
            operator = str(body.get("operator") or body.get("operator_id") or "human")
            note = body.get("note")
            to_status = {"ack": "acknowledged", "resolve": "resolved", "dismiss": "dismissed"}[action]
            event = agent.transition(event_id, to_status, operator=operator, note=note)
            self.send_json(event, 200, request_id)

        def log_message(self, *_args) -> None:  # 关闭默认 stderr 访问日志，改用结构化日志
            pass

    return Handler


def create_server(agent: PigFarmAgent | None = None, host: str | None = None, port: int | None = None):
    agent = agent or PigFarmAgent()
    host = host or agent.config.host
    port = port or agent.config.port
    logger = StructLogger(agent.config.log_level)
    handler = make_handler(agent, logger)
    return ThreadingHTTPServer((host, port), handler), agent, logger


def main() -> None:
    config = load_config()
    agent = PigFarmAgent(config)
    server, _, logger = create_server(agent)
    poller = None
    if config.polling_enabled:
        from .poller import build_poller

        poller = build_poller(config, agent, logger)
        threading.Thread(target=poller.run_forever, daemon=True, name="dir-poller").start()
    logger.info(
        "server_started",
        host=agent.config.host,
        port=agent.config.port,
        model_mode=agent.config.model_mode,
        data_dir=str(agent.config.data_dir),
        polling_enabled=config.polling_enabled,
        polling_watch_dir=str(config.polling_watch_dir) if poller else None,
        writes_protected=config.writes_protected,
        health_status=agent.health()["status"],
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("server_stopped")
    finally:
        if poller is not None:
            poller.stop()
        server.server_close()
        agent.close()


if __name__ == "__main__":
    main()
