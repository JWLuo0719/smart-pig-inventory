"""研究模型 Runner：把 pig-farm-agent 的 DCR-SoftNMS ONNX 模型桥接到
smart-pig-inventory 推理契约（inference-job / inference-result schema）。

按外部 Runner 边界设计：本服务属于模型（科研）侧，独立部署在宿主机，
推理服务容器通过 YOLO_HTTP_ENDPOINT=http://host.docker.internal:<port> 调用。

行为口径（与研究 Provider 的治理语义一致）：
- single 视角：返回检测框与 count（供研究通道降级为复核证据使用）；
- left_center_right / video：不做跨图去重，count=None 且标注 warning，
  由产品侧的互斥分区/轨迹聚合能力负责，未标定即人工复核。

GET /ready  -> {"ready": true, model_key, model_version, model_checksum, adapter_version}
POST /count -> CountingJobResult

可选共享令牌：设置 RUNNER_API_TOKEN 后，/count 与 /ready 都要求携带匹配的
X-Runner-Service-Key 请求头（详见下方常量注释的默认关闭权衡）。
"""
from __future__ import annotations

from pathlib import Path
import hashlib
import hmac
import os
import re
import shutil
import sys
import tempfile
import time

import httpx
from fastapi import FastAPI, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from pig_farm_agent.detector import OnnxDetector, load_manifest  # noqa: E402

ARTIFACT_DIR = Path(
    os.getenv("RUNNER_ARTIFACT_DIR", PROJECT_ROOT / "model_artifacts" / "dcr-softnms-yolov13-v1")
)
MINIO_ENDPOINT = os.getenv("RUNNER_MINIO_ENDPOINT", "http://127.0.0.1:9000")
MINIO_USER = os.getenv("RUNNER_MINIO_USER", "")
MINIO_PASSWORD = os.getenv("RUNNER_MINIO_PASSWORD", "")
LISTEN_PORT = int(os.getenv("RUNNER_PORT", "9001"))

app = FastAPI(title="DCR research counting runner")
manifest = load_manifest(ARTIFACT_DIR)
detector = OnnxDetector(ARTIFACT_DIR, manifest)
MODEL_CHECKSUM = hashlib.sha256((ARTIFACT_DIR / "model.onnx").read_bytes()).hexdigest()
ADAPTER_VERSION = "research-runner-1"

# job_id 白名单：只允许字母数字与 _-（1~64 位）。job_id 会进入本地临时目录命名，
# 绝不能携带 ../ 等路径片段——否则 finally 的 shutil.rmtree 可能递删宿主目录。
JOB_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# 可选共享令牌（默认关闭）：设置 RUNNER_API_TOKEN 后，/count 与 /ready 必须携带
# 匹配的 X-Runner-Service-Key 请求头，否则返回契约形 401。默认关闭是刻意权衡：
# 现网 Runner 由推理服务经 YOLO_HTTP_ENDPOINT 直连，强制令牌会让既有部署直接断流；
# 内网研究环境先保持零配置可用，对外暴露前再配置令牌，并叠加 127.0.0.1 绑定、
# MinIO bucket 白名单一起收紧（检查报告 P1-4）。
RUNNER_TOKEN_ENV = "RUNNER_API_TOKEN"
RUNNER_KEY_HEADER = "X-Runner-Service-Key"


class Roi(BaseModel):
    x: float
    y: float
    width: float
    height: float


class Media(BaseModel):
    asset_id: str
    view_position: str
    object_uri: str
    sha256: str
    roi: Roi | None = None


class ModelIdentity(BaseModel):
    model_key: str
    version: str
    checksum: str
    adapter_version: str


class CountingJobRequest(BaseModel):
    job_id: str
    correlation_id: str
    organization_id: str
    capture_set_id: str
    capture_kind: str
    media: list[Media]
    requested_model: ModelIdentity


def fetch_object(object_uri: str, target: Path) -> None:
    """从 MinIO 拉取 s3://bucket/key 对象到本地临时文件（AWS V4 签名）。"""
    from minio import Minio

    bucket, key = object_uri[len("s3://"):].split("/", 1)
    parsed = httpx.URL(MINIO_ENDPOINT)
    client = Minio(
        f"{parsed.host}:{parsed.port}",
        access_key=MINIO_USER,
        secret_key=MINIO_PASSWORD,
        secure=parsed.scheme == "https",
    )
    client.fget_object(bucket, key, str(target))


def crop_by_roi(image_path: Path, roi: Roi, out_path: Path) -> None:
    from PIL import Image

    with Image.open(image_path) as img:
        w, h = img.size
        box = (
            max(0, int(roi.x * w)),
            max(0, int(roi.y * h)),
            min(w, int((roi.x + roi.width) * w)),
            min(h, int((roi.y + roi.height) * h)),
        )
        img.crop(box).save(out_path, "JPEG", quality=95)


def _failed_result(started: float, warnings: list[str], detections: list | None = None) -> dict:
    """契约形失败响应（status=failed）：交产品侧人工复核，本服务不抛 5xx。"""
    return {
        "status": "failed",
        "count": None,
        "detections": detections if detections is not None else [],
        "warnings": warnings,
        "model_key": detector.model_name,
        "model_version": detector.model_version,
        "model_checksum": MODEL_CHECKSUM,
        "adapter_version": ADAPTER_VERSION,
        "inference_source": "research-http-yolo",
        "latency_ms": round((time.perf_counter() - started) * 1000),
    }


def _service_key_ok(provided: str | None) -> bool:
    """X-Runner-Service-Key 校验：未配置 RUNNER_API_TOKEN 时保持开放（权衡见常量注释）。"""
    expected = os.getenv(RUNNER_TOKEN_ENV, "").strip()
    if not expected:
        return True
    return hmac.compare_digest(provided or "", expected)


def _runner_tmp_root() -> Path:
    """RUNNER_TMP 沙箱根：job-* 工作目录的生命周期只允许发生在它之下。"""
    return Path(os.getenv("RUNNER_TMP", "."))


def _assert_inside_tmp(path: Path, tmp_root: Path) -> Path:
    """断言 path resolve 后严格位于 tmp_root 之下，否则抛 ValueError（调用方拒绝）。

    mkdir 与 rmtree 两个时点都要先过这道断言：即使将来有人把客户端输入
    又拼回路径，越界删除也会在这里被挡住。
    """
    root = Path(tmp_root).resolve()
    resolved = Path(path).resolve()
    try:
        rel = resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"workdir escapes RUNNER_TMP: {resolved}") from exc
    if rel == Path("."):
        raise ValueError(f"workdir must be a strict subdirectory of RUNNER_TMP: {resolved}")
    return resolved


def _new_workdir() -> Path:
    """服务端生成独立临时目录（tempfile.mkdtemp 前缀 job-，客户端输入不参与命名）。

    mkdir 前断言沙箱落点、创建后复核目标路径，两次都要求 resolve 后位于
    RUNNER_TMP 之下，越界即拒绝（配合 _cleanup_workdir 的 rmtree 前断言）。
    """
    tmp_root = _runner_tmp_root().resolve()
    _assert_inside_tmp(tmp_root / "job-", tmp_root)  # mkdir 前断言
    tmp_root.mkdir(parents=True, exist_ok=True)
    workdir = Path(tempfile.mkdtemp(prefix="job-", dir=str(tmp_root)))
    return _assert_inside_tmp(workdir, tmp_root)  # 创建后复核


def _cleanup_workdir(workdir: Path | None) -> None:
    """rmtree 前断言 resolve 后位于 RUNNER_TMP 之下；越界则拒绝删除。"""
    if workdir is None:
        return
    try:
        _assert_inside_tmp(workdir, _runner_tmp_root())
    except ValueError:
        return  # 拒绝：绝不递删 RUNNER_TMP 之外的目录
    shutil.rmtree(workdir, ignore_errors=True)


@app.get("/ready")
@app.get("/health/ready")
def ready(x_runner_service_key: str | None = Header(default=None)):
    if not _service_key_ok(x_runner_service_key):
        return JSONResponse(
            status_code=401,
            content={"ready": False, "error": f"unauthorized: {RUNNER_KEY_HEADER} missing or invalid"},
        )
    return {
        "ready": True,
        "model_key": detector.model_name,
        "model_version": detector.model_version,
        "model_checksum": MODEL_CHECKSUM,
        "adapter_version": ADAPTER_VERSION,
    }


@app.post("/count")
def count(request: CountingJobRequest, x_runner_service_key: str | None = Header(default=None)):
    started = time.perf_counter()
    if not _service_key_ok(x_runner_service_key):
        # 契约形 401：body 保持 CountingJobResult 口径（status=failed），不抛 5xx
        return JSONResponse(status_code=401, content=_failed_result(started, ["runner error: unauthorized"]))
    if not JOB_ID_PATTERN.match(request.job_id or ""):
        # job_id 白名单校验：含 ../ 等路径片段的 ID 直接拒绝（穿越会让 rmtree 递删宿主目录）
        return _failed_result(started, ["runner error: invalid job_id (expect ^[A-Za-z0-9_-]{1,64}$)"])
    detections = []
    warnings = []
    workdir: Path | None = None
    try:
        workdir = _new_workdir()
        for i, media in enumerate(request.media):
            raw = workdir / f"{i}-raw"
            fetch_object(media.object_uri, raw)
            image_path = raw
            offset_x = offset_y = 0.0
            if media.roi is not None:
                cropped = workdir / f"{i}-roi.jpg"
                crop_by_roi(raw, media.roi, cropped)
                from PIL import Image

                with Image.open(raw) as img:
                    offset_x = media.roi.x * img.width
                    offset_y = media.roi.y * img.height
                image_path = cropped
            result = detector.predict(str(image_path), request_id=request.job_id, barn_id=None)
            # 契约要求归一化 xyxy（0~1）：按原图尺寸换算，ROI 裁剪偏移一并折算
            from PIL import Image

            with Image.open(raw) as img:
                full_w, full_h = img.size
            for box, score in zip(result.boxes, result.scores):
                # 贴边目标的框会略微超出画面（像素级取整/外扩），契约要求 0~1，
                # 这里夹紧而不是让产品侧整单失败关闭。
                x1, y1, x2, y2 = box
                clamped = [
                    min(max(x1 + offset_x, 0.0) / full_w, 1.0),
                    min(max(y1 + offset_y, 0.0) / full_h, 1.0),
                    min(max(x2 + offset_x, 0.0) / full_w, 1.0),
                    min(max(y2 + offset_y, 0.0) / full_h, 1.0),
                ]
                detections.append(
                    {
                        "asset_id": media.asset_id,
                        "bbox": [round(value, 6) for value in clamped],
                        "confidence": score,
                        "class_id": 0,
                        "track_id": None,
                        "frame_index": None,
                    }
                )
            if result.quality_status != "usable":
                warnings.append(f"{media.view_position}: image quality {result.quality_status}")
    except Exception as exc:  # 网络或解码失败：failed 交给产品侧复核
        return _failed_result(started, [f"runner error: {exc}"], detections)
    finally:
        _cleanup_workdir(workdir)

    multi_view = request.capture_kind != "single"
    if multi_view:
        warnings.append("research runner: cross-view dedup not calibrated; manual review required")
    return {
        "status": "review_required" if multi_view else "succeeded",
        "count": None if multi_view else len(detections),
        "detections": detections,
        "warnings": warnings,
        "model_key": detector.model_name,
        "model_version": detector.model_version,
        "model_checksum": MODEL_CHECKSUM,
        "adapter_version": ADAPTER_VERSION,
        "inference_source": "research-http-yolo",
        "latency_ms": round((time.perf_counter() - started) * 1000),
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=LISTEN_PORT)
