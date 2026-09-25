# App 弱网重放 / 契约探针报告

- 目标：`http://127.0.0.1:8787`
- 目标性质：本仓库 Agent 后端（未实现 App 采集包合同）
- 生成时间：2026-09-16T15:45:55+08:00
- 合同来源：smart-pig-inventory `contracts/openapi.yaml`（v0.8.0，`servers: /api/v1`）
  与 `apps/mobile/lib/features/outbox/application/upload_package_synchronizer.dart`

## 1. 契约探针

| 步骤 | 方法 | 路径 | HTTP | 已实现 | 错误形状 |
|---|---|---|---|---|---|
| create-package | POST | `/upload-packages` | 404 | ❌ | application/json; charset=utf-8 |
| get-package | GET | `/upload-packages/{id}` | 404 | ❌ | application/json; charset=utf-8 |
| put-blob | PUT | `/upload-packages/{id}/blobs/{assetId}` | 501 | ❌ | text/html;charset=utf-8 |
| put-manifest | PUT | `/upload-packages/{id}/manifest` | 501 | ❌ | text/html;charset=utf-8 |
| commit | POST | `/upload-packages/{id}/commit` | 404 | ❌ | application/json; charset=utf-8 |

## 2. 弱网场景

## 3. 结论

- 不变量：0/0 通过（0 项因包在重试窗口内未同步而不适用）。
- 合同端点：0/5 已实现。

> 未同步不代表失败：弱网未恢复时客户端会保留本地队列（不删除原图），下一轮继续按同一 `X-Idempotency-Key` 重放。
