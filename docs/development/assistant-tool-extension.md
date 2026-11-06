# 只读比赛工具扩展契约

版本 1.0；对应 `contracts/assistant-tools/v1.schema.json`，夹具 `synthetic-fixtures.json` 全为合成数据。2026-11-02 三个工具、受限模型HTTP循环和评审页面均已实现，默认关闭外部模型调用，没有长期聊天数据库。[本地交付记录](agent-delivery-20261102.md)覆盖[首批记录](agent-foundation-20261102.md)的最新状态；真实模型、数据库/浏览器运行和云端访问仍待验，契约测试不构成这些运行证据。

| 工具 | 对应现有 v1 业务事实源 | 约束 |
|---|---|---|
| get_day_overview | inventory-tasks、inventory-sessions/{id}、inventory-reports/daily | 日期明确；最多50行，标明hasMore和覆盖数，未知不补零 |
| get_pen_history | inventory-reports/trend、inventory-reports/aggregate | 最多90天；只解释确认历史；缺失日期为null，查询时启用栏舍口径 |
| inspect_session | inventory-sessions/{id}、其受权媒体元数据 | 候选与确认分列；只返回会话引用与受控问题分类，不返回原图、内部失败详情、对象URL |

工具参数不得携带组织、令牌、任意 URL、SQL 或对象路径；schema拒绝额外字段。执行器从已验证请求取得主体、活动组织和成员权限，每次调用重新授权。用户认证关闭时工具不可用；不能把开发模式默认身份当工具授权。跨组织与不存在保持不可区分。所有确认、更正、删图、模型重试均不提供工具。概况/历史通过组织范围的只读SQL投影取同一业务事实，不把SQL权限提供给模型；会话复用业务服务授权。历史最多90天、引用最多50条，引用列表不代表覆盖所有日期。

输出区分 ok（含成功空数据）、unknown、unauthenticated、not_found_or_forbidden、unavailable、invalid_arguments。ok 的 data 必须为对象；成功空列表与未知/null 分开。引用仅为业务资源类型、ID和业务日期：会话必须使用真实会话ID，日报按业务日期寻址且ID为null，不编造日报UUID；前端需通过原受权业务入口读取。任何模型回答必须追溯本次调用，不能自行造数或把模型分数称准确率。

测试环境：将 `scripts/requirements-contracts.txt` 仅安装到忽略的 `tmp/contract-test-deps`，执行 `python scripts/test_assistant_tool_contracts.py`。这是开发检查依赖，不打进产品或推理镜像。

后续按[JoyCode部署说明](../../deployment/joycode/README.md)落实真实模型、成本和数据边界、受限评审账号与外网异常验证；实现基础已具备。不得将管理员 JWT、刷新令牌、服务密钥交给模型或比赛平台；不以 LAN 地址或合成对话证明评审可用。
