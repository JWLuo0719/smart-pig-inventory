# App 弱网重放 / 契约探针报告

- 目标：`http://127.0.0.1:8899`
- 目标性质：mock 上游（tools/fake_upstream.py，仅供自证脚本，不代表真实后端）
- 生成时间：2026-09-16T15:45:45+08:00
- 合同来源：smart-pig-inventory `contracts/openapi.yaml`（v0.8.0，`servers: /api/v1`）
  与 `apps/mobile/lib/features/outbox/application/upload_package_synchronizer.dart`

## 1. 契约探针

| 步骤 | 方法 | 路径 | HTTP | 已实现 | 错误形状 |
|---|---|---|---|---|---|
| create-package | POST | `/upload-packages` | 422 | ✅ | problem+json |
| get-package | GET | `/upload-packages/{id}` | 404 | ✅ | problem+json |
| put-blob | PUT | `/upload-packages/{id}/blobs/{assetId}` | 422 | ✅ | problem+json |
| put-manifest | PUT | `/upload-packages/{id}/manifest` | 422 | ✅ | problem+json |
| commit | POST | `/upload-packages/{id}/commit` | 404 | ✅ | problem+json |

## 2. 弱网场景

### clean

- 采集包 2 个：已同步 2，被拒 0，窗口内未同步 0
- blob：新建 6，按 existingAssets 跳过 0，重发 0；commit 尝试 2 次

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=e028e2cd-1f3a-4411-b084-6c9985c7ec13 |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=ce943937-0d5a-478e-a834-f38090990e85 job=39f6f2b7-0d0b-4710-978f-e605027cf2c4 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=742a6a6c-5233-4dfe-8141-a0e12a9957d2 |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=f6d32f9c-1dcf-440c-abc4-2123c3cb70ef job=2c94553a-e3ef-4317-b912-6f8e8a1a356d |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

### flaky

- 采集包 2 个：已同步 0，被拒 0，窗口内未同步 2
- blob：新建 3，按 existingAssets 跳过 16，重发 0；commit 尝试 1 次
- 注入故障：connection_lost×6，dropped_response×3，server_error×3，timeout×4

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=97849fd0-ad9d-4165-921f-a3340a758889 |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 1 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 10，新建 1，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 1，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I5 同步完成或明确被拒（不留模糊状态） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I6 采集包状态机合法 | ✅ | state=ready_to_commit |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=51150cae-2b5b-4523-bd24-2bdde2d6c06b |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 2 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 6，新建 2，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 2，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I5 同步完成或明确被拒（不留模糊状态） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

### offline-recovery

- 采集包 2 个：已同步 2，被拒 0，窗口内未同步 0
- blob：新建 6，按 existingAssets 跳过 0，重发 0；commit 尝试 2 次
- 注入故障：offline×4

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=cbced98f-613b-42e7-9afa-0467064071da |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=fd097fe5-41b3-4f75-a953-4f84dc544ec6 job=c46dd8ef-8ffd-4a3c-9135-8b1294970d2a |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=ef733d9e-3c35-4f22-8480-bc60d9cfeff7 |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=271c04f2-9916-43b8-8333-6f9d7ac8eb7e job=6dcd6cb9-0b25-40b7-b868-7057029acb34 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

### partial-resume

- 采集包 2 个：已同步 2，被拒 0，窗口内未同步 0
- blob：新建 6，按 existingAssets 跳过 0，重发 0；commit 尝试 2 次

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=e37ed388-762a-4126-8f14-9faaafa5e6a3 |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=17e67356-1499-4e3f-888f-efbbd63176db job=6a3ceb4a-0449-41da-b8e9-99e02e657510 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=9f04d5f0-6a94-4b4c-ae72-ca9d0f2a029e |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=4b587ee9-238c-4d2c-8c85-264cbe844a0d job=359d130b-f4b7-4b0c-891f-531ddf58e7c4 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

### token-expiry

- 采集包 2 个：已同步 2，被拒 0，窗口内未同步 0
- blob：新建 6，按 existingAssets 跳过 0，重发 0；commit 尝试 2 次
- 注入故障：token_expired×2

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=456ef2c0-b444-4c24-8457-bc44a79ef63c |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=e0cc2887-100a-41ed-b1d2-9aec7055bebc job=d5f58521-ecdc-45b7-8e78-d4d38ad5fa92 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=8fff4d1d-eae0-46b5-9a92-7570b6b9c43b |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 3 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 3，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 3，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ✅ | session=01db3bcf-b646-4b8e-956e-f4dedb2fd1b2 job=be832b02-5e2c-44ce-a0f8-d51a779dce47 |
| I5 同步完成或明确被拒（不留模糊状态） | ✅ | 已同步 |
| I6 采集包状态机合法 | ✅ | state=committed |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

### harsh

- 采集包 2 个：已同步 0，被拒 0，窗口内未同步 2
- blob：新建 2，按 existingAssets 跳过 4，重发 0；commit 尝试 0 次
- 注入故障：connection_lost×8，dropped_response×4，server_error×3，timeout×3，token_expired×2

| 不变量 | 结果 | 说明 |
|---|---|---|
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=873faa5b-730b-49c1-acf2-01b7d0aeb95e |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 1 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 4，新建 1，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 2，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I5 同步完成或明确被拒（不留模糊状态） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I6 采集包状态机合法 | ✅ | state=awaiting_manifest |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |
| I1 创建采集包幂等（同一幂等键返回同一 id） | ✅ | server package=a638b0b8-f1a8-4a2e-a013-d0280c6e42dc |
| I2 blob 幂等（服务端不产生第二份内容） | ✅ | 新建 1 份 / 3 张，重发 0 次（重发不产生副本，但白费流量） |
| I3 恢复续传（服务端回报已有的 blob 不重传） | ✅ | 跳过 0，新建 1，重发 0 |
| I8 同一次同步内每张图最多上传一次（不白费弱网流量） | ✅ | PUT 次数 1，重复项 无 |
| I4 提交幂等（重放返回同一 session/job） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I5 同步完成或明确被拒（不留模糊状态） | ➖ | 重试窗口内未同步（客户端仍在队列，不算违规） |
| I6 采集包状态机合法 | ✅ | state=awaiting_manifest |
| I7 错误响应符合 application/problem+json | ✅ | 无失败响应 |

## 3. 结论

- 不变量：88/88 通过（8 项因包在重试窗口内未同步而不适用）。
- 合同端点：5/5 已实现。

> 未同步不代表失败：弱网未恢复时客户端会保留本地队列（不删除原图），下一轮继续按同一 `X-Idempotency-Key` 重放。
