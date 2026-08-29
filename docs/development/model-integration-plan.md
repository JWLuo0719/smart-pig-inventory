# 模型接入框架与实施步骤

状态：实施指南  
适用范围：`services/inference-service`、外部模型 Runner、`services/business-api`、Compose/试点部署  
原则：先跑通隔离研究链路，再进入生产准入；未验收模型一律只给人工复核证据，不自动写入盘点数量。

## 1. 接入目标

本项目的模型接入不是把 YOLO 或训练代码直接放进业务系统，而是建立一条可审计、可降级、可替换的推理链路：

```text
Flutter/管理端采集证据
  -> Spring business-api 生成盘点会话与推理任务
  -> 事务 Outbox 派发 CountingJobRequest
  -> Python inference-service 接收任务并入 Celery
  -> CountingProvider 调独立模型 Runner
  -> Runner 返回 CountingJobResult
  -> inference-service 回调 business-api
  -> business-api 保存结果、触发人工复核或确认
```

最终需要达到：

- 模型权重、训练代码、第三方研究仓库不进入产品 Git 与业务 API 镜像。
- 模型服务只通过版本化 HTTP 合同交互。
- 每次结果保存 `model_key`、`model_version`、`model_checksum`、`adapter_version`、`inference_source`。
- 未通过准入门禁时，结果必须是 `review_required` 且 `count = null`。
- 回调幂等：同一 `job_id` 相同结果可重放，不同结果冲突。

## 2. 模块分工

| 模块 | 责任 | 不允许做的事 |
|---|---|---|
| `services/business-api` | 业务状态、权限、上传提交、事务 Outbox、推理结果落库、人工确认、审计 | 不加载模型、不跑训练、不让模型直写 MySQL |
| `services/inference-service` | 推理合同入口、Celery 队列、Provider 选择、安全降级、结果回调 | 不决定最终业务口径、不保存权限状态 |
| 外部模型 Runner | 加载权重、读取对象存储图片、执行检测/计数、返回标准结果 | 不访问业务库、不伪造回调、不绕过复核 |
| MinIO/S3 | 保存采集媒体证据 | 不公开桶、不长期暴露签名 URL |
| 管理端/移动端 | 展示任务、媒体、模型证据和复核状态 | 不展示未经业务 API 确认的最终数量 |

## 3. 合同框架

### 3.1 请求合同

外部模型 Runner 必须接受 `CountingJobRequest` JSON。以 `contracts/inference-job.schema.json` 为准，核心字段如下：

```json
{
  "job_id": "uuid",
  "correlation_id": "trace-id",
  "organization_id": "uuid",
  "capture_set_id": "uuid",
  "capture_kind": "single | left_center_right",
  "media": [
    {
      "asset_id": "uuid",
      "view_position": "single | left | center | right",
      "object_uri": "s3://bucket/key",
      "sha256": "64位小写hex",
      "roi": {"x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8}
    }
  ],
  "requested_model": {
    "model_key": "pig-yolo",
    "version": "2026-08-xx",
    "checksum": "sha256:...",
    "adapter_version": "http-v1"
  }
}
```

Runner 需要做的校验：

- `job_id`、`asset_id` 必须是 UUID。
- `sha256` 必须与下载到的对象内容一致。
- `capture_kind=single` 时只接受单图；`left_center_right` 时按左/中/右三视图处理。
- `roi` 坐标是 0 到 1 的归一化比例；没有 ROI 时使用整图。
- 日志只能记录对象键摘要、job_id、模型版本、耗时和错误码，不能记录凭据、完整签名 URL 或原图内容。

### 3.2 结果合同

外部 Runner 必须返回 `CountingJobResult` JSON。以 `contracts/inference-result.schema.json` 为准：

```json
{
  "status": "succeeded | review_required | failed",
  "count": 12,
  "detections": [
    {
      "asset_id": "uuid",
      "bbox": [0.12, 0.2, 0.34, 0.48],
      "confidence": 0.91,
      "class_id": 0
    }
  ],
  "warnings": [],
  "model_key": "pig-yolo",
  "model_version": "2026-08-xx",
  "model_checksum": "sha256:...",
  "adapter_version": "http-v1",
  "inference_source": "external-runner",
  "latency_ms": 420,
  "failure_code": null,
  "failure_message": null
}
```

结果规则：

- `succeeded` 必须有非负整数 `count`。
- `review_required` 和 `failed` 必须是 `count = null`。
- `bbox` 建议统一为归一化 `[x1, y1, x2, y2]`，范围 0 到 1；如果 Runner 内部使用像素坐标，要在适配层转换。
- 低置信度、严重遮挡、三视图不一致、图片质量差、重复疑似、模型版本未准入时返回 `review_required`。
- 模型异常、图片无法读取、checksum 不匹配、合同字段错误时返回 `failed` 或明确的 4xx/5xx，由 `inference-service` 包装为可审计失败结果。

## 4. Provider 选择策略

当前产品侧已有三个 Provider：

| Provider | 环境变量 | 用途 |
|---|---|---|
| `unavailable` | 默认 | 无模型或配置不完整时返回人工复核，不生成数量 |
| `research-http-yolo` | `COUNTING_PROVIDER=research-http-yolo` 且 `MODEL_RESEARCH_ENABLED=true` | 隔离研究链路；即使 Runner 返回成功，也会强制改成 `review_required` |
| `http-yolo` | `COUNTING_PROVIDER=http-yolo` 且 `MODEL_APPROVED=true` | 生产候选；只有准入通过后允许自动计数 |

推荐推进顺序：

1. 本地先保持 `unavailable`，确认上传、Outbox、回调、人工复核闭环稳定。
2. 部署外部 Runner 后切到 `research-http-yolo`，验证真实模型能读图、检测、返回证据，但业务仍强制复核。
3. 完成许可证、金标集、回归、人工验收和负责人批准后，再切到 `http-yolo`。
4. 三视图自动计数还需要额外开启 `MULTIVIEW_AUTO_COUNT_ENABLED=true`；否则 Spring 会把三视图成功结果降级为人工复核。

## 5. 外部模型 Runner 框架

Runner 可以单独建仓或部署在产品仓库外部目录，建议结构：

```text
model-runner/
  app/
    main.py                 # FastAPI 入口
    contract.py             # CountingJobRequest/Result DTO
    storage.py              # S3/MinIO 只读下载与 sha256 校验
    preprocessing.py        # ROI 裁剪、尺寸归一化、EXIF/颜色处理
    model.py                # 权重加载与推理
    postprocessing.py       # NMS、置信度过滤、bbox 归一化、计数聚合
    health.py               # live/ready，暴露模型身份
  tests/
    test_contract.py
    test_storage_checksum.py
    test_golden_regression.py
  Dockerfile
  requirements.txt
```

Runner 推荐接口：

```text
GET  /health/live
GET  /health/ready
POST /v1/count
```

`YOLO_HTTP_ENDPOINT` 应配置到 `POST /v1/count`。例如：

```env
YOLO_HTTP_ENDPOINT=http://model-runner:9000/v1/count
```

Runner 运行要求：

- 启动时加载权重并计算 checksum，ready 接口返回模型身份。
- 使用只读对象存储凭据；权限限制到需要读取的桶或前缀。
- 下载媒体后计算 SHA-256，对不上立即失败。
- GPU 不可用、显存不足或模型加载失败时 ready 返回不可用，不要半健康运行。
- 每个请求输出结构化日志：`job_id`、`correlation_id`、`model_key`、`version`、`latency_ms`、`status`、`warning_count`。

## 6. 详细实施步骤

### 第 0 步：准备准入材料

完成模型接入前先准备以下材料：

- 模型来源、许可证、是否允许商业/现场/网络服务使用的书面结论。
- 权重文件 checksum，例如 `sha256:<hex>`。
- 模型版本命名规则，例如 `pig-yolo-nano-2026-08-29`。
- 金标测试集：图片、标注、栏舍/视角元数据、授权说明。
- 验收指标：计数误差、漏检/误检、人工复核触发率、低质量图片处理规则。
- 部署资源：CPU/GPU、内存、显存、磁盘、网络、对象存储访问方式。

未完成这些材料时，只允许接入 `research-http-yolo`。

### 第 1 步：固定模型 HTTP 合同

确认 Runner 的请求和响应完全兼容：

- 请求字段使用 snake_case，与 `CountingJobRequest` 一致。
- 响应字段使用 snake_case，与 `CountingJobResult` 一致。
- Java 回调侧由 `inference-service` 转换为 camelCase，不需要 Runner 关心。
- 用 `contracts/inference-job.schema.json` 和 `contracts/inference-result.schema.json` 做合同测试。

如果现有模型接口不是这个格式，优先在 Runner 内加适配层，不改业务 API。

### 第 2 步：实现或接入 Runner

Runner 的最小可用流程：

1. 接收 `CountingJobRequest`。
2. 遍历 `media`，按 `object_uri` 下载图片。
3. 校验每张图的 SHA-256。
4. 应用 ROI。
5. 调模型推理。
6. 将检测框转换为归一化坐标。
7. 根据置信度、遮挡、重复和多视图规则生成 `count` 或 `review_required`。
8. 返回 `CountingJobResult`。

研究阶段建议先返回：

- 模型可正常检测且证据可用：`status=review_required`、`count=null`、`detections=[...]`。
- 无法读取图片或 checksum 不符：`status=failed`、`failure_code=MEDIA_CHECKSUM_MISMATCH` 或 `MEDIA_READ_FAILED`。
- 图片质量差：`status=review_required`、`warnings=["LOW_IMAGE_QUALITY"]`。

### 第 3 步：配置产品侧推理服务

本地研究链路 `.env` 示例：

```env
COUNTING_PROVIDER=research-http-yolo
MODEL_RESEARCH_ENABLED=true
MODEL_APPROVED=false
YOLO_HTTP_ENDPOINT=http://host.docker.internal:9000/v1/count
MODEL_KEY=pig-yolo-research
MODEL_VERSION=research-2026-08-29
MODEL_CHECKSUM=sha256:<权重checksum>
MODEL_ADAPTER_VERSION=http-v1
INFERENCE_DISPATCHER_ENABLED=true
INFERENCE_CALLBACK_TOKEN=<随机长密钥>
MULTIVIEW_AUTO_COUNT_ENABLED=false
```

生产候选链路示例：

```env
COUNTING_PROVIDER=http-yolo
MODEL_RESEARCH_ENABLED=false
MODEL_APPROVED=true
YOLO_HTTP_ENDPOINT=http://model-runner:9000/v1/count
MODEL_KEY=pig-yolo-approved
MODEL_VERSION=approved-2026-xx
MODEL_CHECKSUM=sha256:<准入权重checksum>
MODEL_ADAPTER_VERSION=http-v1
INFERENCE_DISPATCHER_ENABLED=true
INFERENCE_CALLBACK_TOKEN=<随机长密钥>
MULTIVIEW_AUTO_COUNT_ENABLED=false
```

注意：

- `INFERENCE_CALLBACK_TOKEN` 必须在 `business-api`、`inference-api`、`inference-worker` 三处一致。
- `MODEL_APPROVED=true` 只能在准入完成后设置。
- 三视图自动计数单独审批；没有三视图金标证据时保持 `MULTIVIEW_AUTO_COUNT_ENABLED=false`。

### 第 4 步：启动并检查基础链路

```powershell
.\scripts\initialize-local-dev.ps1
docker compose up --build
```

健康检查：

```powershell
curl http://localhost:8088/actuator/health
curl http://localhost:8100/health/ready
```

如果通过网关没有暴露推理服务端口，可在 Docker 网络内查看：

```powershell
docker compose exec inference-api python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health/ready').read().decode())"
```

期望：

- `provider=research-http-yolo` 或 `provider=http-yolo`。
- `counting_available=true`。
- Worker 日志能看到任务执行。
- Business API 日志能看到回调成功，HTTP 204 或 200。

### 第 5 步：跑通端到端任务

端到端路径必须覆盖：

1. 移动端或测试脚本创建上传包。
2. 上传 blob 到 MinIO。
3. 提交 manifest。
4. Commit 成功后 Spring 生成推理 job 和 outbox event。
5. Dispatcher 投递到 `inference-service`。
6. Celery Worker 调 Runner。
7. Runner 返回结果。
8. `inference-service` 回调 `/api/v1/inference-jobs/{jobId}/result`。
9. Spring 保存结果和回调 receipt。
10. 管理端/移动端看到 `review_required` 或可确认结果。

关键观察点：

- `inference_jobs` 状态从 `submitted/processing` 到终态。
- `inference_results` 保存模型身份、detections、warnings。
- 相同回调重放返回成功。
- 不同 payload 的重复回调返回冲突。
- Runner 失败时业务侧仍有可审计失败结果，不丢任务。

### 第 6 步：补齐自动化测试

Python 侧：

```powershell
cd services\inference-service
python -m pip install -r requirements.txt
python -m pytest
```

需要覆盖：

- `UnavailableCountingProvider` 不生成数量。
- `ResearchHttpYoloCountingProvider` 强制 `review_required`。
- `HttpYoloCountingProvider` 正确透传成功结果。
- Runner 500、超时、非法 JSON 会被包装为 `failed` 或触发重试。
- JSON Schema 与 Pydantic DTO 字段不漂移。

Spring 侧：

```powershell
cd services\business-api
mvn test
```

需要覆盖：

- Dispatcher 租约、重试和发布状态。
- 回调 token 校验。
- 回调结果幂等。
- 三视图未开关时自动降级复核。
- 结果落库后人工确认、媒体锁定和审计。

Runner 侧：

- 金标集回归。
- checksum mismatch。
- ROI 裁剪。
- 单图和三视图。
- 空圈、遮挡、模糊、重复猪只、强反光、低照度。

### 第 7 步：金标回归与模型准入

从 `research-http-yolo` 升级到 `http-yolo` 前，至少完成：

- 许可证允许当前使用方式。
- 权重 checksum 和镜像 digest 已记录。
- 金标集来源、授权、版本和划分方式已记录。
- 计数指标达到验收线。
- 低质量图片不会输出错误自动数量，而是进入人工复核。
- 三视图场景没有独立证据时不启用自动计数。
- 管理端可查看原图、检测框、warning 和模型身份。
- 运维负责人、产品负责人、技术负责人签字或在项目记录中确认。

准入记录建议保存到 `docs/research/` 或 `docs/deployment/`，不要保存真实媒体和权重。

### 第 8 步：生产/试点部署

试点部署建议：

- Runner 独立容器或独立主机部署，与业务 API 只通过内网 HTTP 通信。
- MinIO/S3 使用只读凭据给 Runner。
- 所有服务开启结构化日志和 correlation id。
- Runner 暴露 Prometheus 指标或至少输出可采集日志：QPS、延迟、失败率、复核率、GPU 显存。
- 模型镜像固定 digest，不使用浮动 latest。
- 回滚只需要把 `COUNTING_PROVIDER` 改回 `unavailable` 或 `research-http-yolo`，并重启 inference 服务。

## 7. 验收清单

接入完成必须逐项打勾：

- [ ] Runner 合同测试通过。
- [ ] Runner 能读取 MinIO/S3 私有对象并校验 SHA-256。
- [ ] `unavailable`、`research-http-yolo`、`http-yolo` 三种 Provider 行为明确。
- [ ] 研究模式下不会写入自动数量。
- [ ] 生产模式必须依赖 `MODEL_APPROVED=true`。
- [ ] Spring 回调 token 配置一致。
- [ ] 回调幂等和冲突测试通过。
- [ ] 三视图自动计数默认关闭。
- [ ] 模型身份完整落库。
- [ ] 管理端可看到检测证据和人工复核入口。
- [ ] 金标回归报告已归档。
- [ ] 许可证、权重 checksum、部署镜像 digest 已归档。
- [ ] 出现模型故障时能降级到人工复核，不阻塞上传闭环。

## 8. 常见问题排查

| 现象 | 优先检查 |
|---|---|
| `/health/ready` 显示 `provider=unavailable` | `COUNTING_PROVIDER`、`MODEL_RESEARCH_ENABLED`、`MODEL_APPROVED`、`YOLO_HTTP_ENDPOINT` 是否同时满足条件 |
| Commit 后没有推理任务 | `INFERENCE_DISPATCHER_ENABLED` 是否为 `true`，Spring outbox 表是否有待派发事件 |
| Worker 没有执行 | Redis URL、Celery worker 是否启动、任务名是否为 `inference.count` |
| Runner 收不到请求 | `YOLO_HTTP_ENDPOINT` 是否从容器内可访问；本机服务可用 `host.docker.internal` |
| 回调 401/403 | `INFERENCE_CALLBACK_TOKEN` 在 Spring 与 Python 是否一致 |
| 回调 409 | 同一 `job_id` 已保存不同 fingerprint 的最终结果；检查 Runner 是否非确定性返回 |
| 三视图结果仍是复核 | `MULTIVIEW_AUTO_COUNT_ENABLED=false` 时这是预期行为 |
| 图片读取失败 | Runner 的对象存储 endpoint、bucket、只读凭据、网络和 `object_uri` 解析 |
| checksum mismatch | 上传链路、对象读取模式、图片转码或 Runner 是否错误读取了缩略图 |

## 9. 推荐里程碑

| 里程碑 | 完成标准 |
|---|---|
| M1 合同跑通 | 手工请求 Runner 能返回合法 `CountingJobResult` |
| M2 研究链路 | Compose 下 `research-http-yolo` 完成 Commit -> Runner -> 回调 -> 人工复核 |
| M3 证据展示 | 管理端能展示原图、检测框、warning、模型身份 |
| M4 金标回归 | Runner 在授权金标集上达到指标并输出报告 |
| M5 生产准入 | 配置 `http-yolo`，自动计数只在批准范围内生效 |
| M6 试点稳定 | 弱网、重启、模型失败、回滚、审计全部通过 |

## 10. 当前项目建议

结合当前仓库状态，下一步优先做这三件事：

1. 把外部 Runner 的 `/v1/count` 合同固定下来，并用 JSON Schema 做测试。
2. 使用 `research-http-yolo` 在隔离 Compose 中重新跑一遍真实采集包端到端链路，确认检测框和 warnings 能进入业务结果。
3. 准备授权金标集和模型准入报告；没有这两项前，不要打开 `MODEL_APPROVED=true`。
