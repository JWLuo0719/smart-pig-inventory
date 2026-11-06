# 新对话交接

2026-11-06 团队取码补充：用户已授权将最新代码提交并推送现有 GitHub 远程仓库，供金种子杯 Demo 录制。取码分支为 `codex/competition-code-completion-20261023`，见[团队录屏交接](docs/development/golden-seed-demo-handoff-20261106.md)。下文“未提交/不要为交接自动提交”的描述是本轮上传前基线，不能据此推断本轮上传后的 Git 状态；以实际本地与远程提交读回为准。本次未扩大到云部署或赛事提交。

更新时间：2026-11-06（北京时间）。新对话继续完成第二届全国人工智能应用创新大赛作品上线、验收、材料制作与实际提交。**比赛交付尚未完成；JoyCode 远程开发环境已经连通。**

## 先读与当前任务

1. 本文件与 `AGENTS.md`，随后按 [NEXT_STEPS.md](NEXT_STEPS.md) 推进。
2. [选题一交付要求](docs/product/ai-race-topic1-delivery-plan.md)、[JoyCode部署说明](deployment/joycode/README.md)。
3. [已验证的网络修复](docs/deployment/joycode-network-repair.md)、[赛事平台权益复核](docs/research/ai-race-platform-recheck-20261106.md)。
4. [20页PPT与视频内容底稿](docs/product/competition-materials-draft.md)、[本地代码交付证据](docs/development/agent-delivery-20261102.md)。

旧交接全文已原样保存在[历史交接](docs/development/handoffs/20261106-before-consolidation.md)，仅作证据；不要从旧“待开发”列表重写已经实现的功能。本文件及当前源码优先于历史状态。编写后续任务时使用[当前续办提示词](task-prompts/current.md)和[任务契约](docs/TASK_CONTRACT.md)。

## 已确定的作品与提交出口

- 题名：**牧数智核——面向智慧猪场的视觉感知与可信盘点智能体**；通用赛道—其他。其余选题仅为后续优化备选。
- 主线：单图采集/ROI → 真实视觉候选 → 人工复核确认/锁定 → 已确认报表 → 三工具只读Agent解释与引用。候选、确认、未知分开；多图不求和，不扩展健康/估重/视频自动总数或新框架。
- **2026-11-10 24:00为报名及作品上传截止**。官网10月13日调整通知及当前湖南区域赛通知覆盖旧PDF中的10月20日。当前按11月9日准备可提交版本、11月10日上传核验安排；不要沿用已过时的内部里程碑。
- 最终三项：PPT≤20页、16:9、≤50MB；MP4≤6分钟、≤300MB；可外网访问的Agent链接及专用只读到期评审凭据。至少准备3个主题相关的真实提示词及实际输出、引用与追问证据。
- 作品内容按匿名规则清理学校、学生/教师姓名、Logo、水印、备注和属性；文件命名按官方字段及校方解释执行。正式上传后读取系统回执并再次打开文件/链接，不能把“已生成”或“上传按钮点击成功”记为已提交。
- 报名、缴费、组队、校内信息表回执目前**未读回确认**；JoyCode登录或云项目创建不代表报名完成。原报名资料来源为 `D:/Project/牧数智核/比赛准备/人工智能大赛/`；基础成员资料见用户原商业计划书 `D:/Project/牧数智核/比赛准备/牧数智核商业计划书 (1).docx`，不要把身份信息放进匿名作品。

## JoyCode 现状与恢复操作

- 用户在网页已创建 `mushu-ai-race`，项目ID `86627`，Java21模板，1核/2GB、10GB表单存储规格。没有为此项目新建额外中间件或正式应用镜像；费用/套餐权益仍需核对。
- 本机客户端3.0.10先前创建项目/读取详情访问不可达的 `joycode-api-saas.jd.com` 私有地址。**已通过用户设置 `server.baseUrl=https://joycode.jd.com` 修复**：备份 → 仅改此设置 → GUI“开发人员：重新加载窗口” → 用户在网页再次点“IDE打开”。
- 已直接控制客户端核验窗口 `workspace [SSH: MUSHU-AI-RACE_86627]`，打开远端 `App.java`并读到Java HTTP Hello World模板代码。云端目录为 `/config/workspace`，可见 `.joycode`、`bin`、`App.java`。这不是业务源码已上传。
- 配置备份和修改证据：忽略目录 `tmp/joycode-network-repair-20261106/`；不要整份输出用户设置，或上传备份。当前保留已验证的公网入口。不要连接不明VPN、改Hosts把管理域名映射为应用IP、破坏正常Clash配置或重复创建项目。
- 公网应用入口最后实测仍**502**；完整项目地址只保留在本地忽略证据/用户云控制台。下一步检查实际8080监听及 `/bin/start.sh`，不能凭容器Started推定应用可访问。
- Windows系统 `ssh` 默认读取 `.ssh/config` 时因Everyone ACL拒绝。已从JoyCode自动生成的 `.ssh/joycode/config`中只选目标项目，写入当前用户专用的忽略文件 `tmp/joycode-network-repair-20261106/ssh-config`。用 `ssh -F` 重试能到达远端SSH，但保持 `StrictHostKeyChecking=yes`，因缺少可信ED25519主机密钥而拒绝；**CLI未通过**。原SSH配置、ACL和私钥未改动。自动上传前从可信渠道核验主机指纹，或使用已连通IDE支持的文件上传方式；不要关闭主机密钥校验。
- 浏览器操作曾因工具无法可靠确认URL而强制停止；后来原生JoyCode操作成功。新对话按当前技能/工具重新发现窗口，不复用旧窗口ID。Windows UI使用 `computer-use`当前文档中的 `node_repl + @oai/sky`，不通过UI自动执行终端命令；远程CLI与GUI是不同工作流，按实际能力选择。

## 真实模型、免费权益和预算

- 官网湖南区域赛通知第六部分明确：完成报名注册后，JoyCode为参赛者免费提供编程和大模型调用服务。报名/平台账号与租户匹配、是否向自建应用提供独立API、额度/有效期、云主机与数据库是否包含，仍未核实。先追查赛事权益，不能只因IDE免费就断言应用API或云资源免费。
- 学校校赛QQ群 `1103840357`；湖南区域赛咨询群 `1131175762`。报名后培训及技术支持有校赛通知依据，但群置顶/群文件、账户内课程尚未读取。本次未代发消息；按用户明确授权处理对外联络。
- 用户原先选择教程 `https://upgpts.com/tutorials/tools/cliproxyapi-codex`，希望模型预算上限50美元。CLIProxyAPI v8.0.53只做过隔离回环冒烟：匿名401、带本地测试key模型列表200但0模型、管理接口404；没有导入OAuth凭据，没有真实模型调用，50美元**未配置为生效限额**。代理不是自动获得官方API余额。
- 现有Java适配器使用完整 `chat/completions` 地址、非流式工具协议；任何真实供应方/订阅接口都需实际验证协议和云端可用性。不能把IDE订阅凭据直接导出到云上，不能用合成模型替代参赛真实输出。
- OpenAI订阅接入的适用性此前查过官方SIWC文档，不能笼统宣称全部禁止或全部支持；若继续此路线需按当时官方条件核实，特别是云端托管场景。
- **云资源预算未给定**；50美元是模型预算，不能当作云资源购买授权。形成具体规格和费用后再处理必要的付费决定。数据默认仅用合成/脱敏记录；原研究图片和权重的云端使用范围未核实，不复制研究数据集进源码包。

## 本地实现与验证证据

- 分支 `codex/competition-code-completion-20261023`，HEAD `d7a3850`。大量Agent与部署源码仍为未提交/未跟踪的有效工作，保留工作树，不清理、reset、误当残留删除，也不要为交接自动提交或推送。
- 已实现三工具 `inspect_session`、`get_day_overview`、`get_pen_history`、HTTP模型适配及有限循环、`/assistant`评审页、事实卡/受权引用、内存令牌、并发/频率/超时门禁，以及Flyway V14专用只读到期评审身份。OpenAPI0.13.0；真实MySQL迁移未验收。
- 11月2日证据：Spring test/verify各196项，161通过、35因Docker跳过；Admin41项、lint/typecheck/build通过；18个合成HTTP模型工作流通过。**真实模型、真实数据库和评审浏览器运行未通过验收**。本轮网络修复未重新运行业务测试，不将历史计数称为今日结果。
- Docker镜像构建和Docker集成当时不可用；本地Next启动两次被自动审批以“blocked by policy”拒绝。记录真实限制，新环境重新判断能力，不包装或反复绕过拒绝。
- 云镜像候选包含Next/Java/Nginx，8080入口，内部3000/8081回环；外置MySQL8.4、Redis、私有MinIO、Python推理/Runner仍需落实。环境模板在 `deployment/joycode/environment.example`，密钥仅服务端注入，默认模型和推理派发关闭。
- 最近源码包：`artifacts/joycode/20261102-160711-700/joycode-source.zip`（160项白名单文件）；本次交接重新核对ZIP SHA256为 `0682443e458a28476f80f8349e8c4b9886c1a341d0ce9f2195e49e4a89115617`。文档和工作树随后有改动，正式上传前运行 `scripts/package-joycode.ps1`重建并核验，避免使用过期暂存目录或把`.joycode`运行文件混入。
- 签名/TLS、设备Debug草稿、P0卷、历史确认数据必须保留；模型批准仍false。App21及旧BuildOnly APK不能冒充本轮联网验收包。

## 新对话按此顺序继续

1. 读当前交接并核对工作树、客户端仍连接及配置；不重复菜单探索或从头研究选题。
2. 核查比赛报名/组队/缴费/校内登记及平台权益状态。同步推进能独立完成的材料，缺失的信息只问关键项。
3. 保留现有云项目，核对远端工具/启动脚本/8080服务，解决可信上传路径，重建并导入白名单源码。
4. 落实隔离MySQL/Redis/MinIO与推理、真实模型及额度；构建后读回源码/镜像身份、Flyway版本、组织权限和到期账号；不要导入P0生产卷。
5. 完成HTTPS `/assistant` 外网三问、追问/改日期/引用、只读/跨组织/到期/超时检查，以及同版本单图→确认→报表→Agent链路。按[集中验收脚本](docs/development/competition-acceptance-runbook.md)和[成绩卡](docs/product/competition-model-scorecard.md)留下实际证据。
6. 按底稿制作正式PPT/MP4，填入真实截图/成绩/三问，匿名化并检验格式、页数、时长、体积和模型事实一致性；当前只有Markdown底稿，没有最终PPT/MP4。
7. 在11月10日截止前按用户授权完成上传并读取回执，确认官网最终文件和Agent链接可用，记录提交版本及持续维护责任。用户需接管登录、验证码、付款或条款等情形时遵守当前工具要求，不自行声称提交完成。

Review Hub：原云接入任务 `ai-race-cloud-intake-20261104-01` / `ai-race-registration-preparation`，审计 `audit-20261104063857-6d15d3fb` 检索成功0匹配，仍为retrieved/open；原始证据在 `tmp/cloud-intake-20261104/`。本次交接不把尚未完成的部署/模型/提交审计结案，也不批准待审核知识候选。
