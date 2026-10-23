# 参赛 App 开发与验收追踪

用户于 2026-10-18 批准实施“App 主线＋扩展契约、单技术主线”。本文件为实施入口，细节依据 [审查清单](competition-readiness-review-20261018.md)、[开源对标](../research/competition-product-patterns-20261018.md) 与项目 AGENTS。日期为目标，不代表验收通过。

| 工作包 | 范围 | 状态 |
|---|---|---|
| M0 | 固定源码/产物基线、合同与追踪；校内赛事截止由队长核准 | 技术基线已登记；校内截止待队长核准 |
| M1 | F01–F06：组织队列、候选权威、逐图热图、零值/覆盖、坐标、状态刷新 | 代码与定向回归已落地；运行与像素门禁待验 |
| M2 | F07–F10：整组重拍、ROI、任务上下文、中文；带框核验与上传作业卡 | Flutter 71通过/1环境跳过、analyze与Debug构建通过；真机待验 |
| M3 | Admin 确认/更正表单、版本链、研判依据与行动；三个只读工具契约 | Spring106项含真实MySQL链路通过，Admin26项与构建通过；隔离栈镜像构建Docker EOF，无浏览器读回 |
| M4 | 同签名 Android 候选、源码/镜像/迁移/模型身份清单 | v20签名BuildOnly及119文件源码哈希已核验；联网部署清单与冻结待验 |
| M5 | 同版本真机、弱网、真实场景、录屏及连续三次彩排 | 待运行证据 |

优先顺序为 M0→M1→M2→M3→M4→M5；11/6 为内部候选目标，11/7–15 集中验收。若更早截止，以队长核准的校赛通知为准，不宣称在线 Agent 已完成。模型证据、授权样本、访谈与材料由团队并行准备。

## 完成门槛

合同先行；旧响应新增字段缺失表示未知；保持组织隔离、候选/确认分离、幂等和历史版本不可变。保持 Drift v6，不修改已应用迁移、签名/TLS 身份、模型批准和多图/视频自动计数开关。不公开服务，不操作报名/缴费/提交。

每批执行对应模块门禁。Spring test/verify、Admin test/lint/typecheck/build、Flutter dart analyze/test/Debug；相关 Admin 运行只用固定隔离栈并核对镜像和迁移，要求最终语义读回。签名构建、真机联通、真实场景、模型批准分别记录。

比赛工具只交付三个版本化只读输入输出、现有接口映射、合成夹具与契约检查，不实现模型 SDK、执行 Facade、聊天数据库、评审网关或实际 Agent。无授权场景证据时保留待验，不虚构成绩。

## 基线

- 实施前 HEAD：`f429e4a55b04c4f85c7965ebc8b5d83cb571b6f9`；移动版本 `0.1.0+19`。
- 既存未提交内容：CURRENT_HANDOFF、requirements-traceability、9/28 汇报底稿及本轮审查/对标报告，保持原文。
- 9/27 测试与9/28设备记录仅为历史证据，不能视为本轮回归。
- Review Hub：`audit-20261018032718-c4c255e3`，一条跨项目复盘仅作 informational：幂等、语义读回和历史保全已有项目规则明确要求，不声称改变方案。

## 2026-10-20 实施批次与追踪

当前为开发工作树，版本预留 `0.1.0+20`，没有推送或部署到 P0，没有安装/卸载手机。OpenAPI 为兼容新增的 0.10.0；Drift v6、Flyway V1–V13、签名/TLS 身份与模型批准保持原边界。构建基础镜像改为已验证可执行的 Maven 3.9.11（旧 3.9.9 镜像本机 `/bin/sh` 返回 exec format error），仍需隔离栈运行验证。

| 问题/工作包 | 已实现的核心行为 | 自动证据与剩余门禁 |
|---|---|---|
| F01 | Outbox 经 draft 组织关联统一限定展示、预检、领取、重试、状态写入、启动/Worker；逐阶段核对身份，401 不跨身份重放 | upload_package_synchronizer、authorized_retry、auth_identity_race；真实后台切换/弱网待验 |
| F02 | 手机/Admin/规则只取 rawModelCount；null 不数框，合法 0 保留；历史版本显示人工值 | AssistantInsightServiceTest、competition_review_test；三图/真实单图运行读回待验 |
| F03 | 热图逐 assetId 分开，位置单位为“处”；不解释为去重总量或栏舍真实空间 | density_heatmap_test 的边界与空值；多图界面待像素走查 |
| F04 | 趋势以样本存在区分零/null，补覆盖栏舍数和查询时启用范围；全零图轴至少1；移除全场不同覆盖的偏差比较 | InventoryTrendTest；授权数据与图表截图待验 |
| F05 | Admin 图片 contain 与框共用实际图像矩形和留白；不猜旋转补偿 | review-command.test 的横/竖图矩形；四角/EXIF 原图截图待验 |
| F06 | 状态完整映射，3秒/60秒非并发轮询、生命周期/路由停止、手动恢复；编辑值保留、迟到结果丢弃、终态通知投影更新 | competition_review_test；真实后台/确认响应丢失待验 |
| F07 | 未入队整组重拍和放弃；先固化新媒体，再事务校验旧组组织/栏舍/业务日/状态/Outbox；新UUID，旧原图保留 | recapture_boundary_test；相机取消、三图中途重启待真机 |
| F08 | ROI 不可变快照，保存时停止编辑，事务校验组织/草稿/未入队 | roi_editor_test 的实际 painter 失效判断及 roi_test；不能替代像素/真机验证 |
| F09 | 今日任务直达目标，历史任务明确只读或开始今日；最近作业按真实草稿ID恢复，排队后直达作业卡 | 草稿恢复/组织测试；历史日期/停用栏舍走查待验 |
| F10 | 中文 Material 本地化、方向/状态中文、保留主题；组织变化清除旧界面快照；未知本机统计不填0 | Flutter 静态/测试；日期选择器、130%字号、强光和无障碍待验 |
| 复核/上传体验 | 全屏整图带框1–8倍缩放/重置/原图切换/稳定编号分数；作业卡显示栏舍/日/缩略图/阶段/文件完成数/下一步，UUID只在诊断 | 计算与传输回归；实际媒体布局和端到端导航待验 |
| Admin 复核 | 原图与正式表单并排，候选/人工/差异/理由预览；未决意图同键，失败先读回；成功重读会话、锁图、版本和日报 | review-command、route-policy；固定 admin-runtime 合成栈待最终语义读回 |
| 版本查询 | 新增管理员只读 versions，默认20/上限50；沿 supersedes 祖先/后继查链，不靠同栏同日或共用证据串联；无确认版本时 currentSessionId=null | InventoryReviewServiceTest、InventoryCorrectionIntegrationTest；真实 MySQL/HTTP 受 Docker 稳定性影响，详见验证记录 |
| 规则依据 | 可展开值来源/基线/样本数/区间及受权会话引用；受控 session/capture/report/master_data 行动；数量变化不作疾病推断 | AssistantInsightServiceTest；现场解释与目标页待走查 |
| 比赛扩展 | 三个独立v1工具 schema、合成夹具、现有API映射和CI契约检查；无运行 Agent | [扩展说明](../development/assistant-tool-extension.md)，合成检查2项；在线里程碑单列 |

[本轮验证记录](../development/competition-verification-20261020.md) 是实际命令与限制入口。门禁未过不因已写代码或目标日期到达而标为阶段完成。

集中验收使用 [同版本检查表与演示脚本](../development/competition-acceptance-runbook.md)，模型与业务实测填 [成绩卡](competition-model-scorecard.md)。真实设备、授权样本、连续三次彩排、运行镜像/迁移/模型清单补齐前不冻结候选。在线 Agent、评审公网/受限账号与报名提交继续独立。
