# 功能收口对照（2026-09-12）

通过已安装 GitHub 工具分别检索农场管理记录、ODK 离线采集、库存库位管理。宽泛查询结果多为小型衍生项目，未为凑数采用；进一步核验以下三个直接对应领域的官方仓库 README 与仓库元数据。仅借鉴产品职责划分，独立实现，不复制或集成代码。

| 候选与证据 | 已验证事实 | 迁移适配判断（本项目推断） | 安全、维护与许可 |
|---|---|---|---|
| [farmOS](https://github.com/farmOS/farmOS)、[README 3.x](https://github.com/farmOS/farmOS/blob/3.x/README.md) | 农场管理、规划及记录系统；仓库默认分支已为 4.x，最近 push 2026-09-02；README 标示 GPL 2.0 | 参考先完成业务对象和记录流程的方向；无需引入 Drupal/PHP，现有 Spring/Flutter 继续为权威 | GPL 代码不进入专有主线；整栈迁移会增加权限与数据迁移成本，自托管本身不证明组织隔离 |
| [ODK Collect README](https://github.com/getodk/collect/blob/master/README.md) | 面向网络/供电受限环境的 Android 表单采集；README 标示 Apache 2.0，元数据许可证识别为 Other；最近 push 2026-09-10 | 参考离线采集与签名候选回归分开验收；现有 Drift/Outbox 与 UUID 合同不改为 XForms | 不采用新栈或复制代码，若未来采用需逐文件核对许可；账号、服务器及本地数据生命周期仍自行验证 |
| [InvenTree README](https://github.com/inventree/InvenTree/blob/master/README.md) | 库存/部件跟踪，Django 管理与 REST API、扩展插件；MIT，最近 push 2026-09-12 | 参考统一业务 API 供维护界面使用；本项目直接补主数据 API 和图库，冻结 Django 原型不重启 | 采用整体系统会增加两套权限和事实源；MIT 也不代替安全审查，只借鉴 API 与界面分工，维护成本最低 |

以上活跃时间只说明仓库近期有提交，不证明稳定性。未采用自动计数或跨图去重算法结论；源码事实、产品借鉴与本地推断分开。当前选择为在现有合同内补主数据维护、按日期栏舍图库与历史报表，并以真实回归收口。
