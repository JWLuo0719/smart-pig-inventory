# 移动 App 完整开发顺序

状态：执行基线
适用范围：Flutter Android P0 现场试用及其依赖的 Spring、Python、管理端和基础设施
权威上游：`docs/product/PRD.md`、`docs/product/acceptance-criteria.md`、`contracts/openapi.yaml`、`docs/architecture.md`

## 1. 目标与执行原则

首个可交付目标不是完成演示页面，而是在真实 Android 设备上完成以下证据闭环：

```text
同步并离线缓存栏舍
-> 选择栏舍
-> 拍摄/导入并物化原图
-> 保存方向、尺寸、EXIF、SHA-256 和 ROI
-> 杀进程后恢复草稿
-> 创建可重放 Outbox
-> 按 package/blob/manifest/commit 续传
-> 推理或人工复核
-> 确认结果并锁定媒体
```

执行时遵守以下顺序：

1. 业务口径先于页面。
2. 外部字段先修改 OpenAPI，再修改 Spring、Flutter 或 Web。
3. 数据库先新增 Flyway 迁移；不得修改已经应用的迁移。
4. Flutter 页面不得直接访问 Dio、Drift 或文件系统。
5. 每个阶段必须满足退出门禁，不能用演示数据或现场手工绕过。
6. 没有服务器真实结果时不显示数量。
7. 三视图 Provider 未验收前只能进入人工复核。
8. 每次合并更新需求追踪矩阵和可复现验证证据。

## 2. 工作流与分支

每项工作按以下顺序执行：

```text
需求/决策
-> 合同和状态机
-> 数据迁移
-> Domain/Application
-> Infrastructure
-> UI
-> 自动化测试
-> 实机或集成证据
-> 更新追踪矩阵
```

建议分支：

- `docs/*`：产品决定、合同说明和开发基线。
- `feat/mobile-*`：Flutter 纵向切片。
- `feat/api-*`：Spring 业务能力。
- `feat/inference-*`：推理编排与 Provider。
- `test/*`：跨模块集成和 E2E。

一个提交只包含一个可回滚目的；涉及合同或迁移时在提交说明中明确版本影响。

## 3. 阶段总览

| 阶段 | 目标 | 主要验收 | 是否允许并行 |
|---|---|---|---|
| 0 | 决策、合同和开发底座收口 | 合同校验、迁移策略、工具链 | 可与合成夹具并行 |
| 1 | Flutter 离线基础设施 | DB/文件/哈希/权限测试 | 后端可并行做主数据 |
| 2 | 主数据与身份 | 离线选栏、组织隔离 | 身份和主数据可并行 |
| 3 | 单图离线采集 | AC-01 单图子集 | 不与三图 UI 混做 |
| 4 | 三视图、ROI 与草稿恢复 | AC-01、AC-07、AC-08 客户端部分 | 可并行服务端上传 |
| 5 | 服务端上传状态机 | AC-03、AC-04 服务端部分 | 可并行 Flutter Outbox |
| 6 | Flutter Outbox 与弱网续传 | AC-02、AC-03、AC-04 | 依赖阶段 5 合同稳定 |
| 7 | 推理闭环与降级 | AC-06、AC-07、AC-08 | 管理端只读页可并行 |
| 8 | 图库、复核、确认和锁定 | AC-05、AC-09 | 管理端复核并行 |
| 9 | 任务、报表和综合盘点 | AC-10 | 依赖确认口径稳定 |
| 10 | RBAC、安全与运维 | AC-11、AC-12 | 从阶段 2 持续实施 |
| 11 | E2E、实机和试点准入 | AC-01 至 AC-12 | 最终门禁 |

## 4. 阶段 0：开发前置收口

### 4.1 产品和人工决策

必须登记并由负责人确认：

- 正式 OIDC/身份供应商及账号生命周期。
- 设备离线且 Token 过期时是否允许继续采集，以及最长离线时长。
- 用户是否可能属于多个组织，是否允许在 App 内切换组织。
- 业务日期按猪场时区还是设备时区，跨午夜班次如何归属。
- 任务由谁创建、分配粒度、截止时间和“完成”口径。
- 原图、缩略图、审计和本地已同步媒体的保留期限。
- 首批试点猪场、授权测试人员和试点边缘服务器。
- 低端 Android 验收设备是否可取得。

未确认项记录到 `docs/product/open-decisions.md`。实现可以使用明确标注的临时假设，但不得把临时假设写成上线承诺。

### 4.2 合同收口

完成以下合同后才能大规模实现页面：

- 当前用户、组织与角色查询。
- 主数据游标、删除项类型和游标失效恢复。
- 完整 Capture Manifest：采集时间、原名、尺寸、EXIF、方向、哈希、ROI。
- 上传包状态查询和可重放语义。
- 任务、图库、盘点列表和详情查询。
- 推理结果返回 Spring 的幂等合同。
- 普通删除、要求重拍、人工确认和管理员覆盖合同。
- 统一 400/401/403/404/409/422/429/5xx Problem 错误体。

合同完成定义：

- OpenAPI 3.1 校验通过。
- Flutter/Spring DTO 命名和空值语义一致。
- 每个写接口明确幂等键作用域和“同键不同载荷”行为。
- 组织 ID 的可信来源明确。
- ROI 坐标以 EXIF 纠正后的图像为基准，并验证不越界。

### 4.3 工具链和仓库

- 修复 Docker Desktop/WSL 并启动完整 Compose。
- 增加 Maven Wrapper，避免依赖系统 Maven。
- 建立 Python `.venv` 并安装锁定依赖。
- CI 固定 Flutter 版本，不再对已提交 Android 工程执行 `flutter create`。
- 增加 OpenAPI、JSON Schema、Flyway、许可证策略和 Compose smoke test。
- 修正文档中已过期的环境状态。

### 4.4 阶段退出门禁

- 所有不需要业务确认的合同缺口已经修复。
- 人工决策项有负责人和截止时间。
- Flutter analyze/test、Spring verify、Python pytest、Web lint/build 可重复执行。
- Compose 完整栈健康，MinIO 桶为私有。

## 5. 阶段 1：Flutter 离线基础设施

### 5.1 模块结构

```text
lib/
  core/
    auth/
    config/
    errors/
    network/
    storage/
    time/
  features/
    master_data/{data,domain,application,presentation}/
    capture/{data,domain,application,presentation}/
    outbox/{data,domain,application,presentation}/
    inventory/{data,domain,application,presentation}/
    gallery/{data,domain,application,presentation}/
```

首批抽象：

- `AuthSessionRepository`
- `MasterDataRepository`
- `MediaMaterializer`
- `MediaMetadataReader`
- `CaptureDraftRepository`
- `CaptureDraftUseCase`
- `OutboxRepository`
- `UploadPackageSynchronizer`
- `ConnectivityPolicy`
- `Clock`

### 5.2 本地数据库

至少包含：

- 当前账号、组织和同步游标。
- 组织、栋舍、栏舍及删除标记。
- CaptureDraft、CaptureSet、LocalMediaAsset。
- UploadPackage、UploadAsset、OutboxOperation。
- 服务器 package/session/job 映射。
- 尝试次数、下次重试时间、错误码、相关 ID。
- 盘点结果和媒体锁定状态缓存。

要求：

- 外键和查询索引明确。
- UTC 时间与业务日期分开。
- 每个 schemaVersion 都有升级测试。
- 草稿及其媒体/Outbox 使用事务写入。
- 2,000 栏舍本地搜索具备性能测试。

### 5.3 文件存储

- 先复制到 App 私有持久目录，再创建业务草稿。
- 使用流式 SHA-256，不使用整文件 `readAsBytes()`。
- 文件名不信任用户输入，目录按组织/草稿/资产 UUID 隔离。
- 校验复制后的大小和哈希。
- Commit 成功前禁止自动删除原图。
- 存储不足、权限拒绝和损坏文件必须返回可操作错误。

### 5.4 阶段退出门禁

- DB 创建、升级、事务回滚测试通过。
- 10MB 合成图片流式物化和哈希测试通过。
- 杀进程模拟后记录和文件仍可恢复。
- Android 主 Manifest 权限、应用名和开发签名路径正确。

## 6. 阶段 2：身份与主数据

### 6.1 身份

- 使用系统安全存储保存 Token；禁止 localStorage 类明文方案。
- 实现登录、刷新、退出和失效状态。
- 后台 Worker 不从普通输入参数接收长期凭据。
- 离线采集权限依据最后一次已验证会话和产品确认的离线策略。
- 组织和角色只接受服务端认证上下文。

### 6.2 主数据

- 全量首次同步、游标增量同步、删除项和游标失效重置。
- 同步事务失败不得覆盖旧的可用缓存。
- 离线时显示最后同步时间。
- 禁用栏舍不可创建新草稿，但已有草稿仍可恢复并提示处理方式。

### 6.3 阶段退出门禁

- 不同组织缓存隔离。
- 断网可搜索和选择最近同步栏舍。
- Token 过期、刷新失败和离线状态有明确 UI。
- 达到 AC-11 的基础隔离要求。

## 7. 阶段 3：单图离线采集

按以下顺序实现：

1. 从真实缓存选择栏舍。
2. 创建稳定的草稿、CaptureSet 和 asset UUID。
3. 相机拍摄或图库导入。
4. 处理 Android Activity 回收后的 lost data。
5. 物化、流式哈希、读取尺寸和允许的 EXIF。
6. 展示预览，支持删除和重拍。
7. 保存草稿但不显示数量。
8. 完成后原子创建 queued Outbox。

退出门禁：

- 强退、重启和返回键不丢失已物化图片。
- 同一草稿重试保持 UUID、哈希、方向和业务日期稳定。
- 相机权限拒绝、存储不足、损坏图片有自动化测试。

## 8. 阶段 4：三视图、ROI 与草稿恢复

- 三图只允许 left、center、right 各一张。
- 切换单图/三图前检查已有媒体并要求确认，不能静默清空。
- ROI 在 EXIF 纠正后的预览坐标中编辑并归一化保存。
- 校验 `x + width <= 1`、`y + height <= 1`。
- 草稿恢复到下一缺失方向。
- 三图完成后仍不展示自动合计数量。

退出门禁：AC-01、AC-07 客户端部分和 AC-08 客户端部分通过。

## 9. 阶段 5：Spring 上传状态机

实现顺序：

1. 认证组织上下文和栏舍归属校验。
2. 创建/恢复 UploadPackage。
3. Blob 流式写临时对象并校验 SHA-256/大小。
4. Manifest 校验方向、引用、ROI 和精确重复。
5. Commit 使用事务 CAS 创建 Session、CaptureSet、Media、InferenceJob 和 Outbox。
6. 孤儿临时对象按安全窗口回收。
7. 统一 Problem 错误和相关 ID。

必须用 Testcontainers MySQL/MinIO 验证：

- 相同请求重放。
- 相同幂等键不同载荷冲突。
- 20 次并发 Commit 只创建一个业务任务。
- 组织内重复阻断、组织间不泄露。
- 数据库回滚时不产生正式对象引用或丢失任务。

退出门禁：AC-03、AC-04 服务端证据通过。

## 10. 阶段 6：Flutter Outbox 与弱网续传

状态建议：

```text
queued
-> creating_package
-> uploading_blobs
-> putting_manifest
-> committing
-> synced
```

任何中间状态可进入 `retry_wait` 或 `blocked`，但不得删除原图。

实现要求：

- 每个 Blob 独立持久化完成状态。
- 指数退避加随机抖动，区分可重试和永久错误。
- 前台手动重试和 WorkManager 使用同一个 Synchronizer。
- 使用数据库租约避免前后台并发上传同一包。
- Token 失效进入等待认证，不伪装成同步成功。
- Commit 响应持久化后才标记 synced。
- 支持进度、取消自动重试和诊断信息，但取消不删除证据。

退出门禁：AC-02、AC-03、AC-04 E2E 通过。

## 11. 阶段 7：推理闭环与安全降级

- Spring Outbox 幂等派发推理任务。
- Python 按固定合同返回或回调结果。
- Spring 是任务最终状态的业务事实来源。
- unavailable、超时、格式错误和 Worker 重启进入可解释状态。
- 单图 Provider 成功后按 ROI 中心点规则计算候选值。
- 三视图未启用验证 Provider 时直接进入人工复核。
- 保存模型 key、版本、checksum、adapter version、来源和耗时。

退出门禁：AC-06、AC-07、AC-08 通过。

## 12. 阶段 8：图库、复核、确认和锁定

- 图库按栏舍/日期/状态查询，图片使用短期签名 URL。
- 未锁定且允许删除的媒体支持普通软删除。
- 感知近重复只生成复核告警。
- 复核员可确认、填写修正原因或要求重拍。
- 确认事务同时创建结果版本、锁定全部引用媒体并写审计。
- 管理员覆盖必须填写原因，只允许软删除。

退出门禁：AC-05、AC-09 通过。

## 13. 阶段 9：任务、报表和综合盘点

- 任务列表、栋舍进度和栏舍详情接真实 API。
- 同栏舍同业务日期只保留一个最终确认版本。
- 更正创建新版本，不覆盖历史。
- 综合盘点只包含确认状态，保留原始均值和参与日期。
- App 不在服务器结果前计算或展示业务数量。

退出门禁：AC-10 通过。

## 14. 阶段 10：RBAC、安全、运维和管理端

- OPERATOR、REVIEWER、FARM_ADMIN、SYSTEM_ADMIN 后端授权测试。
- 所有列表和详情查询验证组织隔离。
- 生产 CORS 白名单、TLS、私有桶、短签名 URL。
- 日志脱敏，禁止 Token、密码、密钥、原图和完整签名 URL。
- 上传成功率、队列深度、推理耗时、复核率、重试和重复拦截指标。
- 备份恢复演练、日志轮转、磁盘告警和 Outbox 堆积告警。
- 管理端按态势、任务、复核、组织、报表、模型同步和审计顺序接线。

退出门禁：AC-11、AC-12 通过。

## 15. 阶段 11：最终验证和试点准入

### 15.1 自动化

- Spring：`mvn test`、`mvn verify`。
- Flutter：格式化、analyze、test、debug APK。
- Python：pytest、合同和金标回归。
- Web：lint、typecheck、build、关键 E2E。
- Infrastructure：Compose config、完整启动、健康和恢复 smoke test。

### 15.2 实机

realme GT 7 Pro 和低端候选机执行：

- 断网三图。
- 杀进程和设备重启。
- 高延迟、低带宽和中途断流。
- 权限拒绝、低存储、EXIF 旋转。
- 后台上传和厂商省电策略。
- 130% 字体、触控目标和关键错误提示。
- 冷启动、搜索和上传内存指标。

### 15.3 发布判定

只有 AC-01 至 AC-12 都具备自动化或可复现实机证据，且人工决策项关闭后，才允许进入现场试用。

## 16. 每阶段完成定义

每项功能只有满足以下条件才算完成：

- 对应需求和 AC 编号明确。
- OpenAPI/Schema/Flyway 先行且通过校验。
- Domain 和失败分支有测试。
- UI 不含未标记演示数据。
- 错误说明数据是否安全及下一步动作。
- 无真实结果时不展示数量。
- 需求追踪矩阵已更新。
- 验证命令、设备和结果可复现。

## 17. 当前建议的首个实施切片

按以下提交顺序开始：

1. `docs: establish mobile development sequence and open decisions`
2. `contract: complete capture manifest and error semantics`
3. `chore: align Android and CI development baseline`
4. `feat: introduce versioned Drift offline domain schema`
5. `feat: materialize media and calculate streaming sha256`
6. `feat: persist and restore single-image drafts`
7. `feat: add three-view and ROI draft workflow`
8. `test: prove AC-01 with process-restart fixtures`

在第 8 步完成前，不扩展演示首页、任务页或图库的视觉功能。
