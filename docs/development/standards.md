# 开发规范

## 仓库结构

- `apps/mobile`：Flutter 现场端。
- `apps/admin-web`：Next.js 管理端。
- `services/business-api`：Spring Boot 业务 API，唯一业务数据库写入者。
- `services/inference-service`：Python 推理网关与 Worker。
- `contracts`：OpenAPI 和推理 JSON Schema。
- `infra`：Nginx、初始化与部署配置。
- `services/backend`：冻结 Django 原型。
- `eg`：只读遗留参考。

## API 与数据

- 路由前缀 `/api/v1`；资源名使用复数和 kebab-case。
- 所有写请求按合同支持客户端 UUID 和 `X-Idempotency-Key`。
- 时间为 ISO-8601 UTC；业务日期单独使用 `YYYY-MM-DD`。
- 错误体使用 `application/problem+json`，包含 `code`、`title`、`detail`、`correlationId` 和可选字段错误。
- Flyway 脚本命名 `V{version}__{description}.sql`，已应用脚本不可修改。

## Spring

- Controller 只负责协议，Application Service 编排事务，Domain 承载规则，Infrastructure 实现外部适配。
- 禁止在数据库事务中执行大文件上传和长时间模型推理。
- 组织 ID 来自认证上下文，不接受客户端任意指定后直接信任。
- 使用构造器注入；禁止记录凭据和原始媒体内容。

## Flutter

- feature-first 目录；页面不直接访问 Dio 或 Drift。
- 先物化媒体再建草稿；状态转换集中在 Repository/UseCase。
- Widget 文案使用统一词汇；关键状态具备语义标签和测试 key。

## Web

- Server/Client Component 边界明确；API 客户端集中封装。
- Token 不写入可被脚本长期读取的 localStorage；生产优先 HttpOnly Cookie/BFF。
- 所有可点击元素支持键盘和可见焦点。

## Git 与评审

- 分支：`feat/*`、`fix/*`、`docs/*`、`chore/*`。
- 提交使用 Conventional Commits；一个提交只处理一个可回滚目的。
- PR 必须链接需求/验收编号、说明数据库和合同变化、列出验证证据。
- 禁止把 `eg/` 文件加入产品模块或在 PR 中声称其代码为新实现。
