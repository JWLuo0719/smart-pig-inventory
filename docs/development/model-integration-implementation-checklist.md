# 模型接入逐步实施清单

目标：按最小风险顺序完成模型接入。先以研究模式跑通真实模型链路，所有结果强制人工复核；通过许可证、金标回归和负责人批准后，再切换为生产自动计数。

## 阶段 1：确认当前产品推理链路可用

### 1.1 初始化本地环境

在仓库根目录执行：

```powershell
cd E:\pig\smart-pig-inventory
.\scripts\initialize-local-dev.ps1
```

检查 `.env` 至少有这些值：

```env
MYSQL_PASSWORD=<非空>
MYSQL_ROOT_PASSWORD=<非空>
MINIO_ROOT_PASSWORD=<非空>
SECURITY_ENABLED=false
COUNTING_PROVIDER=unavailable
INFERENCE_DISPATCHER_ENABLED=false
```

成功标准：

- `.env` 已生成。
- 密码类字段不是空字符串。
- 当前仍保持 `COUNTING_PROVIDER=unavailable`。

### 1.2 启动完整产品栈

```powershell
docker compose up --build
```

另开一个 PowerShell 检查：

```powershell
docker compose ps
curl http://localhost:8088/actuator/health
```

成功标准：

- `mysql`、`redis`、`minio`、`inference-api`、`inference-worker`、`business-api`、`admin-web`、`gateway` 都在运行。
- `http://localhost:8088/actuator/health` 返回健康。

如果失败：

- MySQL 失败：检查 `.env` 的 `MYSQL_PASSWORD` 和 `MYSQL_ROOT_PASSWORD`。
- MinIO 失败：检查 `MINIO_ROOT_PASSWORD`。
- Business API 失败：先看 `docker compose logs business-api`。

### 1.3 验证默认安全降级

进入 inference-api 容器执行：

```powershell
docker compose exec inference-api python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health/ready').read().decode())"
```

成功标准：

- 返回里包含 `"provider":"unavailable"`。
- 返回里包含 `"counting_available":false`。

这一步说明：没有准入模型时，系统不会伪造数量。

## 阶段 2：准备外部模型 Runner

### 2.1 在产品仓库外建立 Runner

建议不要放进 `E:\pig\smart-pig-inventory`。可以建到：

```powershell
mkdir E:\pig-model-runner
cd E:\pig-model-runner
```

推荐结构：

```text
E:\pig-model-runner
  app
    main.py
    contract.py
    storage.py
    model.py
    preprocessing.py
    postprocessing.py
  tests
    test_contract.py
    test_storage_checksum.py
    test_golden_regression.py
  Dockerfile
  requirements.txt
  README.md
```

成功标准：

- 模型代码、权重、第三方研究代码不进入产品仓库。
- Runner 是一个独立服务，只暴露 HTTP 接口。

### 2.2 实现 Runner 的三个接口

Runner 至少提供：

```text
GET  /health/live
GET  /health/ready
POST /v1/count
```

`GET /health/live` 返回：

```json
{"alive": true}
```

`GET /health/ready` 返回：

```json
{
  "ready": true,
  "model_key": "pig-yolo-research",
  "model_version": "research-2026-08-29",
  "model_checksum": "sha256:<权重checksum>",
  "adapter_version": "http-v1"
}
```

`POST /v1/count` 接收产品侧 `CountingJobRequest`，返回 `CountingJobResult`。

成功标准：

- Runner 启动后，浏览器或 curl 能访问 `/health/ready`。
- `/health/ready` 能明确返回模型身份。

### 2.3 实现请求解析

Runner 的 `/v1/count` 要按下面顺序处理：

1. 解析 `job_id`。
2. 读取 `correlation_id`。
3. 读取 `capture_kind`。
4. 读取 `media` 列表。
5. 读取 `requested_model`。
6. 校验 `media` 数量：单图为 1，三视图最多 3。
7. 校验每个 `sha256` 是 64 位小写 hex。
8. 校验 `object_uri` 以 `s3://` 开头。
9. 记录结构化日志，不记录凭据和完整签名 URL。

成功标准：

- 缺字段时返回明确 4xx。
- 字段合法时进入图片读取阶段。

### 2.4 实现对象存储读取

Runner 根据 `object_uri` 下载图片：

```text
s3://pig-inventory/path/to/object.jpg
```

处理规则：

1. 解析 bucket 和 object key。
2. 用只读 MinIO/S3 凭据读取对象。
3. 计算下载内容 SHA-256。
4. 与请求里的 `sha256` 比较。
5. 不一致时返回失败结果。

checksum 不一致时建议返回：

```json
{
  "status": "failed",
  "count": null,
  "detections": [],
  "warnings": [],
  "model_key": "pig-yolo-research",
  "model_version": "research-2026-08-29",
  "model_checksum": "sha256:<权重checksum>",
  "adapter_version": "http-v1",
  "inference_source": "external-runner",
  "latency_ms": 0,
  "failure_code": "MEDIA_CHECKSUM_MISMATCH",
  "failure_message": "Downloaded media checksum does not match request sha256"
}
```

成功标准：

- 能读取 MinIO/S3 私有对象。
- checksum 对不上时不会继续推理。

### 2.5 实现预处理

每张图按以下顺序处理：

1. 解码图片。
2. 处理 EXIF 方向。
3. 如果有 ROI，按归一化坐标裁剪。
4. 转成模型需要的尺寸、颜色通道和 tensor 格式。
5. 记录原图尺寸、裁剪区域和推理输入尺寸。

成功标准：

- ROI 为 null 时使用整图。
- ROI 超出范围时返回 `review_required` 或 4xx，不静默修正。

### 2.6 实现模型推理

推理过程建议：

1. 服务启动时加载权重。
2. 启动时计算并校验权重 checksum。
3. 请求进入时只执行前向推理，不重复加载模型。
4. 设置置信度阈值。
5. 执行 NMS 或使用模型框架内置 NMS。
6. 只保留猪只类别。

成功标准：

- `/health/ready` 只有在模型加载成功后才返回 `ready=true`。
- 单张图片能稳定返回 detections。
- 推理失败时返回 `failed`，不要让进程直接崩溃。

### 2.7 实现后处理和结果生成

研究阶段建议一律返回人工复核：

```json
{
  "status": "review_required",
  "count": null,
  "detections": [
    {
      "asset_id": "<请求中的asset_id>",
      "bbox": [0.1, 0.2, 0.3, 0.4],
      "confidence": 0.91,
      "class_id": 0
    }
  ],
  "warnings": ["Research model output requires manual review"],
  "model_key": "pig-yolo-research",
  "model_version": "research-2026-08-29",
  "model_checksum": "sha256:<权重checksum>",
  "adapter_version": "http-v1",
  "inference_source": "external-runner",
  "latency_ms": 420,
  "failure_code": null,
  "failure_message": null
}
```

生产准入后，只有在高置信、质量合格、规则明确时才返回：

```json
{
  "status": "succeeded",
  "count": 12,
  "detections": [],
  "warnings": [],
  "model_key": "pig-yolo-approved",
  "model_version": "approved-2026-xx",
  "model_checksum": "sha256:<准入权重checksum>",
  "adapter_version": "http-v1",
  "inference_source": "external-runner",
  "latency_ms": 420,
  "failure_code": null,
  "failure_message": null
}
```

成功标准：

- `succeeded` 必须有 `count`。
- `review_required` 和 `failed` 必须 `count=null`。
- bbox 坐标统一为归一化 `[x1, y1, x2, y2]`。

## 阶段 3：让产品侧接入研究 Runner

### 3.1 配置 `.env`

在 `E:\pig\smart-pig-inventory\.env` 设置：

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

说明：

- Runner 如果跑在本机 Windows 上，Docker 容器访问它通常用 `host.docker.internal`。
- Runner 如果也在 Compose 网络里，改成 `http://model-runner:9000/v1/count`。
- 研究模式下 `MODEL_APPROVED` 必须保持 `false`。

成功标准：

- `.env` 保存后不提交到 Git。
- callback token 非空，并且长度足够。

### 3.2 重启产品栈

```powershell
cd E:\pig\smart-pig-inventory
docker compose down
docker compose -f docker-compose.yml -f docker-compose.runner-local.yml up --build
```

检查 Provider：

```powershell
docker compose exec inference-api python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health/ready').read().decode())"
```

成功标准：

- 返回 `"provider":"research-http-yolo"`。
- 返回 `"counting_available":true`。

如果仍是 `unavailable`：

- 检查 `COUNTING_PROVIDER=research-http-yolo`。
- 检查 `MODEL_RESEARCH_ENABLED=true`。
- 检查 `YOLO_HTTP_ENDPOINT` 非空。
- 重启 `inference-api` 和 `inference-worker`。

### 3.3 验证 Runner 可从容器访问

```powershell
docker compose exec inference-api python -c "import urllib.request; print(urllib.request.urlopen('http://host.docker.internal:9000/health/ready').read().decode())"
```

成功标准：

- inference-api 容器内能访问 Runner ready 接口。

如果失败：

- Runner 是否已启动。
- Runner 是否监听 `0.0.0.0`，不是只监听 `127.0.0.1`。
- Windows 防火墙是否拦截。
- URL 端口是否正确。

### 3.4 让本机 Runner 访问 MinIO

A 方案中 Runner 跑在 Windows 主机上，产品 MinIO 跑在 Docker Compose 内。需要使用本地 override 暴露 MinIO 端口。注意 Runner 自己占用 `9000`，所以 MinIO 暴露到主机 `9100`：

```powershell
cd E:\pig\smart-pig-inventory
docker compose -f docker-compose.yml -f docker-compose.runner-local.yml up --build
```

然后在 `E:\pig-model-runner\.env` 填入和产品 `.env` 一致的 MinIO 账号：

```env
S3_ENDPOINT_URL=http://localhost:9100
S3_ACCESS_KEY_ID=<MINIO_ROOT_USER>
S3_SECRET_ACCESS_KEY=<MINIO_ROOT_PASSWORD>
S3_REGION=us-east-1
```

成功标准：

- Windows 主机可以访问 `http://localhost:9100/minio/health/live`。
- Runner 能用 `s3://pig-inventory/...` 下载产品上传的图片。

## 阶段 4：跑通一次真实端到端

### 4.1 准备一组真实采集数据

可以通过 Flutter App 采集，也可以用已有上传测试路径。至少准备：

- 单图采集包 1 组。
- 三视图采集包 1 组。
- 每张图都能成功上传到 MinIO。

成功标准：

- 上传包 Commit 成功。
- Business API 创建推理任务。

### 4.2 观察 Spring Outbox

查看 business-api 日志：

```powershell
docker compose logs -f business-api
```

成功标准：

- 能看到上传 Commit。
- 能看到推理任务派发或回调处理。

如果没有派发：

- 检查 `INFERENCE_DISPATCHER_ENABLED=true`。
- 检查上传包是否真的 Commit。
- 检查业务状态是否停在待提交或上传失败。

### 4.3 观察 inference-worker

```powershell
docker compose logs -f inference-worker
```

成功标准：

- Worker 收到 `inference.count` 任务。
- Worker 调用了 Runner。
- Worker 执行了回调。

如果 Worker 没反应：

- 检查 Redis 是否健康。
- 检查 inference-api 是否成功入队。
- 检查 Celery worker 是否启动。

### 4.4 观察 Runner

查看 Runner 日志，确认：

- 收到 `/v1/count` 请求。
- `job_id` 与产品侧一致。
- 成功读取对象存储图片。
- checksum 校验通过。
- 输出 detections 和 warnings。
- 返回 `review_required`。

成功标准：

- 研究模式下 Runner 即使检测成功，也不让业务形成最终自动数量。

### 4.5 验证业务回调结果

查看 business-api 日志：

```powershell
docker compose logs business-api
```

成功标准：

- 回调 HTTP 204 或 200。
- 业务会话进入 `review_required`。
- 管理端能看到待复核任务。

如果回调 401/403：

- `INFERENCE_CALLBACK_TOKEN` 在 business-api、inference-api、inference-worker 是否一致。

如果回调 409：

- 同一 `job_id` 返回了不同结果。
- 检查 Runner 是否每次返回不同 warnings、latency 或 detections 顺序导致 fingerprint 改变。

## 阶段 5：把研究结果显示给复核员

### 5.1 管理端展示内容

管理端复核页需要能看到：

- 原始采集图片。
- 检测框。
- 置信度。
- 模型版本。
- 权重 checksum。
- warnings。
- 失败原因。
- 人工确认/修正入口。

成功标准：

- 复核员可以基于图片和模型证据确认数量。
- 页面不暴露 MinIO/S3 原始对象 URL。

### 5.2 移动端展示内容

移动端至少展示：

- 已提交。
- 等待处理。
- 需要复核。
- 已确认。
- 失败需重试或联系管理员。

成功标准：

- 移动端不显示未经确认的模型自动数量。
- 断网恢复后状态能刷新。

## 阶段 6：补齐测试

### 6.1 Python inference-service 测试

```powershell
cd E:\pig\smart-pig-inventory\services\inference-service
python -m pip install -r requirements.txt
python -m pytest
```

必须覆盖：

- 默认 `UnavailableCountingProvider` 返回 `review_required`。
- `research-http-yolo` 强制人工复核。
- `http-yolo` 在 approved 时透传成功结果。
- Runner 超时会产生可审计失败或重试。
- 回调失败会重试。

### 6.2 Spring business-api 测试

```powershell
cd E:\pig\smart-pig-inventory\services\business-api
mvn test
```

必须覆盖：

- Outbox 派发。
- 回调鉴权。
- 回调幂等。
- 不同结果重复回调冲突。
- 三视图未准入时强制复核。
- 人工确认写审计。

### 6.3 Runner 测试

在 Runner 仓库执行自己的测试，至少覆盖：

- 合同字段校验。
- MinIO/S3 下载。
- checksum mismatch。
- ROI 裁剪。
- 模糊图。
- 空栏图。
- 遮挡图。
- 单图。
- 三视图。
- 金标集回归。

成功标准：

- 三边测试都通过后，才进入准入评审。

## 阶段 7：生产准入前门禁

不要急着开 `MODEL_APPROVED=true`。先完成：

1. 许可证确认：模型代码和权重允许当前使用方式。
2. 权重确认：记录 `MODEL_CHECKSUM`。
3. 镜像确认：记录 Runner 镜像 digest。
4. 金标确认：数据来源、授权、版本、划分清楚。
5. 指标确认：计数误差、漏检率、误检率、复核率达标。
6. 异常确认：低质量、遮挡、重复、空栏不会给错误自动数量。
7. 审计确认：模型身份、结果、人工修正都有记录。
8. 回滚确认：切回 `unavailable` 后上传和人工复核仍可用。
9. 负责人确认：产品、技术、运营至少完成记录。

成功标准：

- 准入材料归档在 `docs/research/` 或 `docs/deployment/`。
- 真实图片、权重、第三方源码不进入产品 Git。

## 阶段 8：切换生产候选 Provider

只有阶段 7 完成后，才修改 `.env`：

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
MULTIVIEW_AUTO_COUNT_ENABLED=false
```

重启：

```powershell
docker compose down
docker compose up --build
```

检查：

```powershell
docker compose exec inference-api python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health/ready').read().decode())"
```

成功标准：

- Provider 为 `http-yolo`。
- 单图准入范围内可以返回 `succeeded + count`。
- 三视图仍然进入人工复核，除非额外完成三视图准入。

## 阶段 9：三视图自动计数单独准入

如果要开启三视图自动计数，必须额外完成：

- 左/中/右视角金标集。
- 跨视角重复猪只去重规则。
- 三视图缺图、错位、遮挡处理规则。
- 三视图人工复核抽检。
- Spring 降级规则复验。

完成后才设置：

```env
MULTIVIEW_AUTO_COUNT_ENABLED=true
```

成功标准：

- 三视图 `succeeded` 结果才会被业务 API 接受为自动数量。
- 不确定场景仍返回 `review_required`。

## 阶段 10：上线后监控与回滚

上线后至少监控：

- Runner 请求量。
- 推理平均耗时和 P95 耗时。
- Runner 失败率。
- `review_required` 比例。
- 人工修正幅度。
- checksum mismatch 次数。
- 回调失败和重试次数。
- GPU 显存和温度。

快速回滚方式：

```env
COUNTING_PROVIDER=unavailable
MODEL_APPROVED=false
```

然后重启 inference 服务：

```powershell
docker compose up --build inference-api inference-worker
```

成功标准：

- 回滚后不再调用模型。
- 新任务进入人工复核。
- 上传、查看、人工确认仍可用。

## 最短执行路线

如果只想先跑通第一版，按这个顺序做：

1. 保持 `unavailable`，启动 Compose，确认健康。
2. 在产品仓库外启动 Runner，完成 `/health/ready`。
3. 实现 Runner `/v1/count`，先返回固定 `review_required`。
4. 配置 `research-http-yolo`，让 inference-service 能调到 Runner。
5. 让 Runner 读取 MinIO/S3 图片并校验 SHA-256。
6. 接入真实模型，返回 detections。
7. 跑一次 Commit -> Outbox -> Worker -> Runner -> Callback。
8. 管理端确认能看到待复核结果。
9. 补测试和金标回归。
10. 准入通过后再切 `http-yolo`。

## 一键启动脚本

本地 A 方案已经提供一键脚本：

```powershell
cd E:\pig\smart-pig-inventory
.\scripts\start-local-yolo-stack.cmd
```

它会自动：

- 检查 Docker 是否可用。
- 检查并启动 `E:\pig-model-runner`。
- 用 `docker-compose.runner-local.yml` 启动产品后台。
- 等待 Runner、网关和 MinIO 健康。
- 验证 `inference-api` 容器能访问 Runner。

停止本地栈：

```powershell
cd E:\pig\smart-pig-inventory
.\scripts\stop-local-yolo-stack.cmd
```

使用 `.cmd` 入口可以绕过 PowerShell 默认脚本执行策略限制。
