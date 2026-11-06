# 人工智能大赛作品定位与 JoyCode 平台核对

日期：2026-11-01。性质：第一轮讨论建议，尚未由用户锁定定位或实施方案。作品截止按用户确认的11月10日；本轮不处理报名信息。

## 讨论结论

建议定位为“牧数智核——面向智慧猪场的可信盘点与巡检智能体”。面向场长/巡检负责人，以视觉感知和组织内盘点事实为依据，回答哪些栏舍需要优先复核、原因和证据是什么、下一步应补采或核验什么。一线人员通过现有App采集和人工确认，Agent组织证据并给出建议。

| 定位候选 | 价值 | 当前证据与工作量判断 | 本轮建议 |
|---|---|---|---|
| 视觉数猪工具 | 数量识别直观，便于展示模型效果 | 有研究和产品基础；需要版本一致的模型成绩与真实链路，Agent交互覆盖有限 | 作为感知底座和案例 |
| 可信盘点与巡检智能体 | 将盘点结果、历史、失败和复核优先级组织成可核查建议 | 现有业务事实源和三个只读契约可以支持增量实现；运行Agent、评审链接仍缺 | 优先讨论的作品主线 |
| 猪群健康、生长与经营综合决策智能体 | 愿景完整、潜在价值广 | 行为时序、疾病风险、图像—称重配对、环境接入和跨场验证需求大；缺口无法由对话包装消除 | 保留分阶段路线，独立列明成熟度 |

上述工作量和适配判断是基于项目现状的推断，不是实际实现工时或评分预测。没有宣称大模型调用本身构成算法创新。

## 三个突出能力与演示问题

1. 视觉结果可复核：原图、候选框、ROI、候选/确认分离与版本留痕。演示一次现场采集到人工确认的业务链；当前版本仍需整体验收。
2. 跨记录组织证据：按问题读取当日概况、单栏历史和具体会话，用数据日期、状态、来源解释复核优先级。Agent需要真实工具调用与证据引用；不能只展示预制答案。
3. 证据不足时给出明确下一步：缺采、历史不足、推理失败继续保留未知，不把缺失当0；说明补采、核验或人工复核步骤。

| 问题示例 | 预期可见行为 | 不得扩大为 |
|---|---|---|
| 今天哪些栏舍需要先复核，依据是什么？ | 调取当日状态，按可解释事实列出问题与证据 | 已验证的健康风险排序或模型准确率 |
| 这个栏舍的确认数量发生变化，能说明什么？ | 查已确认历史、样本和缺失，说明可判断与不可判断项 | 从数量变化直接诊断疾病或自动归因死亡 |
| 这次为什么没有数量结果，我接下来怎么做？ | 查会话状态与受控问题分类，保留空值并给下一步 | 自动确认数量、自动重试模型、自动改历史 |

对话中更换日期/栏舍、追问依据、查询缺失记录应真实改变输出。人工确认仍在原受权业务流程完成。默认不扩充工具写权限。

## JoyCode 已核实能力与未知项

- [产品概览](https://joycode.jd.com/docs/start/product-overview/)将其定位为团队级AI编码平台。它可以作为开发环境；使用其编程助手不自动证明作品Agent已经运行。
- [快速入门](https://joycode.jd.com/docs/start/getting-started/)和[智能体说明](https://joycode.jd.com/docs/functions/functions/ai-agent/)说明可配置角色、提示词与工具；[MCP说明](https://joycode.jd.com/docs/functions/functions/mcp/)给出本地服务接入示例。由此可评估用JoyCode验证业务工具调用，但连接、安全和结果未实测。
- [个人中心](https://joycode.jd.com/docs/teamAndEnterpriseManagement/personal-center/)明确区分远程开发项目与发布应用，并提供公网地址。它为评审入口提供可行性依据；不能推定现有多服务产品、推理模型和存储能原样一键部署。
- [团队空间](https://joycode.jd.com/docs/teamAndEnterpriseManagement/team-space/)描述配置资产的分享与复制；该链接与部署后的可操作应用入口需要分别核验。快速入门还限制企业内共享，实际评审访问路径不能凭“分享”二字确定。
- 平台IDE模型额度、应用运行模型API、云部署资源是不同问题。本轮未核验账户权益、应用推理接口、费用、资源和评审访问，没有据“限时免费”作成本承诺。

建议先把平台角色分为开发工具、工具调用验证宿主、应用发布入口三项，分别验证。不因同属京东生态，把JoyCode与JoyAgent开源产品视作同一个服务。比赛是否强制采用哪一种交付方式，用户提供的支持平台链接不足以单独确定。

## GitHub 对标：借鉴模式，未选定组件

使用GitHub连接器，分别检索agent工作流/证据、MCP鉴权和工具调用，读取下列三个候选的README、LICENSE与默认分支提交。候选属于完整产品、协议适配和编排框架三个不同边界，不按热度选型。曾尝试`jlowin/fastmcp`，连接器未返回可读README，未计为已验证候选。

| 仓库 | 已核实模式、适配判断 | 隐私与权威边界 | 成本、许可、当前决定 |
|---|---|---|---|
| [JoyAgent-JDGenie](https://github.com/jd-opensource/joyagent-jdgenie/blob/data_agent/README.md) | README描述端到端多Agent产品及可挂载子智能体/工具；可参考任务到结果的可见流程。与当前Java后端有语言接近部分，但这不足以证明可直接接入 | 通用工具不能绕过Spring组织授权；报告不能成为确认库存事实源；不引入任意代码/SQL执行权限 | 完整产品迁移和运维成本高（本轮推断）；[LICENSE](https://github.com/jd-opensource/joyagent-jdgenie/blob/data_agent/LICENSE)标Apache2.0。只借鉴流程，不整体采用 |
| [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk/blob/main/README.md) | 官方Python SDK暴露工具/资源/提示词，含stdio及HTTP传输；与独立薄适配层相容。当前README的API与旧示例不同，若实施须固定发布版本 | 协议不提供本项目业务授权；组织从认证上下文取得，不接受模型自报组织；不把业务令牌交给模型 | 适配量相对较小，仍新增Python服务/鉴权维护（推断）；[MIT](https://github.com/modelcontextprotocol/python-sdk/blob/main/LICENSE)。只参考工具合同与协议，不在本轮安装 |
| [LangGraph](https://github.com/langchain-ai/langgraph/blob/main/README.md) | README提供有状态编排、持久执行和人工介入；可参考追踪调用与中断。当前三个只读问题未显示必须引入长流程编排的证据 | 检查点与对话状态可能形成第二份业务/敏感数据副本；确认、更正仍以现有不可变会话为准 | 新增状态库与编排概念的迁移成本中高（推断）；[MIT](https://github.com/langchain-ai/langgraph/blob/main/LICENSE)。借鉴可追踪性，不选为默认框架 |

最近默认分支提交核对（不等于发布稳定性或项目全分支活跃度）：

- JDGenie `data_agent`：[2417e0b](https://github.com/jd-opensource/joyagent-jdgenie/commit/2417e0b8b636d941ad5fb14c59b20dddfef5375d)，2026-02-12。
- MCP Python SDK `main`：[d7845c0](https://github.com/modelcontextprotocol/python-sdk/commit/d7845c073a2b9ba5ab2817ecf93d3e45ef24cd14)，2026-10-27。
- LangGraph `main`：[e5c961d](https://github.com/langchain-ai/langgraph/commit/e5c961d7fbe7ca6fdd4c94c84d90511372514d55)，2026-10-31。

许可证仅针对所读代码范围，不替代依赖、权重、数据或托管条款审查。未复制代码、引入依赖、采用整栈或上传用户资料。直接公共GitHub API曾限流，以上提交证据随后通过GitHub连接器读回。

## 当前依据、需要讨论的决定与停止边界

项目依据：[合并开发计划](../product/competition-development-plan.md)、[只读工具契约](../development/assistant-tool-extension.md)、[交接](../../CURRENT_HANDOFF.md)。最近交接的产品源码锚点为`7d8710b`，这是历史交接记录，非本轮运行版本声明。三个工具为`get_day_overview`、`get_pen_history`、`inspect_session`；只有契约和合成夹具，不是已运行Agent。

本轮优先讨论：主要用户是场长还是一线盘点人员；评委最应记住的是视觉算法改进还是证据驱动的复核决策；整体愿景中哪些能力放入本次主演示。建议默认场长/巡检负责人、复核决策主线、视觉感知支撑，并让一线App完整流程证明可用性。正式题目、平台运行方式、实现范围均未锁定。

已核对文档与源码交接；未安装JoyCode、注册平台、部署、花费、调用应用模型、接入真实数据或运行评审验收；未改变既有模型批准、写入权限和人工确认规则。文档建议不构成实施完成。

Review Hub命中三条：声明边界卡仅informational（项目规则原已要求实现/验收分离）；跨项目检索卡informational（未改变当前检索流程）；浏览器下载卡rejected（与本轮平台文档/作品定位不匹配）。不声称知识改变了结论。官方平台资料候选`joycode-54f6c530`为待审核synthesis，未批准或转入项目规则。
