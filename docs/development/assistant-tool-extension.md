# 只读比赛工具扩展契约

版本 1.0；对应 `contracts/assistant-tools/v1.schema.json`，夹具 `synthetic-fixtures.json` 全为合成数据。没有模型 SDK、工具执行器、Facade、聊天数据库或在线 Agent，契约测试不构成运行证据。

| 工具 | 后续适配的现有 v1 HTTP 事实源 | 约束 |
|---|---|---|
| get_day_overview | inventory-tasks、inventory-sessions/{id}、inventory-reports/daily | 日期明确；最多50行，标明hasMore和覆盖数，未知不补零 |
| get_pen_history | inventory-reports/trend、inventory-reports/aggregate | 最多90天；只解释确认历史；缺失日期为null，查询时启用栏舍口径 |
| inspect_session | inventory-sessions/{id}、其受权媒体元数据 | 候选与确认分列；只返回会话引用与受控问题分类，不返回原图、内部失败详情、对象URL |

工具参数不得携带组织、令牌、任意 URL、SQL 或对象路径；schema拒绝额外字段。后续执行器从已验证请求取得主体、活动组织和成员权限，每次调用重新授权。用户认证关闭时工具不可用；不能把开发模式默认身份当工具授权。跨组织与不存在保持不可区分。所有确认、更正、删图、模型重试均不提供工具。

输出区分 ok（含成功空数据）、unknown、unauthenticated、not_found_or_forbidden、unavailable、invalid_arguments。ok 的 data 必须为对象；成功空列表与未知/null 分开。引用仅为业务资源类型、ID和业务日期：会话必须使用真实会话ID，日报按业务日期寻址且ID为null，不编造日报UUID；前端需通过原受权业务入口读取。任何模型回答必须追溯本次调用，不能自行造数或把模型分数称准确率。

测试环境：将 `scripts/requirements-contracts.txt` 仅安装到忽略的 `tmp/contract-test-deps`，执行 `python scripts/test_assistant_tool_contracts.py`。这是开发检查依赖，不打进产品或推理镜像。

后续在线 Agent 依次完成：核准比赛平台/领域/最新截止与匿名规则 → 确定模型、成本和数据边界 → 实现只读适配与限时委托鉴权 → 三个真实提示词及输出 → 专用评审账号 → 外部访问和异常验证。不得将管理员 JWT、刷新令牌、服务密钥交给模型或比赛平台；不以 LAN 地址或合成对话证明评审可用。
