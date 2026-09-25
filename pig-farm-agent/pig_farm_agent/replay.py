"""回放测试框架：固定图片集的确定性对比，模型升级门槛（技术文档第 10 节）。

设计要点
- **全链路口径**：回放走 `PigFarmAgent.analyze` 真实闭环（检测 -> 状态 -> 风险 -> 证据），
  因此可以同时锁定候选数、计数、质量状态、**风险等级/代码**和端到端耗时，
  与文档第 10 节"比较候选数、计数、风险等级和运行时间"逐项对应。
- **互不干扰**：每次回放都在独立的临时数据目录里跑，不写生产 SQLite/证据，
  结束后清理；基线只保留可比的确定性字段（不含 event_id、created_at 等运行时值）。
- **升门槛失败即非 0 退出**：计数、质量状态、风险代码或风险等级出现差异时退出码 1，
  便于挂在升级流程里做卡点。夹具文件指纹变化会单独报告，避免"改了图片还以为模型漂移"。

用法：
  # 生成/更新基线（模型升级前，或在 mock 联调模式锁定闭环行为）
  python -m pig_farm_agent.replay --update-baseline

  # 升级新制品后回放对比（默认夹具 tests/fixtures/replay/images）
  python -m pig_farm_agent.replay

  # 指定图片目录与基线、放宽容忍度、附加端到端耗时门槛
  python -m pig_farm_agent.replay --images <dir> --baseline data/replay_baseline.json \
      --tolerance 1 --max-ms 3000

  # 只跑检测器口径（不含风险规则），用于快速定位是模型还是规则引起差异
  python -m pig_farm_agent.replay --mode detector --print
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import statistics
import sys
import tempfile

from .agent import PigFarmAgent
from .config import AgentConfig, PROJECT_ROOT, load_config
from .detector import Detector, build_detector

ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
DEFAULT_IMAGES_DIR = PROJECT_ROOT / "tests" / "fixtures" / "replay" / "images"
DEFAULT_BASELINE_PATH = PROJECT_ROOT / "tests" / "fixtures" / "replay" / "baseline.json"
SCHEMA_VERSION = 2

# 基线中参与门槛判定的字段（顺序即报告顺序）
COMPARE_FIELDS = (
    ("candidate_count", "候选数"),
    ("detected_count", "计数"),
    ("quality_status", "质量状态"),
    ("risk_code", "风险代码"),
    ("risk_level", "风险等级"),
)

TOLERATED_FIELDS = {"candidate_count", "detected_count"}


def collect_images(images_dir: Path) -> list[Path]:
    """按文件名排序收集回放图片（`barn-A01-01.jpg` 形式可指定栏舍）。"""
    directory = Path(images_dir)
    if not directory.is_dir():
        raise FileNotFoundError(f"回放图片目录不存在: {directory}")
    return sorted(
        p for p in directory.iterdir()
        if p.is_file() and p.suffix.lower() in ALLOWED_SUFFIXES
    )


def barn_for(image: Path, default_barn: str) -> str:
    """从文件名解析栏舍，支持以下命名：

    - `barn-A01-01.jpg`（推荐，回放夹具用这种）
    - `A01_20260916_083000.jpg`（摄像头常见的"栏舍_时间"命名）
    - 其它命名回退到 default_barn。

    同一栏舍的图片按文件名顺序回放，因此连续两帧超阈值的密度规则会被真实触发，
    风险等级口径才具备门槛意义（连续确认、冷却合并都需要历史观测）。
    """
    parts = image.stem.replace("__", "-").split("-")
    for i, token in enumerate(parts):
        if token.lower() == "barn" and i + 1 < len(parts) and parts[i + 1]:
            return parts[i + 1]
    if len(parts) > 1 and parts[0]:
        return parts[0]
    head = image.stem.split("_")[0]
    if head != image.stem and head and head.isascii():
        return head
    return default_barn


def file_sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:16]


def _run_agent_replays(config: AgentConfig, images: list[Path], data_dir: Path,
                       default_barn: str) -> list[dict]:
    """在临时数据目录里跑完整 Agent 闭环，逐张收集可比指标。"""
    replay_config = AgentConfig(**{**config.__dict__, "data_dir": Path(data_dir)})
    agent = PigFarmAgent(replay_config)
    try:
        results = []
        for index, image in enumerate(images):
            barn_id = barn_for(image, default_barn)
            if barn_id not in replay_config.barns:
                raise ValueError(f"回放图片 {image.name} 指向未配置栏舍 {barn_id!r}")
            started = datetime.now()
            response = agent.analyze(
                {
                    "request_id": f"replay-{index:04d}",
                    "farm_id": "replay",
                    "barn_id": barn_id,
                    "captured_at": f"2026-01-01T{index // 60:02d}:{index % 60:02d}:00+08:00",
                    "source": "manual",
                    "image_path": str(image),
                }
            )
            elapsed_ms = (datetime.now() - started).total_seconds() * 1000.0
            event = response["event"]
            state = event.get("state", {})
            risk = event.get("risk", {})
            metrics_rel = event.get("evidence", {}).get("metrics")
            detection: dict = {}
            if metrics_rel:
                metrics_path = Path(data_dir) / metrics_rel
                if metrics_path.exists():
                    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
                    detection = metrics.get("detection", {}) or {}
            results.append(
                {
                    "file": image.name,
                    "barn_id": barn_id,
                    "detected_count": state.get("pig_count"),
                    "candidate_count": detection.get("candidate_count"),
                    "quality_status": (state.get("quality") or {}).get("status"),
                    "coverage": (state.get("quality") or {}).get("coverage"),
                    "density": state.get("density"),
                    "risk_level": risk.get("level"),
                    "risk_code": risk.get("code"),
                    "merged": bool(response.get("merged")),
                    "evidence_complete": bool(
                        event.get("evidence", {}).get("image")
                        and event.get("evidence", {}).get("metrics")
                        and event.get("evidence", {}).get("annotated")
                    ),
                    "event_ms": round(elapsed_ms, 1),
                }
            )
        return results
    finally:
        agent.close()


def _run_detector_replays(config: AgentConfig, images: list[Path], default_barn: str) -> list[dict]:
    """只跑检测器（不含风险规则），用于快速区分模型差异与规则差异。"""
    detector: Detector = build_detector(config)[0]
    if detector is None:  # pragma: no cover - 真实模式制品缺失
        raise RuntimeError("模型不可用：无法回放")
    results = []
    for index, image in enumerate(images):
        barn_id = barn_for(image, default_barn)
        detection = detector.predict(str(image), request_id=f"replay-{index:04d}", barn_id=barn_id)
        results.append(
            {
                "file": image.name,
                "barn_id": barn_id,
                "detected_count": detection.kept_count,
                "candidate_count": detection.candidate_count,
                "quality_status": detection.quality_status,
                "coverage": detection.coverage,
                "inference_ms": detection.inference_ms,
            }
        )
    return results


def run_replay(config: AgentConfig, images_dir: Path = DEFAULT_IMAGES_DIR, *,
               mode: str = "agent", default_barn: str = "A01") -> dict:
    """对固定图片集回放一遍，返回可序列化的回放结果（不含运行时易变字段）。"""
    images = collect_images(images_dir)
    if not images:
        raise FileNotFoundError(f"目录中没有可回放的图片: {images_dir}")

    if mode == "detector":
        results = _run_detector_replays(config, images, default_barn)
        model_name, model_version = config.model_name, config.model_version
    elif mode == "agent":
        with tempfile.TemporaryDirectory(prefix="pig-replay-") as tmp:
            results = _run_agent_replays(config, images, Path(tmp), default_barn)
        model_name = config.model_name
        model_version = config.model_version
        if config.model_mode != "real":
            model_version = f"mock-{config.model_version}"
    else:
        raise ValueError(f"未知回放模式: {mode}")

    timings = [r["event_ms"] if "event_ms" in r else r["inference_ms"] for r in results]
    return {
        "schema_version": SCHEMA_VERSION,
        "mode": mode,
        "model_name": model_name,
        "model_version": model_version,
        "model_mode": config.model_mode,
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "images_dir": str(images_dir),
        "image_count": len(results),
        "timing": {
            "total_ms": round(sum(timings), 1),
            "mean_ms": round(statistics.fmean(timings), 1),
            "max_ms": round(max(timings), 1),
        },
        "fixtures": {r["file"]: file_sha256(Path(images_dir) / r["file"]) for r in results},
        "results": results,
    }


def compare(baseline: dict, current: dict, *, tolerance: int = 0,
            allow_risk_change: bool = False) -> list[str]:
    """返回差异清单；空列表表示通过回放门槛。"""
    diffs: list[str] = []

    if baseline.get("model_version") != current.get("model_version"):
        diffs.append(
            f"模型版本不同: 基线 {baseline.get('model_name')}@{baseline.get('model_version')}"
            f" vs 当前 {current.get('model_name')}@{current.get('model_version')}"
        )
    if baseline.get("mode") and baseline["mode"] != current.get("mode"):
        diffs.append(f"回放模式不同: 基线 {baseline['mode']} vs 当前 {current.get('mode')}")

    base_fixtures = baseline.get("fixtures") or {}
    curr_fixtures = current.get("fixtures") or {}
    if base_fixtures and curr_fixtures:
        for name in sorted(set(base_fixtures) | set(curr_fixtures)):
            if base_fixtures.get(name) != curr_fixtures.get(name):
                diffs.append(f"回放夹具已变化（指纹不同）: {name}")

    base = {r["file"]: r for r in baseline.get("results", [])}
    curr = {r["file"]: r for r in current.get("results", [])}
    for name in sorted(set(base) - set(curr)):
        diffs.append(f"当前制品缺少图片结果: {name}")
    for name in sorted(set(curr) - set(base)):
        diffs.append(f"当前制品多出图片结果: {name}")

    for name in sorted(set(base) & set(curr)):
        b, c = base[name], curr[name]
        for field, label in COMPARE_FIELDS:
            before, after = b.get(field), c.get(field)
            if before == after:
                continue
            numeric = isinstance(before, (int, float)) and isinstance(after, (int, float)) \
                and not isinstance(before, bool) and not isinstance(after, bool)
            if field in TOLERATED_FIELDS and numeric and abs(before - after) <= tolerance:
                continue
            if field in ("risk_code", "risk_level") and allow_risk_change:
                continue
            if numeric:
                diffs.append(f"{name}: {label} {before} -> {after}（容忍度 ±{tolerance}）")
            else:
                diffs.append(f"{name}: {label} {before} -> {after}")
    return diffs


def summarize(result: dict) -> str:
    """一屏摘要：模型版本、计数分布、风险分布与耗时。"""
    results = result["results"]
    counts = [r["detected_count"] for r in results if isinstance(r.get("detected_count"), int)]
    risks: dict[str, int] = {}
    for r in results:
        key = r.get("risk_code") or "none"
        risks[key] = risks.get(key, 0) + 1
    lines = [
        f"模型: {result.get('model_name')}@{result.get('model_version')}"
        f"（{result.get('model_mode')} / {result.get('mode')} 模式）",
        f"图片: {result.get('image_count')} 张，目录 {result.get('images_dir')}",
    ]
    if counts:
        lines.append(
            f"计数: 合计 {sum(counts)}，单张 {min(counts)}~{max(counts)}，均值 {statistics.fmean(counts):.1f}"
        )
    lines.append("风险: " + "，".join(f"{k}×{v}" for k, v in sorted(risks.items())))
    timing = result.get("timing") or {}
    if timing:
        unit = "端到端" if result.get("mode") == "agent" else "推理"
        lines.append(
            f"{unit}耗时: 合计 {timing.get('total_ms')}ms，均值 {timing.get('mean_ms')}ms，"
            f"最大 {timing.get('max_ms')}ms"
        )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="DCR-SoftNMS-YOLOv13 回放测试（模型升级门槛）")
    parser.add_argument("--images", default=str(DEFAULT_IMAGES_DIR), help="回放图片目录")
    parser.add_argument("--baseline", default=str(DEFAULT_BASELINE_PATH), help="基线 JSON 路径")
    parser.add_argument("--update-baseline", action="store_true", help="用当前结果覆盖基线")
    parser.add_argument("--tolerance", type=int, default=0, help="候选数/计数容忍度（默认 0）")
    parser.add_argument("--max-ms", type=float, default=0.0,
                        help="单张端到端耗时上限（毫秒，0 表示不设门槛）")
    parser.add_argument("--mode", choices=("agent", "detector"), default="agent",
                        help="agent=全链路（默认，含风险等级）；detector=仅检测器")
    parser.add_argument("--allow-risk-change", action="store_true",
                        help="风险等级/代码变化不计入失败（仅供人工排查时使用）")
    parser.add_argument("--print", dest="print_result", action="store_true",
                        help="打印完整回放结果 JSON（供测试或人工复核）")
    parser.add_argument("--data-dir", default=None,
                        help="真实模式的制品/数据目录（默认读 config.json 与环境变量）")
    args = parser.parse_args(argv)

    config = load_config(data_dir=args.data_dir)
    current = run_replay(config, Path(args.images), mode=args.mode)

    if args.print_result:
        print(json.dumps(current, ensure_ascii=False, indent=2))

    if args.update_baseline:
        baseline_path = Path(args.baseline)
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps(current, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"基线已写入 {baseline_path}")
        print(summarize(current))
        return 0

    baseline_path = Path(args.baseline)
    if not baseline_path.exists():
        print(f"基线不存在: {baseline_path}，先运行 --update-baseline 生成", file=sys.stderr)
        return 2
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    print(summarize(current))

    diffs = compare(
        baseline, current, tolerance=args.tolerance, allow_risk_change=args.allow_risk_change
    )
    if args.max_ms:
        slow = [r for r in current["results"] if (r.get("event_ms") or 0) > args.max_ms]
        for r in slow:
            diffs.append(
                f"{r['file']}: 端到端耗时 {r.get('event_ms')}ms 超过门槛 {args.max_ms}ms"
            )

    if diffs:
        print(f"\n未通过回放门槛，{len(diffs)} 处差异：")
        for line in diffs:
            print(f"  - {line}")
        print("\n请人工复核差异；确认无误后可用 --update-baseline 重置基线。")
        return 1
    print(f"\n回放通过：与基线 {baseline_path.name} 一致（{len(current['results'])} 张图片）。")
    return 0


def _copy_fixtures(src: Path, dst: Path) -> None:  # pragma: no cover - 运维辅助
    dst.mkdir(parents=True, exist_ok=True)
    for image in collect_images(src):
        shutil.copy2(image, dst / image.name)


if __name__ == "__main__":
    sys.exit(main())
