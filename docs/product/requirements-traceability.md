# 需求—实现—验收追踪矩阵

该表用来防止“页面已画完”被误判为“业务已完成”。状态只允许：草案、开发中、已验证、阻塞。

| 需求 | 权威设计 | 主要实现位置 | 验收 | 当前状态 |
|---|---|---|---|---|
| 组织/栋舍/栏舍离线同步 | PRD 3.1 | Flutter master-data；Spring organization | AC-01、AC-11 | 草案 |
| 单图与三视图采集 | PRD 3.2 | Flutter capture；Spring capture | AC-01、AC-08 | 开发中（页面/策略） |
| ROI | PRD 3.2/3.4 | Flutter capture；推理合同 | AC-01、AC-07 | 草案 |
| 草稿恢复与本地媒体 | PRD 3.2 | Drift CaptureDrafts/LocalMediaAssets | AC-01 | 开发中（表结构） |
| Outbox 与续传 | PRD 3.3 | Drift OutboxEntries；Upload API | AC-02 | 开发中（骨架） |
| 幂等上传包 | OpenAPI Upload | Spring media/capture | AC-02、AC-03 | 草案 |
| SHA-256 精确去重 | PRD 3.3 | Flutter hash；MySQL 唯一索引 | AC-04 | 开发中（服务端索引） |
| 感知哈希审核 | PRD 3.4 | Spring review；管理端 | AC-05 | 草案 |
| 推理安全降级 | 架构 7 | Python UnavailableProvider；Spring Provider | AC-06 | 开发中（实现已落地，待本机验证） |
| 三视图禁止简单相加 | PRD 3.4 | CaptureSetPolicy；Provider | AC-08 | 开发中（策略测试） |
| 人工确认和媒体锁定 | PRD 3.5 | Spring inventory/media/audit | AC-09 | 数据库草案 |
| 综合平均 | PRD 3.5/6 | InventoryAggregationPolicy | AC-10 | 开发中（策略测试） |
| 组织隔离/RBAC | 范围、NFR | Spring Security；MySQL | AC-11 | 框架已搭，规则待实现 |
| 私有对象存储和生产安全 | NFR | Compose/网关/部署配置 | AC-12 | 开发基线，生产未验证 |
| 管理端态势与复核 | PRD 5 | Next.js | AC-05、AC-09 | 页面框架预览 |
| 初版品牌资产 | 视觉系统 | Flutter/Next.js Logo 资产 | 视觉评审、商标检索 | 开发中（临时资产，未注册） |
| 主流/低端 Android 覆盖 | NFR | realme GT 7 Pro / REDMI Note 14 5G 候选 | AC 设备测试 | 主流机已确定；低端机待取得 |
| 金蝶同步 | PRD 3.1 | ErpOrganizationProvider | P1 专项 | 阻塞（缺正式文档） |
| 真实 YOLOv13 | PRD P1 | HttpYoloProvider | 推理金标回归 | 阻塞（缺权重/许可证/基准） |
| 视频/端侧/Agent | PRD P2 | 隔离 PoC | P2 专项 | 边界外 |

每个合并请求必须更新受影响行；只有自动化或可复现实机证据通过后才能标记为“已验证”。
