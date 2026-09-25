# 猪场智能运营 Agent

把 DCR-SoftNMS-YOLOv13 的可信计数能力包装成面向猪场的日常巡检与异常处置 Agent。

> **2026 需求重构进行中**：最新需求基线见 `docs/requirements-v2.md`（六条公理与冲突裁决），
> 最新设计方案见 `docs/product-design-v2.md`（三平面架构、领域模型、路线图 R0–R6）。
> 产品定位已从"单级 `barn_id` 的事件中心 Agent"调整为**以栏舍（猪圈）为原子单元的感知—决策—执行闭环**，
> 并纳入"每圈独立控制"的范围变更。文档权威关系见 `docs/README.md`。
> 下文"产品目标 / 三种输入方式 / 行为要点"描述的是**当前代码的 V1 现状**，与 V2 设计存在差距（见 `docs/product-design-v2.md` §6）。

## 产品目标

- **看得见**：从栏舍图片或视频帧识别猪只、计数并标注证据。
- **能判断**：结合密度、输入质量和历史趋势，输出风险等级、实际阈值与证据。
- **可执行**：给出巡检、通风、分群、设备检查等可落地建议，并保留人工确认入口。

## 快速开始

```powershell
cd pig-farm-agent
python -m pig_farm_agent.server
```

服务默认监听 `http://127.0.0.1:8787`（`PIG_AGENT_HOST` / `PIG_AGENT_PORT` 可改），
浏览器打开 `http://127.0.0.1:8787/` 即为 Web 看板（事件流 / 日报 / 上传分析）。

```powershell
# 健康检查（服务、模型制品、存储与写保护状态）
curl http://127.0.0.1:8787/health

# 提交一次分析（JSON 元数据；当前为 mock 模式，可不带图片）
curl -X POST http://127.0.0.1:8787/analyze -H "Content-Type: application/json" -d "{\"barn_id\":\"A01\"}"

# App 风格上传（multipart，client_request_id 幂等）
curl -X POST http://127.0.0.1:8787/v1/mobile/analyze -F barn_id=A01 -F client_request_id=req-001 -F image=@barn.jpg

# 查询事件 / 查询请求结果
curl "http://127.0.0.1:8787/events?barn_id=A01&status=open"
curl http://127.0.0.1:8787/v1/mobile/requests/req-001

# 人工确认与关闭
curl -X POST http://127.0.0.1:8787/events/<event_id>/ack -d "{\"operator\":\"vet-li\",\"note\":\"已复核\"}"
curl -X POST http://127.0.0.1:8787/events/<event_id>/resolve -d "{}"

# 日报（JSON 与 CSV）
curl "http://127.0.0.1:8787/report/daily?date=2026-09-16"
curl -o daily.csv "http://127.0.0.1:8787/report/daily.csv?date=2026-09-16"

# 模型升级门槛摘要（回放基线状态）
curl http://127.0.0.1:8787/model/replay

# 证据回放（事件 evidence 块中的相对路径）
curl http://127.0.0.1:8787/files/evidence/<event_id>.json

# 运行测试
python -m pytest tests
```

## 三种输入方式

| 输入 | 用法 | 说明 |
|---|---|---|
| 手工上传 | 看板"上传分析"页 / `POST /v1/mobile/analyze` | App 与 Web 共用同一接口，`client_request_id` 幂等 |
| 目录轮询 | `python -m pig_farm_agent.poller`（或配置 `polling.enabled=true` 随服务启动） | 摄像头按周期写入 `data/polling/<栏舍ID>/`，自动分析并归档 |
| 定时快照 | 同目录轮询，`--once` 配合系统计划任务 | 定时任务里跑一轮，适合低频快照 |

目录轮询的来源可追溯：`source=polling`，`state.source_device` 记录设备号
（侧车 `.json` 的 `device_id` > `--device` / `polling.device_id` > 栏舍名），
`captured_at` 优先取文件名里的时间戳（`20260916_083000` 等），其次侧车
`captured_at`，最后回退文件修改时间。处理完成的图片（连同侧车）移入
`_processed/<栏舍>/`，失败的移入 `_failed/<栏舍>/`；同一文件在相邻两轮扫描
间大小与 mtime 不变才处理，避免读到摄像头正在写入的半张图。

可选侧车文件（与图片同名 `.json`）：

```json
{"device_id": "cam-A01-03", "captured_at": "2026-09-16T08:30:00+08:00"}
```

## 模型升级门槛（回放测试）

模型升级必须先通过回放门槛：固定图片集上逐张跑完整链路，比较**候选数、计数、
质量状态、风险等级/代码**，任何差异都判失败（退出码 1）。

```powershell
# 1) 查看当前基线与覆盖
python -m pig_farm_agent.replay

# 2) 首次/重新生成基线（模型升级前必须先跑一遍留档）
python -m pig_farm_agent.replay --update-baseline

# 3) 换新制品后对比；可放宽计数容忍度、附加端到端耗时门槛
python -m pig_farm_agent.replay --tolerance 1 --max-ms 3000

# 4) 只跑检测器口径（快速区分是模型还是规则差异）
python -m pig_farm_agent.replay --mode detector
```

- 夹具：`tests/fixtures/replay/images/`（合成占位图，覆盖正常区间、`DENSITY_WATCH`、
  `DENSITY_HIGH`、`DATA_QUALITY_LOW` 与冷却合并；用现场脱敏图片替换后重新生成基线）。
- 基线：`tests/fixtures/replay/baseline.json`，含图片指纹，夹具内容被改动会单独报出。
- 重新生成夹具：`python tools/make_replay_fixtures.py --clean`（会自检风险通路覆盖）。

## 局域网部署与写保护

默认绑定 `127.0.0.1` 且写操作开放，适合单机试用。放到场内边缘主机时：

```powershell
$env:PIG_AGENT_HOST = "0.0.0.0"
$env:PIG_AGENT_API_TOKEN = "<自定义令牌>"
python -m pig_farm_agent.server
```

启用令牌后所有写接口（上传、确认、关闭、驳回）需要 `X-Api-Token` 请求头，
读取接口保持开放，便于放行只读看板；看板右上角 🔑 可填入并保存在本机浏览器。

## 与科研模型的连接

产品通过 `model_artifacts/<version>/manifest.json` 加载 DCR-SoftNMS-YOLOv13 制品（启动时做 SHA256 校验，失败即 fail-closed）。**真实模式优先加载制品目录中的 `model.onnx`（推荐，运行时只需 `onnxruntime`）**；没有 ONNX 时回退 `.pt` + ultralytics。DRRA 是科研阶段的历史架构名，不是产品模型名。

当前 `config.json` 默认 `mode=mock`（确定性 MockDetector，便于联调测试；其随机性只由
`request_id + 栏舍 + 图片指纹` 决定，不含完整路径，因此回放基线与结果可跨机器复现）。
切换真实模式：把 `model.model` 的 `mode` 改为 `"real"`，并在装有
`onnxruntime/numpy/pillow` 的环境运行（`pip install -e ".[real]"` 或使用 pig-agent conda 环境）。

说明：DCR 的 correctness rescorer 依赖科研侧关系模型的候选特征（p_duplicate 等），该制品尚未随目录导出。产品侧如实执行 manifest 冻结口径的线性 Soft-NMS，事件 model 块标注 `postprocess=onnx+linear-softnms` 并记录 manifest 声明的 score_mode 供追溯，不做静默冒充。从科研 `.pt` 重新导出 ONNX 的方法见 `model_artifacts/dcr-softnms-yolov13-v1/README.md`。

## 与 smart-pig-inventory App 的关系

现有 App 作为现场采集和快速复核端继续使用。**注意：App 仓库的实际上传合同是 4 步采集包
（create → blob → manifest → commit，全部带 `X-Idempotency-Key`，Bearer JWT，`/api/v1`），
不是本仓库文档里的单次 multipart**；本仓库的 `/v1/mobile/analyze` 是自带的轻量兼容层，
用于无 App 环境下的联调。实测探针显示本 Agent 对其合同 0/5 端点。

```powershell
# 契约探针：目标服务实现了 App 的哪些合同端点（只读）
python tools/run_app_replay.py --base http://127.0.0.1:8787 --probe-only

# 弱网重放：断网 / 超时 / 响应丢失 / 5xx / 401 过期 + 断点续传
python tools/run_app_replay.py --base https://<业务后端> --username <账号> --password <口令> \
    --profile all --packages 2 --report test-assets/app-replay-report.md

# 无环境自证（mock 上游，应 5/5 端点、全部不变量通过）
python tools/fake_upstream.py --port 8899
python tools/run_app_replay.py --base http://127.0.0.1:8899 --username demo --password demo-password-123 --profile all
```

字段级契约、App 的重试/续传语义、以及"Agent 做 App 后端"还是"Agent 做推理 Provider"
两条路径的取舍，见 `docs/app-integration-contract.md`；对真实 App（单次上传路径）的
App 风格兼容接口与幂等规则见 `docs/v1-technical-development.md`。

## 行为要点

- **风险规则可解释**：密度超阈值且连续 2 次观测成立才生成 `DENSITY_HIGH`/`DENSITY_WATCH`；实际阈值写入事件。
- **质量门**：输入模糊或覆盖率不足生成 `DATA_QUALITY_LOW`，抑制高风险结论。
- **冷却合并**：同栏舍同代码在冷却窗口内合并进未关闭事件，原始观测全部保留。
- **自动恢复**：连续 2 次观测回到正常区间后，系统自动 `resolved` 告警事件（可追溯审计）。
- **存储**：SQLite（事件/观测/审计/幂等表）+ JSONL 快照（`data/events.jsonl`），证据落盘 `data/evidence/`。
- **部署配置**：`PIG_AGENT_MODEL_DIR`、`PIG_AGENT_DATA_DIR`、`PIG_AGENT_HOST/PORT`、`PIG_AGENT_LOG_LEVEL`、`PIG_AGENT_WEIGHTS`、`PIG_AGENT_API_TOKEN`、`PIG_AGENT_POLLING_DEVICE`、`PIG_AGENT_CONFIG`。

## 验收与自检工具

```powershell
python -m pytest tests                                  # 单元与契约测试
python tools/smoke_server.py --base http://127.0.0.1:8787 --token <令牌>   # 端到端冒烟（32 项）
node tools/check_dashboard_js.mjs                       # 看板脚本语法 + 路由一致性
python -m pig_farm_agent.replay                         # 模型升级门槛
```

`tools/e2e-config.json` 是联调用的示例配置（开启轮询 + 写保护令牌 + 2 秒间隔），
用 `PIG_AGENT_CONFIG=tools/e2e-config.json` 启动即可复现"网关投图 → 自动分析 → 看板呈现"的链路；
令牌值仅供本机联调，实际部署请通过 `PIG_AGENT_API_TOKEN` 覆盖。

## 目录

- `pig_farm_agent/agent.py`：分析闭环编排（校验 → 检测 → 状态 → 风险 → 证据 → 持久化）
- `pig_farm_agent/server.py`：零依赖 HTTP API（含 multipart、统一错误格式、写保护、结构化日志）
- `pig_farm_agent/poller.py`：目录轮询输入（设备/时间可追溯、写完保护、失败隔离）
- `pig_farm_agent/replay.py`：回放测试框架与模型升级门槛
- `pig_farm_agent/models.py`：事件契约与状态机（open → acknowledged → resolved / dismissed）
- `pig_farm_agent/detector.py`：Detector 协议、manifest 校验、Mock/ONNX/Ultralytics 适配器
- `pig_farm_agent/state.py` / `risk.py`：状态计算与规则引擎
- `pig_farm_agent/storage.py` / `evidence.py` / `report.py`：存储、证据、日报
- `pig_farm_agent/static/index.html`：最小 Web 看板（单文件、零依赖）
- `pig_farm_agent/model_runtime/`：精简后的 DCR-SoftNMS 推理模块
- `config.json`：猪场、模型、风险规则、上传与轮询参数
- `tests/`：单元与契约测试；`tests/fixtures/replay/`：回放夹具与基线
- `tools/`：夹具生成、端到端冒烟、看板脚本检查、App 弱网重放与契约探针、mock 上游
- `docs/`：产品方向、开发规划、V1 技术开发文档、差距清单与 App 联调契约
