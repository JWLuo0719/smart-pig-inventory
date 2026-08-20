# 下一步

## Iteration 1：可运行开发底座

1. 完成 Android SDK 安装及许可证确认后，在 `apps/mobile` 执行 `flutter create`，评审并提交 Android 原生壳；生成 Drift 代码，跑 analyze/test/debug APK。工作站规则见 `docs/development/workstation-setup.md`。
2. 用户确认 Docker Desktop 许可和 WSL 数据目录后，安装 Docker Desktop，运行 Compose 配置、镜像、MySQL Flyway、MinIO 私有桶和各健康检查。首个试点部署基线见 `docs/deployment/pilot-baseline.md`。
3. 为 Spring 增加本地开发身份服务方案或连接现有 OIDC；生产 Profile 保持强制 JWT。
4. 增加 Testcontainers MySQL 集成测试，锁定 BINARY UUID、JSON、CHECK、唯一索引和并发语义。

## Iteration 2：AC-01 至 AC-04

1. 实现主数据增量同步和组织隔离。
2. 实现采集包 create/blob/manifest/commit 的 Controller、Application Service、Mapper 和事务 Outbox。
3. Flutter 完成真实媒体物化、SHA-256、草稿恢复、Repository/UseCase 和前后台 Outbox。
4. 通过断网三图、杀进程、弱网恢复、并发 Commit 和精确重复 E2E。

## Iteration 3：AC-05 至 AC-12

1. 实现近重复审核、人工确认、媒体锁定、带原因软删除和审计。
2. 管理端接入任务、媒体审核、组织栏舍、报表、模型同步和审计 API。
3. 完成综合平均、RBAC、安全配置、备份恢复和实机测试：主流机固定为 realme GT 7 Pro；低端机优先 REDMI Note 14 5G（6GB+128GB），不可获得时选择 Android 14+、6GB RAM/128GB 存储、UFS 2.2 级别或更低的等效机型。

## P1 准入项

- 取得金蝶正式接口文档后实现 Kingdee Provider；此前只用 Manual/Mock。
- 取得 YOLO 权重、许可证和金标集后实现 HttpYolo Provider；通过回归门禁前保持 unavailable。
- 端侧、多视角、视频和 Agent 均以隔离 PoC 验证，不进入 P0 关键路径。

## 已准备的测试数据边界

- 已提供外部 YOLO 研究集的只读扫描脚本；它生成本机忽略的 SHA-256/标注摘要，不复制图片或标签。
- 仍需取得经授权的业务金标、左中右采集组和弱网/重启场景媒体；具体准入规则见 `docs/development/test-data-governance.md`。

## 仍需确认

- 首批试点猪场、低端 Android 候选机是否可获得，以及边缘服务器规格。
- 数据保留年限、备份恢复目标是否接受当前 NFR 草案。
