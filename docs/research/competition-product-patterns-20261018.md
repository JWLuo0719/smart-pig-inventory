# 参赛产品打磨的 GitHub 对标

核验日期：2026-10-18。决策入口：[参赛审查与四周计划](../product/competition-readiness-review-20261018.md)。

使用 GitHub connector 检索仓库并读取 README、许可证、源码及最新实际提交。检索覆盖 `livestock counting`、`ODK collect offline`、`computer vision annotation review`、`object counting supervision`。泛查询的小型计数演示不足以支撑完整产品对标，进一步核验现场采集、人机复核、视觉工具和动物计数评测四类。没有发现能整体替代本项目组织盘点/确认/锁图/历史版本业务的直接对应物；以下按可迁移模式对标，不能把上游指标当本项目成绩。

未克隆、安装、上传媒体或修改远端；个别 API 路径被拒绝后用 connector 支持的文件读取能力取得内容，未用一般网页搜索替代 GitHub 仓库核验。下列“适配、成本、采纳”是本项目判断，能力/许可/提交为仓库证据。默认分支链接将随上游变动，最新提交链接保留本轮维护时间观察，后续直接采代码前仍须固定所用版本重新检查。

## 核验概览

| 项目 | 核验能力 | 本轮所见最新实际提交 | 许可边界 |
|---|---|---|---|
| [ODK Collect](https://github.com/getodk/collect) | 弱网 Android 采集、项目级后台调度、逐条提交结果 | [2026-10-14](https://github.com/getodk/collect/commit/84a7e3518315c08e6d1a3ca7921c12e27917f244) | [Apache-2.0](https://github.com/getodk/collect/blob/master/LICENSE.md) |
| [CVAT Community](https://github.com/cvat-ai/cvat) | 自托管标注、组织角色、图上问题、质量差错分类 | [2026-10-16](https://github.com/cvat-ai/cvat/commit/d6d718f1168664617b30b8c74c721efbbf903473) | [MIT core](https://github.com/cvat-ai/cvat/blob/develop/LICENSE)，模型/依赖等另核 |
| [Supervision](https://github.com/roboflow/supervision) | 模型无关检测结构、叠加、区域判定/追踪配套 | [2026-10-17](https://github.com/roboflow/supervision/commit/1fb42a45f8d223909480bdeef9ec19b30a646afb) | [MIT](https://github.com/roboflow/supervision/blob/develop/LICENSE.md)，示例模型另核 |
| [HerdNet](https://github.com/Alexandre-Delplanque/HerdNet) | 动物检测计数、点标注、计数和检测评测、结果图 | [2024-11-05](https://github.com/Alexandre-Delplanque/HerdNet/commit/7e25f482d875522c59c446dc0c78c8f6f2dd448d) | [代码 MIT](https://github.com/Alexandre-Delplanque/HerdNet/blob/main/LICENSE.md)，预训练权重[CC BY-NC-SA-4.0/学术非商用说明](https://github.com/Alexandre-Delplanque/HerdNet/blob/main/README.md#pretrained-models) |

## 1. ODK Collect：状态透明和逐条恢复

[README](https://github.com/getodk/collect/blob/master/README.md)定位资源和网络受限环境。[调度源码](https://github.com/getodk/collect/blob/master/collect_app/src/main/java/org/odk/collect/android/backgroundwork/FormUpdateAndInstanceSubmitScheduler.java)将 projectId 纳入工作标识、支持网络约束；[提交源码](https://github.com/getodk/collect/blob/master/collect_app/src/main/java/org/odk/collect/android/instancemanagement/send/InstanceSubmitter.kt)逐项报告进度与成功/失败/中断，[结果结构](https://github.com/getodk/collect/blob/master/collect_app/src/main/java/org/odk/collect/android/instancemanagement/send/InstanceUploadResult.kt)保留失败原因。

- 可借鉴：本地保存、待联网、逐包上传、服务器处理、待确认、已确认明确区分；每条失败有下一步，批次完成不能掩盖个别失败。
- 架构适配：现有 Flutter/Drift 与 create → blobs → manifest → commit 继续作为事实源，独立实现呈现。不要把 ODK 的 projectId 等同于本项目服务端组织授权。
- 隐私/安全：本地元数据与后台任务同样要组织隔离；不采用提交后自动删除来处理锁定证据。
- 维护/迁移：借鉴状态交互成本低至中；完整采用 Kotlin/XForms/OpenRosa 会引入第二套数据模型和移动栈，成本高。
- 许可：Apache-2.0 仅对相应代码适用，若未来复制需再审通知等要求。本轮无复制。
- 决策：采用状态透明与组织限定调度的模式；不集成完整 ODK。对应主报告 F01/F06、U02。

## 2. CVAT：可定位的人工复核

[README](https://github.com/cvat-ai/cvat/blob/develop/README.md)说明自托管、组织角色和标注能力。[图上问题对话](https://github.com/cvat-ai/cvat/blob/develop/cvat-ui/src/components/annotation-page/review/issue-dialog.tsx)包含图中位置、缩放、作者/时间、评论与解决状态；[质量报告契约](https://github.com/cvat-ai/cvat/blob/develop/cvat-core/src/quality/quality-report.ts)区分多标、漏标、标签不符、遮挡等类型，得分可空。

- 可借鉴：原图/标注切换、带框缩放、目标编号、局部定位；人工改数保留漏检/误检等原因；从模型候选走到确认及更正的可追溯时间线。
- 架构适配：Flutter/Next.js 独立实现，复杂纠错需先版本化合同。标注系统的 reopen/delete 不直接映射为已确认库存的修改/删除；更正仍生成新版本。
- 隐私/安全：自托管本身不证明权限正确，云存储、模型服务和组织边界分别检查；不把真实猪场图片送往公共演示站。
- 维护/迁移：借鉴交互中等成本；完整集成大型 Python/前端/标注运维体系成本高，与当前业务重复。
- 许可：MIT core 不能推广到所有模型、serverless 资产、依赖和数据。
- 决策：采用可解释复核模式，不引入整套 CVAT。对应 F05、U01。

## 3. Supervision：结构化候选与坐标语义

[README](https://github.com/roboflow/supervision/blob/develop/README.md)定位模型无关视觉工具。[Detections](https://github.com/roboflow/supervision/blob/develop/src/supervision/detection/core.py)包含坐标、类别、可空置信度、可选 tracker_id 和扩展数据；[区域计数指南](https://github.com/roboflow/supervision/blob/develop/docs/how_to/count_in_zone.md)与 [PolygonZone](https://github.com/roboflow/supervision/blob/develop/src/supervision/detection/tools/polygon_zone.py)表明区域判定使用框锚点和掩码，不能当作跨视角身份去重的证据。

- 可借鉴：框、分数、类别、图像尺寸/坐标系、关联 asset、追踪标识和模型身份语义明确；图层有编号和图例。
- 架构适配：保留 versioned provider contract 和服务器候选字段。区域/跨线计数与左中右去重是不同任务；不能客户端数框来绕过多图限制。
- 隐私/安全：候选不入 confirmed-only 报表，客户端阈值不授权自动确认；模型分数不等于正确概率或总体准确率。源码允许分数为空，也有为部分无评分输出填 1.0 的适配路径，展示应服从真实来源。
- 维护/迁移：借鉴结构和叠加层成本低至中；直接引入额外 Python/图像数值依赖需评估打包与维护，不作为本轮必要条件。
- 许可：MIT 不自动授权示例模型、权重或训练数据。
- 决策：借鉴检测契约与叠加语义，不为 UI 打磨新增推理依赖。对应 F02/F03/F05、U01/U03。

## 4. HerdNet：计数和检测分别评测

[README](https://github.com/Alexandre-Delplanque/HerdNet/blob/main/README.md)说明航拍动物领域、点标注及 F1/MAE/RMSE 等指标；[metrics.py](https://github.com/Alexandre-Delplanque/HerdNet/blob/main/animaloc/eval/metrics.py)同时累计检测与计数结果；[推理工具](https://github.com/Alexandre-Delplanque/HerdNet/blob/main/tools/infer.py)与说明展示检测 CSV、叠加图和局部缩略图。

- 可借鉴：分开报告检测质量、每图计数误差、人工纠正后结果、作业时间；按密度/遮挡/光照分层，保留失败图例。
- 架构适配：独立整理本项目成绩卡，复用既有本地回归工具和外部只读清单；不用上游结果替代猪舍手机场景评价。
- 隐私/安全：样本/标签授权和隔离单独确认；航拍动物与栏舍手机照片有明显领域差异。
- 维护/迁移：借鉴评价方法成本低；本轮所见维护较久、训练环境较旧，整体采用与迁移成本高。
- 许可：代码 MIT 与权重非商用条件必须分开，不引入权重，不因代码许可证推定模型可发布。
- 决策：采用分层评测与失败案例的报告模式，不换模型/训练栈。对应主报告第 5 节。

## 采纳边界

四个候选支持当前架构上的增量打磨：ODK 的状态透明、CVAT 的证据复核、Supervision 的结构化候选、HerdNet 的分层评测。没有复制代码或资产、引入新依赖、采用外部模型、上传用户数据或修改当前合同。下一步如真正引入组件，须按实际版本重审许可、数据边界、依赖和回归；本次对标不构成部署或模型批准。
