"""测试辅助：脚本化 Detector 与临时配置。"""
from __future__ import annotations

from pathlib import Path

from pig_farm_agent.config import load_config
from pig_farm_agent.detector import DetectionResult, Detector

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def make_detection(count: int = 30, *, quality: str = "usable", coverage: float | None = 0.95) -> DetectionResult:
    return DetectionResult(
        boxes=[[float(i), 0.0, float(i) + 10, 10.0] for i in range(count)],
        scores=[0.8] * count,
        labels=[0] * count,
        image_width=640,
        image_height=480,
        model_name="DCR-SoftNMS-YOLOv13",
        model_version="test-v1",
        inference_ms=12.5,
        candidate_count=count + 3,
        quality_status=quality,
        coverage=coverage,
        postprocess="test",
    )


class ScriptedDetector(Detector):
    """按脚本顺序返回结果；耗尽后重复最后一个，用于控制密度序列。"""

    model_name = "DCR-SoftNMS-YOLOv13"
    model_version = "scripted-v1"

    def __init__(self, results: list[DetectionResult]):
        self.results = list(results)
        self.calls: list[str] = []

    def predict(self, image, *, request_id: str, barn_id: str | None = None) -> DetectionResult:
        self.calls.append(request_id)
        if self.results:
            self.last = self.results.pop(0)
        return self.last


def make_agent(tmp_dir, results: list[DetectionResult] | None = None):
    from pig_farm_agent.agent import PigFarmAgent

    config = load_config(
        PROJECT_ROOT / "config.json",
        data_dir=Path(tmp_dir),
        use_env=False,
    )
    agent = PigFarmAgent(config)
    if results is not None:
        agent.detector = ScriptedDetector(results)
    return agent
