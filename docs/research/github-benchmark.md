# GitHub 对比结论

更新时间：2026-08-17。结论基于各仓库 README、许可证和可见工程结构；架构适配属于本项目推断，不代表上游承诺。

| 项目 | 已核对事实 | 可转移模式 | 不采用原因 |
|---|---|---|---|
| [epoch8/data-collector](https://github.com/epoch8/data-collector) | Flutter/Drift 数据采集，Apache-2.0 | 媒体物化、逐文件上传、Manifest/Commit 和幂等恢复 | 项目较新，后台上传和测试不足；不整仓 Fork |
| [ODK Collect](https://github.com/getodk/collect) | Android 弱网采集，Apache-2.0 | 离线表单、草稿恢复、设备与网络测试 | Kotlin/XForms 体量远超当前产品，不迁移技术栈 |
| [Ultralytics YOLO Flutter App](https://github.com/ultralytics/yolo-flutter-app) | 自定义模型与移动推理示例，AGPL-3.0 | 仅用于端侧性能/兼容性 PoC 的测试思路 | 不作为产品依赖，不复制代码，避免许可证锁定 |
| [farmOS Field Kit](https://github.com/farmOS/field-kit) | 农业实体与离线同步，GPL-3.0 | 农业主数据和同步冲突的领域思路 | 许可证和技术演进不适合作为本项目基座 |
| [imagededup](https://github.com/idealo/imagededup) | 图片精确/近重复工具，Apache-2.0 | SHA-256 硬阻断 + 感知哈希软审核的分层策略 | 不引入完整 CNN 依赖，服务端按轻量合同独立实现 |
| [counting-pigs](https://github.com/xixiareone/counting-pigs) / [multi-camera-pig-tracking](https://github.com/AIFARMS/multi-camera-pig-tracking) | 猪只计数/多相机研究代码 | 金标、跟踪、多视角算法研究问题 | 前者栈老且 GPL；后者许可不明确；均不作为产品基座 |

## 对路线 B+ 的影响

- 选择性吸收“协议、状态机和测试方法”，而不是复制界面或源码。
- 业务主干保持 Spring Boot/MySQL，GitHub 项目不能仅因流行度触发重写。
- App 和服务端以版本化合同连接模型，使 YOLO/Agent 研究与业务证据链独立迁移。
- 隐私边界是组织隔离、私有对象存储和不可伪造审计；任何第三方云上传需另行审批。

本工程当前不含上述仓库代码。未来若确需移植 Apache-2.0 片段，必须保留许可证、版权与修改说明，并在 PR 中记录来源；GPL/AGPL 和许可不明代码保持隔离。
