# 下一步

完整实施顺序和阶段退出门禁见 `docs/development/mobile-development-sequence.md`；需要负责人确认的事项统一登记在 `docs/product/open-decisions.md`。后续实现必须按合同 -> 迁移 -> Domain/Application -> Infrastructure -> UI -> 验证的顺序执行。

## Iteration 1：可运行开发底座

1. 已完成 Android 原生壳、Drift 生成、analyze/test 与 debug APK；后续在真实 Android 设备验证相机、权限和后台上传。工作站规则见 `docs/development/workstation-setup.md`。
2. 已恢复 Docker Desktop WSL 引擎并完成完整 Compose、MySQL Flyway V1/V2、私有 MinIO 桶和网关健康验证；后续持续保留 Compose smoke test。首个试点部署基线见 `docs/deployment/pilot-baseline.md`。
3. 已按 ADR-0003 实现环境变量一次性管理员初始化、BCrypt、JWT、可撤销刷新令牌及 login/refresh/logout/me，并已接入 Flutter 安全存储、登录/刷新/登出和 7 天离线会话恢复；认证启用的 Compose 已完成 API smoke test，下一步在实机验证身份与主数据同步，后续通过身份适配器接入金蝶账号。
4. 已增加 Testcontainers MySQL Flyway 集成测试；持续保留该门禁。下一步扩展至 BINARY UUID、JSON、CHECK、唯一索引、对象写入和并发语义，并补充 MinIO 集成测试。

## Iteration 2：AC-01 至 AC-04

1. 已实现以 JWT 激活组织为可信来源的主数据全量/增量同步、游标失效全量恢复和删除墓碑，并接入 Flutter 的组织隔离缓存、搜索、禁用栏舍拦截和真实 API；认证 Compose 与 realme GT 7 Pro 已验证登录、同步和离线缓存闭环。
2. 已实现采集包 create/blob/manifest/commit 的 Controller、Application Service、JDBC Infrastructure、MinIO 暂存提升和事务 Outbox；Spring 现在可领取 Outbox、租约恢复后派发 Python 任务，Python Worker 通过服务密钥幂等回传最终结果。下一步完成 Compose 端到端派发/回调、失败重试可观测性以及 MinIO HTTP 集成测试。
3. Flutter 已完成媒体物化、流式 SHA-256、单图/三图草稿、ROI 口径、本地完整采集组入队、草稿恢复 UI、主数据接线，以及带租约、退避和 Commit 后同步标记的前后台真实上传状态机；三视图断网强杀恢复、恢复网络后重试提交真机 E2E 已通过，三视图剩余 Blob 自动化续传已通过；WorkManager 已在 realme GT 7 Pro 验证网络恢复、应用重启后的自动提交。下一步接入任务状态/复核结果展示，完成服务端推理 Compose E2E。
4. 断网三图、杀进程恢复和恢复网络重试已通过；仍需通过上传中途断流只续传剩余 Blob、WorkManager 后台执行、推理/复核和并发 Commit E2E。

## Iteration 3：AC-05 至 AC-12

1. 已完成不依赖人工测试的 P0 开发：管理端会话媒体预览/人工确认、日报/综合报表、审计页面；合成 OPERATOR/REVIEWER/FARM_ADMIN 与第二组织 fixture；RBAC/跨组织自动化 MySQL/JWT 集成测试；近重复告警带理由解决审计。下一步是在 `pig-inventory-p0` 隔离 Compose 中执行浏览器与真机验收，不得重置默认 MySQL 卷。P0 人工验收状态见 `docs/development/p0-manual-acceptance-runbook.md`。
2. 管理端局域网 HTTP 登录的 `crypto.randomUUID` 兼容性已修复，但需要以 `docker compose -p pig-inventory-p0 up --build -d admin-web gateway` 部署回归。继续接入会话媒体预览/确认、组织栏舍、日报/综合报表、模型同步和审计 API。
3. Flutter v`0.1.0+3` 已修复三图恢复证据预览、取消伪造离线队列数量，并在复核页 401 时自动 Refresh Token 后重试读取/确认。该路径及 Outbox 运行中 Access Token 过期后以同一幂等键重试均已有 Flutter 自动化测试；主流机固定为 realme GT 7 Pro，待实机回归，低端机优先 REDMI Note 14 5G（6GB+128GB）。

## P1 准入项

- 取得金蝶正式接口文档后实现 Kingdee Provider；此前只用 Manual/Mock。
- iMoonLab YOLOv13 Nano 已以产品仓库外的 `research-http-yolo` Runner 部署并完成隔离产品测试；它强制人工复核，不代表自动计数准入。取得部署许可或经批准的替代模型、权重 checksum 与金标集后，配置独立 HTTP 模型服务并启用 `http-yolo` Provider；通过回归门禁前不得自动计数。详见 `docs/research/yolov13-research-runner.md`。
- 端侧、多视角、视频和 Agent 均以隔离 PoC 验证，不进入 P0 关键路径。

## 已准备的测试数据边界

- 已提供外部 YOLO 研究集的只读扫描脚本；它生成本机忽略的 SHA-256/标注摘要，不复制图片或标签。
- 仍需取得经授权的业务金标、左中右采集组和弱网/重启场景媒体；具体准入规则见 `docs/development/test-data-governance.md`。

## 仍需确认

- 离线 Token 最长时限暂定 7 天，组织切换 UI 后置；正式试点前需复审。
- 首次本地管理员初始化参数、生产 JWT 密钥轮换流程和后续金蝶账号接入时机。
- 首批试点猪场、低端 Android 候选机是否可获得，以及边缘服务器规格。
- 数据保留年限、备份恢复目标是否接受当前 NFR 草案。
- 详细问题、临时假设和影响见 `docs/product/open-decisions.md`。
