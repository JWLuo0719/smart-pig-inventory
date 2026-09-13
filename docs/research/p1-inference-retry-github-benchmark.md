# P1 失败推理任务重试 GitHub 对比

日期：2026-08-31

## 问题边界

本轮只比较“失败任务查询、人工重试、并发幂等、历史追溯”模式。`app-yolo` 已有 MySQL 业务事实、事务 Outbox、Redis/Celery 传输和按 Job ID 幂等的最终回调，因此不以替换调度/工作流栈为目标。

## 候选

### [conductor-oss/conductor](https://github.com/conductor-oss/conductor)

- 已核实：Apache-2.0；持久化工作流与每次 Task execution；at-least-once 投递；失败重试创建新的 Task execution；运行中的执行保留启动时定义快照；支持查询、restart/rerun/retry。
- 可迁移模式：原失败执行不可变；重试有新执行身份；输入/模型版本快照随执行保存；Worker 的副作用仍需幂等。
- 不直接采用：引入独立工作流引擎会重复现有 Spring Outbox + Celery 边界，部署、数据迁移和运维成本远超本轮单一推理任务状态机。

### [kagkarlsson/db-scheduler](https://github.com/kagkarlsson/db-scheduler)

- 已核实：Apache-2.0；Java 17+；支持 MySQL 8；持久任务；通过乐观锁或 `select-for-update` 保证单实例领取；有事务化 staging 示例和失败任务运维扩展。
- 可迁移模式：管理员创建后继任务时锁定源记录；任务与业务写入同一事务；数据库唯一约束作为并发兜底。
- 不直接采用：其单表 scheduler 会与当前 `domain_event_outbox`/租约派发器重叠；接入还需重新证明 Celery 合同和回调边界，没有增量收益。

### [jobrunr/jobrunr](https://github.com/jobrunr/jobrunr)

- 已核实：JVM 持久后台任务、RDBMS/NoSQL 存储、乐观锁集群协调、自动退避和 Dashboard；仓库同时提供 LGPL 与其他授权文本，许可路径比 Apache-2.0 候选复杂。
- 可迁移模式：失败任务应具备管理员可见的状态、错误和明确 rerun 操作；运行身份必须持久化，而不能只存在于队列。
- 不直接采用：除了重复现有调度能力，还会扩大许可证审查面；其通用 Dashboard 也不能替代本项目的组织隔离、模型身份、媒体证据和审计理由合同。

## 结论

采用增量实现，不引入新依赖：

1. 每次管理员重试创建新的 `inference_job`，通过 `root_job_id`、`retry_of_job_id`、`retry_sequence` 形成线性链；原失败 Job、结果收据、失败码和时间戳不变。
2. 将请求模型身份快照持久化到每个 Job；后继复制源 Job 的模型身份、Session、CaptureSet 和媒体引用，不读取“当前默认模型”替换历史意图。
3. 使用源 Job `FOR UPDATE`、每个失败 Job 唯一后继、`(capture_set_id, retry_sequence)` 唯一约束，以及 `X-Idempotency-Key + reason` 回放检查封住并发双击。
4. 后继 Job、重试 Outbox 和 `inference.retry_requested` AuditEvent 在一个 MySQL 事务中提交；Redis/Celery 继续只承担传输。
5. 只允许 `FARM_ADMIN`/`SYSTEM_ADMIN` 管理当前组织的失败任务；跨组织与无权限访问继续表现为不存在。

这是对三个项目的架构模式借鉴，不复制其源码，也不引入其运行时或 UI。
