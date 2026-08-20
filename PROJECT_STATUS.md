# 当前状态

更新时间：2026-08-20  
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

## 已验证证据

| 范围 | 结果 |
|---|---|
| Spring 编译与领域测试 | Maven build success；6 tests passed |
| Python Provider/合同漂移/Worker 注册测试 | 3 tests passed |
| Next.js | ESLint passed；TypeScript passed；production build passed |
| OpenAPI | openapi-spec-validator 0.7.2 passed |
| 推理 JSON Schema | JSON 语法与 Python 序列化键集合测试通过 |
| 外部 YOLO 数据清单 | 500 图像、12,421 标注目标、0 图像—标签配对问题；本机生成且 Git 忽略 |
| Compose | YAML 语法通过；Docker 运行验证未执行 |

## 未验证与阻塞

- Flutter SDK 已安装并固定；Android SDK/许可证尚未完成，无法生成原生 Android 壳、Drift 代码或验证 APK。
- 本机尚未安装 Docker Desktop；需由用户确认 Docker 许可并选择其 WSL 数据目录后，才能执行 `docker compose config`、镜像构建、MySQL Flyway 实跑和健康检查。
- P0 上传包 Controller/Service/Mapper、真实持久 Outbox 派发、登录/RBAC、真实页面数据接线尚未实现。
- 金蝶正式 API、线上 YOLOv13 权重、模型许可证、金标基准和部署服务器规格尚未提供。
- 低端 Android 候选机是否可获得，以及首批试点猪场、边缘服务器规格仍待确认。

## 发布判定

目前只完成可持续迭代的架构与界面基线，不是可现场使用版本。只有 `docs/product/acceptance-criteria.md` 的 AC-01 至 AC-12 均具备自动化或实机证据后，才能进入现场试用。
