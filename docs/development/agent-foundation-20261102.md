# 2026-11-02 Agent 首批开发与平台决定

## 平台决定

用户要求开始开发并询问 JoyCode 是否必选、是否可以只用 Codex。默认由 Codex 在当前仓库完成开发；JoyCode 保留为可选开发/部署工具，不迁移现有栈。这里的“Codex 开发”指编写、调试、测试和准备部署代码，作品运行仍需独立的 LLM API 或自托管模型及可持续评审服务，不使用当前聊天作为评审入口。

已再读[官网](https://www.ai-race.com.cn/)与本届提交说明：当前已读规则未发现强制 JoyCode，官网列其为合作伙伴；不能由合作关系推导为强制平台。其他专项赛道或后来单独通知仍需按对应规定核对。[JoyCode 快速入门](https://joycode.jd.com/docs/start/getting-started/)说明 IDE、团队智能体/MCP 资产；[个人中心](https://joycode.jd.com/docs/teamAndEnterpriseManagement/personal-center/)说明云部署与公网链接，混合语言需要 Dockerfile。由此判断它可成为部署候选，但不能推定现有数据库、对象存储、模型 Runner 多服务可直接一键迁入或享有免费应用模型额度。

| 选择 | 用途与适配结论 |
|---|---|
| Codex＋现有 Spring/Next.js/Flutter＋独立运行环境 | 推荐；保留业务授权与数据权威，模型和部署供应方可以后选 |
| Codex 开发＋JoyCode/京东云部署 | 可选组合；需要另核验资源、网络、额度与多服务适配 |
| 其他编码 IDE、托管 Agent 平台或自托管模型 | 存在替代路线；本届三个只读场景尚无迁移必要，自托管需硬件和维护能力 |

沿用[11/1 比较及 11/2 计划核对](../product/ai-race-topic1-delivery-plan.md)：JDGenie、MCP Python SDK、LangGraph 分别代表整套产品、工具协议、状态编排；此次没有新增框架或复制第三方代码。首个工具为平台中立的受权 HTTP 合同。

## 已实现

- OpenAPI 0.12.0，新增 `POST /api/v1/assistant/tools/inspect-session`，请求/响应引用既有 `inspect_session` v1 schema。
- `InventoryReviewService.inspectSessionFacts` 读取明确的确认/候选字段，复用当前组织与成员授权，不使用界面数量回退。新增只读 `SessionInspectionTool` 和控制器，参数仅允许 tool 与 sessionId。
- 无有效 JWT 或开发用户认证关闭时拒绝；不存在/无权限同样返回 404，无数据与引用。两次授权读取任一次失败均不返回先前取得的事实。
- 只返回状态、候选、确认、受控问题类别和业务引用；失败原因正文、模型身份、对象 URL/原图不进入输出。全局忽略 null 的 Jackson 配置在工具响应中显式覆盖，保持 v1 的未知/null 字段。
- Admin 同源代理仅增加该精确 POST 路径及允许/错误方法/额外段测试；尚无聊天界面或真实模型调用。

## 自动检查与限制

Spring `mvn test`、`mvn verify`：139 项，105 通过，34 项 Docker 集成跳过，无失败；其中新增控制器/工具 9 项和事实投影/授权 2 项。控制器检查为进程内 MockMvc；不是已部署 HTTP/MySQL 验收，不替代 JWT 签名过滤器与真实跨组织数据库回归。

Admin `pnpm test` 35 项通过，lint/typecheck/build 通过；工具契约脚本 2 项通过。pnpm 初次因依赖预检查试图自动安装而在非交互终端退出；读取本机 pnpm 配置实现后，以本次进程 `pnpm_config_verify_deps_before_run=false` 使用既有依赖完成上述检查，没有重装、清理 node_modules 或修改锁文件。跳过项与首轮测试夹具误用未认证 JWT 构造器的失败日志均保留在忽略的 `tmp/agent-foundation-20261102/`。

未使用模型 API、外发数据、部署或修改现有数据库/模型批准。下一批完成另两个工具与模型适配，再开展真实工具调用和评审对话页面。模型 API 与部署资源信息缺口继续保留，已有契约开发可以进行。Review Hub 检索成功零匹配，不声称改变技术决定。
