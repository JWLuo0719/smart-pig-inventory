"""Detector 协议、制品校验与适配器。

DetectionResult 契约（文档 4.2）：必须携带原图尺寸、推理耗时、候选数、
保留数、模型版本与质量状态。模型文件缺失、manifest 校验失败时抛出
ModelArtifactError，禁止静默回退到原始 score。
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import hashlib
import json
import random
import time

from .config import AgentConfig
from .models import ModelUnavailable


class ModelArtifactError(RuntimeError):
    pass


@dataclass
class DetectionResult:
    boxes: list[list[float]]
    scores: list[float]
    labels: list[int]
    image_width: int
    image_height: int
    model_name: str
    model_version: str
    inference_ms: float = 0.0
    candidate_count: int = 0
    quality_status: str = "usable"
    coverage: float | None = None
    postprocess: str = "none"
    score_mode: str | None = None

    @property
    def kept_count(self) -> int:
        return len(self.boxes)


class Detector:  # Protocol-style base；测试可注入脚本化实现
    model_name: str = ""
    model_version: str = ""

    def predict(self, image, *, request_id: str, barn_id: str | None = None) -> DetectionResult:
        raise NotImplementedError


def load_manifest(directory: str | Path) -> dict:
    """校验制品目录并返回 manifest；缺失、字段不全或 sha256 不符则 fail-closed。"""
    root = Path(directory)
    manifest_path = root / "manifest.json"
    if not manifest_path.exists():
        raise ModelArtifactError(f"manifest 缺失: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as exc:
        raise ModelArtifactError(f"manifest 不是合法 JSON: {manifest_path}: {exc}") from exc
    for name in ("model_name", "model_version"):
        if name not in manifest:
            raise ModelArtifactError(f"manifest 字段缺失: {name}")
    for item in manifest.get("files", []):
        path = root / item["path"]
        if not path.exists():
            raise ModelArtifactError(f"制品文件缺失: {path}")
        if item.get("sha256"):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != item["sha256"]:
                raise ModelArtifactError(f"制品校验和不匹配: {path}")
    return manifest


def file_signature(path: Path, *, probe_bytes: int = 65536) -> str:
    """图片的稳定指纹：文件名 + 字节数 + 前 64KB 摘要。

    不包含完整路径，因此同一张图片在任何机器、任何数据目录下都得到相同结果
    （回放基线与升级门槛依赖这一性质）；同时随内容变化，便于构造覆盖不同
    质量/密度通路的联调夹具。
    """
    target = Path(path)
    try:
        size = target.stat().st_size
        with target.open("rb") as handle:
            head = handle.read(probe_bytes)
    except OSError:
        return f"{target.name}|missing"
    digest = hashlib.sha256(head).hexdigest()[:12]
    return f"{target.name}|{size}|{digest}"


class MockDetector(Detector):
    """联调用检测器。

    以 request_id、栏舍与图片指纹（文件名 + 字节数 + 内容摘要，见
    `file_signature`）为种子做确定性抽样：结果不随数据目录或机器变化，保证
    App 幂等重试一致、回放基线可迁移、测试可复现；约 12% 的请求产生低质量
    输入，用于验证 DATA_QUALITY_LOW 通路。
    """

    def __init__(self, model_name: str = "DCR-SoftNMS-YOLOv13", model_version: str = "mock-v1"):
        self.model_name = model_name
        self.model_version = model_version

    def predict(self, image, *, request_id: str, barn_id: str | None = None) -> DetectionResult:
        signature = file_signature(Path(str(image))) if image else "none"
        rng = random.Random(f"{request_id}|{barn_id or ''}|{signature}")
        count = rng.randint(18, 44)
        roll = rng.random()
        coverage: float
        if roll < 0.07:
            quality_status, coverage = "blurry", round(rng.uniform(0.45, 0.75), 3)
        elif roll < 0.12:
            quality_status, coverage = "usable", round(rng.uniform(0.60, 0.79), 3)
        else:
            quality_status, coverage = "usable", round(rng.uniform(0.86, 0.99), 3)

        boxes, scores = [], []
        for i in range(count):
            col, row = i % 8, i // 8
            x1 = 20 + col * 74 + rng.randint(-6, 6)
            y1 = 30 + row * 52 + rng.randint(-5, 5)
            boxes.append([float(x1), float(y1), float(x1 + rng.randint(46, 60)), float(y1 + rng.randint(34, 46))])
            scores.append(round(rng.uniform(0.35, 0.92), 3))

        return DetectionResult(
            boxes=boxes,
            scores=scores,
            labels=[0] * count,
            image_width=640,
            image_height=480,
            model_name=self.model_name,
            model_version=self.model_version,
            inference_ms=round(rng.uniform(40, 220), 1),
            candidate_count=count + rng.randint(2, 8),
            quality_status=quality_status,
            coverage=coverage,
            postprocess="mock",
        )


def _linear_soft_nms_numpy(
    boxes: list[list[float]],
    scores: list[float],
    *,
    iou_thres: float,
    score_floor: float,
    max_det: int,
) -> tuple[list[int], list[float]]:
    """线性 Soft-NMS（numpy 实现，口径来自制品 manifest / rescorer.json）。"""
    import numpy as np

    if not boxes:
        return [], []
    arr = np.asarray(boxes, dtype=np.float64)
    sc = np.asarray(scores, dtype=np.float64).copy()
    tl = np.maximum(arr[:, None, :2], arr[None, :, :2])
    br = np.minimum(arr[:, None, 2:], arr[None, :, 2:])
    wh = np.clip(br - tl, 0.0, None)
    inter = wh[:, :, 0] * wh[:, :, 1]
    area = (arr[:, 2] - arr[:, 0]).clip(0.0) * (arr[:, 3] - arr[:, 1]).clip(0.0)
    union = (area[:, None] + area[None, :] - inter).clip(min=1e-9)
    iou = inter / union

    alive = sc >= score_floor
    keep: list[int] = []
    kept_scores: list[float] = []
    while len(keep) < max_det:
        candidates = np.flatnonzero(alive)
        if candidates.size == 0:
            break
        best = candidates[np.argmax(sc[candidates])]
        keep.append(int(best))
        kept_scores.append(float(sc[best]))
        alive[best] = False
        decay = 1.0 - iou[best]
        sc = np.where((iou[best] > iou_thres) & alive, sc * decay, sc)
        alive &= sc >= score_floor
    return keep, kept_scores


def _rescorer_soft_nms_params(model_dir: Path) -> dict:
    path = Path(model_dir) / "rescorer.json"
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8-sig")).get("soft_nms", {})
        except json.JSONDecodeError:
            pass
    return {}


def _letterbox(image_path: Path, size: int):
    """ultralytics 口径的 letterbox 预处理：等比缩放居中填充到 size×size。"""
    import numpy as np
    from PIL import Image

    with Image.open(image_path) as img:
        rgb = img.convert("RGB")
        orig_w, orig_h = rgb.size
        scale = min(size / orig_w, size / orig_h)
        new_w, new_h = round(orig_w * scale), round(orig_h * scale)
        resized = rgb.resize((new_w, new_h), Image.BILINEAR)
        canvas = Image.new("RGB", (size, size), (114, 114, 114))
        pad_x, pad_y = (size - new_w) // 2, (size - new_h) // 2
        canvas.paste(resized, (pad_x, pad_y))
        array = np.asarray(canvas, dtype=np.float32) / 255.0
    return array.transpose(2, 0, 1)[None], scale, pad_x, pad_y, orig_w, orig_h


def decode_onnx_output(
    output,
    *,
    scale: float,
    pad_x: float,
    pad_y: float,
    conf_thres: float,
):
    """把 [1, 5, N] 的单类检测输出还原为原图坐标的 xyxy 框与分数。

    纯 numpy 实现，独立成函数便于单元测试；坐标换算与导出时的
    letterbox 参数（等比 scale、居中 pad）严格对应。
    """
    import numpy as np

    preds = np.asarray(output[0]).transpose(1, 0)  # (N, 5): cx, cy, w, h, score
    mask = preds[:, 4] >= conf_thres
    preds = preds[mask]
    if preds.size == 0:
        return [], []
    cx, cy, w, h = preds[:, 0], preds[:, 1], preds[:, 2], preds[:, 3]
    x1 = (cx - w / 2 - pad_x) / scale
    y1 = (cy - h / 2 - pad_y) / scale
    x2 = (cx + w / 2 - pad_x) / scale
    y2 = (cy + h / 2 - pad_y) / scale
    boxes = np.stack([x1, y1, x2, y2], axis=1).round(1).tolist()
    scores = [round(float(s), 4) for s in preds[:, 4]]
    return boxes, scores


class OnnxDetector(Detector):
    """ONNX 制品推理：运行时只依赖 onnxruntime，不需要科研分叉代码。

    这是技术文档 4.1 节的推荐部署形态；后处理在产品侧执行冻结口径
    的线性 Soft-NMS（参数来自制品 manifest / rescorer.json）。
    """

    def __init__(self, model_dir: str | Path, manifest: dict, conf_thres: float = 0.25):
        try:
            import onnxruntime as ort
        except ImportError as exc:
            raise ModelArtifactError("ONNX 模式需要安装 onnxruntime") from exc
        self.model_dir = Path(model_dir)
        self.manifest = manifest
        self.conf_thres = float(conf_thres)
        self.model_name = str(manifest["model_name"])
        self.model_version = str(manifest["model_version"])
        onnx_path = self.model_dir / "model.onnx"
        if not onnx_path.exists():
            raise ModelArtifactError(f"ONNX 制品缺失: {onnx_path}")
        self.session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
        input_shape = self.session.get_inputs()[0].shape  # [1, 3, size, size]
        self.input_size = int(input_shape[-1]) if len(input_shape) == 4 and isinstance(input_shape[-1], int) else 640

        soft_nms = _rescorer_soft_nms_params(self.model_dir)
        self.iou_thres = float(soft_nms.get("iou_thres", 0.4))
        self.score_floor = float(soft_nms.get("score_floor", 0.001))
        self.max_det = int(soft_nms.get("max_det", 300))
        self.score_mode = str(manifest.get("score_mode", ""))

    def predict(self, image, *, request_id: str, barn_id: str | None = None) -> DetectionResult:
        if not image:
            raise ModelArtifactError("ONNX 模式必须提供图片路径")
        import numpy as np

        path = Path(image)
        started = time.perf_counter()
        tensor, scale, pad_x, pad_y, orig_w, orig_h = _letterbox(path, self.input_size)
        output = self.session.run(None, {self.session.get_inputs()[0].name: tensor})
        boxes, scores = decode_onnx_output(
            output[0], scale=scale, pad_x=pad_x, pad_y=pad_y, conf_thres=self.conf_thres
        )
        keep, kept_scores = _linear_soft_nms_numpy(
            boxes, scores, iou_thres=self.iou_thres, score_floor=self.score_floor, max_det=self.max_det
        )
        # Soft-NMS 标准口径：重叠候选被线性衰减后，仍需回到置信度阈值之上才保留；
        # 否则同一目标的重复框会以极低分数留在结果里，导致计数虚高。
        kept = [(i, s) for i, s in zip(keep, kept_scores) if s >= self.conf_thres]
        keep = [i for i, _ in kept]
        kept_scores = [s for _, s in kept]
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        return DetectionResult(
            boxes=[boxes[i] for i in keep],
            scores=kept_scores,
            labels=[0] * len(keep),
            image_width=orig_w,
            image_height=orig_h,
            model_name=self.model_name,
            model_version=self.model_version,
            inference_ms=round(elapsed_ms, 1),
            candidate_count=len(boxes),
            quality_status=_probe_image_quality(path),
            coverage=None,
            postprocess="onnx+linear-softnms",
            score_mode=self.score_mode,
        )


def _probe_image_quality(path: Path) -> str:
    """用 PIL 做轻量质量探测：灰度标准差过低判为模糊，极端亮度判为 degraded。"""
    try:
        from PIL import Image
    except ImportError:
        return "usable"
    import numpy as np

    try:
        with Image.open(path) as img:
            gray = np.asarray(img.convert("L"), dtype=np.float32)
    except Exception:
        return "unreadable"
    std, mean = float(gray.std()), float(gray.mean())
    if std < 18.0:
        return "blurry"
    if mean < 35.0 or mean > 225.0:
        return "degraded"
    return "usable"


class UltralyticsDetector(Detector):
    """真实模式适配器：manifest 校验 -> ultralytics 推理 -> 线性 Soft-NMS。

    说明：DCR 的 correctness rescorer 依赖科研侧关系模型输出（21 维候选
    特征中的 p_duplicate / p_neighbor / p_background_conflict），该制品尚未
    随制品目录导出，因此产品侧如实标注 postprocess="softnms-only"，事件
    model 块中记录 manifest 声明的 score_mode 供追溯；不做静默冒充。
    """

    def __init__(self, model_dir: str | Path, manifest: dict, weights: str | Path | None = None):
        try:
            from ultralytics import YOLO
        except ImportError as exc:
            raise ModelArtifactError("真实模式需要安装 ultralytics") from exc
        self.manifest = manifest
        self.model_dir = Path(model_dir)
        self.weights_path = Path(weights) if weights else self._resolve_weights()
        self.model = YOLO(str(self.weights_path))
        self.model_name = str(manifest["model_name"])
        self.model_version = str(manifest["model_version"])

        soft_nms = _rescorer_soft_nms_params(self.model_dir)
        self.iou_thres = float(soft_nms.get("iou_thres", 0.4))
        self.score_floor = float(soft_nms.get("score_floor", 0.001))
        self.max_det = int(soft_nms.get("max_det", 300))
        self.score_mode = str(manifest.get("score_mode", ""))

    def _resolve_weights(self) -> Path:
        for item in self.manifest.get("files", []):
            if item["path"].endswith(".pt"):
                return self.model_dir / item["path"]
        raise ModelArtifactError("manifest 中未声明 .pt 权重文件")

    def predict(self, image, *, request_id: str, barn_id: str | None = None) -> DetectionResult:
        if not image:
            raise ModelArtifactError("真实模式必须提供图片路径")
        started = time.perf_counter()
        results = self.model.predict(source=str(image), verbose=False)
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        if not results:
            return DetectionResult([], [], [], 0, 0, self.model_name, self.model_version,
                                   elapsed_ms, 0, "empty", None, "softnms-only", self.score_mode)
        result = results[0]
        boxes_obj = result.boxes
        xyxy = boxes_obj.xyxy.cpu().tolist() if boxes_obj is not None else []
        conf = boxes_obj.conf.cpu().tolist() if boxes_obj is not None else []
        labels = [int(x) for x in boxes_obj.cls.cpu().tolist()] if boxes_obj is not None else []
        h, w = result.orig_shape

        keep, kept_scores = _linear_soft_nms_numpy(
            xyxy, conf, iou_thres=self.iou_thres, score_floor=self.score_floor, max_det=self.max_det
        )
        # 与 OnnxDetector 相同口径：衰减后仍需回到置信度阈值之上
        conf_cutoff = getattr(self, "conf_thres", 0.25)
        kept_pairs = [(i, s) for i, s in zip(keep, kept_scores) if s >= conf_cutoff]
        keep = [i for i, _ in kept_pairs]
        kept_scores = [s for _, s in kept_pairs]
        quality = _probe_image_quality(Path(image))
        return DetectionResult(
            boxes=[xyxy[i] for i in keep],
            scores=[round(s, 4) for s in kept_scores],
            labels=[labels[i] for i in keep],
            image_width=int(w),
            image_height=int(h),
            model_name=self.model_name,
            model_version=self.model_version,
            inference_ms=round(elapsed_ms, 1),
            candidate_count=len(xyxy),
            quality_status=quality,
            coverage=None,
            postprocess="softnms-only",
            score_mode=self.score_mode,
        )


def build_detector(config: AgentConfig) -> tuple[Detector | None, dict]:
    """按配置构建检测器。返回 (detector, model_info)；model_info 用于 /health。

    真实模式优先使用制品目录中的 model.onnx（只需 onnxruntime，符合文档
    4.1 节部署形态）；没有 ONNX 时回退到 .pt + ultralytics。制品校验
    失败时抛 ModelArtifactError，由调用方决定 fail-closed。
    """
    if config.model_mode != "real":
        detector = MockDetector(config.model_name, f"mock-{config.model_version}")
        return detector, {
            "mode": "mock",
            "name": detector.model_name,
            "version": detector.model_version,
            "artifacts": None,
            "manifest_verified": False,
            "postprocess": "mock",
        }

    if not config.model_dir:
        raise ModelArtifactError("真实模式需要 PIG_AGENT_MODEL_DIR 或 config.model.artifacts")
    manifest = load_manifest(config.model_dir)
    files = [item["path"] for item in manifest.get("files", [])]
    has_onnx = (config.model_dir / "model.onnx").exists()

    if has_onnx:
        detector: Detector = OnnxDetector(config.model_dir, manifest)
        postprocess = "onnx+linear-softnms"
    else:
        detector = UltralyticsDetector(config.model_dir, manifest, config.weights)
        postprocess = "softnms-only"
    return detector, {
        "mode": "real",
        "runtime": "onnxruntime" if has_onnx else "ultralytics",
        "name": detector.model_name,
        "version": detector.model_version,
        "artifacts": str(config.model_dir),
        "manifest_verified": True,
        "score_mode": manifest.get("score_mode"),
        "files": files,
        "postprocess": postprocess,
    }


__all__ = [
    "DetectionResult",
    "Detector",
    "MockDetector",
    "OnnxDetector",
    "UltralyticsDetector",
    "ModelArtifactError",
    "ModelUnavailable",
    "build_detector",
    "decode_onnx_output",
    "load_manifest",
]
