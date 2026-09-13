# 需求—实现—验收追踪矩阵

## 2026-09-13 非视频真机验收反馈

用户反馈前四项非视频功能测试成功，视频相关测试后置。移动端视频采集/上传/播放与视频自动计数仍保持待验收，不能由本次非视频反馈替代。

## 2026-09-13 上传包自动恢复真机证据

v18 真机覆盖安装后，原包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 在未点击重试/放弃的情况下自动完成创建、Blob、Manifest 和 Commit。服务端会话为 `review_required`、候选 21；手机重启显示已提交服务器、本机待上传 0。该项的上传恢复验收已通过，候选仍不能替代人工确认或模型批准。

## 2026-09-13 上传包自动重试增量

真机步骤 2 的包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 在创建阶段卡住，服务端未收到创建请求。移动端现已覆盖 Socket/TLS/超时暂时性失败的租约清理与退避，并修复 Drift 时间绑定；Flutter 全量 42 项测试通过。该项的自动化状态已验证，v17 设备覆盖安装及原包自动恢复仍待无线 ADB 真机读回，不能提前标记完整上传验收通过。

## 2026-09-13 真机增量证据

v16 同签名 Release 已在 Redmi K60 通过无线 ADB 覆盖安装。mDNS/HTTPS、认证恢复和首页当日任务自动加载在真实设备上读回成功：网关 `/me`、刷新后的 `/me`、`inventory-tasks` 均为 200，UI 显示网络已验证、2 个任务和 `0 / 2`。认证状态从加载/离线到在线时首页自动刷新任务的缺口已修复，widget 测试覆盖两类恢复。该证据不替代采集、续传、图库、视频、报表和主数据同步的人工验收。

该表用来防止“页面已画完”被误判为“业务已完成”。状态只允许：草案、开发中、已验证、阻塞。

| 需求 | 权威设计 | 主要实现位置 | 验收 | 当前状态 |
|---|---|---|---|---|
| Android 独立 Release 签名 | NEXT_STEPS 首项；Android 发布说明 | Gradle release signing；initialize/build/test-release scripts | AC-12、统一真机验收 | 工程已验证（2026-09-10 v0.1.0+4，独立候选证书、九项 Gradle 门禁、APK 签名/版本/非调试/禁明文；Flutter analyze、27 tests 通过。只有保留域名 build-only 包，稳定 HTTPS、备份、设备升级和人工验收仍待完成；见 docs/development/android-release.md） |
| 科研阶段登录/令牌刷新 | PRD P0；ADR-0003 | Flutter auth；Spring identity；Next.js 同源代理 | AC-11、AC-12 | 开发中（Spring 身份和 Flutter 自动测试已通过；2026-09-08 管理端隔离 Edge/HTTP 实测旧令牌过期后并发面板只 Refresh 一次、内存令牌重载不保留。新增迟到 401、刷新网络失败、会话替换、Headers 边界回归，管理端共 9 tests，CI 已执行；生产构建通过。真机与生产身份验收仍待执行） |
| 组织/栋舍/栏舍离线同步 | PRD 3.1 | Flutter master-data；Spring masterdata | AC-01、AC-11 | 开发中（Spring 全量/增量游标、删除墓碑和组织隔离已通过 MySQL 集成测试；Flutter 已原子写入隔离缓存、搜索并拦截禁用栏舍，待实机 Compose 联调） |
| 移动端五入口真实数据 | PRD 5 | Flutter home/gallery/profile/task；Drift；Inventory API | AC-01、AC-02、AC-10 | 已自动化验证；首页启动读回已真机验证（v16 认证恢复后 `/me` 与当日任务 200，UI 显示 2 个真实任务和 `0 / 2`）。图库和“我的”按激活组织读取 Drift 证据、字节数、同步时间和网络策略；离线时仅显示本机可证实状态，不硬编码猪场、数量、进度或演示活动。采集、图库、报表和主数据同步的集中真机操作仍待用户手动完成 |
| 单图与三视图采集 | PRD 3.2 | Flutter capture；Spring capture | AC-01、AC-08 | 开发中（单图/三图本地采集、方向唯一和页面接线已测试；realme GT 7 Pro 已人工通过完整左/中/右三图强制关闭恢复，v0.1.0+3 明示三张缩略图并可查看大图；三视图不自动相加的复核实机回归待完成） |
| ROI | PRD 3.2/3.4 | Flutter ROI domain；推理合同 | AC-01、AC-07 | 已自动化验证（边界校验、草稿持久化和服务端 Manifest 校验已测试；HTTP Provider 对归一化检测框执行有限数值/边界校验，并以框中心落入 ROI、边界包含的口径过滤后重新计数） |
| 草稿恢复与本地媒体 | PRD 3.2 | Drift v5 CaptureDrafts/CaptureSets/LocalMediaAssets；MediaMaterializer | AC-01 | 已验证（流式物化、EXIF 方向/尺寸、原子持久化、数据库重开恢复已测试；realme GT 7 Pro 已人工验证三张本地证据在强制停止后完整恢复且可查看） |
| Outbox 与续传 | PRD 3.3 | Drift v6 OutboxEntries/UploadAssetEntries；UploadPackageSynchronizer；Upload API；Spring capture/inference dispatch | AC-02 | 开发中（完整采集组入队、逐 Blob 状态、稳定幂等键、租约、退避、三视图已确认 Blob 跳过、后台 WorkManager 批处理及 Commit 后同步标记均已自动化测试；隔离 Compose 已通过 Commit、事务 Outbox、MinIO、Celery、Callback 和 Commit 重放闭环。仍待真机执行上传中途断流后的仅剩余 Blob 续传与后台调度时序验收） |
| 幂等上传包 | OpenAPI Upload | Spring capture application/infrastructure/UI | AC-02、AC-03 | 已验证（Testcontainers MySQL 覆盖 create、Blob、Manifest、Commit 重放及唯一任务） |
| SHA-256 精确去重 | PRD 3.3 | Flutter hash；Spring capture；MySQL 唯一索引 | AC-04 | 已验证（同组织精确重复在 Manifest 阶段阻断的 MySQL 集成测试） |
| 感知哈希审核 | PRD 3.4 | Flutter capture/outbox；Spring capture/review；管理端 | AC-05 | 已自动化验证（Flutter 在后台 Isolate 中为支持且受尺寸/像素上限约束的图像生成 64 位 dHash，提交 Manifest；Spring 以汉明距离 <= 8 建立只读告警，绝不自动删除媒体；复核员可带原因解决告警并写入审计，媒体仍保留；Flutter 与 MySQL 集成测试均覆盖） |
| 推理安全降级 | 架构 7；ADR-0003 | Spring transactional Outbox/结果回调；Python Celery callback/UnavailableProvider | AC-06 | 已验证（隔离 Compose E2E 已实际经过 Commit、Outbox、Celery、受服务密钥保护的回调；unavailable Provider 不返回模拟数量。P1 故障栈进一步验证 Runner 未就绪 503、Provider 超时结构化为 `PROVIDER_TIMEOUT`、停止 fail-closed、重启后显式就绪及恢复成功；失败会话保持 review_required 且数量为空。真实获准 Provider 仍为 P1 阻塞） |
| 推理失败管理与重试 | PRD P1；架构 5/6 | OpenAPI；Spring inference administration/Outbox/audit；Next.js 管理端 | AC-06、AC-11 | 已验证（仅 FARM_ADMIN/SYSTEM_ADMIN 可按组织查询失败任务并带理由重试；每次重试创建保留原媒体、失败码和请求模型身份的新任务，原失败任务不可变。同键同理由顺序/并发重放只产生一个后继和一条审计，不同意图返回 409；晚到回调不能覆盖已人工确认会话。MySQL 8.4 V1–V9 集成测试及隔离 `pig-inventory-p1-retry` Compose E2E 已通过） |
| 三视图禁止简单相加 | PRD 3.4 | CaptureSetPolicy；Spring 回调归一化；Provider | AC-08 | 开发中（三视图成功结果在未启用验证多视角 Provider 时强制转为 review_required；研究模式单图可由检测框数量形成待复核候选值，三视图检测框始终不汇总且候选值为空；MySQL 集成测试已覆盖，待真机复核回归） |
| 人工确认和媒体锁定 | PRD 3.5 | Spring inventory/media/audit；Flutter session review | AC-09 | 已验证（隔离 Compose E2E 以 bootstrap SYSTEM_ADMIN 实际确认 unavailable 推理结果、锁定媒体、验证普通删除 409、执行带原因管理员软删除，并得到两条审计事件；见 `docs/development/p0-closure-e2e.md`） |
| 确认后审计更正 | PRD 3.5/6；OpenAPI 0.7.0 | Flyway V10；Spring inventory/audit；Next.js 管理端；Flutter 复核展示 | AC-09、AC-10、AC-11 | 已验证（自动化：MySQL 8.4 唯一当前版本、RBAC、幂等、审计与报表通过；2026-09-08 隔离 Edge 页面将 v1 17 更正为 v2 19，HTTP 读回旧 v1 superseded/17、相同锁定图片、只含 v2 的日报、同意图重放和变更意图 409；OPERATOR/跨组织更正 404。新增并通过晚到重试回调不得重新打开 superseded 原证据会话的测试。人工验收未替代，见 `docs/development/admin-runtime-e2e.md`） |
| 综合平均 | PRD 3.5/6 | InventoryAggregationPolicy；Spring inventory reports；Flutter tasks | AC-10 | 已验证（已新增按业务日期派生的栏舍任务、仅已确认日盘点报表和按栏舍/日期范围的原始均值/展示值 API；单元测试覆盖均值口径，隔离 Compose 以真实确认数量验证任务、日报和综合报表） |
| 已确认报表导出 | PRD P1；OpenAPI 0.6.0 | Spring inventory report export；Next.js 管理端 | AC-10、AC-11、AC-12 | 已自动化验证（PDF/XLSX 共用组织隔离的 confirmed-only 快照；限制 366 天/10,000 条，排除候选、失败、未确认、其他组织、模型/媒体内部信息；MySQL 集成、渲染/公式安全测试及隔离 Compose HTTP E2E 通过，PDF/XLSX 已做内容与视觉复核） |
| 组织隔离/RBAC | 范围、NFR | Spring Security；MySQL；合成 P0 fixture | AC-11 | 已自动化验证（真实 MySQL 成员关系与组织绑定 JWT 覆盖 OPERATOR 只读/不可确认、REVIEWER 可确认/不可覆盖删除、FARM_ADMIN 可确认/覆盖/审计，以及第二组织不可发现；隔离 Compose fixture 创建四个合成账号、两组织、栋舍和栏舍） |
| 私有对象存储和生产安全 | NFR | Compose/网关/部署配置；内部回调服务密钥 | AC-12 | 开发中（2026-09-08 回调服务密钥始终校验，与用户登录开关独立；缺失/错误/未配置密钥返回 401，用户 JWT 不可替代。MVC 安全链和隔离 HTTP/MySQL 两模式回归验证拒绝前无写入、合法 204/重放 200/冲突 409。派发器启动非空密钥门禁保持；生产 TLS、密钥轮换和恢复仍未验证） |
| 可观测性基线 | NFR | Spring Actuator/Micrometer；Python readiness；本地 promtool | NFR 可观测性 | 部分自动化验证（2026-09-08 Spring 61 tests、V11、上传阶段 Counter/重复拦截、只读队列/复核/终态/耗时/重试 Gauge、独立监控密钥、6 组规则测试及隔离 HTTP/MySQL 差值回归通过。未完成真实 Prometheus 告警流转、Broker/Worker 专项指标、端到端 P95 和目标容量验收；详见 `docs/development/business-observability.md`，不将诊断阈值当作生产 SLO） |
| 管理端态势与复核 | PRD 5 | Next.js；Flutter session review | AC-05、AC-09、AC-10 | 开发中（管理端已实现受认证登录、同源受限 API 代理、真实任务、会话受限媒体预览、候选框/置信度/模型身份/耗时展示、人工确认、近重复带理由解决、日报/综合及审计读取；候选与确认数量文案明确隔离，媒体只通过受认证业务 API Blob 传输。Next lint/typecheck/build 与隔离 Compose 真实 Chromium 候选证据回归已通过；2026-09-08 三个可选面板显式加载/无权限/失败/真实空状态，管理端共 24 tests；隔离 Edge 15 组异常/空数据与两个角色页面回归、刷新恢复均通过。人工键盘/130% 字体等验收按要求后置） |
| 初版品牌资产 | 视觉系统 | Flutter/Next.js Logo 资产 | 视觉评审、商标检索 | 开发中（临时资产，未注册） |
| 主流/低端 Android 覆盖 | NFR | realme GT 7 Pro / REDMI Note 14 5G 候选 | AC 设备测试 | 主流机已确定；低端机待取得 |
| 金蝶同步 | PRD 3.1 | ErpOrganizationProvider | P1 专项 | 阻塞（缺正式文档） |
| 真实 YOLOv13 | PRD P1 | 产品仓库外 ResearchHttpYolo Runner；正式为 Python http-yolo Provider | 推理金标回归 | 开发中（团队权重已完成 checksum、严格模型身份/readiness、ROI 二次过滤、MinIO/Worker/Callback/会话候选 E2E、结构化失败展示、Docker 故障注入、验证集选阈值后测试集一次性全量回归、研究发布清单、不可覆盖漂移基线和隔离版本回滚；当前研究阈值 0.60，测试 MAE 1.049、WAPE 3.75%、±2 内 93.44%。损坏候选 checksum 会 503 fail-closed 并可回滚到锚点。单图真实链路产生 25 个待复核候选，三视图仍禁止汇总。研究集分布不足以准入；正式自动计数仍阻塞于许可、授权业务金标、权重准入和负责人审批；见 `docs/research/team-yolov13-candidate-evaluation.md` 和 `docs/research/p1-model-release-rollback-benchmark.md`） |
| 视频/端侧/Agent | PRD P2 | 隔离 PoC | P2 专项 | 边界外 |

每个合并请求必须更新受影响行；只有自动化或可复现实机证据通过后才能标记为“已验证”。

## 2026-09-12 本轮功能候选证据

| 需求增量 | 实现 | 当前状态与边界 |
|---|---|---|
| 手工主数据维护 | 合同 PUT master-data；V12 命令台账；管理员表单 | 已验证：MySQL 组织/权限/并发幂等/版本/层级约束、Edge 新增及读回通过；手机新资料同步待人工验收 |
| 日期栏舍媒体库与删错 | GET media-assets；手机服务器/本机图库；后台删除入口 | 已验证：按栏日期隔离、删除后的确认拦截、确认与删除加锁、后台覆盖审计通过；真实手机浏览/删除交互待人工验收 |
| 历史日报与综合 | 手机日期任务和报表；管理端历史查询 | 已验证：后台历史日报、已确认投影、均值及参与日期读回；P02 真机显示确认 24，未确认新结果不顶替确认记录 |
| 视频证据人工流程 | MP4 采集/导入、持久化和播放；V13；Celery 手工结果分支 | 开发中：API/MinIO/Celery/回调、原文件一致、空候选、人工确认锁定及删除 409 全部通过；手机录制与播放待集中人工验收，不代表视频自动计数获批 |
| 正式候选及部署配置 | 同签名 APK、镜像包、production overlay/配置门禁 | 阻塞：正式服务器、域名与首批猪场账号尚未确定；已完成候选构建和配置检查，未正式上线 |

本轮自动验证：Spring test/verify 69 项；Admin 24 项与 lint/typecheck/build，完整固定 Edge 回归；Inference 38 项与视频运行回归；Flutter analyze、39 项含真实 TLS、Debug APK 通过。更新后的签名包和手机安装结果以 CURRENT_HANDOFF.md 为准。模型准确度研究按用户明确要求后置。

2026-09-12 恢复增量：已实现冷快照、归档校验与全新项目卷恢复；4 项安全测试及合成 HTTP/MySQL/MinIO/Redis 恢复演练通过（历史 17、当前 19、锁定媒体 SHA-256 和删除 409）。生产异机与加密密钥恢复仍待目标确定。用户已明确真机验收后置，不能标记为已执行。
