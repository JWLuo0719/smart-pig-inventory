# P0 采集—确认闭环 Compose E2E 记录

日期：2026-08-27
环境：本机隔离 Compose 项目 `pig-inventory-e2e`；全部为新建的合成组织、栋舍、栏舍和字节串，未使用现场数据。

## 运行前提

- Docker Desktop Linux engine 已运行。
- 使用新建的 Compose 卷，不能复用与当前 `.env` 凭据不一致的历史 `pig-inventory_mysql_data` 卷。
- `SECURITY_ENABLED=true` 时，`INFERENCE_CALLBACK_TOKEN` 必须为非空随机值，并且 Spring、inference-api 和 inference-worker 使用完全相同的值。
- 本轮为隔离测试在启动命令中临时提供了该随机 callback token，并设置 `INFERENCE_DISPATCHER_ENABLED=true`；令牌没有写入仓库或输出到日志。

## 已验证路径

1. 本地 bootstrap SYSTEM_ADMIN 登录，创建 JWT。
2. 在测试数据库写入一个合成栋舍和栏舍。
3. 使用 JWT 完成 `create package -> blob -> manifest -> commit`；对象被写入私有 MinIO 桶。
4. Spring 事务 Outbox 被 dispatcher 领取，Python Celery Worker 调用 unavailable Provider，并以服务身份回调 Spring；回调返回 HTTP 204。
5. 会话变为 `review_required`，无可用自动数量，告警说明没有已验证 Provider。
6. SYSTEM_ADMIN 以人工数量 `11` 和原因确认会话；会话变为 `confirmed`，引用媒体被锁定，写入 `inventory.confirmed` 审计事件。
7. 普通 `DELETE /media-assets/{assetId}` 在锁定后返回 HTTP 409。
8. 管理员带原因调用 `override-delete` 返回 HTTP 200；媒体保留为软删除，另写 `media.override_deleted` 审计事件。

最终数据库断言：`confirmed|11|1|2`，依次代表确认状态/数量、同时具备 locked_at 和 deleted_at 的引用媒体数、确认与管理员覆盖审计事件数。

## 同轮自动化验证

- `mvn test`：29 passed，0 skipped；Testcontainers MySQL 8.4 已实际应用 V1 至 V7。
- `flutter analyze`：通过；`flutter test`：23 passed。
- `python -m pytest`：6 passed。
- `openapi-spec-validator contracts/openapi.yaml`：通过。

## 后续真机验收记录

- 2026-08-27：realme GT 7 Pro 已完成完整左/中/右采集组的强制停止恢复；重开后 3/3 原图缩略图可见、可打开大图、仍属同一采集组且不显示数量。该 AC-01 场景通过。
- 同轮完整三视图包已自动完成 Commit 并显示 `已提交，等待处理`。进入复核页时发现 Access Token 过期未自动 Refresh 的客户端缺陷；Flutter v`0.1.0+3` 已修复读取/确认的 401 Refresh Token 重试，尚待实机回归，因此不得将 AC-06、AC-08 或 AC-09 记为本轮真机通过。
- 同轮管理端 LAN HTTP 登录发现 `crypto.randomUUID` 浏览器兼容问题；已修复，尚待重新构建容器回归。

## 尚未覆盖

- 真机 Flutter 复核页的刷新/确认 E2E、近重复审核、管理端媒体复核、低端设备与弱网场景仍需独立证据。
- 历史默认 MySQL 开发卷的账号口令与当前 `.env` 不一致时，必须通过经确认的数据迁移或仅删除明确的本地测试卷修复；不得在试点或生产环境重置卷。
