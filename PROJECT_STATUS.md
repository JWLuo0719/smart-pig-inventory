# 当前状态


## 2026-09-13 v16 真机启动与首页任务读回已验证

v16 签名 LAN APK 已在 Redmi K60 上通过无线 ADB 覆盖安装，版本 `0.1.0+16`，设备保留原数据且首次安装时间未变。手机 `192.168.255.26:42187` 与电脑 `192.168.255.99` 同网，服务端 HTTPS/mDNS 可达。冷启动日志和 UI 读回确认认证恢复后 `/api/v1/me`、当日任务接口均成功，首页显示网络已验证、两个真实任务和 `0 / 2`，没有未知任务或假零。

真机发现的首页生命周期缺口已修复：认证状态从加载/离线转为在线时主动重新拉取任务；新增两个 widget 测试覆盖离线恢复和初始认证为空两种情况。Flutter 全量测试 40 项通过（TLS 真实链路另行 2 项通过），`flutter analyze`、Debug 构建和 v16 签名 Release 门禁通过。详见 `CURRENT_HANDOFF.md` 与 `NEXT_STEPS.md`，设备证据在 `artifacts/functional-v16-device-*.{txt,xml}`。

本轮仍未声称完整人工验收：ADB 模拟点击被系统拒绝，采集/上传续传、图库、视频、报表、主数据同步等需要用户手动操作。正式目标未确定，未正式上线；模型准确度和模型批准保持后置。


## 2026-09-12 最新推进：真机核验后置，恢复工具已验证

用户明确真机核验后置，继续可以独立进行的开发，不再以手机连接为当前开发阻塞。功能候选 v14 保留，未修改手机功能或重建 APK；本轮补齐 `scripts/inventory_snapshot.py` 冷快照/完整校验/全新卷恢复工具与 `scripts/run_snapshot_e2e.py` 隔离合成演练。4 项安全测试及真实 MySQL/MinIO/Redis 恢复通过：当前确认 19、历史 17、同一证据 SHA-256、锁图删除 409、Redis 数据均保留；拒绝运行中备份、已有目标卷和损坏归档。演练容器/网络已清理，数据卷保留，未访问 P0 数据。

说明见 `docs/deployment/backup-recovery.md`，证据为 `test-assets/generated/snapshot-recovery/f834c1f68553/summary.json`。备份是停写物理快照，需原镜像和受保护介质；本地演练不代表生产异机、加密密钥恢复、容量/RTO 或正式切换通过。补充交付包 `artifacts/releases/20260912-recovery-tools.zip` 仅含工具、说明和合成验证摘要，不含备份数据。

接下来仍可在不依赖真机的范围维护自动回归和修复新暴露的问题。当前无已确认但未实现的首批功能缺口；金蝶需正式接口资料，模型精度/视频自动计数/三图去重随团队模型后续推进。生产目标、TLS/账号和异机介质未确定，正式上线仍未执行；真机集中验收按用户要求后置。

## 2026-09-12 功能候选：主数据、图库、历史报表与视频人工证据

用户要求模型精度后置，继续按原始需求完成功能；正式服务器/域名/猪场账号回答“尚未确定”。已经实现并部署 LAN：管理员维护当前猪场/栋舍/栏舍，按日期栏舍图库与错图删除，后台覆盖删除审计，历史任务/日报/均值，视频持久保存/上传/播放及人工确认流程。视频不生成自动数量，三视图不相加，模型仍未批准。金蝶需对方接口资料及账号。

- Business V13 已部署到 P0，JAR 与本次构建 SHA-256 一致；Admin 构建编号已核对；Inference API/Worker 使用本次视频人工流程。P02 历史确认仍为候选 19 / 人工 24，锁定证据保留。升级前数据库快照和旧镜像信息在忽略的 artifacts 下。
- Spring `mvn test` / `mvn verify` 各 69 项通过；Admin 24 项及 lint/typecheck/build 通过，隔离 Edge 完整流程、15 组面板异常/空数据、主数据/历史/图库/覆盖审计均通过。Inference 38 项及真实视频 API/MinIO/Celery/回调/锁定/删除 409 通过。
- Flutter 启动请求节制与失败不显示假零已修正；analyze、39 项测试（含真实 TLS）、Debug 和同签名 v14 Release 构建通过。交付目录 artifacts/releases/20260912-functional-v14，APK SHA-256 为 1317f054464ea1575557fa05d60c800a70c65868f0291fcb51a5ae852447721d。中断前最后确定安装的是 v13，冷启动读回 P01 待复核、P02 确认 24；v14 覆盖安装命令结果丢失，恢复时手机无线 ADB 不可达，不能声称 v14 已安装。视频录制/播放、图库交互和新主数据手机同步仍待集中人工确认。
- 正式部署 overlay、无密钥模板和配置检查已完成；正向/拒绝模型提前批准/拒绝占位域名均通过。还没有正式服务器部署，备份恢复演练与目标 TLS/账号验收仍待执行。见 docs/deployment/functional-release-candidate.md。
- Review Hub 功能审计 audit-20260912055415-7e029451 零匹配；功能运行证据已补齐，正式目标与集中设备验收未完成。原 v12 上传问题已由用户确认续传成功。


恢复检查（2026-09-12 18:58）：Docker 已启动，P0 核心容器恢复，带原 CA 的本机 HTTPS 健康为 UP；Business JAR SHA-256 与 Admin BUILD_ID 再次匹配交付源码。电脑当前网络已变化，手机旧无线地址不可达，不能沿用下午的手机联通结论。可分发文件为 artifacts/releases/20260912-functional-v14.zip（SHA-256 7811b44efc0bbf290c46a72572373dc1a35e39e6561e8dc618da937b38634af5），ZIP 完整性检查通过。

下文为历史记录，不再执行旧版本重试、重新登录或模型精度采样指令；当前剩余工作以本节和 docs/product/functional-release-plan.md 为准。


## 2026-09-12 v12 修复新图上传 422：已安装待续传

“放弃失败草稿”已由用户真机确认。新图文件上传成功，但相似度 dHash 的原生 64 位整数溢出产生负号，清单被拒；已用该失败原图及合成回归复现。v12 修复生成及旧草稿发送兼容，保留原图、持久化清单和包/幂等键。静态检查、34 个不同 Flutter 测试（含补跑真实 TLS）、Debug/签名 Release 构建通过；K60 已覆盖安装 v12、保留数据、登录自动恢复。手机拒绝 ADB 模拟点击，等待用户对现有失败草稿点“重试”后核验服务端候选，不能视为上传验收已通过。详见 `docs/development/manual-test-2026-09-12.md`；模型未批准，P02 确认 24 的会话和锁图保持。

## 2026-09-12 授权实猪单图闭环：通过工作流验证

签名联网候选 v9 已在 Redmi K60 完成一轮授权实猪单图。服务端确认采集包、单一媒体、清单、Commit、研究 Runner 推理和回调全部成功；会话 `bdc21fd6-e194-4ace-9673-560dac993aa3` 随后由人工确认。数据库最终状态为 `confirmed`，候选数 **19**、确认数 **24**，关联媒体数 1 且已锁定，审计事件 `inventory.confirmed` 为 1；手机页面同步显示“已确认并锁定 24 头，模型候选 19 头”。

该样本的模型候选比人工真值少 **5** 头（绝对误差 5，按人工数计算低估约 20.8%）。它验证了真实图片的 Release/LAN 上传、研究候选、人工修正、证据锁定与审计闭环，不能证明模型精度达标、模型获批或完整实猪验收通过。当前使用的栏舍主数据仍是 DEV-E2E fixture；继续强制复核并保持 `MODEL_APPROVED=false`。

## 2026-09-12 v11 LAN 地址与会话恢复修复：已验证安装

手机和电脑 WLAN 分别为 `192.168.255.26/24`、`192.168.255.99/24`。LAN 监督器此前错误选取另一张多网卡地址 `172.17.219.182`，现改为依实际默认 IPv4 路由发布；状态文件回读 `ready`、`192.168.255.99`，手机 ICMP 和 TCP 8443 均可达。App 随后能到达服务端；此前离线/登录失败来自前台恢复与无工作后台 Worker 并发刷新同一轮换令牌，日志为 refresh 200 后 refresh 409 `REFRESH_TOKEN_REUSED`。v11 删除启动时的无条件任务注册，并要求 Worker 先发现可同步 Outbox 项才刷新令牌。

签名 LAN APK：`artifacts/android-release/20260912-130658-521/inventory-release-lan-acceptance.apk`，版本 `0.1.0+11`，SHA-256 `d08b0ef2026b52b8f121c0b632d41a7a737b983c22258b39140be682bdb78669`。Flutter analyze、30 项测试、11 项 Release 门禁、签名/HTTPS/禁用明文验证通过；已无线覆盖安装 Redmi K60，系统回读 versionCode 11，冷启动无应用 fatal，原数据保留。旧刷新会话已失效，必须重新登录一次后继续 P01 验收。

## 2026-09-12 v10 失败草稿恢复修复：待真机验证

第一个栏舍只有一份未提交的 `awaiting_blobs` 包，原因是此前图片与当前组织已有图片完全重复；它没有创建盘点会话。第二个栏舍的 24 头会话已确认，不能以新图片替换。为释放第一个栏舍重新测试，v10 仅允许将没有服务端会话的 `blocked` 本地草稿停止重试并标为 `abandoned`，保留原图且不改动服务端已确认/锁定证据。签名 LAN APK：`artifacts/android-release/20260912-122436-180/inventory-release-lan-acceptance.apk`，版本 `0.1.0+10`，SHA-256 `e4d35d15b5385bca299d98d3cc076a72a0360e4e4da7b7221f2c3fa22457e249`。静态检查、30 项 Flutter 测试和 Release 门禁通过。Redmi K60 已通过无线 ADB 无流式覆盖安装，系统回读 `versionCode=10`、`versionName=0.1.0`；原数据未清除，冷启动进程存活且无 Android Runtime fatal。下一步只需核验 P01 草稿释放和新图上传。

## 2026-09-12 Android Release v9 真机联网验证

签名联网候选 `0.1.0+9` 已在 Redmi K60 上冷启动，未出现启动闪退；APK 为 `artifacts/android-release/20260911-205429-813/inventory-release-lan-acceptance.apk`，SHA-256 `c9712ff511272f7541a85c023ca53a5144649bf630609c1e0781726e66caf26e`。最新状态文件的热点地址为 `172.17.219.182`，LAN HTTPS `https://pig-inventory.local:8443`、数据库、Flyway V1–V11 与研究 Runner 已就绪，状态文件已回读 `ready`。

手机通过无线 ADB `192.168.255.26:42753` 接入；手机到 TCP 8443 可达。服务端日志确认 `local-admin` 登录链路完成：refresh 200，`/api/v1/me` 200，今日任务 200。当前仍只是联网和认证证据，尚未完成授权真实猪只单图上传、候选数与人工真值对照、人工确认/报表及弱网/后台恢复验收。继续保持 `MODEL_APPROVED=false`、研究 Provider 和 `review_required`。

## 2026-09-11 Android Release v8 启动修复与 LAN 发现

签名联网候选已更新为 `0.1.0+8`：`artifacts/android-release/20260911-203648-633/inventory-release-lan-acceptance.apk`，SHA-256 `45c006bd7461746db994883d1cd895ef9a84d87bc610d23ad88c9ec66aef87d5`。`workmanager` 已升级到 0.10.10/AndroidX 2.11.2，Redmi K60 无线覆盖安装、冷启动和进程存活均已验证，未出现此前 WorkManager 启动 fatal。Android 现在对 `pig-inventory.local` 做 mDNS 解析，只接收私网 IPv4，TLS 仍以原域名校验证书。`flutter analyze`、29 项 Flutter 测试（含真实 LAN TLS）和 11 项 Release Gradle 门禁通过。用户解锁后用授权账号登录、真实单图计数及实猪人工验收仍待执行；研究模型继续强制复核，`MODEL_APPROVED=false`。

## 2026-09-11 局域网验收配置最新结果（覆盖下文历史状态）

已完成 `https://pig-inventory.local:8443` 本机 HTTPS/mDNS 与当前用户登录监管，现有签名密钥/P0 卷/Debug 草稿保留。新联网候选 `0.1.0+5`：`artifacts/android-release/20260911-112011-947/inventory-release-lan-acceptance.apk`，SHA-256 `eb19857cfc7395634b66a1136db8b629bb3b2dec0fa9e16904b323efbaf58553`；不是旧保留域名 build-only 包。Flutter analyze、29 tests、11 项 Gradle 门禁通过。HTTPS 实际上传/推理/确认/报表/锁图回归通过：候选 29、独立 fixture 标注和确认 28；此为自动工作流验证，人工实猪验收仍待执行。签名加密本机备份及解密回读通过，异机备份仍待完成。

防火墙已由管理员执行并回读核验：Private 入站 Allow 的 TCP 8443、UDP 5353。下一项是用保留旧 Debug 草稿的安装方案验证手机同网连接，随后集中开展授权实猪/弱网/重启恢复验收。校园网隔离/组播支持、手机安装、实际重启均未验证。MODEL_APPROVED=false 不变。完整步骤、证书有效期/更新和启动边界见 `docs/development/lan-real-pig-acceptance.md`；设计依据见 `docs/research/lan-https-options.md`。未提交/推送，旧证据保留。


## 2026-09-10 签名构建与真实单图增量

已生成 `0.1.0+4` 独立签名 Release **build-only** 包，最新 SHA-256 `993984b4de57348c8552735cd6ebd6af032deeaedd63584b7b118dc01fcc34a6`。签名/证书指纹、APK 版本、非调试、禁用明文验证通过；九项 Gradle 门禁、Flutter analyze 与 27 tests 通过。登录错误分类和单图 1/3 文案已修正。密钥本机忽略且 ACL 受限，未作异机备份；未安装/卸载手机。

Docker 已恢复，P0 先备份数据库后迁移至 V11，原卷保留。当前源码构建 JAR 与运行 JAR checksum 一致；新基础镜像下载停滞后改用已有运行环境封装当前 JAR，详细镜像和启动 override 见 `CURRENT_HANDOFF.md`。实际外部 Runner 已就绪，原模型/0.60 阈值/0.7 IoU/640 尺寸保持。最新研究单图 E2E 返回 28 个候选、Commit 幂等、待人工复核，确认数和业务数均 NULL；证据仅在忽略的 artifacts 中。未冒充全套 Spring/Admin 回归或业务金标评估。

尚无稳定 HTTPS 域名/证书环境，APK 内置保留域名 `api.pig-inventory.invalid`，因此 **不是可联网验收的交付包**。后续先部署真实入口并重建签名候选，补 Runner 常驻/重启和完整确认报表回归，再统一人工/实猪验收。详见 `docs/development/android-release.md`；下文旧环境状态以本节覆盖。

## 2026-09-10 用户调整目标

交接复查：Docker 引擎管道不可连接，当前服务运行状态未验证；09-09 真机测试使用旧业务/管理端镜像（启动日志 Flyway V8），最新源码为 V11，重建和迁移核验待办。现存 LAN Debug APK 哈希已核验，签名 Release 工程尚未实现；运行细节及同进程环境覆盖要求见 `CURRENT_HANDOFF.md`。

当前目标为含真实单图 AI 候选计数的签名 Release APK；开发顺序以 `NEXT_STEPS.md` 的新顺序为准，覆盖下文历史“监控优先”描述。人工验收集中后置并纳入真实猪只计数与人工真值对照。现阶段仍为未发布：Release 签名、稳定 HTTPS 环境、最新服务镜像和统一验收待完成。真实 AI 链路已有研究实现，不能将本轮 unavailable 单图上传当作 AI 精度验证。

2026-09-09 用户提供三张截图，网关日志核验登录、主数据、单图上传和会话读取成功，记录见 `docs/development/manual-test-2026-09-09.md`。此前“所有测试通过”仅用于估算，未发生的验收仍待执行。

更新时间：2026-09-08（隔离管理端浏览器/HTTP 回归通过；人工验收继续后置）
阶段：Development Readiness / Not Release Ready

新对话操作入口见 `CURRENT_HANDOFF.md`；实际后续顺序见 `NEXT_STEPS.md`。2026-09-04 复核确认技术路线没有整体跑偏，但旧文档曾过早宣称 P0 已完全自动收口。2026-09-08 已完成原推荐首项隔离运行时回归；用户暂时无法人工验收，后续优先安全边界和可观测性自动补齐，更细 RBAC 与设备推送仍需产品/部署侧明确。

## 2026-09-08 增量验证与修复

### 最新：业务指标与本地规则自动化基线

- 新增 `observability` 模块：上传分阶段新建/重放/拒绝/失败 Counter、重复拦截 Counter；只读数据库 Gauge 覆盖 Outbox/未终结任务/待复核、24h 推理终态与耗时、管理员重试、原始证据会话复核完成量。幂等回调和更正版本不会虚增数据库样本。口径与局限见 `docs/development/business-observability.md`。
- 监控接口安全收紧：Prometheus/Metrics 及子指标只允许独立 `MONITORING_SERVICE_KEY`，两个用户认证模式均生效；任意用户 JWT 不再能读取全局运维视图。无身份/模型/路径/秘密标签；快照失败为 NaN+不可用，监控和派发采用独立调度线程。
- Flyway V11 增加时间窗查询索引。`mvn verify` **61 tests，0 failures/errors/skipped**；容器构建、Compose、diff 检查通过。首轮测试退出时发现采集线程仍访问销毁后的 Testcontainers，已隔离调度并在测试中显式采样，最终全量重跑正常退出。
- 两个记录规则、四个本地诊断告警，**6 组 promtool 场景通过**：持续时间、陈旧/缺失采集、恢复、最低流量、Counter 重置、复核分流率和零分母。规则测试已入 CI；无 Alertmanager 或外部接收器。
- `scripts/run-observability-e2e.ps1` 真实验证 create/blob/manifest/commit、重放、SHA 重复 409、失败回调 204/200、管理员重试 201/200、更正不重复计完成量、队列差值、1250ms→1.25s，以及两种用户认证模式/缺失监控密钥的 HTTP 拒绝。扩展脚本曾将更正的 200 误期望为 201，修复断言及可重复执行的差值后通过；未改业务合同。
- 最终忽略摘要 `test-assets/generated/observability/summary.json`：`2026-09-08T03:22:58.7055379+00:00`。测试使用合成字节，不声称图片解码或 Worker/模型性能覆盖；只移除 `pig-inventory-p0-observability` 容器/网络、保留卷，P0 原容器仍停止。无提交/推送。
- 尚未完成：真实 Prometheus 长期采集和告警状态流转、Redis 消息队列/Worker 心跳/自动重试、端到端 P95、目标容量及生产阈值。当前 Outbox 深度不能冒充 Broker 长度，Provider 耗时不能冒充端到端延迟；人工/生产验收仍未通过。GitHub 对照见 `docs/research/business-observability-github-benchmark.md`。

### 此前：管理端可选面板状态已收口

- 近重复告警、失败任务和审计日志采用显式 loading/forbidden/error/ready 状态；只有成功列表可展示零条。按 `/me` 当前组织角色判断展示权限，后端仍是授权权威；403 显示无权限，404/401/429/5xx/网络/响应异常显示加载失败，不再吞成空数组。
- 刷新时隐藏旧面板行，失败面板支持刷新重试，独立请求完成后分别更新；重新登录清理旧任务/报表/媒体上下文，避免上次账号内容闪现。
- 管理端 **24 tests passed**，`pnpm lint`、`pnpm typecheck`、本地及容器 `pnpm build`、Compose 和 `git diff --check` 通过。Spring/Python/Flutter 本轮未修改、未冒充重跑；其历史结果见下文。
- `run-admin-runtime-e2e.ps1` 在固定隔离栈通过：三个面板 × 503/404/网络中断/无效 JSON/成功空数组，共 **15 组**，覆盖加载、未知数量、不污染兄弟面板及刷新恢复；真实 OPERATOR/REVIEWER 页面验证无权限展示及不请求受限面板。故障由浏览器侧拦截合成，不代表后端真实宕机测试。
- 原有真实令牌过期单次轮换、页面更正、失败重试、媒体锁定、confirmed-only 日报、幂等/唯一审计/越权全部重跑通过，未捕获页面异常 0。忽略摘要完成于 `2026-09-08T02:56:57.512Z`；仅清理测试容器/网络、保留三个卷，P0 仍停止且未动。
- 下一项为业务指标口径、埋点与本地告警规则验证；没有接入外部告警、改模型批准或提交/推送。人工/部署验收继续未通过。

### 此前：回调鉴权独立边界已收口

- `InferenceCallbackAuthenticator` 已移除 `security=false` 绕过；OpenAPI 澄清服务密钥始终必需，用户 JWT 不可替代。派发器启动时的非空密钥门禁保持不变，未配置密钥且派发器关闭时可启动，但回调请求一律拒绝。
- 新增真实 MVC/安全链 8 项参数化测试：修复前 3 项失败，修复后全部通过；覆盖用户认证开/关、缺失/空白/错误密钥、合法密钥、管理员 JWT 不能替代、未配置密钥及拒绝前不调用业务服务。Python 补服务密钥/稳定任务幂等键发送及 401/403 永久失败边界测试。
- 最新 `mvn verify` 为 **54 tests，0 failures/errors/skipped**；Python **37 passed**；业务容器重建、Spectral 合同检查与 Compose 配置通过。管理端/Flutter 本轮未改动，上一阶段浏览器证据不冒充本轮重跑。
- `scripts/run-callback-auth-e2e.ps1` 固定 `pig-inventory-p0-callback-auth` 和 loopback 8094。真实 HTTP/MySQL 两种用户认证模式均验证 missing/wrong key 401 且不写数据库，valid 204、replay 200、conflict 409，只产生一条结果/回执，确认数仍空；未配置密钥亦返回 401。摘要 `test-assets/generated/callback-auth/summary.json`，完成时间 `2026-09-08T02:38:58.1365358Z`。
- 该隔离栈成功后容器/网络已清理、三个卷保留；P0 未动，未提交或推送。后续面板状态已在上方最新增量完成，业务指标与告警验证仍待办。人工验收继续待办。

### 此前：管理端运行时与更正谱系

- 新增 `scripts/run-admin-runtime-e2e.ps1`、固定 Compose override 和 CLI 浏览器断言，详见 `docs/development/admin-runtime-e2e.md`。只使用 `pig-inventory-p0-admin-runtime`、loopback 8093、测试专用身份和生成 PNG，不读产品 `.env` 或研究输入。
- 浏览器最终语义读回通过：真实旧 Access Token 失效后并发面板只 Refresh 一次；页面更正 v1 17 → v2 19；旧 v1 保持 superseded/17，相同原始图片仍锁定，日报只含 v2；更正重放同一版本、变更意图 409、唯一审计；失败任务可创建不可变重试后继；OPERATOR/第二组织更正返回 404；令牌仅在内存，重载需登录，未捕获页面异常 0。
- 修复管理端迟到 401 导致额外刷新、刷新网络失败未清会话、旧刷新覆盖新登录会话、Headers/tuple 请求头丢失边界；管理端测试从 5 增至 9，并加入 CI。
- 集成测试先复现“重试 → 人工确认 → 更正 → 晚到回调”把旧 v1 重新置为 review_required，随后修复为同时保护 confirmed/superseded。补齐 Testcontainers 夹具对更正谱系外键和 CHECK 约束的清理，未修改任何已应用迁移。
- 本轮 `mvn verify`：46 tests，0 failures/errors/skipped；管理端 9 tests、lint/typecheck、Docker 中生产 build 通过。真实 `/actuator/prometheus` 鉴权请求 200、匿名 401，含 JVM/HTTP 指标；自定义业务指标/告警仍未完成。
- 最终浏览器证据：本机忽略的 `test-assets/generated/admin-runtime/summary.json`，完成时间 `2026-09-08T02:20:07.561Z`；截图为 `dashboard.png`。脚本成功后移除该隔离栈容器/网络，保留测试卷；P0 原容器/卷未变更。
- 没有提交或推送累计工作区改动；本轮未改 Flutter、模型、阈值或批准状态。历史全栈结果见下文，本轮不将其冒充为重新执行。

## 已决定

- 采用路线 B+：Flutter + Next.js + Spring Boot/MySQL + 独立 Python 推理服务。
- 学长代码 `eg/` 只读并被 Git 忽略；以 clean-room 方式独立实现。
- Django 原型冻结，只保留行为回归价值；Spring 是唯一新业务主干。
- Android、服务端推理、照片闭环优先。视频、端侧、多视角自动去重和 Agent 编排后置。
- 产品名称确定为“智慧猪场场主”；初版原创 Logo 已入库，可在品牌定稿后替换。
- V1 明确不包含死猪上报；作为后续独立业务域候选。
- MinIO 继续作为默认对象存储；上线前仍需完成其 AGPL 分发义务评估。
- 主流 Android 验收机为 realme GT 7 Pro；低端机候选为 REDMI Note 14 5G（6GB+128GB），待采购或借测确认。
- 外部 YOLO 研究数据集只可作为本机只读验证来源；产品仓库只保留脚本和数据治理规则，不保存原始图片、标签或生成清单。

## 本轮完成

- 建立综合 PRD、范围边界、非功能需求、视觉系统、信息架构、验收标准和需求追踪矩阵。
- 固定业务 OpenAPI、推理请求/结果 JSON Schema、上传状态机和路线 B+ ADR。
- 建立 Spring Boot 3/Java 21 主服务、MySQL Flyway 基线、组织成员、证据链、模型注册、审计和事务 Outbox 表。
- 建立 Python FastAPI/Celery Provider 骨架，默认 Unavailable Provider 不产生模拟数量。
- 重构 Flutter 五入口页面壳、现场视觉组件、Drift 主数据/草稿/媒体/Outbox 草案和新版上传客户端合同。
- 建立 Next.js 管理端“现场态势”：受认证登录后通过同源受限代理读取真实当日栏舍任务、会话媒体、近重复告警、日报/综合报表和审计；可由后端授权执行人工确认与近重复解决，不再展示演示数量或暴露对象 URL。
- 切换 Docker Compose 为 MySQL、Redis、MinIO、Spring、推理 API/Worker、Next.js 和 Nginx 网关。
- 建立 CI、开发规范、测试规范、许可证边界和冻结原型说明。
- 建立工作站初始化/核验脚本、随机本机 `.env` 生成流程和测试数据治理规则。
- 已对外部 YOLO 研究集生成本机忽略的完整性清单：500 张图像、12,421 个标注目标，图像—标签配对问题为 0；这不是业务金标或产品分发授权证明。
- 已建立公开 GitHub 仓库 [`JWLuo0719/smart-pig-inventory`](https://github.com/JWLuo0719/smart-pig-inventory)，默认分支为 `main`，原创产品源码按 Apache-2.0 发布；公开前已排除 `.env`、模型/权重、外部研究数据、测试产物、真实媒体和 `eg/` 参照物。
- 已安装 Flutter 3.44.7、Android SDK 36、Build Tools 36.0.0 和 platform-tools；Android SDK 许可证已接受，Android 原生壳与 Drift 生成代码已入工程。
- 已安装 Docker Desktop 4.87.0（per-user、WSL 2、Linux containers），并将 WSL 数据根设置为 `D:\DockerDesktop\wsl-data`；已恢复 Desktop 引擎并完成 Compose 首次完整启动。
- 已安装 Maven 3.9.11 至 `D:\ProgrammingLanguage\apache-maven-3.9.11`，并将其纳入本机核验脚本。
- 已用 Testcontainers MySQL 8.4 实际验证 Flyway V1/V2；`src/test/resources/docker-java.properties` 将 Docker Java 客户端 API 固定为 1.44，解决 Docker Desktop 29.7 经 Windows npipe 的兼容问题，不依赖系统全局环境变量。
- Flutter Drift 已升级至本地 schema v6：单图/三图媒体物化、流式 SHA-256、EXIF 方向/尺寸、方向唯一、ROI 边界持久化、完整采集组入队，以及认证上下文、组织主数据游标缓存均具备自动化证据；上传队列现已实现 create/blob/manifest/commit 的持久状态机、租约、失败分流和 Commit 后才标记 synced，WorkManager 已接入安全存储会话、网络约束、指数退避和后台批处理，并已在 realme GT 7 Pro 验证网络恢复、应用重启后的自动上传。
- 已实现推理闭环的系统边界：Spring 对提交事件进行带租约的事务 Outbox 派发；Python Celery Worker 以 `job_id` 回传最终结果；Spring 以结果指纹保证相同回调重放成功、不同结果冲突，并将结果和模型身份写入业务库。未获验证的三视图结果强制进入人工复核，不使用自动数量。
- 已部署 iMoonLab YOLOv13 Nano 的产品仓库外本机研究 Runner，并以隔离 Compose 项目验证了 MinIO 读取、原始模型推理、产品 HTTP Provider 调用与二次安全降级。该路径始终返回人工复核和空计数；它不是获准的猪只自动计数模型。
- 已实现 P0 审计确认纵向切片：会话结果查询、复核员确认/手工修正、确认幂等重放、事务锁定全部引用媒体、普通删除对锁定证据的冲突拒绝、AuditEvent，以及仅管理员可用的带原因软删除。Flutter 已可从已提交上传队列进入服务器复核页；隔离 Compose 已验证 Commit -> Outbox -> Celery -> 受服务密钥保护的回调 -> 人工确认/锁定/软删除闭环。已新增真实任务投影、仅确认日盘点日报和综合平均 API，并将移动端任务页接到真实数据；近重复的服务端告警/复核 API、管理端媒体审核/确认/报表及移动端感知哈希均已完成，人工验收另行后置。
- P0 真机验收发现并修复三项客户端/管理端缺陷：局域网 HTTP 下管理端 `crypto.randomUUID` 不可用、采集页伪造“3 个采集包”离线计数且仅展示第一张恢复证据、复核页 Access Token 过期时未自动刷新。Flutter v`0.1.0+3` 已显示左/中/右本地证据缩略图和大图、取消伪造状态，并在复核读取/确认 401 时尝试 Refresh Token 重试；管理端兼容 UUID fallback 已通过 LAN HTTP Chromium 登录与同源数据加载冒烟。Flutter 真机和管理端完整人工回归仍待执行。
- 已完成不依赖人工测试的 P0 管理/权限切片：管理端可受认证预览会话媒体、人工确认、解决近重复告警、读取日报/综合报表及审计；媒体通过业务 API 流式读取，未暴露对象 URL。新增隔离 `pig-inventory-p0` 专用合成 OPERATOR、REVIEWER、FARM_ADMIN、第二组织账号与主数据 fixture；MySQL/JWT 自动化覆盖角色和跨组织不可发现，隔离 Compose HTTP smoke 已以四个合成账号验证角色/组织任务范围。近重复解决要求理由、幂等并写审计，绝不删除媒体。Flutter 为复核与 Outbox 的 401 refresh/retry 加入自动化测试，上传重放仍复用原幂等键。
- 已按 PRD 重新确认开发顺序：先收口 P0 可自动化闭环，再推进 P1 真实单图 YOLO 研究准入；必须依赖真人、真机或部署负责人的 P0 签署按用户要求后置但不视为通过。Spring 允许研究模式单图检测框形成待人工确认候选数，但左/中/右检测框始终不汇总。隔离验收配置脚本会补齐推理派发开关和非空回调令牌；团队权重的 checksum、合同和计数复查记录在 `docs/research/team-yolov13-candidate-evaluation.md`，仍保持研究模式。
- 按用户要求将必须由真人、真机或部署负责人签署的验收后置，但未将其标记为通过。P0 剩余可自动化门禁已经补齐：Provider 严格核对请求模型身份、验证归一化框、按框中心与 ROI 边界过滤并重新计数；单图候选与三视图禁止汇总均有测试。
- P1 团队权重研究链路已实际跑通：外部 Runner 启动时校验权重 SHA-256，固定研究阈值 0.60，经私有 MinIO、Celery Worker、受保护回调保存 25 个候选框；相同 Commit 重放复用推理任务，数据库业务计数保持为空。管理端已接入候选框、置信度、模型版本/checksum、来源与耗时展示，候选不会进入日报。
- P1 已加入只读、可复现的全量计数回归：验证集 102 张选择阈值 0.60，MAE 0.647、WAPE 3.15%；固定阈值后测试集 61 张仅评估一次，MAE 1.049、WAPE 3.75%、±2 内 93.44%。旧手工测试指标无法复现，已明确由当前固定脚本结果取代。当前 Windows CPU 运行时稳态 P95 为 64.1 ms；该研究集数量分布单一，不构成业务金标或生产性能证明。
- Python HTTP Provider 的连接/总超时现可配置并严格校验；Worker 的 Provider 超时会形成同一任务 ID 的终态失败回调，回调 429/5xx/网络超时与 4xx 永久失败分类已有自动化覆盖。
- P1 隔离 `pig-inventory-p1-fault` Docker E2E 已验证：Runner 未就绪时推理 API 返回 503；2 秒 Provider 超时形成 `PROVIDER_TIMEOUT`、空候选/业务数量并进入人工复核；Runner 停止后 readiness fail-closed；容器重启后仍等待显式 ready，恢复后上传/Worker/Callback 返回 1 个合成候选。成功后仅清理隔离容器和网络，保留卷，`pig-inventory-p0` 未受影响。
- 推理失败现以 `inferenceStatus`、`failureCode`、`failureMessage` 从数据库会话查询传到 OpenAPI、管理端和 Flutter；管理端/移动端明确显示“自动计数失败，已安全转人工复核”，不会把失败或候选写入日报。
- P1 已增加研究模型发布门禁：清单重新计算权重与回归摘要 SHA-256，固定模型/适配器/阈值/运行时证据，拒绝外部路径入清单，并强制许可、业务金标和负责人审批保持 pending。当前全量结果已显式建立不可覆盖的本机基线，零漂移比较通过；模型 identity、阈值、MAE/WAPE、±2、最大误差、P95 或吞吐超限会失败。
- P1 隔离 `pig-inventory-p1-rollback` 已实际完成逻辑版本切换、损坏 checksum 503 `RUNNER_IDENTITY_MISMATCH` 和回滚锚点恢复；回滚约 11.4 秒恢复 readiness。该证据只覆盖 Stub 控制面，不代表真实权重加载 RTO；成功后测试容器/网络已清理，P0 栈未停止。
- P1 失败推理任务管理已完成：OpenAPI 提供组织内失败任务查询和管理员重试，FARM_ADMIN/SYSTEM_ADMIN 才可操作。Flyway V9 将原“一采集组一任务”扩展为不可变线性重试谱系；每次重试保留原媒体、失败码、请求模型身份与审计链并创建新任务。同键同理由的顺序/并发重放只产生一个后继、一条 Outbox 和一条 AuditEvent，不同意图返回 409；晚到重试回调不会覆盖已人工确认会话。Next.js 已接入失败列表、阻断原因和带理由重试。隔离 `pig-inventory-p1-retry` 已验证 `PROVIDER_TIMEOUT` -> 管理员重试 -> Worker/Callback 恢复、模型身份保持和审计唯一，成功后仅清理隔离容器/网络，P0 未受影响。
- P1 已确认盘点报表导出已完成：OpenAPI 提供按组织和日期范围下载 PDF/XLSX；Spring 从同一确认快照生成两种格式，限制为 366 天和 10,000 条，PDF 使用可配置中文字体与独立拉丁字体分段嵌入，XLSX 对外部文本保持字符串类型并提供摘要公式。Next.js 同源代理保留下载头，管理端提供日期范围和双格式入口。隔离 `pig-inventory-p1-report-export` E2E 证明仅导出本组织确认数 17，排除未确认候选 999 和其他组织确认数 88，422 校验、文件签名、内容类型与确定性文件名均通过；产物视觉和可搜索文本/公式错误也已复核。
- 2026-09-04 P0 需求回查修复已完成：Next.js 同源代理改为集中式 fail-closed 方法/路径策略并补齐刷新、失败重试与更正路由；管理端 401 只做一次共享 Token 轮换并重放原请求。Flutter 首页、图库和“我的”全部改读激活组织的真实 API/Drift 数据，离线状态不再虚构数量、进度或场站信息。
- 已实现确认后不可变更正：OpenAPI 0.7.0、Flyway V10、Spring 事务/RBAC/审计、管理端入口与 Flutter 版本展示均已接线。旧确认版本转 `superseded`，新版本引用同一证据根，数据库唯一约束保证同栏舍/业务日期只有一个当前确认版本；同意图幂等重放、冲突和 confirmed-only 报表切换已由真实 MySQL 验证。
- 安全与可观测性基线补强：启用推理派发器时，空回调令牌无论终端用户认证开关如何都会启动失败；Spring 已加入 Prometheus registry。业务级指标与告警规则仍未完成，不据此宣称满足全部 NFR。

## 已验证证据

| 范围 | 结果 |
|---|---|
| Spring 上传链路、身份、主数据、领域与 Flyway 集成测试 | `mvn verify` success；45 tests passed，0 skipped；Testcontainers 实际启动 MySQL 8.4 并应用 V1–V10，覆盖确认后更正版本/证据谱系/幂等/RBAC/报表切换、确认报表组织与日期边界、PDF/XLSX 渲染及既有失败任务重试 |
| Python Provider/合同漂移/Worker/ready/失败路径/回归指标/发布门禁测试 | 33 tests passed；新增验证同一证据和模型身份可由不同管理重试任务 ID 再次进入派发边界 |
| Next.js | 代理策略与认证轮换 5 tests passed；ESLint、TypeScript、production build passed（登录/刷新、失败任务、确认后更正、媒体、报表和审计路由已纳入白名单；并发 401 单次刷新、原幂等键重放和失败清会话已测试） |
| OpenAPI | openapi-spec-validator 0.7.2 passed |
| 推理 JSON Schema | JSON 语法与 Python 序列化键集合测试通过 |
| 外部 YOLO 数据清单 | 500 图像、12,421 标注目标、0 图像—标签配对问题；本机生成且 Git 忽略 |
| Flutter Android | `flutter analyze` 通过；27 项测试通过（新增激活组织本地活动投影，含结构化推理失败、复核 401 Refresh Token 与 Outbox 原幂等键重试）；debug APK 已复建，SHA-256 `A0CD2506FC9CBD422078E01B8FDCBE4CEF5C1C41AAAB2C22B31593B8BE85DE05` |
| Docker Desktop / Compose | 历史隔离 E2E 已验证 bootstrap 登录、`/me`、令牌刷新、主数据同步及 LAN 真机三图断网/强杀恢复；本轮 `docker compose config --quiet` 与 fault 叠加配置通过。2026-09-04 当前 `docker ps` 为空，P0 持久卷/网络仍在且未被修改；旧的“当前 P0 正在运行”状态已撤销 |
| Flyway / MinIO | MySQL 已实际应用 V1–V10；V9 推理重试谱系与 V10 盘点更正谱系均由迁移/业务集成测试验证；`minio-init` 已完成私有桶初始化 |
| Flutter 离线采集与上传恢复 | analyze 通过；27 项测试通过；v`0.1.0+3` debug APK 构建成功；10MB 流式物化、方向唯一、ROI、本地入队、激活组织真实活动投影和三视图剩余 Blob 续传均覆盖。realme GT 7 Pro 曾人工验证完整左/中/右三图强制关闭恢复；复核页 Token 自动刷新与本轮首页/图库/我的改造仍待实机回归。 |
| Python Provider | pytest 通过；32 项测试通过，覆盖 ROI 重计数、非法模型身份、未知媒体、越界框拒绝、可配置 HTTP 超时、Runner readiness/身份不一致 fail-closed、Provider 超时终态回调、回调瞬态/永久失败分类、回归指标计算，以及发布清单/漂移门禁；外部 Runner 7 项测试通过，含权重 checksum 成功/失败关闭 |
| Docker 推理故障注入 | 隔离项目验证 not-ready 503、`PROVIDER_TIMEOUT` 安全转人工、Runner 停止 fail-closed、重启后显式 readiness 和恢复成功；本机忽略摘要记录 cold gate 15 ms、restart gate 12 ms（仅 Stub 控制面，不是模型性能） |
| Docker 推理管理员重试 | 隔离 `pig-inventory-p1-retry` 验证源任务保持 `PROVIDER_TIMEOUT`、同键重放命中同一后继、第二意图 409、请求模型身份保持、Worker/Callback 恢复成功、AuditEvent 恰为 1；本机忽略摘要为 `test-assets/generated/inference-retry-e2e-summary.json` |
| Docker 已确认报表导出 | 隔离 `pig-inventory-p1-report-export` 真实 HTTP 验证 PDF/XLSX 200、错误日期/格式 422、确定性下载文件名、仅本组织 confirmed 行；产物只含确认数 17，不含候选 999、其他组织 88、内部 URL/模型/失败字段，PDF 中文可搜索且视觉无重叠，XLSX 两工作表无公式错误；成功后容器/网络已清理，P0 原容器恢复健康且卷未触碰 |
| 团队权重全量回归 | 验证集 102 张在候选阈值中选择 0.60：MAE 0.647、WAPE 3.15%；固定后测试集 61 张：MAE 1.049、WAPE 3.75%、±2 内 93.44%、最大误差 3；Windows CPU 稳态 P95 64.1 ms。产物仅本机保存且 Git 忽略 |
| 模型发布与漂移门禁 | 真实权重与全量摘要生成/二次校验通过；研究安全状态和三项 pending 阻断不可绕过；当前不可覆盖基线比较 0 violation，P95/吞吐比均为 1.0；旧模型缺可复现摘要，未伪造跨模型历史通过 |
| 模型版本回滚 | 隔离 `pig-inventory-p1-rollback` 完成锚点 -> 候选 -> 损坏 checksum 503 -> 锚点恢复，原因精确为 `RUNNER_IDENTITY_MISMATCH`，约 11.4 秒恢复 readiness；未接触业务数据库，自动计数保持关闭 |
| 推理派发、结果回调与确认锁定 | Maven 29 项通过、0 skipped；Testcontainers MySQL 8.4 已实际应用 V1-V7。隔离 Compose 以受认证的 bootstrap SYSTEM_ADMIN 完成 create/blob/manifest/commit、Outbox、Celery unavailable 回调（HTTP 204）、review_required、人工确认、媒体锁定、普通删除 409、管理员软删除和两条 AuditEvent；详情见 `docs/development/p0-closure-e2e.md`。Python `pytest` 6 项、OpenAPI 校验均通过 |
| YOLOv13 研究部署 | 外部 Runner 已健康；使用 Nano 权重完成私有 MinIO 对象推理。隔离产品 Worker 选择 `research-http-yolo` 并强制 `review_required`/空计数 |
| 研究候选数安全口径 | `InferenceResultServiceIntegrationTest` 6 项通过、0 skipped；真实 MySQL 8.4 应用 V1-V8，覆盖单图检测候选数与三视图检测不汇总 |
| 团队权重真实研究 E2E | 外部 28 头测试图在阈值 0.60 返回 25 个真实候选；隔离 `pig-inventory-p0` 完成 MinIO/Worker/Callback，Commit 重放复用任务 `536f64f5-a3db-46a0-ad9f-1c3f15d13567`，结果为 `review_required`，模型 checksum 精确匹配，业务 `count_value` 为空 |
| P1 管理端自动浏览器回归 | 真实 Chromium 以合成 OPERATOR 打开研究会话，显示 25 个候选框/置信度、精确版本/checksum、2672 ms 耗时和研究警告；任务卡数量为“—”、日报 0 条，local/session storage 为空 |
| 管理端 LAN HTTP 冒烟 | `pig-inventory-p0` 真实 Chromium 登录成功；任务、近重复、审计、日报和综合报表均通过同源代理返回 200；local/session storage 为空。仅 `favicon.ico` 返回 404；不代表完整人工浏览器验收 |

## 未验证与阻塞

- Docker Desktop 初次启动的 WSL 引擎问题已通过重新启动 Desktop 进程恢复；完整栈、Flyway、私有 MinIO 桶与网关健康已复验。`docker compose config --quiet` 已复验。管理端 Docker 构建曾因缺少 `.dockerignore` 覆盖 Linux `node_modules` 而失败，已修复并验证构建。
- `mvn verify` 的 Flyway 运行时对 MySQL 8.4 输出“最新版已验证至 MySQL 8.1”的升级建议，但 V1–V10 已实际成功迁移；进入发布准备前应升级/复验 Flyway 与 MySQL 8.4 的兼容性，或固定到受支持的 MySQL 版本。
- 管理端 Token/更正 v2/失败任务路由的隔离真实浏览器 E2E 已于 2026-09-08 通过；仍未执行人工键盘、130% 字体和真机验收。后续面板行为变更需要重跑该脚本。
- Prometheus 抓取 registry 已接入，但 NFR 指定的上传成功率、队列深度、推理耗时、复核率、失败重试数和重复拦截数尚未全部形成稳定业务指标、告警和容量证据。
- P0 上传包 create/blob/manifest/commit、事务 Outbox 派发、MinIO 暂存提升、受服务密钥保护的回调、Bootstrap 管理员、login/refresh/logout/me、JWT 刷新轮换和组织隔离主数据同步均已实现；Flutter 已接入安全令牌存储、7 天离线恢复、主数据缓存、持久化 Outbox 和 WorkManager。实机已验证完整三视图强杀恢复及一次自动 Commit；上传中途断流仅续传剩余 Blob、复核页 Refresh Token 回归、完整 RBAC 与后台 Worker 实机 E2E 仍未完成。
- 金蝶正式 API、线上 YOLOv13 权重、模型许可证、金标基准和部署服务器规格尚未提供。
- 提供的 `yolov13-official-main.zip` 已核实为 Ultralytics AGPL-3.0 源码且不含权重；不能直接纳入专有产品主线。当前仅保留独立 HTTP Provider 合同，待许可与金标准入后启用真实模型。
- 已采用 iMoonLab 上游仓库的 Nano 权重开展本机隔离研究测试；其 AGPL-3.0 代码和权重仍未获得专有产品、现场或自动计数准入。默认开发卷含历史 MySQL 账号口令，不与当前 `.env` 一致；本轮通过新建的 `pig-inventory-yolo-research` 隔离卷完成测试，未改写原卷。
- 2026-08-30 Docker Hub OAuth 超时已定位为直连 DNS/路由异常叠加 Buildx 未继承桌面代理：Docker Desktop 手动代理和发起构建的 PowerShell 显式使用 Clash `127.0.0.1:7897` 后，基础镜像解析恢复到数秒；无需开启 TUN，也未添加不安全镜像站。本轮业务镜像已重建，`pig-inventory-p0` 完成真实 MinIO/Worker/Callback/管理端候选证据 E2E；人工真机与生产签署仍按手册后置。
- 低端 Android 候选机是否可获得，以及首批试点猪场、边缘服务器规格仍待确认。

## 发布判定

目前只完成可持续迭代的架构与界面基线，不是可现场使用版本。只有 `docs/product/acceptance-criteria.md` 的 AC-01 至 AC-12 均具备自动化或实机证据后，才能进入现场试用。
# 2026-09-13 v17 增量状态

## 非视频功能人工验收状态

用户反馈前四项非视频功能测试成功，视频相关测试后置。当前候选包可继续推进非视频功能收口；视频流程、视频播放和视频自动计数仍保持待验收状态。

## v18 真机上传恢复已验证

v18 (`0.1.0+18`) 已同签名覆盖安装到 Redmi K60，保留原应用数据。原步骤 2 卡住包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 未点击重试或放弃，通过启动后自动调度完成上传；服务端包为 `committed`，会话 `review_required`，候选 21，手机重启读回“已提交服务器”、本机待上传 0、等待复核 1。自动与真机恢复证据见 `artifacts/functional-v18-*` 和 `artifacts/releases/20260913-functional-v18/`。正式目标未选定，未正式上线，`MODEL_APPROVED=false`。

步骤 1 首页/任务读回已通过。步骤 2 的新图包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 发现移动端后台网络异常后永久保留 `creating_package` 的缺陷；v17 已修复并以 42 项 Flutter 测试、analyze、Debug 构建和签名 LAN Release 构建验证。设备覆盖安装及该包自动恢复的真机读回尚未完成，因无线 ADB 端口暂时拒绝连接；正式服务器、域名和账号仍未确定，未正式上线，`MODEL_APPROVED=false`。
