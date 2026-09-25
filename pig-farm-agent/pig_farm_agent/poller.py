"""目录轮询输入：定时摄像头快照的自动分析入口。

监控 `data/polling/<栏舍ID>/` 下的新图片（摄像头或网关按固定周期写入），逐张调用
`PigFarmAgent.analyze` 完成检测、风险判断和事件落盘，处理后移入 `_processed/`，
失败移入 `_failed/`。对应产品规划 V1 输入要求"支持手工上传和目录轮询"。

来源可追溯（产品规划 §4.1"记录来源、设备和时间"）：
- `source` 固定为 `polling`；
- `device_id` 取侧车 JSON 的 `device_id` 字段，其次 `--device` / 配置
  `polling.device_id`，最后回退到栏舍目录；
- `captured_at` 优先取标准快照文件名中的时间戳（`20260916_083000`、
  `2026-09-16T08:30:00` 等），其次侧车 `captured_at`，最后用文件修改时间。

稳定运行：
- `request_id` 由文件指纹派生（`poll-<sha1(名字:大小:纳秒mtime)>`），服务重启后
  天然幂等，同一快照不会产生重复事件；
- 未写完的文件（大小或 mtime 在连续两轮扫描间仍在变化）会推迟到下一轮，
  避免读到半张图片；
- 单张图片失败只隔离该文件，不中断轮询；`.json` 侧车文件始终与图片同进同出。
"""
from __future__ import annotations

from dataclasses import replace
from datetime import datetime
from pathlib import Path
import hashlib
import json
import re
import threading
import time

from .agent import PigFarmAgent
from .config import AgentConfig
from .models import DomainError

ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
PROCESSED_DIR = "_processed"
FAILED_DIR = "_failed"
SIDECAR_SUFFIX = ".json"

# 快照文件名里的常见时间戳：20260916_083000 / 20260916-083000 / 2026-09-16T08:30:00
_NAME_TIME_PATTERNS = (
    re.compile(r"(?P<y>\d{4})[-_]?(?P<m>\d{2})[-_]?(?P<d>\d{2})[Tt_\- ]?(?P<H>\d{2})[:._-]?(?P<M>\d{2})[:._-]?(?P<S>\d{2})"),
    re.compile(r"(?P<y>\d{4})[-_](?P<m>\d{2})[-_](?P<d>\d{2})"),
)


def snapshot_time_from_name(name: str) -> str | None:
    """从文件名解析拍摄时间；解析不出返回 None（调用方回退到文件 mtime）。"""
    for pattern in _NAME_TIME_PATTERNS:
        match = pattern.search(name)
        if not match:
            continue
        parts = match.groupdict()
        try:
            moment = datetime(
                int(parts["y"]), int(parts["m"]), int(parts["d"]),
                int(parts.get("H") or 0), int(parts.get("M") or 0), int(parts.get("S") or 0),
            )
        except ValueError:
            continue
        return moment.astimezone().isoformat(timespec="seconds")
    return None


class DirectoryPoller:
    def __init__(self, agent: PigFarmAgent, watch_dir: Path, interval_seconds: float = 30.0,
                 logger=None, device_id: str | None = None, settle_scans: int = 1):
        self.agent = agent
        self.watch_dir = Path(watch_dir)
        self.interval_seconds = max(1.0, float(interval_seconds))
        self.logger = logger
        self.device_id = device_id or getattr(agent.config, "polling_device_id", None)
        self.settle_scans = max(0, int(settle_scans))
        self._stop = threading.Event()
        self._seen: dict[Path, tuple[int, int]] = {}

    def _log(self, level: str, message: str, **fields) -> None:
        if self.logger is not None:
            self.logger.log(level, message, **fields)

    # ---------- 扫描 ----------

    def poll_once(self) -> list[dict]:
        """扫描一轮并处理新文件；返回本轮产生的分析响应。"""
        responses: list[dict] = []
        if not self.watch_dir.exists():
            return responses
        for barn_dir in sorted(p for p in self.watch_dir.iterdir()
                               if p.is_dir() and not p.name.startswith("_")):
            barn_id = barn_dir.name
            if barn_id not in self.agent.config.barns:
                self._log("warning", "polling_skip_unknown_barn", barn=barn_id)
                continue
            for image in sorted(p for p in barn_dir.iterdir()
                                if p.is_file() and p.suffix.lower() in ALLOWED_SUFFIXES):
                if not self._is_stable(image):
                    self._log("debug", "polling_defer_unstable_file", file=str(image))
                    continue
                response = self._process(barn_id, image)
                if response is not None:
                    responses.append(response)
        return responses

    def _is_stable(self, image: Path) -> bool:
        """文件大小与 mtime 在相邻两轮扫描间不变才认为写完（避免半张图）。

        `settle_scans=0` 时不做稳定等待（定时任务一次性扫描、单元测试等场景）。
        """
        if self.settle_scans <= 0:
            return True
        try:
            stat = image.stat()
        except OSError:
            return False
        fingerprint = (stat.st_size, stat.st_mtime_ns)
        previous = self._seen.get(image)
        self._seen[image] = fingerprint
        return previous == fingerprint

    # ---------- 单张处理 ----------

    def _process(self, barn_id: str, image: Path) -> dict | None:
        try:
            captured_at, device_id = self._provenance(barn_id, image)
            response = self.agent.analyze(
                {
                    "request_id": request_id_for(image),
                    "farm_id": "edge",
                    "barn_id": barn_id,
                    "captured_at": captured_at,
                    "source": "polling",
                    "device_id": device_id,
                    "image_path": str(image),
                }
            )
        except DomainError as exc:
            self._archive(image, FAILED_DIR, barn_id)
            self._log("error", "polling_analyze_rejected", file=str(image), error=exc.message)
            return None
        except Exception as exc:  # 推理环境等异常：隔离坏文件，保持轮询运转
            self._archive(image, FAILED_DIR, barn_id)
            self._log("error", "polling_analyze_failed", file=str(image), error=str(exc))
            return None
        self._archive(image, PROCESSED_DIR, barn_id)
        event = response.get("event", {})
        self._log(
            "info", "polling_analyzed",
            file=image.name, barn=barn_id, device=device_id, captured_at=captured_at,
            count=event.get("state", {}).get("pig_count"),
            risk=event.get("risk", {}).get("level"), merged=response.get("merged", False),
        )
        return response

    def _provenance(self, barn_id: str, image: Path) -> tuple[str, str]:
        """解析拍摄时间与设备号：侧车 JSON > 文件名/配置 > 文件 mtime/栏舍名。"""
        sidecar = self._read_sidecar(image)
        captured_at = (
            sidecar.get("captured_at")
            or snapshot_time_from_name(image.name)
            or datetime.fromtimestamp(image.stat().st_mtime).astimezone().isoformat(timespec="seconds")
        )
        device_id = str(sidecar.get("device_id") or self.device_id or f"barn-{barn_id}")
        return str(captured_at), device_id

    def _read_sidecar(self, image: Path) -> dict:
        """读取同名 `.json` 侧车文件（可选）：支持 captured_at / device_id。"""
        path = image.with_suffix(SIDECAR_SUFFIX)
        if not path.exists():
            return {}
        try:
            payload = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            self._log("warning", "polling_sidecar_invalid", file=str(path), error=str(exc))
            return {}
        return payload if isinstance(payload, dict) else {}

    def _archive(self, image: Path, category: str, barn_id: str) -> None:
        """把已处理文件（连同侧车）移到 _processed/<栏舍> 或 _failed/<栏舍>。"""
        for path, suffix in ((image, image.suffix), (image.with_suffix(SIDECAR_SUFFIX), SIDECAR_SUFFIX)):
            if not path.exists():
                continue
            target_dir = self.watch_dir / category / barn_id
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / path.name
            counter = 1
            while target.exists():  # 同名快照按序号保留，不覆盖
                target = target_dir / f"{path.stem}-{counter}{suffix}"
                counter += 1
            path.replace(target)
        self._seen.pop(image, None)

    # ---------- 主循环 ----------

    def run_forever(self) -> None:
        """阻塞式轮询主循环（供守护线程使用）。"""
        self._log("info", "polling_started", watch_dir=str(self.watch_dir),
                  interval_seconds=self.interval_seconds, device_id=self.device_id)
        while not self._stop.is_set():
            try:
                self.poll_once()
            except Exception as exc:
                self._log("error", "polling_cycle_failed", error=str(exc))
            self._stop.wait(self.interval_seconds)
        self._log("info", "polling_stopped")

    def stop(self) -> None:
        self._stop.set()


def request_id_for(image: Path) -> str:
    """文件指纹派生的幂等 request_id：同名同内容重放不会产生重复事件。"""
    stat = Path(image).stat()
    fingerprint = f"{Path(image).name}:{stat.st_size}:{stat.st_mtime_ns}"
    return f"poll-{hashlib.sha1(fingerprint.encode('utf-8')).hexdigest()[:16]}"


def build_poller(config: AgentConfig, agent: PigFarmAgent, logger=None,
                 settle_scans: int = 1) -> DirectoryPoller:
    """按配置构建轮询器（服务端与独立运行共用）。"""
    watch_dir = config.polling_watch_dir
    if watch_dir is None:
        raise ValueError("未配置 polling.watch_dir")
    watch_dir.mkdir(parents=True, exist_ok=True)
    return DirectoryPoller(agent, watch_dir, config.polling_interval, logger,
                           device_id=config.polling_device_id, settle_scans=settle_scans)


def main() -> None:
    """独立运行目录轮询（不启动 HTTP 服务）。"""
    import argparse

    from .config import load_config
    from .server import StructLogger

    parser = argparse.ArgumentParser(description="目录轮询：自动分析摄像头快照")
    parser.add_argument("--once", action="store_true", help="只扫描一轮后退出（便于定时任务/联调）")
    parser.add_argument("--device", default=None, help="设备号，写入事件的来源信息")
    parser.add_argument("--interval", type=float, default=None, help="轮询间隔秒数")
    parser.add_argument("--defer-scans", type=int, default=None,
                        help="同一文件需要连续扫描几次不变才处理（默认 1；0 表示不等待）")
    args = parser.parse_args()

    config = load_config()
    if args.interval is not None:
        config = replace(config, polling_interval=max(1.0, args.interval))
    agent = PigFarmAgent(config)
    logger = StructLogger(config.log_level)
    settle = args.defer_scans
    if settle is None:
        settle = 1 if not args.once else 0  # 定时任务只跑一轮，不做稳定等待
    poller = build_poller(config, agent, logger, settle_scans=settle)
    if args.device:
        poller.device_id = args.device
    try:
        if args.once:
            responses = poller.poll_once()
            logger.info("polling_once_done", analyzed=len(responses), watch_dir=str(poller.watch_dir))
        else:
            poller.run_forever()
    except KeyboardInterrupt:
        poller.stop()
    finally:
        agent.close()


if __name__ == "__main__":
    main()
