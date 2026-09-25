"""生成回放夹具图片与风险通路自检（不含真实猪只照片）。

用法：
  python tools/make_replay_fixtures.py                  # 生成并自检风险覆盖
  python tools/make_replay_fixtures.py --clean
  python tools/make_replay_fixtures.py --candidates 96  # 扩大候选池

回放框架（pig_farm_agent/replay.py）需要一组固定、可长期留档的图片作为模型
升级门槛的输入。这里用几何图形合成"栏舍俯视"占位图，完全可复现、无版权与
隐私问题；图片内容对 mock 联调模式不构成质量差异（MockDetector 由 request_id
确定性派生结果），因此在真实制品接入前，夹具的作用是**锁定全链路行为**：
正常区间、DENSITY_WATCH、DENSITY_HIGH、DATA_QUALITY_LOW 与冷却合并。

脚本按回放位置（replay-000i）挑选候选，保证生成后回放能覆盖全部通路，
并在落盘前用临时数据目录自检；覆盖不达标则不写入。做模型升级验收时，
用脱敏现场图片替换同目录文件并重新生成基线：

  python -m pig_farm_agent.replay --update-baseline
"""
from __future__ import annotations

import argparse
from dataclasses import replace
from pathlib import Path
import random
import shutil
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:  # 允许直接以脚本方式运行（python tools/xxx.py）
    sys.path.insert(0, str(PROJECT_ROOT))

from pig_farm_agent.config import load_config  # noqa: E402
from pig_farm_agent.detector import MockDetector  # noqa: E402

DEFAULT_IMAGES_DIR = PROJECT_ROOT / "tests" / "fixtures" / "replay" / "images"

SIZE = (640, 480)
FLOOR = (176, 168, 152)
PEN_LINE = (120, 112, 98)
PIG = (232, 214, 206)
PIG_SHADE = (206, 184, 176)
CAPACITY = 45

# 每个栏舍的回放序列：(标签, 该位置的通过条件)
#   high    = 连续两帧密度 ≥ 0.82 -> 第二次命中生成 DENSITY_HIGH
#   merge   = 冷却窗口内再次命中同一代码 -> 合并进未关闭事件
#   low     = 密度 < 0.60 且质量正常 -> 正常区间
#   watch   = 连续两帧 0.68 ≤ 密度 < 0.82 -> DENSITY_WATCH
#   quality = 质量非 usable 或覆盖率 < 0.8 -> DATA_QUALITY_LOW
SEQUENCES: dict[str, list[tuple[str, str]]] = {
    "A01": [("high", "dense"), ("high", "dense"), ("merge", "dense"),
            ("low", "light"), ("low", "light")],
    "A02": [("watch", "watch"), ("watch", "watch"), ("merge", "watch"),
            ("quality", "poor"), ("low", "light"), ("low", "light")],
}

TARGET_CODES = {"none": 2, "DENSITY_WATCH": 1, "DENSITY_HIGH": 1, "DATA_QUALITY_LOW": 1}


def build(kind: str, seed: int) -> Image.Image:
    """合成一张栏舍占位图；kind 影响亮度与模糊，便于人工辨认夹具类型。"""
    rng = random.Random(seed)
    image = Image.new("RGB", SIZE, FLOOR)
    draw = ImageDraw.Draw(image)
    for x in range(0, SIZE[0], 160):          # 隔栏，提供稳定对比度
        draw.line([(x, 0), (x, SIZE[1])], fill=PEN_LINE, width=4)
    draw.line([(0, SIZE[1] // 2), (SIZE[0], SIZE[1] // 2)], fill=PEN_LINE, width=3)
    for _ in range(26):                        # 地面纹理，避免纯色块
        draw.point((rng.randrange(SIZE[0]), rng.randrange(SIZE[1])), fill=(166, 158, 142))
    pig_count = {"dense": rng.randrange(26, 40), "light": rng.randrange(4, 12)}.get(kind, 20)
    for _ in range(pig_count):                 # 猪只椭圆
        x, y = rng.randrange(20, SIZE[0] - 80), rng.randrange(20, SIZE[1] - 70)
        w, h = rng.randrange(52, 74), rng.randrange(30, 42)
        draw.ellipse([x, y, x + w, y + h], fill=PIG, outline=PIG_SHADE, width=2)
        draw.ellipse([x + w - 16, y + 6, x + w - 6, y + 16], fill=PIG_SHADE)
    if kind == "blur":
        image = image.filter(ImageFilter.GaussianBlur(9))
    elif kind == "lowlight":
        image = image.point(lambda v: int(v * 0.10))
    return image


def _passes(requirement: str, frame: dict) -> bool:
    # 质量门优先于密度规则：覆盖率 <0.8 或质量非 usable 时只会出 DATA_QUALITY_LOW，
    # 因此密度类候选必须同时满足覆盖率，否则连续确认永远不会成立。
    density, quality, coverage = frame["density"], frame["quality"], frame["coverage"] or 1.0
    if requirement == "dense":
        return quality == "usable" and coverage >= 0.8 and density >= 0.82
    if requirement == "watch":
        return quality == "usable" and coverage >= 0.8 and 0.68 <= density < 0.82
    if requirement == "light":
        return quality == "usable" and coverage >= 0.8 and density < 0.60
    if requirement == "poor":
        return quality != "usable" or coverage < 0.8
    if requirement == "any":
        return True
    return False


def plan_sequence(barn: str, layout: list[tuple[str, str]], candidates: int,
                  base_index: int, probe_dir: Path) -> list[tuple[str, str, int]] | None:
    """为栏舍挑选夹具：每个位置搜索候选图像，直到该位置的观测满足目标通路。

    MockDetector 以 request_id + 栏舍 + 图片指纹（文件名/字节数/内容摘要）为种子，
    因此这里对每个位置枚举候选图像（不同随机种子生成，内容和字节数都不同），
    用与回放完全一致的口径探测（相同文件名、相同 request_id、真实文件），
    命中目标条件后再渲染到最终目录——生成结果与回放结果严格一致。
    """
    detector = MockDetector()
    chosen: list[tuple[str, str, int]] = []
    for offset, (label, requirement) in enumerate(layout):
        request_id = f"replay-{base_index + offset:04d}"
        base_name = f"barn-{barn}-{offset + 1:02d}"
        found = None
        for candidate in range(candidates):
            name = f"{base_name}{'' if candidate == 0 else chr(ord('b') + candidate - 1)}.jpg"
            path = probe_dir / name
            build(label, 9000 + candidate * 131 + base_index + offset).save(path, "JPEG", quality=92)
            result = detector.predict(path, request_id=request_id, barn_id=barn)
            frame = {
                "density": round(min(1.0, result.kept_count / CAPACITY), 4),
                "quality": result.quality_status,
                "coverage": result.coverage,
            }
            if _passes(requirement, frame):
                found = (label, name)
                break
        if found is None:
            print(f"  ! {barn} 第 {offset + 1} 帧（{label}/{requirement}）在 {candidates} 个候选内"
                  f"无匹配；请增大 --candidates")
            return None
        chosen.append(found)
    return chosen


def verify(images_dir: Path, config) -> dict:
    """在临时数据目录里回放一遍，统计实际风险通路覆盖。"""
    from pig_farm_agent.replay import run_replay

    with tempfile.TemporaryDirectory(prefix="pig-fixture-") as tmp:
        result = run_replay(replace(config, data_dir=Path(tmp)), images_dir, mode="agent")
    codes: dict[str, int] = {}
    for item in result["results"]:
        key = item["risk_code"] or "none"
        codes[key] = codes.get(key, 0) + 1
    return {
        "codes": codes,
        "merged": sum(1 for r in result["results"] if r["merged"]),
        "quality": sorted({r["quality_status"] for r in result["results"]}),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="生成回放夹具图片")
    parser.add_argument("--images", default=str(DEFAULT_IMAGES_DIR))
    parser.add_argument("--candidates", type=int, default=64, help="每个位置搜索的候选图像数")
    parser.add_argument("--clean", action="store_true", help="先清空目标目录中的图片")
    args = parser.parse_args(argv)

    config = load_config()
    target = Path(args.images)
    target.mkdir(parents=True, exist_ok=True)

    probe_dir = Path(tempfile.mkdtemp(prefix="pig-fixture-probe-"))
    plan: list[tuple[str, str]] = []
    try:
        for barn, layout in SEQUENCES.items():
            chosen = plan_sequence(barn, layout, args.candidates, len(plan), probe_dir)
            if chosen is None:
                return 1
            plan.extend(chosen)

        # 只自检选中的图片：候选搜索会在 probe_dir 留下未选中的文件，先隔离出来
        selected = Path(tempfile.mkdtemp(prefix="pig-fixture-selected-"))
        try:
            for _label, name in plan:
                shutil.copyfile(probe_dir / name, selected / name)
            report = verify(selected, config)
        finally:
            shutil.rmtree(selected, ignore_errors=True)

        print(f"自检：风险覆盖 {report['codes']} | 质量 {report['quality']} "
              f"| 合并观测 {report['merged']}")
        missing = [code for code, need in TARGET_CODES.items()
                   if report["codes"].get(code, 0) < need]
        if missing or report["merged"] < 2:
            print(f"覆盖不足（缺少 {missing}，合并 {report['merged']}/2）；未写入夹具。"
                  f"请增大 --candidates。")
            return 1

        if args.clean:
            for existing in target.glob("*.jpg"):
                existing.unlink()
        for _label, name in plan:
            shutil.copyfile(probe_dir / name, target / name)
    finally:
        shutil.rmtree(probe_dir, ignore_errors=True)

    print(f"已写入 {len(plan)} 张夹具到 {target}")
    print("替换为现场脱敏图片后重新生成基线：\n"
          "  python -m pig_farm_agent.replay --update-baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
