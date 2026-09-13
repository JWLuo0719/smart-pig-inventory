# 业务指标与本地规则

本阶段是自动化运维基线，不代表生产告警上线、模型性能达标或人工验收通过。

## 采集边界

- GET `/actuator/prometheus`、`/actuator/metrics` 及其子指标只接受 `X-Monitoring-Service-Key`。配置变量 `MONITORING_SERVICE_KEY` 缺失/空白时一律 401；用户 JWT、管理员身份和 `SECURITY_ENABLED=false` 均不能代替监控密钥。健康探针保持原行为。
- 此为有意收紧此前“登录即可访问”的运维接口；既有采集客户端须更新认证。用独立随机密钥，经私网/TLS 与 Secret 文件注入，不复用回调或 JWT 密钥。不向管理端代理添加监控路由。
- 数据库指标跨组织聚合，只用于运维；无组织、用户、任务、模型、路径、图像、失败消息等动态标签。不是任何组织的业务报表。
- 每 30 秒读取一个只读、可重复读事务快照，单条查询最多 3 秒、事务 5 秒。Flyway V11 新增查询索引，不改旧迁移。监控与派发器使用独立单线程调度器；抓取指标本身不执行 SQL。连接池耗尽等情况可能超过查询时限，需观察采集陈旧告警；目标数据量开销尚需容量验收。
- 采集前或失败后业务 Gauge 为 NaN，可用性为 0；保留上次成功时间，不把旧值伪装为新值。实例恢复后重新采样。测试显式触发采样，避免 Testcontainers 销毁后后台线程访问旧连接。

## 指标口径

| Prometheus 指标 | 类型与准确含义 |
| --- | --- |
| `pig_upload_requests_total{step,outcome}` | 进程 Counter。step 固定 create/blob/manifest/commit；outcome 固定 created(201)/replayed(200)/rejected(非 2xx 且非 5xx)/failed(5xx 或未处理异常)。只统计已路由到 MVC 的请求完成，不包含认证链提前拒绝。重放是成功请求，但不是新包。重启归零，用 rate/increase 处理；业务成功率以 commit 为首选阶段，不混合四步。 |
| `pig_upload_duplicate_rejections_total` | 进程 Counter。实际返回 EXACT_DUPLICATE_IMAGE 的请求次数；同一重复意图再次尝试会再次计数，不等于独立重复图片数量。 |
| `pig_inference_outbox_pending` / `pig_inference_outbox_oldest_seconds` | Gauge。两种推理事件的 PENDING+DISPATCHING 总数/最长等待秒数，含退避和租约中事件。派发器关闭时仍显示真实积压。不是 Redis 消息数。 |
| `pig_inference_jobs_outstanding` | Gauge。数据库 submitted+processing 数量，可能与 Outbox 重叠；两者禁止相加。 |
| `pig_inventory_review_pending` | Gauge。当前 review_required 会话数量，候选数不进入业务报表。 |
| `pig_inventory_review_completed_last24h` | 滚动 Gauge。过去 24h 确认的原始证据会话，当前状态 confirmed 或 superseded；更正版本不重复计数。不是累计 Counter。 |
| `pig_inference_results_{succeeded,review_required,failed}_last24h` | 滚动 Gauge。过去 24h 已终结且有唯一结果的任务，各状态独立；回调重放不新增样本。重试后继是独立尝试。 |
| `pig_inference_latency_{状态}_{samples,seconds}_last24h` | 滚动 Gauge。上述终结任务中非空 latency_ms 的样本数/秒数和；二者相除可得均值。来自 Provider 的已接收耗时，不是排队+回调端到端延迟，也不提供 P95。 |
| `pig_inference_retries_last24h` | 滚动 Gauge。过去 24h 实际创建的管理员重试后继数；同键重放不增加。不是 Celery 自动重试次数。 |
| `pig_metrics_snapshot_available` / `pig_metrics_snapshot_last_success_timestamp_seconds` | 采集可用性 0/1、上次成功的 Unix 秒时间。 |

`last24h` 指标是窗口存量，会随时间减少，禁止 `rate()` / `increase()`。多业务实例共享同一数据库时快照值不能跨副本求和，应选单一目标或明确去重；请求 Counter 则可按实例汇总。

规则 `pig:upload_request_success:ratio5m` 是成功/全部请求（含重放、业务拒绝），按阶段区分。无请求时 NaN，不假设 100%。`pig:inference_review:ratio24h` 是终结尝试中 `review_required` 的占比，失败单列；它是推理分流率，不是人工完成率或准确率。研究模式通常高复核占比，不据此自动批准模型。

## 本地告警与测试

`infra/monitoring/business-rules.yml`：两个记录规则、四个诊断告警。抓取失败/快照不可用持续 2 分钟、快照超过 90 秒陈旧、Outbox 最长等待超过 300 秒且持续 5 分钟、5 分钟上传失败率 >10% 且至少 10 次请求并持续 2 分钟。这些是本地诊断初值，生产必须按试点容量/业务时段校准；没有配置 Alertmanager、Webhook、邮件或推送。

```powershell
pwsh -NoProfile -File scripts/run-observability-e2e.ps1
```

固定 `pig-inventory-p0-observability`，仅绑定 `127.0.0.1:8095`；测试配置与摘要在忽略目录 `test-assets/generated/observability/`。不读取产品 `.env`；每轮新增 UUID 合成组织/栏位/字节。测试字节不是真实图片，不运行 Worker/模型解码，不代表图像质量验收。默认重建；`-SkipBuild` 仅在确认镜像包含当前代码时使用。成功清理本测试容器/网络、保留卷；失败保留诊断栈。不得改名指向 P0。

验证实际上传新建/重放、SHA-256 重复拦截、回调/重试幂等不虚增、确认后更正不重复计复核完成量、队列增量、1250ms→1.25s、独立监控密钥的双安全模式/缺失配置拒绝，以及无身份标签。promtool 以网络隔离、只读规则挂载验证持续时间、缺失指标、恢复、低流量与 Counter 重置；CI 同步执行。

## 下一步，仍未完成

- 真正运行 Prometheus 抓取并观察告警 pending→firing→恢复；当前只验证 HTTP 数据与 promtool 规则语义，没有部署长期采集服务。
- Redis Broker 精确队列、Celery Worker 心跳/执行中任务/自动重试、端到端推理耗时分布与 P95；当前 Spring 未完成任务数不冒充这些指标。
- 真实业务容量下 SQL/采集开销、生产告警阈值、密钥轮换和 TLS/通知接收策略验收；外部通知仍需用户明确渠道与收件范围。

取舍证据见 `docs/research/business-observability-github-benchmark.md`。
