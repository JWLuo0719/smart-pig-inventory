# 弱网上传合同 v1

OpenAPI 是字段级权威，本文件解释重试语义。

1. `POST /api/v1/upload-packages`：客户端提交 `clientPackageId + organizationId + penId + businessDate + captureKind`。服务器返回自身 package ID 以及 `existingAssets`；相同客户端包或幂等键恢复原包。
2. `PUT /api/v1/upload-packages/{packageId}/blobs/{assetId}`：完整上传单张照片。请求携带 `X-Content-SHA256`；同一文件重复上传视为成功，同一标识但内容不同返回 409。
3. `PUT /api/v1/upload-packages/{packageId}/manifest`：提交 CaptureSet、方向、采集时间、原始文件名、纠正 EXIF 方向后的尺寸、安全筛选后的 EXIF、哈希、ROI 和媒体引用；服务器校验组织/栏舍权限、Blob 完整性、方向组合和组织范围精确重复。ROI 使用纠正方向后的 0～1 归一化坐标，并校验 `x + width <= 1`、`y + height <= 1`。
4. `POST /api/v1/upload-packages/{packageId}/commit`：在事务内创建正式 InventorySession、媒体引用、唯一推理任务和事务 Outbox 事件。重复 Commit 返回原 session/job，不再次投递。

所有写请求都使用 UUID 格式 `X-Idempotency-Key`。客户端仅在 Commit 成功并持久化 `sessionId`、`inferenceJobId` 后标记 synced，在此之前不得删除本地原图。客户端可通过 `GET /api/v1/upload-packages/{packageId}` 恢复服务端状态和已完成 Blob。

图片按文件级恢复。感知哈希只产生疑似重复告警，不自动删除。视频分块上传属于后续合同，不在 v1 OpenAPI 中暴露。
