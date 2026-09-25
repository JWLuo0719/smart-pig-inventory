"""端到端冒烟测试：对已启动的服务跑完整业务闭环（上传 -> 事件 -> 证据 -> 确认 -> 日报）。

用法：
  python tools/smoke_server.py --base http://127.0.0.1:8787

覆盖 V1 验收相关链路：/health、看板页、multipart 上传与幂等、事件查询、证据回放、
状态机 ack/resolve、日报 JSON/CSV、模型升级门槛摘要，以及（可选）目录轮询导入。
任一步失败即以非 0 退出，便于手工验收与 CI。
"""
from __future__ import annotations

import argparse
import io
import json
import sys
import urllib.error
import urllib.request
import uuid

CHECKS: list[str] = []


def call(method: str, url: str, data: bytes | None = None, headers: dict | None = None):
    request = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), dict(exc.headers)


def check(name: str, condition: bool, detail: str = "") -> None:
    CHECKS.append(name)
    mark = "PASS" if condition else "FAIL"
    print(f"[{mark}] {name}{(' — ' + detail) if detail else ''}")
    if not condition:
        raise SystemExit(f"冒烟测试失败: {name} {detail}")


def jpeg_bytes() -> bytes:
    try:
        from PIL import Image

        buffer = io.BytesIO()
        Image.new("RGB", (420, 300), (128, 120, 110)).save(buffer, format="JPEG")
        return buffer.getvalue()
    except ImportError:
        return b"\xff\xd8\xff\xe0" + b"0" * 512 + b"\xff\xd9"


def multipart(fields: dict[str, str], filename: str, payload: bytes) -> tuple[bytes, str]:
    boundary = "----pigagent" + uuid.uuid4().hex[:12]
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="猪场 Agent 端到端冒烟测试")
    parser.add_argument("--base", default="http://127.0.0.1:8787")
    parser.add_argument("--barn", default="A01")
    parser.add_argument("--token", default=None, help="服务启用 PIG_AGENT_API_TOKEN 时提供")
    args = parser.parse_args(argv)
    base = args.base.rstrip("/")
    auth = {"X-Api-Token": args.token} if args.token else {}
    post_json = {**auth, "Content-Type": "application/json"}

    # 1. 健康检查与看板页
    status, body, _ = call("GET", f"{base}/health")
    health = json.loads(body)
    check("GET /health 可用", status == 200 and health["status"] == "ok", health.get("status", ""))
    check("健康检查报告存储状态", health["storage"]["ok"] is True)

    status, body, headers = call("GET", f"{base}/")
    check("GET / 返回看板单页", status == 200 and "text/html" in headers.get("Content-Type", ""))
    check("看板页包含上传/日报入口",
          all(k in body.decode("utf-8") for k in ("事件流", "日报", "上传分析")))

    # 2. multipart 上传 + 幂等
    request_id = f"smoke-{uuid.uuid4().hex[:8]}"
    payload, content_type = multipart(
        {
            "farm_id": "farm-smoke",
            "barn_id": args.barn,
            "client_request_id": request_id,
            "captured_at": "2026-09-16T08:30:00+08:00",
        },
        "smoke.jpg",
        jpeg_bytes(),
    )
    status, body, _ = call("POST", f"{base}/v1/mobile/analyze", data=payload,
                           headers={**auth, "Content-Type": content_type})
    check("multipart 上传成功", status == 200, f"HTTP {status}")
    first = json.loads(body)
    event = first["event"]
    for key in ("event_id", "state", "risk", "evidence", "suggested_actions", "model"):
        check(f"事件契约字段 {key}", key in event)
    check("上传被幂等记录", first["event"]["request_id"] == request_id)

    status, body, _ = call("POST", f"{base}/v1/mobile/analyze", data=payload,
                           headers={**auth, "Content-Type": content_type})
    check("同 client_request_id 重试返回同一事件",
          json.loads(body)["event"]["event_id"] == event["event_id"])

    # 3. App 查询接口
    status, body, _ = call("GET", f"{base}/v1/mobile/requests/{request_id}")
    check("App 查询请求结果", status == 200 and json.loads(body)["status"] == "completed")

    # 4. 事件列表与单事件
    status, body, _ = call("GET", f"{base}/events?barn_id={args.barn}&limit=5")
    listed = json.loads(body)
    check("事件列表可用", status == 200 and listed["total"] >= 1)
    event_id = event["event_id"]
    status, body, _ = call("GET", f"{base}/events/{event_id}")
    detail = json.loads(body)
    check("单事件详情可用", status == 200 and detail["event_id"] == event_id)
    check("事件带状态轨迹", isinstance(detail.get("status_history"), list) and detail["status_history"])

    # 5. 证据回放（标注图与指标 JSON）
    evidence = detail["evidence"]
    metrics_rel = evidence.get("metrics")
    status, body, headers = call("GET", f"{base}/files/{metrics_rel}")
    check("证据指标 JSON 可回放",
          status == 200 and "application/json" in headers.get("Content-Type", "") and body.strip())
    annotated = evidence.get("annotated") or evidence.get("image")
    status, body, headers = call("GET", f"{base}/files/{annotated}")
    check("证据图可回放", status == 200 and len(body) > 100,
          f"{annotated} {len(body)} bytes")
    status, _, _ = call("GET", f"{base}/files/../../agent.db")
    check("证据路径穿越被拒绝", status in (400, 404))

    # 6. 状态机 ack -> resolve
    status, body, _ = call("POST", f"{base}/events/{event_id}/ack",
                           json.dumps({"operator": "smoke", "note": "冒烟确认"}).encode(), post_json)
    acked = json.loads(body)
    check("ack 转换成功", status == 200 and acked["status"] == "acknowledged")
    check("ack 记录操作者与备注",
          any(h["to"] == "acknowledged" and h["operator"] == "smoke" for h in acked["status_history"]))
    status, body, _ = call("POST", f"{base}/events/{event_id}/resolve", b"{}", post_json)
    check("resolve 转换成功", status == 200 and json.loads(body)["status"] == "resolved")
    status, body, _ = call("POST", f"{base}/events/{event_id}/ack", b"{}", post_json)
    check("已关闭事件拒绝重复确认", status == 409 and json.loads(body)["error_code"] == "INVALID_TRANSITION")

    # 7. 统一错误格式
    status, body, _ = call("POST", f"{base}/analyze", b"{oops", post_json)
    error = json.loads(body)
    check("非法 JSON 返回统一错误格式", status == 400 and set(error) == {"error_code", "message", "request_id"})
    if args.token:
        status, body, _ = call("POST", f"{base}/analyze", b"{}", {"Content-Type": "application/json"})
        check("启用写保护后无令牌写操作被拒绝",
              status == 401 and json.loads(body)["error_code"] == "UNAUTHORIZED")

    # 8. 日报与 CSV
    status, body, _ = call("GET", f"{base}/report/daily")
    report = json.loads(body)
    check("日报 JSON 可用", status == 200 and report["summary"]["events"] >= 1)
    check("日报含栏舍汇总与事件明细",
          isinstance(report["barns"], list) and isinstance(report["event_ids"], list) and report["event_ids"])
    check("日报事件可追溯到事件表", event_id in report["event_ids"])
    status, body, headers = call("GET", f"{base}/report/daily.csv")
    text = body.decode("utf-8-sig")
    check("日报 CSV 导出可用",
          status == 200 and text.startswith("event_id,request_id,farm_id") and event_id in text)

    # 9. 模型升级门槛摘要（看板"日报"页展示）
    status, body, _ = call("GET", f"{base}/model/replay")
    gate = json.loads(body)
    check("回放门槛摘要可用", status == 200 and gate.get("available") is True, gate.get("hint", ""))
    check("回放夹具覆盖高风险与质量通路",
          "DENSITY_HIGH" in (gate.get("risk_codes") or {})
          and "DATA_QUALITY_LOW" in (gate.get("risk_codes") or {}))

    print(f"\n冒烟测试全部通过（{len(CHECKS)} 项检查）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
