# 与 smart-pig-inventory App 的联调契约核对

本文记录 `D:\smart-pig-inventory`（App/业务后端仓库，Apache-2.0，`main` 分支）的**真实**接口契约，
以及它对本仓库 Agent 后端的影响。所有结论都来自阅读其源码/契约文件与实测，不来自推测。

- 上游仓库：https://github.com/JWLuo0719/smart-pig-inventory
- 契约权威：`contracts/openapi.yaml`（版本 0.8.0，`servers: - url: /api/v1`）
- 客户端实现：`apps/mobile/lib/features/outbox/application/upload_package_synchronizer.dart`、
  `apps/mobile/lib/core/network/upload_api.dart`
- 本仓库侧证据：`docs/app-contract-probe-agent.md`（探针报告，实测 0/5 端点）

## 1. 关键结论（先看这里）

1. **App 不调用本仓库的 `/v1/mobile/analyze`**。它的上传是 **4 步采集包合同**
   （create → blob → manifest → commit），写操作使用 `X-Idempotency-Key`，
   图片用 `X-Content-SHA256` 校验，认证是 **Bearer JWT**。
   本仓库 `docs/v1-technical-development.md` §1.1/§8 里那套"单次 multipart + `client_request_id`"
   是**本仓库自己设计的兼容层**，App 侧从未实现（实测探针 0/5）。
2. **App 的业务后端是 Spring Boot（`services/business-api`），不是本 Agent**。
   它的调用链是：Flutter → Spring（采集包/盘点/复核）→ 事务 Outbox → Python Celery Worker
   → 研究推理 Runner → 受服务密钥保护的回调写回 → 人工复核确认。
3. 因此"接进 App"有两种真实路径，且**互斥地决定本仓库的定位**：
   - **A. 本 Agent 做成 App 能直连的后端**：在本仓库实现 OpenAPI 的采集包 4 步 +
     `PUT /inference-jobs/{id}/result` 回调 + BFF 读接口（复核/任务/日报）。工作量大，
     且要复制其 UUID 主数据、JWT 身份、MinIO 级 blob 语义。
   - **B. 本 Agent 只做"模型/推理提供方"，挂在 App 的推理 Provider 契约后面**：
     只实现 `ResearchInferenceRequest` → `PUT /inference-jobs/{id}/result`
     （`contracts/inference-result.schema.json`），其余交给 Spring。
     这是与其现有架构一致的做法，也是**推荐路径**。
4. 无论哪条路径，**弱网重放脚本都不需要改**：它按 App 的真实合同说话，
   对着任意目标（本 Agent / Spring / mock 上游）都能跑，并直接报出差距
   （`docs/app-contract-probe-agent.md` 就是对本 Agent 的实测结果：0/5）。

## 2. 上传合同（字段级，摘自其 OpenAPI 与客户端源码）

### 2.1 四步

| 步骤 | 方法/路径 | 关键请求 | 成功码 | 重放语义 |
|---|---|---|---|---|
| 创建/恢复采集包 | `POST /upload-packages` | `X-Idempotency-Key` + `{clientPackageId, organizationId, penId, businessDate, captureKind}` | 201 新建 / 200 已存在 | 同键或同 `clientPackageId` 返回原包与 `existingAssets` |
| 查询采集包 | `GET /upload-packages/{packageId}` | Bearer | 200 | 返回 `state` 与 `existingAssets`（断点续传依据） |
| 上传照片 | `PUT /upload-packages/{packageId}/blobs/{assetId}` | `X-Content-SHA256`（64 位小写十六进制）、`application/octet-stream`、`Content-Length` | 201 新建 / 200 已存在且一致 | 同标识不同内容 → 409 |
| 提交清单 | `PUT /upload-packages/{packageId}/manifest` | `CaptureManifest` | 201 / 200 重放 | 校验组织/栏舍、blob 完整性、ROI 边界、方向唯一 |
| 提交 | `POST /upload-packages/{packageId}/commit` | `X-Idempotency-Key` | 201 新建 / 200 重放 | 事务内建唯一盘点 + 唯一推理任务 |

`UploadPackage.state`：`awaiting_blobs → awaiting_manifest → ready_to_commit → committed`。
`CommitResult`：`{packageId, sessionId, inferenceJobId, status}`，`status ∈ submitted|processing|review_required`。

### 2.2 采集清单（`CaptureManifest`）

- `captureSetId`（UUID）、`captureKind ∈ single|left_center_right|video`、`penId`（UUID）、`assets[1..3]`
- 每个 asset 必填：`assetId, viewPosition, capturedAt(带时区), originalName, width, height,
  sha256, byteSize, mediaType, exif, roi`
- `viewPosition ∈ single|left|center|right|video`（方向唯一性会被校验）
- `exif` 只允许 `orientation, make, model, focalLengthMm, exposureTimeSeconds, iso`——**禁止 GPS/自由文本**
- `roi` 为 EXIF 纠正后的 0~1 归一化坐标，服务端额外校验 `x+width<=1`、`y+height<=1`；`null` 表示整图

### 2.3 错误与身份

- 所有失败响应是 `application/problem+json`：`{type, title, status, detail, code, correlationId}`
- 认证：`POST /auth/login` → `TokenPair{accessToken, refreshToken, tokenType:"Bearer", ...}`；
  `POST /auth/refresh` 轮换；所有业务接口 `Authorization: Bearer <accessToken>`
- 与**本仓库**的差异：本仓库用 `X-Api-Token` + 无状态、ID 是 `A01` 这类字符串而非 UUID

## 3. App 的弱网与重试语义（复刻依据）

来自 `upload_package_synchronizer.dart`，`tools/app_contract_sim.py` 逐条复刻：

1. 401 → 重新登录（`reconnect`）后用**同一 `X-Idempotency-Key`** 重放整个包（源码注释明确写了
   "Every server write has the same stable idempotency key, so replaying the package after a token
   refresh cannot create duplicate evidence"）；
2. 恢复上传时若已有 `serverPackageId`，先 `GET /upload-packages/{id}` 取 `existingAssets`，
   **只补缺失的 blob**；
3. 4xx（除 401）→ 判定该包被服务端拒绝，标记 `blocked` 并给用户诊断信息，不重试；
4. 网络/超时/5xx → 退避重试：`min(15 × 2^n, 15min) + 0~5s 抖动`；
5. 只有 commit 成功并持久化 `sessionId`/`inferenceJobId` 后才标记 `synced`，
   在此之前**绝不删除本地原图**。

## 4. 本仓库已有的可复用能力（不必重写）

| 能力 | 本仓库实现 | 对上 App 合同时的用途 |
|---|---|---|
| 计数与证据 | `detector.py`（ONNX 优先）、`evidence.py`（原图/标注图/指标 JSON） | 作为 Provider 产出 `detections[]`（`asset_id, bbox, confidence, class_id`） |
| 风险规则 | `risk.py`（阈值/连续帧确认/冷却） | Spring 无此层，可作为 Agent 增量能力叠加在会话上 |
| 事件与复核 | `models.py` 状态机、`storage.py` 审计 | 对应其 `confirmInventorySession` / 更正谱系语义 |
| 回放门槛 | `replay.py` + 基线 | 与 App 的 `model_release_gate.py` 目标一致，两边都是"升级必须过门槛" |
| 弱网重放 | `tools/run_app_replay.py` | 直接对 Spring 或本 Agent 跑，输出不变量与端点差距 |

## 5. 落地建议（按性价比排序）

1. **先跑一次探针**，把差距固化成证据（已完成：`docs/app-contract-probe-agent.md`）。
2. **确定定位**再动手：推荐路径 B（Agent 做推理 Provider），因为 App 的身份、主数据、
   对象存储、复核谱系都在 Spring 侧，重复实现它们没有收益且必然产生两套真相。
3. 若选路径 B，最小改造清单：
   - 新增一个薄 Provider 适配层：接收其 `ResearchInferenceRequest`（含 `job_id`、媒体引用、
     模型身份、ROI），调用现有 `PigFarmAgent.analyze` 得到计数与框，映射为
     `CountingJobResult`（`status/count/detections/warnings/model_*/latency_ms`）并回调
     `PUT /inference-jobs/{jobId}/result`（服务密钥鉴权，非用户 JWT）。
   - 保持 `status=review_required` 与 `count=null` 的语义：其 `AGENTS.md` 要求未经批准的模型
     不得把自动计数写入业务值；本仓库的"质量门"正好可以映射成 `review_required` + `warnings`。
   - 模型身份用 `model_key/model_version/model_checksum/adapter_version` 对齐其
     `model-release-manifest.schema.json`，与本仓库回放基线互相印证。
4. 若选路径 A，则需要实现第 2 节的 5 个端点 + BFF 读接口，并复刻 §3 的幂等语义；
   `tools/app_contract_sim.py` 可直接作为验收脚本（它的 8 条不变量就是验收口径）。

## 6. 复现命令

```powershell
# 1) 对任意目标做契约探针（只读，不写数据）
python tools/run_app_replay.py --base http://127.0.0.1:8787 --probe-only

# 2) 对真实目标做弱网重放（需要该目标的登录账号）
python tools/run_app_replay.py --base https://pig-inventory.local:8443 `
    --username <账号> --password <口令> --profile all --packages 2 `
    --report test-assets/app-replay-report.md

# 3) 无环境自证：mock 上游 + 全部场景（应 5/5 端点、全部不变量通过）
python tools/fake_upstream.py --port 8899          # 另开一个终端
python tools/run_app_replay.py --base http://127.0.0.1:8899 `
    --username demo --password demo-password-123 --profile all

# 4) 自证脚本本身可信（故障注入与不变量都真的生效）
python -m pytest tests/test_app_contract_sim.py
```

注意：`tools/fake_upstream.py` 只是**验证脚本用**的最小实现，不代表 smart-pig-inventory 的真实后端。
真实后端的权威是 Spring 源码与其 `contracts/`。
