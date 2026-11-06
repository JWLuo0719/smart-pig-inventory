# JoyCode 云部署候选

2026-11-06 已修复本机IDE连接：用户设置 `server.baseUrl=https://joycode.jd.com`，重载后从官网打开既有远程项目，实际读取远端文件成功。见[网络修复记录](../../docs/deployment/joycode-network-repair.md)。这不代表下述业务源码、中间件或模型已部署。

这是待云端构建和验收的源码配置，不代表已部署。当前源代码在 Codex 中开发，后续由 JoyCode/京东云承载可访问应用。官方依据：[云控制台和混合语言部署](https://joycode.jd.com/docs/teamAndEnterpriseManagement/personal-center/)。

## 包含与依赖

镜像包含 Next.js 评审页、Spring 业务 API 和单一 8080 HTTP 入口；平台在公网入口终止 HTTPS。Java、Node 都只监听镜像内回环端口，启动脚本监管三个子进程，一个进程异常退出则整体退出，健康入口转发真实 API 健康检查。

MySQL 8.4、Redis、私有 MinIO 和 Python 推理/Runner 仍是独立依赖，需要先在云端/受保护网络准备。此镜像没有捆绑数据库、猪只图片、研究权重或模型批准。前端与Java使用同一Linux/glibc构建环境；多服务内存需要在云端实测，不能把平台默认开发规格当作已批准生产容量。首次建议单副本部署，当前问答限流为进程内；横向扩展前需由网关实施全局额度和并发限制。

## 准备与构建

1. 在仓库根执行 `pwsh -NoProfile -File scripts/package-joycode.ps1`。得到 `artifacts/joycode/<时间>/joycode-source.zip` 与源码 SHA-256 清单。脚本只复制产品源文件、配置与 Flyway 迁移，忽略 Git、工作站环境、历史数据、权重、构建产物与密钥。
2. 将 `environment.example` 的值填到受保护的本地忽略文件，例如 `tmp/joycode-cloud.env`；随后配置到云平台服务端环境，不上传进代码库或前端。
3. 在本地执行 `pwsh -NoProfile -File scripts/test-joycode-configuration.ps1 -EnvironmentFile tmp/joycode-cloud.env`。只输出脱敏通过/失败信息；通过只表示配置形式合格，不能证明 DNS/TLS/中间件/模型接口实际可用。
4. 将源码包导入 JoyCode 项目，根 `Dockerfile` 是混合语言入口，平台运行 `/bin/start.sh`，对外端口8080。也可在 Docker 可用时对包内 source 目录执行 `docker build -t pig-inventory-competition:candidate .` 做本地构建，不直接覆盖 P0 镜像。
5. 目标为全新隔离比赛数据库和存储。Flyway 应成功到 V14；该迁移添加只读角色与成员有效期。旧版服务/旧数据库健康不能作为本次上线依据。不得将生产/P0卷复制进公开云演示。

## 模型启用

默认 `ASSISTANT_ENABLED=false`。模型接入使用服务端配置的完整 `chat/completions` 地址、模型标识与独立 API 密钥。支持常见非流式 `messages/tools/tool_calls` 交换；供应方若要求额外思考字段、专用消息回传或不同协议，须完成相应适配与实测，不能以“兼容”字样代替验证。

只有模型服务可用、额度和数据使用范围落实后，才将 `ASSISTANT_DATA_EGRESS_APPROVED` 与 `ASSISTANT_ENABLED` 设为 true。传出的是最小结构化盘点事实及审核过的 SOP；不传业务 JWT、刷新令牌、原图、对象地址或模型失败详情。不会复用 Codex/JoyCode IDE 登录凭据。缺任一必要条件时启用配置会失败，关闭时页面明确提示未配置，没有假模型回退。

每问最多3轮模型响应、6次只读工具，模型单请求最多25秒、整个循环预算60秒（在调用之间检查）；网络响应最多96KiB。数据库响应仍依赖云端连接/查询超时配置；需要实测拥塞与故障时的端到端上限。每身份每分钟最多12问、同身份只允许1个并发、进程总并发4。供应方有返回时累计token字段；没有字段表示未知，不计算费用。

## 只读评审账号

先在独立比赛环境建立组织并导入已授权、脱敏的演示记录，再配置一次性 `COMPETITION_VIEWER_PROVISION_ENABLED=true`、独立用户名/至少16字符密码、组织代码与明确 UTC 到期时间 `COMPETITION_VIEWER_EXPIRES_AT`。创建账号只赋 `COMPETITION_VIEWER`。初始化拒绝重用或修改既有管理员/其他成员身份，也不自动轮换密码或延长有效期；完成后关闭一次性开关并移除启动密码配置。凭据通过官方受控字段交付，不能写进 PPT、URL、Git 或录屏。

成员到期后不能读取盘点事实，也不能登录/刷新获得该组织权限。评审账号没有上传、确认、更正、删除、重试和主数据维护权限；若需立即撤销，应禁用该成员关系并回读权限。保持有效期覆盖实际评审阶段；晋级后的续期属于受控账号管理，需重新配置和实测，不能默认无限期开放。

## 云端验收出口

- 核对构建源码/镜像身份、V14迁移、外部中间件和推理模型身份，确认候选与人工确认边界。
- 新浏览器/另一网络打开 HTTPS `/assistant`，使用专用账号完成三问、改日期/栏舍与追问，点击引用重新读回。
- 实际验证跨组织、过期、限流、模型超时及服务重启；写接口必须拒绝。已实现的标量/引用检查不能证明模型解释语义完全正确，事实卡和人工核对保持权威。
- 同版本 App 单图采集→推理候选→人工确认→报表→Agent 解释必须另做集中验收；签名、真机、真实猪只和模型批准分别登记。
- 保持服务、模型额度、证书和账号在评审期间可用，指定维护人；提交后再次读回链接及文件回执。

当前本地已完成代码/构建、合成HTTP模型链路和配置测试；Docker引擎不可用，未构建此镜像或执行V14的真实MySQL验收。Next.js本地服务启动被自动审批拒绝，浏览器交互尚未完成。它们都不能标为云端验收通过。
