# 当前状态

更新时间：2026-08-27（P0 真机验收进行中）
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
- 建立 Next.js 管理端“现场态势”：受认证登录后通过同源受限代理读取真实当日栏舍任务、会话媒体、近重复告警、日报/综合报表和审计；可由后端授权执行人工确认与近重复解决，不再展示演示数量或暴露对象 URL。
- 切换 Docker Compose 为 MySQL、Redis、MinIO、Spring、推理 API/Worker、Next.js 和 Nginx 网关。
- 建立 CI、开发规范、测试规范、许可证边界和冻结原型说明。
- 建立工作站初始化/核验脚本、随机本机 `.env` 生成流程和测试数据治理规则。
- 已对外部 YOLO 研究集生成本机忽略的完整性清单：500 张图像、12,421 个标注目标，图像—标签配对问题为 0；这不是业务金标或产品分发授权证明。
- 已建立本地 Git 首次基线；尚未配置远端仓库或向外部服务推送任何内容。
- 已安装 Flutter 3.44.7、Android SDK 36、Build Tools 36.0.0 和 platform-tools；Android SDK 许可证已接受，Android 原生壳与 Drift 生成代码已入工程。
- 已安装 Docker Desktop 4.87.0（per-user、WSL 2、Linux containers），并将 WSL 数据根设置为 `D:\DockerDesktop\wsl-data`；已恢复 Desktop 引擎并完成 Compose 首次完整启动。
- 已安装 Maven 3.9.11 至 `D:\ProgrammingLanguage\apache-maven-3.9.11`，并将其纳入本机核验脚本。
- 已用 Testcontainers MySQL 8.4 实际验证 Flyway V1/V2；`src/test/resources/docker-java.properties` 将 Docker Java 客户端 API 固定为 1.44，解决 Docker Desktop 29.7 经 Windows npipe 的兼容问题，不依赖系统全局环境变量。
- Flutter Drift 已升级至本地 schema v6：单图/三图媒体物化、流式 SHA-256、EXIF 方向/尺寸、方向唯一、ROI 边界持久化、完整采集组入队，以及认证上下文、组织主数据游标缓存均具备自动化证据；上传队列现已实现 create/blob/manifest/commit 的持久状态机、租约、失败分流和 Commit 后才标记 synced，WorkManager 已接入安全存储会话、网络约束、指数退避和后台批处理，并已在 realme GT 7 Pro 验证网络恢复、应用重启后的自动上传。
- 已实现推理闭环的系统边界：Spring 对提交事件进行带租约的事务 Outbox 派发；Python Celery Worker 以 `job_id` 回传最终结果；Spring 以结果指纹保证相同回调重放成功、不同结果冲突，并将结果和模型身份写入业务库。未获验证的三视图结果强制进入人工复核，不使用自动数量。
- 已部署 iMoonLab YOLOv13 Nano 的产品仓库外本机研究 Runner，并以隔离 Compose 项目验证了 MinIO 读取、原始模型推理、产品 HTTP Provider 调用与二次安全降级。该路径始终返回人工复核和空计数；它不是获准的猪只自动计数模型。
- 已实现 P0 审计确认纵向切片：会话结果查询、复核员确认/手工修正、确认幂等重放、事务锁定全部引用媒体、普通删除对锁定证据的冲突拒绝、AuditEvent，以及仅管理员可用的带原因软删除。Flutter 已可从已提交上传队列进入服务器复核页；隔离 Compose 已验证 Commit -> Outbox -> Celery -> 受服务密钥保护的回调 -> 人工确认/锁定/软删除闭环。已新增真实任务投影、仅确认日盘点日报和综合平均 API，并将移动端任务页接到真实数据；近重复的服务端告警/复核 API 已实现，管理端已接入任务与近重复告警，移动端感知哈希生成已完成；管理端媒体审核/确认和报表页面仍未完成。
- P0 真机验收发现并修复三项客户端/管理端缺陷：局域网 HTTP 下管理端 `crypto.randomUUID` 不可用、采集页伪造“3 个采集包”离线计数且仅展示第一张恢复证据、复核页 Access Token 过期时未自动刷新。Flutter v`0.1.0+3` 已显示左/中/右本地证据缩略图和大图、取消伪造状态，并在复核读取/确认 401 时尝试 Refresh Token 重试；管理端已提供兼容 UUID fallback。对应实机回归尚待执行。
- 已完成不依赖人工测试的 P0 管理/权限切片：管理端可受认证预览会话媒体、人工确认、解决近重复告警、读取日报/综合报表及审计；媒体通过业务 API 流式读取，未暴露对象 URL。新增隔离 `pig-inventory-p0` 专用合成 OPERATOR、REVIEWER、FARM_ADMIN、第二组织账号与主数据 fixture；MySQL/JWT 自动化覆盖角色和跨组织不可发现，隔离 Compose HTTP smoke 已以四个合成账号验证角色/组织任务范围。近重复解决要求理由、幂等并写审计，绝不删除媒体。Flutter 为复核与 Outbox 的 401 refresh/retry 加入自动化测试，上传重放仍复用原幂等键。

## 已验证证据

| 范围 | 结果 |
|---|---|
| Spring 上传链路、身份、主数据、领域与 Flyway 集成测试 | `mvn test` success；31 tests passed，0 skipped；Testcontainers 实际启动 MySQL 8.4 并应用 V1–V8，覆盖 create/blob/manifest/commit 重放、并发 Commit、事务 Outbox、精确重复阻断、Bootstrap 管理员、登录、刷新轮换、登出撤销、主数据全量/增量隔离、近重复解决审计及 OPERATOR/REVIEWER/FARM_ADMIN/第二组织 RBAC |
| Python Provider/合同漂移/Worker 注册测试 | 6 tests passed |
| Next.js | ESLint passed；TypeScript passed；production build passed（管理端媒体预览、确认、报表、审计接线后复验） |
| OpenAPI | openapi-spec-validator 0.7.2 passed |
| 推理 JSON Schema | JSON 语法与 Python 序列化键集合测试通过 |
| 外部 YOLO 数据清单 | 500 图像、12,421 标注目标、0 图像—标签配对问题；本机生成且 Git 忽略 |
| Flutter Android | `flutter analyze` 通过；25 项测试通过（含复核 401 Refresh Token 重试及 Outbox 401 后原幂等键重试）；v`0.1.0+3` debug APK 已构建，SHA-256 `d18735318641edbac62a608daa8acb04149141b22f4874bbdb2839b5ee864d46`（嵌入当次 LAN 地址） |
| Docker Desktop / Compose | 客户端/服务端版本校验通过；完整 Compose 已构建并启动；MySQL、Redis、MinIO、推理 API、Spring、管理端和网关健康；认证启用的独立 Compose 已验证 bootstrap 登录、`/me`、令牌刷新及组织/栋舍/栏舍主数据游标同步；LAN E2E 栈已用于真机三图断网/强杀恢复上传验证 |
| Flyway / MinIO | MySQL 已实际应用 V1/V2；`minio-init` 已完成私有桶初始化 |
| Flutter 离线采集与上传恢复 | analyze 通过；23 项测试通过；v`0.1.0+3` debug APK 构建成功；10MB 流式物化、方向唯一、ROI、本地入队和三视图剩余 Blob 续传均覆盖。realme GT 7 Pro 已人工验证完整左/中/右三图强制关闭后恢复：三张缩略图可见、可打开大图、保持同一采集组且不显示数量（AC-01 该场景通过）。当前完整三图包也已自动完成上传并进入 `已提交，等待处理`；复核页 Token 自动刷新修复待实机回归。 |
| Python Provider | pytest 通过；6 项测试通过 |
| 推理派发、结果回调与确认锁定 | Maven 29 项通过、0 skipped；Testcontainers MySQL 8.4 已实际应用 V1-V7。隔离 Compose 以受认证的 bootstrap SYSTEM_ADMIN 完成 create/blob/manifest/commit、Outbox、Celery unavailable 回调（HTTP 204）、review_required、人工确认、媒体锁定、普通删除 409、管理员软删除和两条 AuditEvent；详情见 `docs/development/p0-closure-e2e.md`。Python `pytest` 6 项、OpenAPI 校验均通过 |
| YOLOv13 研究部署 | 外部 Runner 已健康；使用 Nano 权重完成私有 MinIO 对象推理。隔离产品 Worker 选择 `research-http-yolo` 并强制 `review_required`/空计数 |

## 未验证与阻塞

- Docker Desktop 初次启动的 WSL 引擎问题已通过重新启动 Desktop 进程恢复；完整栈、Flyway、私有 MinIO 桶与网关健康已复验。`docker compose config --quiet` 已复验。管理端 Docker 构建曾因缺少 `.dockerignore` 覆盖 Linux `node_modules` 而失败，已修复并验证构建。
- `mvn verify` 的 Flyway 运行时对 MySQL 8.4 输出“最新版已验证至 MySQL 8.1”的升级建议，但 V1/V2 已实际成功迁移；进入发布准备前应升级/复验 Flyway 与 MySQL 8.4 的兼容性，或固定到受支持的 MySQL 版本。
- P0 上传包 create/blob/manifest/commit、事务 Outbox 派发、MinIO 暂存提升、受服务密钥保护的回调、Bootstrap 管理员、login/refresh/logout/me、JWT 刷新轮换和组织隔离主数据同步均已实现；Flutter 已接入安全令牌存储、7 天离线恢复、主数据缓存、持久化 Outbox 和 WorkManager。实机已验证完整三视图强杀恢复及一次自动 Commit；上传中途断流仅续传剩余 Blob、复核页 Refresh Token 回归、完整 RBAC 与后台 Worker 实机 E2E 仍未完成。
- 金蝶正式 API、线上 YOLOv13 权重、模型许可证、金标基准和部署服务器规格尚未提供。
- 提供的 `yolov13-official-main.zip` 已核实为 Ultralytics AGPL-3.0 源码且不含权重；不能直接纳入专有产品主线。当前仅保留独立 HTTP Provider 合同，待许可与金标准入后启用真实模型。
- 已采用 iMoonLab 上游仓库的 Nano 权重开展本机隔离研究测试；其 AGPL-3.0 代码和权重仍未获得专有产品、现场或自动计数准入。默认开发卷含历史 MySQL 账号口令，不与当前 `.env` 一致；本轮通过新建的 `pig-inventory-yolo-research` 隔离卷完成测试，未改写原卷。
- 低端 Android 候选机是否可获得，以及首批试点猪场、边缘服务器规格仍待确认。

## 发布判定

目前只完成可持续迭代的架构与界面基线，不是可现场使用版本。只有 `docs/product/acceptance-criteria.md` 的 AC-01 至 AC-12 均具备自动化或实机证据后，才能进入现场试用。
