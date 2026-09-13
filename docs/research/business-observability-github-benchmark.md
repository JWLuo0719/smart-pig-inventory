# 业务可观测性：增量方案对照

日期：2026-09-08。范围是 NFR 指标和本地规则，不是替换业务栈或部署外部通知。

先通过 GitHub 连接器分别检索 `micrometer metrics instrumentation`、`prometheus monitoring promtool`、`celery prometheus exporter`；泛化示例相关性不足，最终核对两个官方基础项目及一个直接对应 Celery 的 Exporter。Review Hub 审计 `audit-20260908030719-d931a3e1` 无匹配，不强行复用旧经验。

| 候选与直接证据 | 核实事实 | 本项目取舍与成本 |
| --- | --- | --- |
| [Micrometer README](https://github.com/micrometer-metrics/micrometer/blob/main/README.md)、[Gauge 文档](https://docs.micrometer.io/micrometer/reference/concepts/gauges.html) | 统一维度指标接口；Apache-2.0；Gauge 表示采样时状态。连接器报告 README 2026-08-24 更新 | 沿用 Spring 已有依赖；队列/滚动窗口用 Gauge，上传尝试用 Counter。无需框架迁移，维护有限的指标名和 SQL；指标对象由组件持有。 |
| [Prometheus README](https://github.com/prometheus/prometheus/blob/main/README.md)、[规则测试文档](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/)、[v3.5.0 release](https://github.com/prometheus/prometheus/releases/tag/v3.5.0) | Pull 采集、PromQL、独立服务；Apache-2.0；promtool 可验证输入时间序列上的告警行为，固定版本发布存在 | 只运行固定版本 promtool 验证本地规则，已加入 CI；不集成源码、不创建外部接收器。后续真实采集器仍需密钥注入与目标配置。维护成本是指标命名与规则同步。 |
| [celery-exporter README](https://github.com/danihodovic/celery-exporter/blob/master/README.md)、[仓库元数据](https://api.github.com/repos/danihodovic/celery-exporter) | 使用 Celery 事件，暴露任务、Worker 和 Broker 队列指标；需要事件开关。元数据显示 MIT、非归档、2026-08-31 最近推送 | 暂不引入。事件数据不能替代 Spring 幂等回执和最终业务状态；直接部署增加 Broker 权限、事件开销与版本维护。其区分 Broker/Worker/业务任务的方式适用，后续可评估 Worker 专项监控，当前不得把 Outbox 深度称为 Redis 队列长度。 |

上述维护日期不是长期维护承诺。本轮仅借鉴指标类型、语义和测试方法，没有复制第三方源码、fork 或引入 Exporter。许可核对不替代项目整体发布许可决策。

安全推导：数据库快照是跨组织的运维视图，即使没有组织标签，也不应给任何普通用户 JWT 查看。因此使用独立的监控服务密钥，用户认证关闭也不绕过它；原有 API 组织权限完全保留。未知/失败采集输出 NaN 和独立可用性标志，不能把失败解释成没有待办。

实现口径及未覆盖项见 `docs/development/business-observability.md`。以上是局部架构适配判断，不以开源热度作为集成依据。
