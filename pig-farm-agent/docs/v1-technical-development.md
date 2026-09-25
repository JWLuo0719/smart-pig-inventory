# 第一代产品技术开发文档（部分已被取代）

> ⚠️ **部分已被取代（2026 需求重构）**：技术设计以 `docs/product-design-v2.md` 为准。
> 具体失效处：① 单级 `barn_id` → 改为 `猪场 / 栋 / 栏舍(penId)` 三级；② "事件中心"的数据模型
> → 改为"证据账本 + 盘点会话"为中心（事件保留为告警通道）；③ 单一 `risk.py` 阈值引擎 → 拆分为
> "计量质量门"与"控制安全联锁"两套；④ 新增控制平面（本文完全未涉及）。
> 本文保留为 V1 实现记录；接口字段口径仍与 `docs/app-integration-contract.md` 共同有效。

## 1. 目标与范围

V1 在 `D:\pig-farm-agent` 内独立开发，不修改科研项目目录。系统接收图片或视频抽帧，输出猪群状态事件、证据和建议，并提供人工确认与日报接口。代码只保留运行时所需模块；训练、实验追踪和历史脚本留在科研仓库。

### 1.1 App 兼容要求

现有 `smart-pig-inventory` App 是 V1 的移动采集端。本仓库提供一个轻量兼容层
（`POST /v1/mobile/analyze` multipart + `client_request_id` 幂等 + `GET /v1/mobile/requests/{id}`），
使不改造 App 也能做接口联调；同一 `client_request_id` 重试不产生重复事件。

> **重要（2026-09-16 实测）**：App 仓库（`D:\smart-pig-inventory`，Apache-2.0）里**并没有**
> 这个单次 multipart 接口。它真实的上传合同是 **4 步采集包**
> （`POST /upload-packages` → `PUT .../blobs/{assetId}`（`X-Content-SHA256`）→
> `PUT .../manifest` → `POST .../commit`，全部带 `X-Idempotency-Key`，Bearer JWT 认证，
> `servers: /api/v1`），业务后端是 Spring Boot + MySQL + MinIO，推理经 Celery Worker
> 与研究 Runner 回调。用本仓库的契约探针实测：本 Agent 对其合同 **0/5 端点**。
> 完整字段级契约、重试语义与两条集成路径见 `docs/app-integration-contract.md`；
> 集成决策前请先读该文档。

## 2. 总体架构

```text
Input Adapter
  -> Detector (DCR-SoftNMS-YOLOv13 runtime)
  -> Quality Gate / Data Quality
  -> State Extractor (count, density, quality, trend)
  -> Risk Engine (rules + hysteresis + cooldown)
  -> Evidence Store
  -> Agent Orchestrator
  -> HTTP API / App Adapter / Web UI / Daily Report
```

`Detector` 通过协议隔离模型实现。生产环境加载导出的 ONNX/TensorRT 或 TorchScript；开发环境可使用 `MockDetector`。产品配置只引用模型制品目录中的 manifest，不复制训练数据和实验缓存。

## 3. 代码结构

```text
pig_farm_agent/
  __init__.py
  agent.py             # 编排 analyze()、事件和报告
  server.py            # 零依赖 HTTP API（含写保护令牌）
  poller.py            # 目录轮询输入（摄像头快照自动分析）
  replay.py            # 回放测试框架与模型升级门槛
  models.py            # Observation、Evidence、Alert、Action 数据契约
  detector.py          # Detector 协议、MockDetector、真实模型适配器
  state.py             # 状态与趋势计算
  risk.py              # 风险规则、连续帧确认、冷却
  evidence.py          # 标注图和 JSON 证据落盘
  storage.py           # SQLite/JSONL 事件存储
  config.py            # 环境变量和 config.json 解析
  report.py            # 日报聚合与 CSV/JSON 导出
  static/index.html    # 最小 Web 看板（单文件、零依赖）
  model_runtime/       # 精简后的 DCR-SoftNMS 推理模块
docs/
  product-development-plan.md
  v1-technical-development.md
tests/
  fixtures/replay/     # 回放夹具图片与基线 JSON
tools/                 # 夹具生成、端到端冒烟、看板脚本检查
```

不在产品仓库放置 `train.py`、数据集、实验 notebook、云端脚本和科研历史模块。`drra_runtime` 目录应在整理时重命名为 `model_runtime`，内部只保留 scoring、soft_nms、manifest 校验和适配器。

## 4. 模型运行时

### 4.1 制品要求

模型制品目录至少包含：

```text
model_artifacts/dcr-softnms-yolov13-v1/
  model.onnx                 # 或 model.ts / engine
  rescorer.json              # 冻结的 correctness rescorer
  config.json                # pool、Soft-NMS、score 口径
  manifest.json              # sha256、指标、输入尺寸、版本
```

当前冻结口径来自 `results/drra_v3c_final`：`score_mode=quality_product`、`score_power=0.75`、linear Soft-NMS、`soft_iou_thres=0.4`、`score_floor=0.001`、`max_det=300`。在制品复制完成前，不把科研路径写死在代码中；使用 `PIG_AGENT_MODEL_DIR` 或 `config.json` 指定目录。

### 4.2 Detector 协议

```python
class Detector(Protocol):
    model_name: str
    model_version: str

    def predict(self, image: ImageLike, *, request_id: str) -> DetectionResult:
        """返回 boxes、scores、labels、quality 和 model metadata。"""
```

`DetectionResult` 必须包含原图尺寸、推理耗时、候选数、保留数、模型版本和质量状态。模型文件缺失、manifest 校验失败或输入尺寸不支持时，返回可识别错误；禁止静默回退到原始 score。

### 4.3 输入适配器

三种输入进入同一 `analyze` 契约，差异只在 `source` 与来源元数据：

| 输入 | source | 落地方式 |
|---|---|---|
| 手工上传 | `upload` | `POST /analyze` 或 `POST /v1/mobile/analyze`（multipart） |
| 目录轮询 | `polling` | `pig_farm_agent.poller` 扫描 `data/polling/<栏舍ID>/` |
| 定时快照 | `polling` | 同上，`--once` 配合系统计划任务 |

目录轮询的来源可追溯规则（产品规划 §4.1"记录来源、设备和时间"）：

- `state.source_device`：侧车 `.json` 的 `device_id` > `--device` / `polling.device_id` > `farm-<栏舍ID>`；
- `captured_at`：文件名时间戳（`20260916_083000`、`2026-09-16T08:30:00` 等）> 侧车 `captured_at` > 文件 mtime；
- `request_id` 由文件指纹（名字 + 字节数 + 纳秒 mtime）派生为 `poll-<sha1 前 16 位>`，
  服务重启后同一快照仍幂等，不产生重复事件；
- 文件在相邻两轮扫描间大小与 mtime 不变才处理（避免读到摄像头正在写入的半张图，
  `settle_scans` 可调，`--once` 场景默认不等待）；
- 处理完成的图片与侧车移入 `_processed/<栏舍>/`，失败移入 `_failed/<栏舍>/`，同名不覆盖。

## 5. 数据契约

### 5.1 分析请求

```json
{
  "request_id": "req-20260916-0001",
  "farm_id": "farm-demo",
  "barn_id": "barn-a",
  "captured_at": "2026-09-16T08:30:00+08:00",
  "source": "upload",
  "image_path": "inbox/barn-a/20260916_083000.jpg"
}
```

### 5.2 状态事件

```json
{
  "event_id": "evt-...",
  "request_id": "req-...",
  "farm_id": "farm-demo",
  "barn_id": "barn-a",
  "captured_at": "2026-09-16T08:30:00+08:00",
  "state": {"pig_count": 86, "density": 0.72, "quality": {"status": "usable", "coverage": 0.94}},
  "risk": {"level": "medium", "code": "DENSITY_HIGH", "confidence": 0.83},
  "evidence": {"image": "evidence/evt-....jpg", "metrics": "evidence/evt-....json"},
  "suggested_actions": ["复核饮水和通风状态", "30 分钟内再次巡检"],
  "status": "open",
  "model": {"name": "DCR-SoftNMS-YOLOv13", "version": "v1"}
}
```

事件状态机：`open -> acknowledged -> resolved`，也允许 `open -> dismissed`。每次转换记录操作者、时间和备注；重复事件按栏舍和风险代码在冷却窗口内合并，但原始观测仍保留。

## 6. 风险引擎

V1 使用可解释规则，不训练新的行为模型。默认规则：

- 密度超过栏舍阈值且连续两次观测成立，生成 `DENSITY_HIGH`。
- 行为类指标（如卧躺比例）只有在完成现场标注和单独验收后才启用；V1 默认不生成行为诊断告警。
- 计数、清晰度或覆盖率不足，生成 `DATA_QUALITY_LOW`，不生成高风险结论。
- 同一栏舍同一代码在冷却时间内只升级一次；恢复到正常区间持续两次后自动标记 `resolved`，仍允许人工关闭。

风险规则、阈值、连续帧数和冷却时间放入 `config.json`，事件中写入实际阈值，保证可解释和可复盘。

## 7. Agent 编排

`PigFarmAgent.analyze(request)` 负责一次观测闭环：校验输入 -> 调用 Detector -> 计算状态 -> 运行风险规则 -> 生成证据 -> 持久化事件 -> 返回结果。Agent 不直接调用外部大语言模型；建议文本由模板和规则生成，确保断网、低延迟和可审计。后续接入 LLM 时，只允许基于事件 JSON 生成措辞，不能改变风险等级或执行设备动作。

## 8. HTTP API（V1）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 最小 Web 看板（事件流 / 日报 / 上传分析） |
| GET | `/health` | 服务、模型制品和存储状态 |
| POST | `/analyze` | 上传图片路径或 multipart 图片，返回事件 |
| POST | `/v1/mobile/analyze` | 兼容 App 的 multipart 上传接口，字段含 `farm_id`、`barn_id`、`captured_at`、`client_request_id` |
| GET | `/events?barn_id=&status=&date=&limit=&offset=` | 分页查询事件 |
| GET | `/events/{event_id}` | 单事件详情（看板/App 复核用） |
| GET | `/model/replay` | 回放门槛摘要（模型升级门槛状态） |
| GET | `/v1/mobile/requests/{request_id}` | App 查询异步任务状态和结果 |
| POST | `/events/{id}/ack` | 人工确认并写备注 |
| POST | `/events/{id}/resolve` | 关闭事件 |
| POST | `/events/{id}/dismiss` | 驳回事件 |
| GET | `/report/daily?date=` | 生成日报 JSON |
| GET | `/report/daily.csv?date=` | 导出 CSV |
| GET | `/files/{path}` | 证据文件回放（相对路径，防目录穿越） |

统一错误格式：`{"error_code":"MODEL_UNAVAILABLE","message":"...","request_id":"..."}`。上传接口限制大小和格式，所有请求生成 `request_id` 并写结构化日志。

**写保护**：配置 `PIG_AGENT_API_TOKEN`（或 `config.agent.api_token`）后，所有 POST 需要
`X-Api-Token` 头，缺失或不匹配返回 `401 UNAUTHORIZED`；GET 保持开放。默认
（`127.0.0.1`、无令牌）保持零配置可用，便于单机试用；场内边缘主机部署时建议开启。

## 9. 存储与部署

V1 默认 SQLite 保存事件、状态快照和审计记录，证据图保存到本地 `data/evidence/`；JSONL 作为故障恢复和导出格式。单场部署使用 Windows/Linux 边缘主机，Python 3.11，服务绑定内网地址。通过环境变量配置模型目录、数据目录、端口和日志级别；生产启动前执行 manifest SHA256 校验。

- 环境变量：`PIG_AGENT_MODEL_DIR`、`PIG_AGENT_DATA_DIR`、`PIG_AGENT_HOST`、`PIG_AGENT_PORT`、
  `PIG_AGENT_LOG_LEVEL`、`PIG_AGENT_WEIGHTS`、`PIG_AGENT_API_TOKEN`、
  `PIG_AGENT_POLLING_DEVICE`、`PIG_AGENT_CONFIG`。
- `config.json` 的 `agent.polling`：`enabled`（是否随服务启动轮询）、`interval_seconds`、
  `watch_dir`（默认 `<data_dir>/polling`）、`device_id`。
- 局域网部署：绑定内网地址并设置 `PIG_AGENT_API_TOKEN`，只放行只读看板给普通终端；
  摄像头网关只写入 `data/polling/<栏舍ID>/`，无需接触数据库。

## 10. 测试与验收

- 单元测试：Soft-NMS 与 score 口径、规则边界、状态机、冷却合并、manifest 校验。
- 契约测试：`/analyze`、事件确认/关闭、日报字段和错误码。
- App 兼容测试：使用 `smart-pig-inventory` 的真实请求格式验证上传、超时重试、断网恢复、结果展示和确认回写；同一 `client_request_id` 重试只能生成一个事件。
- 回放测试（模型升级门槛）：固定夹具逐张跑完整链路，比较候选数、计数、质量状态、
  风险等级/代码与端到端耗时；任何差异即门槛失败（退出码 1）。
- 稳定性测试：连续运行 7 天或处理 10,000 张图片，检查内存、事件重复率和断电恢复。

### 10.1 回放门槛的落地口径

```powershell
python -m pig_farm_agent.replay --update-baseline   # 升级前留档基线
python -m pig_farm_agent.replay                     # 换制品后对比；差异 -> exit 1
python -m pig_farm_agent.replay --mode detector     # 只比检测器，区分模型/规则差异
```

- 夹具：`tests/fixtures/replay/images/`，命名 `barn-<栏舍ID>-<序号>.jpg`；同一栏舍按文件名
  顺序回放，因此连续帧确认（连续 2 次超阈值）与冷却合并都会被真实触发。
- 夹具用合成占位图，覆盖正常区间、`DENSITY_WATCH`、`DENSITY_HIGH`、`DATA_QUALITY_LOW`
  与冷却合并；`tools/make_replay_fixtures.py` 可重新生成并自检覆盖。
- 基线：`tests/fixtures/replay/baseline.json`，记录模型名/版本、夹具指纹与逐图指标；
  只保存确定性字段（不含 event_id、created_at 等运行时值），因此可跨机器复现。
- 回放使用独立临时数据目录，不写生产 SQLite/证据；耗时只记录（可用 `--max-ms` 设为门槛）。
- 夹具内容被改动会单独报"指纹不同"，避免把夹具变更误判为模型漂移。
- mock 模式的随机性只由 `request_id + 栏舍 + 图片指纹（文件名/字节数/内容摘要）`决定，
  不含完整路径，保证基线与门槛在任意机器、任意数据目录下一致。
- 在真实制品接入前，基线先在 mock 模式下锁定**闭环行为**（规则、连续帧确认、冷却合并、
  质量门、证据完整性）；拿到校准后的制品后，用同一套夹具重建基线即可切换到感知口径。

验收门槛：服务健康检查可用；模型制品缺失时 fail-closed；事件证据完整率 ≥ 95%；关键 API P95 ≤ 500 ms（不含模型推理）；日报与事件明细可相互追溯；人工确认状态在刷新和重启后保持；模型升级通过回放门槛。

## 11. 开发顺序

1. 冻结模型 manifest 和 `DetectionResult` 契约，整理 `model_runtime`。
2. 完成 `storage`、`state`、`risk` 和事件状态机，先用 MockDetector 回放。
3. 接入真实 DCR-SoftNMS-YOLOv13 制品，增加质量检查和证据图。
4. 完成 HTTP API、日报和最小看板。
5. 接入 App Adapter，完成移动端上传、查询和确认回写联调。
6. 按回放、契约、App 兼容性和 7 天稳定性门槛验收，再进入试点部署。

### 11.1 当前进度

- 第 1–4 步已完成：契约冻结、Agent 闭环、真实制品接入（ONNX 优先、`.pt` 回退）、
  HTTP API、日报与最小看板、目录轮询输入、回放门槛框架。
- 第 5 步部分完成：App 的 multipart 上传、幂等重试与结果查询接口已实现并通过契约测试；
  与真机 App 的联调（弱网重放、结果展示、确认回写）待现场验证。
- 第 6 步待办：7 天连续运行/10,000 张图片稳定性测试（需要真实制品与边缘主机），
  以及真实制品上的回放基线（当前基线为 mock 模式，用于锁定闭环行为）。
- 未完成项与责任人见 `docs/v1-gap-list.md`。
