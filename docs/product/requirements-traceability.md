# 需求—实现—验收追踪矩阵

该表用来防止“页面已画完”被误判为“业务已完成”。状态只允许：草案、开发中、已验证、阻塞。

| 需求 | 权威设计 | 主要实现位置 | 验收 | 当前状态 |
|---|---|---|---|---|
| 科研阶段登录/令牌刷新 | PRD P0；ADR-0003 | Flutter auth；Spring identity | AC-11、AC-12 | 开发中（Spring Bootstrap、JWT、登录、刷新轮换、登出和当前用户已通过 MySQL 集成测试；Flutter 安全存储、登录/刷新/登出和 7 天离线恢复已实现。复核读取/确认与 Outbox 上传均在 401 时以原幂等键执行一次 Refresh Token 后重试，新增 Flutter 自动化测试；待实机回归） |
| 组织/栋舍/栏舍离线同步 | PRD 3.1 | Flutter master-data；Spring masterdata | AC-01、AC-11 | 开发中（Spring 全量/增量游标、删除墓碑和组织隔离已通过 MySQL 集成测试；Flutter 已原子写入隔离缓存、搜索并拦截禁用栏舍，待实机 Compose 联调） |
| 单图与三视图采集 | PRD 3.2 | Flutter capture；Spring capture | AC-01、AC-08 | 开发中（单图/三图本地采集、方向唯一和页面接线已测试；realme GT 7 Pro 已人工通过完整左/中/右三图强制关闭恢复，v0.1.0+3 明示三张缩略图并可查看大图；三视图不自动相加的复核实机回归待完成） |
| ROI | PRD 3.2/3.4 | Flutter ROI domain；推理合同 | AC-01、AC-07 | 开发中（边界校验和草稿持久化已测试；服务端 Manifest 边界校验已测试，推理中心点口径待实现） |
| 草稿恢复与本地媒体 | PRD 3.2 | Drift v5 CaptureDrafts/CaptureSets/LocalMediaAssets；MediaMaterializer | AC-01 | 已验证（流式物化、EXIF 方向/尺寸、原子持久化、数据库重开恢复已测试；realme GT 7 Pro 已人工验证三张本地证据在强制停止后完整恢复且可查看） |
| Outbox 与续传 | PRD 3.3 | Drift v6 OutboxEntries/UploadAssetEntries；UploadPackageSynchronizer；Upload API；Spring capture/inference dispatch | AC-02 | 开发中（完整采集组入队、逐 Blob 状态、稳定幂等键、租约、退避、三视图已确认 Blob 跳过、后台 WorkManager 批处理及 Commit 后同步标记均已自动化测试；Spring 已加入事务 Outbox 领取、租约恢复和推理 API 派发；待上传中途断流及 Compose 闭环 E2E） |
| 幂等上传包 | OpenAPI Upload | Spring capture application/infrastructure/UI | AC-02、AC-03 | 已验证（Testcontainers MySQL 覆盖 create、Blob、Manifest、Commit 重放及唯一任务） |
| SHA-256 精确去重 | PRD 3.3 | Flutter hash；Spring capture；MySQL 唯一索引 | AC-04 | 已验证（同组织精确重复在 Manifest 阶段阻断的 MySQL 集成测试） |
| 感知哈希审核 | PRD 3.4 | Flutter capture/outbox；Spring capture/review；管理端 | AC-05 | 已自动化验证（Flutter 在后台 Isolate 中为支持且受尺寸/像素上限约束的图像生成 64 位 dHash，提交 Manifest；Spring 以汉明距离 <= 8 建立只读告警，绝不自动删除媒体；复核员可带原因解决告警并写入审计，媒体仍保留；Flutter 与 MySQL 集成测试均覆盖） |
| 推理安全降级 | 架构 7；ADR-0003 | Spring transactional Outbox/结果回调；Python Celery callback/UnavailableProvider | AC-06 | 已验证（隔离 Compose E2E 已实际经过 Commit、Outbox、Celery、受服务密钥保护的回调，并在 unavailable Provider 下进入 review_required 且不返回模拟数量；真实获准 Provider 仍为 P1 阻塞） |
| 三视图禁止简单相加 | PRD 3.4 | CaptureSetPolicy；Spring 回调归一化；Provider | AC-08 | 开发中（三视图成功结果在未启用验证多视角 Provider 时强制转为 review_required，集成测试已覆盖） |
| 人工确认和媒体锁定 | PRD 3.5 | Spring inventory/media/audit；Flutter session review | AC-09 | 已验证（隔离 Compose E2E 以 bootstrap SYSTEM_ADMIN 实际确认 unavailable 推理结果、锁定媒体、验证普通删除 409、执行带原因管理员软删除，并得到两条审计事件；见 `docs/development/p0-closure-e2e.md`） |
| 综合平均 | PRD 3.5/6 | InventoryAggregationPolicy；Spring inventory reports；Flutter tasks | AC-10 | 已验证（已新增按业务日期派生的栏舍任务、仅已确认日盘点报表和按栏舍/日期范围的原始均值/展示值 API；单元测试覆盖均值口径，隔离 Compose 以真实确认数量验证任务、日报和综合报表） |
| 组织隔离/RBAC | 范围、NFR | Spring Security；MySQL；合成 P0 fixture | AC-11 | 已自动化验证（真实 MySQL 成员关系与组织绑定 JWT 覆盖 OPERATOR 只读/不可确认、REVIEWER 可确认/不可覆盖删除、FARM_ADMIN 可确认/覆盖/审计，以及第二组织不可发现；隔离 Compose fixture 创建四个合成账号、两组织、栋舍和栏舍） |
| 私有对象存储和生产安全 | NFR | Compose/网关/部署配置；内部回调服务密钥 | AC-12 | 开发基线，生产未验证 |
| 管理端态势与复核 | PRD 5 | Next.js；Flutter session review | AC-05、AC-09、AC-10 | 开发中（管理端已实现受认证登录、同源受限 API 代理、真实任务、会话受限媒体预览、人工确认、近重复带理由解决、日报/综合及审计读取；媒体只通过受认证业务 API Blob 传输，不公开对象 URL。Next lint/build 已通过，待隔离 Compose 浏览器回归） |
| 初版品牌资产 | 视觉系统 | Flutter/Next.js Logo 资产 | 视觉评审、商标检索 | 开发中（临时资产，未注册） |
| 主流/低端 Android 覆盖 | NFR | realme GT 7 Pro / REDMI Note 14 5G 候选 | AC 设备测试 | 主流机已确定；低端机待取得 |
| 金蝶同步 | PRD 3.1 | ErpOrganizationProvider | P1 专项 | 阻塞（缺正式文档） |
| 真实 YOLOv13 | PRD P1 | 产品仓库外 ResearchHttpYolo Runner；正式为 Python http-yolo Provider | 推理金标回归 | 阻塞（Nano 研究 Runner 已完成隔离产品测试并强制人工复核；AGPL-3.0 许可、猪只金标、正式权重准入与自动计数审批仍缺失） |
| 视频/端侧/Agent | PRD P2 | 隔离 PoC | P2 专项 | 边界外 |

每个合并请求必须更新受影响行；只有自动化或可复现实机证据通过后才能标记为“已验证”。
