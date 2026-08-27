# 当前状态

更新时间：2026-08-21
阶段：Development Readiness / Not Release Ready

## 已决定

- 采用路线 B+：Flutter + Next.js + Spring Boot/MySQL + 独立 Python 推理服务。
- 学长代码 `eg/` 只读并被 Git 忽略；以 clean-room 方式独立实现。
- Django 原型冻结，只保留行为回归价值；Spring 是唯一新业务主干。
- Android、服务端推理、照片闭环优先。视频、端侧、多视角自动去重和 Agent 编排后置。
- 产品名称确定为“智慧猪场场主”；初版原创 Logo 已入库，可在品牌定稿后替换。
- V1 明确不包含死猪上报；作为后续独立业务域候选。
- MinIO 继续作为默认对象存储；上线前仍需完成其 AGPL 分发义务评估。
- 主流 Android 验收机为 realme GT 7 Pro；低端机候选为 REDMI Note 14 5G（6GB+128GB），待采购或借测确认。
- 外部 YOLO 研究数据集只可作为本机只读验证来源；产品仓库只保留脚本和数据治理规则，不保存原始图片、标签或生成清单。

## 本轮完成

- 建立综合 PRD、范围边界、非功能需求、视觉系统、信息架构、验收标准和需求追踪矩阵。
- 固定业务 OpenAPI、推理请求/结果 JSON Schema、上传状态机和路线 B+ ADR。
- 建立 Spring Boot 3/Java 21 主服务、MySQL Flyway 基线、组织成员、证据链、模型注册、审计和事务 Outbox 表。
- 建立 Python FastAPI/Celery Provider 骨架，默认 Unavailable Provider 不产生模拟数量。
- 重构 Flutter 五入口页面壳、现场视觉组件、Drift 主数据/草稿/媒体/Outbox 草案和新版上传客户端合同。
- 建立 Next.js 管理端“现场态势”页面框架；所有静态数量都已标明为演示数据。
- 切换 Docker Compose 为 MySQL、Redis、MinIO、Spring、推理 API/Worker、Next.js 和 Nginx 网关。
- 建立 CI、开发规范、测试规范、许可证边界和冻结原型说明。
- 建立工作站初始化/核验脚本、随机本机 `.env` 生成流程和测试数据治理规则。
- 已对外部 YOLO 研究集生成本机忽略的完整性清单：500 张图像、12,421 个标注目标，图像—标签配对问题为 0；这不是业务金标或产品分发授权证明。
- 已建立本地 Git 首次基线；尚未配置远端仓库或向外部服务推送任何内容。
- 已安装 Flutter 3.44.7、Android SDK 36、Build Tools 36.0.0 和 platform-tools；Android SDK 许可证已接受，Android 原生壳与 Drift 生成代码已入工程。
- 已安装 Docker Desktop 4.87.0（per-user、WSL 2、Linux containers），并将 WSL 数据根设置为 `D:\DockerDesktop\wsl-data`；已恢复 Desktop 引擎并完成 Compose 首次完整启动。
- 已安装 Maven 3.9.11 至 `D:\ProgrammingLanguage\apache-maven-3.9.11`，并将其纳入本机核验脚本。
- 已用 Testcontainers MySQL 8.4 实际验证 Flyway V1/V2；`src/test/resources/docker-java.properties` 将 Docker Java 客户端 API 固定为 1.44，解决 Docker Desktop 29.7 经 Windows npipe 的兼容问题，不依赖系统全局环境变量。
- Flutter Drift 已升级至本地 schema v6：单图/三图媒体物化、流式 SHA-256、EXIF 方向/尺寸、方向唯一、ROI 边界持久化、完整采集组入队，以及认证上下文、组织主数据游标缓存均具备自动化证据；上传队列现已实现 create/blob/manifest/commit 的持久状态机、租约、失败分流和 Commit 后才标记 synced，WorkManager 已接入安全存储会话、网络约束、指数退避和后台批处理，待 Android 后台触发实机验证。

## 已验证证据

| 范围 | 结果 |
|---|---|
| Spring 上传链路、身份、主数据、领域与 Flyway 集成测试 | `mvn verify` success；17 tests passed，0 skipped；Testcontainers 实际启动 MySQL 8.4 并应用 V1/V2/V3/V4，覆盖 create/blob/manifest/commit 重放、并发 Commit、事务 Outbox、精确重复阻断、Bootstrap 管理员、登录、刷新轮换、登出撤销及主数据全量/增量隔离 |
| Python Provider/合同漂移/Worker 注册测试 | 3 tests passed |
| Next.js | ESLint passed；TypeScript passed；production build passed |
| OpenAPI | openapi-spec-validator 0.7.2 passed |
| 推理 JSON Schema | JSON 语法与 Python 序列化键集合测试通过 |
| 外部 YOLO 数据清单 | 500 图像、12,421 标注目标、0 图像—标签配对问题；本机生成且 Git 忽略 |
| Flutter Android | `flutter analyze` 通过；21 项测试通过；`flutter build apk --debug` 成功，debug APK 已生成 |
| Docker Desktop / Compose | 客户端/服务端版本校验通过；完整 Compose 已构建并启动；MySQL、Redis、MinIO、推理 API、Spring、管理端和网关健康；认证启用的独立 Compose 已验证 bootstrap 登录、`/me`、令牌刷新及组织/栋舍/栏舍主数据游标同步；LAN E2E 栈已用于真机三图断网/强杀恢复上传验证 |
| Flyway / MinIO | MySQL 已实际应用 V1/V2；`minio-init` 已完成私有桶初始化 |
| Flutter 离线采集与上传恢复 | analyze 通过；20 项测试通过；debug APK 构建成功；10MB 流式物化、方向唯一、ROI、本地入队和三视图剩余 Blob 续传均覆盖；realme GT 7 Pro 已验证单图/三图拍摄和入队、不显示数量、三图 left 后强杀恢复到 center，以及三图断网强杀恢复、恢复网络后重试提交闭环 |
| Python Provider | pytest 通过；3 项测试通过 |

## 未验证与阻塞

- Docker Desktop 初次启动的 WSL 引擎问题已通过重新启动 Desktop 进程恢复；完整栈、Flyway、私有 MinIO 桶与网关健康已复验。`docker compose config --quiet` 已复验。管理端 Docker 构建曾因缺少 `.dockerignore` 覆盖 Linux `node_modules` 而失败，已修复并验证构建。
- `mvn verify` 的 Flyway 运行时对 MySQL 8.4 输出“最新版已验证至 MySQL 8.1”的升级建议，但 V1/V2 已实际成功迁移；进入发布准备前应升级/复验 Flyway 与 MySQL 8.4 的兼容性，或固定到受支持的 MySQL 版本。
- P0 上传包 create/blob/manifest/commit 的 Controller/Application/Infrastructure、事务 Outbox 记录、MinIO 暂存提升和 MySQL 集成测试，以及环境变量一次性 Bootstrap 管理员、login/refresh/logout/me、JWT、刷新令牌轮换和组织隔离的主数据全量/增量同步已实现；Flutter 已接入安全令牌存储、登录/刷新/登出、7 天离线会话恢复、真实主数据缓存同步、持久化 Outbox 上传状态机和 WorkManager 后台任务。真实 Outbox 派发、完整 RBAC，以及后台 Worker 的 Android 实机 E2E 尚未实现。
- 金蝶正式 API、线上 YOLOv13 权重、模型许可证、金标基准和部署服务器规格尚未提供。
- 低端 Android 候选机是否可获得，以及首批试点猪场、边缘服务器规格仍待确认。

## 发布判定

目前只完成可持续迭代的架构与界面基线，不是可现场使用版本。只有 `docs/product/acceptance-criteria.md` 的 AC-01 至 AC-12 均具备自动化或实机证据后，才能进入现场试用。
