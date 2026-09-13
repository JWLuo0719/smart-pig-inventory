# 新对话交接

## 2026-09-13 非视频功能人工验收完成

用户反馈前四项非视频功能测试成功，视频相关测试后置。结合 v18 的自动读回，上传包自动恢复、服务端提交、人工复核入口及非视频页面功能可继续保留为候选包验收证据；视频采集/上传/播放和视频自动计数仍未验收，不得据此标记通过。模型准确度研究继续后置，`MODEL_APPROVED=false`。

## 2026-09-13 v18 真机上传恢复已通过

v18 (`0.1.0+18`) 同签名覆盖安装到 Redmi K60，`firstInstallTime=2026-09-11 19:59:25` 保持不变。应用启动后自动重新安排了仍可同步的本地队列；原包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 未点击重试或放弃，服务端按创建包、Blob、Manifest、Commit 顺序成功接收。服务端读回：包 `e57c2e63-e39c-4660-b49b-da970f65de18` 为 `committed`，会话 `7b43bb4e-f062-4cf9-bee8-57dadf9a9e18` 为 `review_required`，候选 21，未确认；手机重启读回显示“已提交服务器”、本机待上传 0、等待复核 1。

v18 APK：`artifacts/android-release/20260913-135028-090/inventory-release-lan-acceptance.apk`，SHA-256 `46203a229cbd12d1263ef18e22f514e4ab9c6672a6d4a697194ce6d7ee6a96d1`；候选包 `artifacts/releases/20260913-functional-v18.zip`，SHA-256 `2d025cdf19163fa283e98d9fa9986f9bb926dc491f7b2baf4c63969e07af50e6`。Flutter 全量 42 项、analyze、Debug/Release、签名/TLS 门禁通过。候选数仍必须独立人工清点后确认，`MODEL_APPROVED=false`；正式服务器、域名、猪场和账号仍未确定。

## 2026-09-13 v17 上传包卡住修复（历史，已由 v18 覆盖）

步骤 2 的新包 `775046d8-7ea4-4ade-91f8-878e90a7a94f` 曾停在“正在创建上传包”，用户未点击重试。只读回读显示没有对应网关创建包请求，WorkManager 返回 `RETRY`，旧实现却留下 `creating_package` 租约。移动端已修复：网络套接字/TLS 握手/超时异常清理租约并进入 `retry_wait`，Drift 时间更新改为类型化绑定；新增测试后 Flutter 全量 42 项、analyze、Debug 构建通过。

v17 Release APK：`artifacts/android-release/20260913-133405-617/inventory-release-lan-acceptance.apk`，SHA-256 `29569978fc4600be91534236ba2f282e546c56b7a0d10ec43d6187e919251fa0`，版本 `0.1.0+17`，沿用发布证书和 LAN CA。构建签名/TLS/非调试/禁明文校验通过。构建完成时无线 ADB mDNS 记录存在但 TCP 端口拒绝连接，尚未覆盖安装 v17，也没有改动或清除设备数据；待用户重新打开无线调试后，用 `adb install -r` 保留数据覆盖安装并只读回包状态。期间不要点击该包的重试或放弃。


## 2026-09-13 v16 真机启动与首页任务读回已验证

已通过无线 ADB 在 Redmi K60 上覆盖安装同一发布证书的 `0.1.0+16`，保留原应用数据（`firstInstallTime=2026-09-11 19:59:25`）。当前设备地址为 `192.168.255.26:42187`，电脑局域网地址为 `192.168.255.99`，入口仍为 `https://pig-inventory.local:8443`。

本次真机读回验证了 mDNS/HTTPS、认证恢复和首页任务自动加载：服务端记录 `/api/v1/me` 200、刷新后再次 `/me` 200、`/api/v1/inventory-tasks?businessDate=2026-09-13` 200；首页显示“网络连接已验证”、两个真实 E2E 任务和 `0 / 2`，没有“任务状态未知”或伪造的 `0 / 0`。真机发现首页在认证从加载/离线转为在线后没有重新请求任务，已在 `home_screen.dart` 增加认证状态监听，并以三个 Flutter widget 测试覆盖离线恢复和初始认证为空的转在线场景。

证据：`artifacts/functional-v16-device-ui.xml`、`artifacts/functional-v16-device-package.txt`、`artifacts/functional-v16-server-requests.log`；APK 为 `artifacts/android-release/20260913-122203-772/inventory-release-lan-acceptance.apk`，SHA-256 `8d3b838b55974edd560e9c7dac33763bab17823edf782d030249122c7a8696b7`。Flutter 全量测试 40 项通过（未设置 `LAN_TLS_DIRECTORY` 的全量命令仅跳过 1 项），真实 LAN TLS 单独 2 项通过，`flutter analyze` 与 Debug 构建通过；签名 Release 构建脚本门禁通过。

手机系统拒绝 ADB `INJECT_EVENTS`，因此本轮只记录了冷启动、联网、认证和首页真实任务读回；拍照/导入、上传续传、图库、视频、报表和主数据同步仍需用户在手机上手动操作后再记为集中验收通过。正式服务器、域名、猪场和账号仍未确定，未正式发布；`MODEL_APPROVED=false`，模型精度、视频自动计数和三图自动去重继续后置，金蝶仍缺接口资料。

手动验收的逐项操作、预期结果与禁止触碰的锁定证据见 `docs/development/manual-device-acceptance-v16.md`。每一步完成后以无线 ADB、服务端日志和只读数据回读复核。

步骤 1 已由用户完成并回读通过：手机首页显示网络已验证和 2 个真实任务，P01/P02 均为未开始；网关任务请求 200，应用无 FATAL/ANR。证据为 `artifacts/functional-v16-step1-ui.xml`。下一步是选择一个未确认任务做单图采集和上传，完成后再回读上传状态。


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


## 2026-09-12 当前方向：功能需求收口，精度研究后置

用户确认 v12 续传成功；服务器 13:43 manifest 201、Commit 201，没有重新上传 Blob，数据库 committed / review_required。用户反馈多次计数误差较大，明确等待团队优化模型后再研究准确度。本轮按根目录原始 8 条需求继续开发，见 `docs/product/functional-release-plan.md`。正式服务器/域名/猪场账号尚未确定，先完成可部署候选与门禁，不能声称已正式上线。旧 v12 审计已核验完成，新的功能审计为 `audit-20260912055415-7e029451`（零匹配，进行中）。主数据、日期图库、历史报表与删错图确认保护正在开发验证；尚未部署这些新功能到 P0。

## 2026-09-12 v12 上传清单修复：已安装，待手动重试

- 用户已确认“放弃失败草稿并重新采集”成功。新图 Blob 201、manifest 422；用该失败原图复现 dHash 有符号溢出产生负号，违反 16 位小写十六进制合同。
- v12 改用 BigInt，并兼容旧草稿发送时的负号哈希编码；保留原持久化清单、原图、包/资产/幂等键，直接续传，不需要放弃或重新拍摄。`flutter analyze`、34 个不同测试（含补跑真实 TLS）、Debug/Release 构建及签名/HTTPS/禁用明文验证通过。
- APK 为 `artifacts/android-release/20260912-133617-031/inventory-release-lan-acceptance.apk`，SHA-256 `59679743e4ab5943650b8cc69b92d2fd70a9a2193d9672ffc6aab3c5873e1055`。K60 已无线覆盖安装，versionCode 12、首次安装时间不变，登录自动刷新恢复成功。
- 下一步：用户在上传队列对这份新图失败草稿点“重试”。ADB 模拟点击被系统 `INJECT_EVENTS` 权限拒绝，不能冒称已完成续传。失败服务器包 `a876cc48-d6c9-4f8e-94a8-66aba4eb696b` 仍无会话、Blob 已存；P02 确认 24 的会话和锁图保留。等待独立人工数与候选分别记录；`MODEL_APPROVED=false`。
- 详见 `docs/development/manual-test-2026-09-12.md`。Review Hub 零匹配审计 `audit-20260912052816-14fa9f11` 等待真机续传结果，仍打开。未提交或推送。

## 2026-09-12 授权实猪单图闭环：已验证，模型未获批准

- Redmi K60 上的签名联网候选 v9 已完成一轮授权实猪单图。服务端顺序证据为：创建采集包、上传图片、提交清单、提交采集包、研究 Runner 推理、回调写入候选、人工确认，均成功。
- 会话 `bdc21fd6-e194-4ace-9673-560dac993aa3` 的数据库读回为 `confirmed`：模型候选 **19** 头、人工确认 **24** 头；一个关联媒体已锁定，并有一条 `inventory.confirmed` 审计事件。手机界面也已回读“已确认并锁定 24 头，模型候选 19 头”。
- 此样本的候选较人工真值少 **5** 头（绝对误差 5，按人工数计算低估约 20.8%）。它证明 Release、LAN HTTPS、上传、真实研究推理、人工纠正、证据锁定和审计闭环可用；仅一个样本，不能作为模型精度通过、模型批准或真实农场主数据验收的结论。当前栏舍主数据仍是 DEV-E2E fixture。
- 继续保持 `MODEL_APPROVED=false` 与强制人工复核。下一阶段先固定独立人工真值和通过阈值，再以不同新图片完成空栏、遮挡、光照和不同数量的样本矩阵；真实图片与哈希只留受控服务/本机忽略目录，不入 Git。

## 2026-09-12 v11 LAN 与登录恢复修复：已安装，待重新登录

- Redmi K60 的 Wi-Fi 为 `192.168.255.26/24`，而 LAN 监督器曾因多网卡枚举错误公布 `172.17.219.182`，使手机无法到达 HTTPS 入口。`scripts/start-lan-acceptance.ps1` 现按实际 IPv4 默认路由选择地址；最新状态为 `ready`、`192.168.255.99`、`https://pig-inventory.local:8443`、Runner ready。手机已 ping 通该地址且 TCP 8443 可达。
- 离线/登录未完成的直接触发原因不是 TLS：服务端实际收到 App 的 `/me` 401、两条并发 refresh（先 200、后 409 `REFRESH_TOKEN_REUSED`）。前台启动无条件安排 WorkManager，而后台任务即使没有可同步工作也先刷新令牌，争用了轮换令牌。v11 移除了启动时的无条件任务注册，并让后台任务先确认存在可同步 Outbox 项再读取/刷新会话。
- v11 产物为 `artifacts/android-release/20260912-130658-521/inventory-release-lan-acceptance.apk`，SHA-256 `d08b0ef2026b52b8f121c0b632d41a7a737b983c22258b39140be682bdb78669`，版本 `0.1.0+11`；同一发布证书、LAN CA/HTTPS 健康、禁用明文和非调试门禁已验证。已通过无线 ADB 覆盖安装在 Redmi K60，系统回读 versionCode 11，原首次安装时间不变，冷启动进程存活且无应用 fatal。
- 因那次 409 已使旧刷新会话失效，用户需在 v11 登录页重新输入已有授权账号一次；登录页的“离线时可……”是离线能力说明，不是当前网络连通性结论。登录成功后再验证 P01 的失败草稿释放和一张未出现过的新图上传。

## 2026-09-12 v10 释放失败草稿候选：待真机覆盖验证

- 首栏舍 `E2E-P01` 的首个重复图片失败包仍停在 `awaiting_blobs`，未创建盘点会话；第二栏舍 `E2E-P02` 的 24 头记录则已确认并锁定。确认记录不能由新图片覆盖，计数更正也只能引用原证据。
- 移动端原先会恢复并锁住这份 `blocked` 单图草稿，却没有停止重试入口，导致首栏舍无法重新拍摄。v10 增加“放弃失败草稿并重新采集”：仅适用于没有服务端会话的 `blocked` 草稿，标为 `abandoned`、保留手机原图与服务器暂存，不触碰任何已确认/锁定证据。
- v10 产物为 `artifacts/android-release/20260912-122436-180/inventory-release-lan-acceptance.apk`，SHA-256 `e4d35d15b5385bca299d98d3cc076a72a0360e4e4da7b7221f2c3fa22457e249`，版本 `0.1.0+10`。`flutter analyze`、30 项测试与 Release 签名/HTTPS/禁用明文门禁通过。
- Redmi K60（`23013RK75C`）已通过无线 ADB `192.168.255.26:38547` 以同一发布签名无流式覆盖安装 v10。系统包信息回读 `versionCode=10`、`versionName=0.1.0`，原应用数据目录和首次安装时间保持；强制停止后的冷启动进程存活，日志没有 `AndroidRuntime` 或 `FATAL EXCEPTION`。此前 USB 流式安装返回空错误的尝试不再构成阻塞。没有执行卸载、清数据或删除任何服务端/本地证据；下一步是在 P01 验证失败草稿释放与新图上传。

## 2026-09-12 Android Release v9 真机联网验证

- 当前签名联网候选为 `0.1.0+9`：`artifacts/android-release/20260911-205429-813/inventory-release-lan-acceptance.apk`，SHA-256 `c9712ff511272f7541a85c023ca53a5144649bf630609c1e0781726e66caf26e`。版本、签名证书、禁用明文、研究候选和强制复核配置沿用 v9 构建证据。
- Docker Desktop 已恢复，LAN Compose、Flyway V1–V11、业务 API 和研究 Runner 均已就绪。最新 `artifacts/lan-acceptance/status.json` 地址为 `172.17.219.182`，入口仍是 `https://pig-inventory.local:8443`；mDNS 进程已随热点地址更新，APK 不固定 DHCP 地址。
- Redmi K60 已通过无线 ADB `192.168.255.26:42753` 连接。冷启动 v9 无 `AndroidRuntime`、WorkManager fatal；手机到 `192.168.255.99:8443` TCP 可达。
- 用户账号登录已取得服务端证据：LAN HTTPS 收到 `/api/v1/auth/refresh` 200，随后 `/api/v1/me` 与今日任务接口均 200。真实单图上传、研究候选计数、人工真值和集中实猪验收仍待执行。
- Windows 当前热点网络已回读为 `Private`；防火墙仍只允许 Private、本地子网 TCP 8443 与 UDP 5353。保持手机 Wi-Fi/热点与电脑同网，不能关闭 Wi-Fi 或绕过 TLS。

## 2026-09-11 Android Release v8 启动修复与 LAN 发现

- 当前候选是 `0.1.0+8`：`artifacts/android-release/20260911-203648-633/inventory-release-lan-acceptance.apk`，SHA-256 `45c006bd7461746db994883d1cd895ef9a84d87bc610d23ad88c9ec66aef87d5`。证书、版本、禁用明文和 LAN HTTPS 健康检查均已由构建脚本验证。
- 已将 `workmanager` 升级至 `0.10.10`（AndroidX WorkManager 2.11.2），不再覆盖旧插件的底层库。Redmi K60 已无线覆盖安装 v8，冷启动后版本号为 8、进程存活，日志没有 `AndroidRuntime` 或 `WorkManager` fatal；原来 v5/v6 的启动崩溃已修复。
- Android 端增加只针对 `pig-inventory.local` 的 mDNS 查询和多播锁：仅接受 RFC1918 IPv4 地址，并在保持原域名 SNI/证书链校验的前提下建立 TLS，未固定 DHCP 地址、未关闭 TLS。Windows 实际 TLS 测试仍使用系统 mDNS 解析器。
- `flutter analyze` 与 29 项 Flutter 测试（包含真实 LAN TLS、错误 CA/主机名、跨源拒绝）通过，11 项签名 Gradle 门禁通过。已完成 Review Hub 审计 `audit-20260911113528-05f64bda`，结果为部分验证。
- K60 在验证后锁屏，ADB 无权限注入解锁；用户需正常解锁并用授权账号登录，才能取得 mDNS/HTTPS 认证和真实单图计数证据。此包仍是 research provider、`MODEL_APPROVED=false`、强制人工复核，不能宣称实猪验收或模型批准已完成。

## 2026-09-11 局域网验收配置最新结果（覆盖下文历史状态）

已完成 `https://pig-inventory.local:8443` 本机 HTTPS/mDNS 与当前用户登录监管，现有签名密钥/P0 卷/Debug 草稿保留。新联网候选 `0.1.0+5`：`artifacts/android-release/20260911-112011-947/inventory-release-lan-acceptance.apk`，SHA-256 `eb19857cfc7395634b66a1136db8b629bb3b2dec0fa9e16904b323efbaf58553`；不是旧保留域名 build-only 包。Flutter analyze、29 tests、11 项 Gradle 门禁通过。HTTPS 实际上传/推理/确认/报表/锁图回归通过：候选 29、独立 fixture 标注和确认 28；此为自动工作流验证，人工实猪验收仍待执行。签名加密本机备份及解密回读通过，异机备份仍待完成。

防火墙已由管理员执行并回读核验：Private 入站 Allow 的 TCP 8443、UDP 5353。下一项是用保留旧 Debug 草稿的安装方案验证手机同网连接，随后集中开展授权实猪/弱网/重启恢复验收。校园网隔离/组播支持、手机安装、实际重启均未验证。MODEL_APPROVED=false 不变。完整步骤、证书有效期/更新和启动边界见 `docs/development/lan-real-pig-acceptance.md`；设计依据见 `docs/research/lan-https-options.md`。未提交/推送，旧证据保留。


更新时间：2026-09-10

## 2026-09-10 17:23 最新执行结果（覆盖下文历史状态）

- 已完成独立 Release 签名配置、初始化/构建/九项门禁脚本，说明见 `docs/development/android-release.md`。版本 `0.1.0+4`；密钥已生成至当前用户 LocalAppData/PigInventory/signing，配置为被忽略的 `apps/mobile/android/key.properties`，ACL 已限制，密码未输出。不要再初始化或轮换；异机加密备份未落实。
- 最新签名 APK：`artifacts/android-release/20260910-172050-914/inventory-release-build-only.apk`，SHA-256 `993984b4de57348c8552735cd6ebd6af032deeaedd63584b7b118dc01fcc34a6`，约 61.2 MB。证书指纹 `4d658496b8074bc391fa4f6cac97f577e534c94daf5c7ac2d072e0ad3102fdd6`，签名、版本、非 debuggable、禁用明文均通过。此包使用 `https://api.pig-inventory.invalid`，是 **build-only 工程验证包，不能联网验收**；没有域名/TLS 部署资源，不能称为已接通 AI 的交付。
- 用户表示不清楚签名/域名选择并授权自行尝试解决。本轮已自行生成候选密钥；未购买域名、未公开部署服务。下一项优先落实实际稳定 HTTPS 入口后重新构建；不要索要密码，不要把 DHCP 或临时隧道当成稳定入口。
- Docker 引擎经 `docker desktop restart` 恢复。已备份 P0 数据库到忽略的 `artifacts/p0-backup-before-release-*.sql`，保留原卷。当前 P0 已运行源码 V11，V1–V11 数据库均 success=1。
- 业务标准镜像构建遇新 Temurin 基础层下载停滞，已终止该次构建。改为当前 Dockerfile 的 build 阶段产物 + 已有 observability 运行环境封装 `pig-inventory-release-business-api:20260910`。运行 JAR 与当前源码构建 JAR 的 SHA-256 均为 `f0edfd8af45196f45c3506673b5dc54f0ff0cf91efb97013eb92c5b44adfd994`；不是复用旧业务 JAR。管理端/推理服务已按当前构建上下文重建（命中有效缓存）。完整全新基础环境构建仍待网络恢复。
- 当前启动命令：同一 PowerShell 设置 `$env:GATEWAY_PORT='8089'`，再 `docker compose -p pig-inventory-p0 -f docker-compose.yml -f docker-compose.runner-local.yml -f tmp/compose-release-runtime.yml up -d --no-build`。最后一个忽略 override 指定上述业务镜像；不可遗漏后误启旧 P0 业务标签。Runner overlay 保留 loopback 9100 MinIO 入口。
- 外部实际 Runner 为 `D:\Project\pig-model-runner`，不是旧 `model-research/yolov13-runner` 骨架。通过其 `scripts/start-runner.ps1 -ProductEnvPath D:\Project\app-yolo\.env` 隐藏进程启动，日志在外部 `.run/release-20260910.*.log`。本次 Python PID 36584（重启后须重新确认），监听 9000；readiness=true，模型/阈值/IoU/尺寸与原研究清单一致。未配置开机自启或进程监管，仍须补充常驻与重启恢复。
- 当前 `.env` 研究配置生效：`research-http-yolo`、`MODEL_RESEARCH_ENABLED=true`、`MODEL_APPROVED=false`。最新真实单图 E2E 经上传/MinIO/Worker/Runner/Callback 返回 **28** 个候选框；Commit 重放同任务，数据库 `review_required`、candidate_count=28、confirmed_count=NULL、count_value=NULL，耗时字段 3845 ms。只验证研究图链路，不代表业务精度/手机/HTTPS/人工验收通过。证据：`artifacts/release-single-image-e2e-20260910.log`、`artifacts/release-single-image-evidence-20260910.json`。
- 已修正单图保存后的 1/3 文案及登录错误分类。最终 Flutter analyze、27 tests、Release 构建通过；九项 Gradle 门禁通过（缺签名另有首次失败验证），`git diff --check` 通过。未重跑 Spring/Admin 全套单测，未进行真机安装或人工确认，未提交/推送。
- 下一顺序：稳定 HTTPS/签名密钥备份 → Runner 监管与真实完整确认/报表自动回归 → 新地址签名候选包 → 统一授权实猪、弱网和复核人工验收。已有 Debug 安装、草稿、旧 APK、研究证据和 P0 卷保持保留。

下文是本轮开始前的历史交接；关于“Release 尚未生成、Docker 不可用、源码只到 V8、unavailable Provider”的描述均已被上方结果替代。

## 当前最高优先级（覆盖下文历史顺序）

用户要求快速交付含单图自动 AI 计数的签名 Release APK，人工测试集中安排且包含真实猪只计数。按 `NEXT_STEPS.md` 推进：Release 签名/HTTPS入口 → 真实单图 AI 闭环 → 自动回归/体验修复 → 统一实猪及弱网人工验收 → 发布收口。扩展监控不再是第一开发项。AI 候选自动生成，报表仍只接受人工确认；模型批准与数据授权不能由签名构建代替。

2026-09-09 真机单图证据见 `docs/development/manual-test-2026-09-09.md`。P0 已恢复，使用 unavailable Provider；由于 Docker Hub 拉取失败，业务/管理端沿用旧镜像，尚未验证当前源码全量版本。不得将本轮真机单图通过扩展为全部 P0 通过。后续首项检查 Android release 仍使用 debug signingConfig，落实真正发布签名及密钥保管。

最近自动化基线（2026-09-08，非本次重跑）：Spring 61 tests、Flyway V1–V11、6 组 promtool 和固定 observability 栈 HTTP/MySQL 验证通过；管理端 24 tests/15 组 Edge 场景、Python 37 tests。业务指标及独立监控密钥已实现，详见 `docs/development/business-observability.md`。扩展监控已后置，不再作为下一项。

## 新对话第一项工作

先实现签名 Release 构建配置与脚本：读取 `apps/mobile/android/app/build.gradle.kts`（目前 release 使用 debug 密钥）、`.gitignore`、现有 LAN 构建脚本和环境说明；接入本机忽略的签名配置/环境变量，缺失发布签名时明确失败；核对版本号与 APK 签名验证工具，并规划稳定 HTTPS 地址注入。可自动完成的工程工作先做，密钥归属/保管与最终部署地址未确定时准确列出，不把 Debug 包当交付。

用户本轮只要求调整计划和交接，尚未实现新的签名或 AI 部署变更。用户希望功能齐备后统一人工验收，暂不继续逐项催做真机测试。模型接入复用现有 Runner，必要自动化回归仍随开发完成。

已见问题：登录失败均显示“无法恢复登录状态”（之前失败原因未由手机日志确认）；单图页面显示 1/3；管理员复核截图没有确认入口，需核查代码/权限/旧服务镜像，不能直接断言功能不存在。

## 当前 APK 与运行环境

- 2026-09-10 交接复查：Docker API 无法连接，`dockerDesktopLinuxEngine` 管道不存在。不能沿用 09-09“服务 healthy”的状态；恢复前先检查引擎。
- 09-09 测试栈为 `pig-inventory-p0`，网关 8089，APK 内置 `http://172.17.219.182:8089`。这是当时的 Wi-Fi DHCP 地址，后续必须重新确认。
- `.env` 保留 `COUNTING_PROVIDER=research-http-yolo`、`MODEL_RESEARCH_ENABLED=true`、`MODEL_APPROVED=false`；当时 Runner 不可达导致 readiness 503。测试启动通过进程环境覆盖 `COUNTING_PROVIDER=unavailable`、`MODEL_RESEARCH_ENABLED=false`、`MODEL_APPROVED=false`，不是修改模型批准。
- PowerShell 每次命令是独立进程。恢复 unavailable 场景时，`GATEWAY_PORT=8089` 和上述三个覆盖必须在每次调用 Compose/fixture 脚本的同一进程设置，否则脚本会恢复读取 `.env` 的研究配置。
- 本地管理员名为 local-admin，密码读取本机 `.env` 的 APP_BOOTSTRAP_ADMIN_PASSWORD；fixture 角色使用不同的 APP_E2E_FIXTURE_PASSWORD。不要输出密码或令牌。
- Docker Hub 认证端点超时导致新业务/管理端镜像未构建成功，最后用 `--no-build` 启动旧镜像；日志只验证到 Flyway V8。当前源码已至 V11，下一次全栈验收前必须重建、验证迁移与版本一致性。
- 可用文件：`apps/mobile/build/app/outputs/flutter-apk/app-lan-test-20260909.apk`，SHA-256 `1337bac6f76c9b6d3b61248bed78be7f013da0b8468617110cb0f3fe63d0f77c`（本次复查匹配），约 180.3 MiB；同目录 app-debug.apk 为同轮构建。这是 Debug 包，Release 包尚未生成。
- 手机现有数据和 P0 卷需保留。正式签名通常不能直接覆盖 Debug 签名包；先设计升级/数据保留验证，再安排安装，不要默认让用户卸载清数据。

## 从这里开始

新对话按以下顺序读取：

1. `AGENTS.md`：长期工程、安全和验证规则。
2. `docs/product/PRD.md`、`docs/product/acceptance-criteria.md`、`docs/product/requirements-traceability.md`：范围与验收权威。
3. `PROJECT_STATUS.md`：已完成能力和验证证据。
4. `NEXT_STEPS.md`：当前实际开发顺序。
5. `docs/research/team-yolov13-candidate-evaluation.md`、`docs/research/p1-inference-fault-injection-benchmark.md`、`docs/research/p1-model-release-rollback-benchmark.md`、`docs/research/p1-inference-retry-github-benchmark.md`、`docs/research/p1-report-export-github-benchmark.md`：本轮模型研究、重试与报表导出设计结论。

## 工作区状态

- 当前分支为 `codex/p0-closure-fixes`，起点 HEAD 为 `a9d9970`。工作区包含多轮累计且尚未提交的 P0/P1 实现与文档；这些改动属于用户，不得 `reset --hard`、checkout 覆盖、clean 或批量删除。分支只提供引用保护，没有替用户提交混合历史改动。
- 新对话先运行 `git status --short` 和 `git diff --check`，只在用户明确要求时提交。不要把当前未跟踪文件误判为垃圾；其中包含本轮新增合同、测试、脚本和研究文档。
- P0 在 09-09 经用户真机测试流程恢复并写入单图测试数据；09-10 Docker 引擎不可连接，详细配置见上文。没有清理 P0 数据卷。回归测试仍使用各自固定隔离项目。
- 本机研究证据位于被 Git 忽略的 `test-assets/generated/`。不得提交这些文件，也不得把外部权重、数据集或绝对路径写入仓库。

## 2026-09-04 自动修复阶段

**更新：2026-09-08 已完成隔离管理端运行时回归。** 浏览器实际验证过期令牌只 Refresh 一次、失败任务重试、更正 v1 17 → v2 19、原媒体锁定、confirmed-only 日报、幂等/审计及越权 404。新增管理端迟到 401/网络失败/会话替换/Headers 边界测试，并修复晚到推理回调重新打开 superseded 历史版本的问题。本轮 Spring 46 tests 与管理端 9 tests、lint/typecheck、容器生产 build 通过；Prometheus 真实鉴权 200/匿名 401。复现命令与范围见 `docs/development/admin-runtime-e2e.md`。用户暂时不能人工验收，未将相关门禁标记通过。

需求—实现回查确认项目架构没有整体跑偏，但旧状态文档对部分 P0 完成度有过报。已按“保护工作区 -> 修代理/认证 -> 移动端真实数据 -> 不可变更正 -> 安全/可观测性 -> 全栈门禁”的顺序完成：

- 管理端同源代理改为集中式方法/路径白名单，补齐登录/刷新、失败推理重试和确认后更正入口；Access Token 401 只轮换一次 Refresh Token，并以原 RequestInit/幂等键重放。
- Flutter 首页、图库和“我的”改读激活组织的真实 API/Drift 数据；离线只显示可证实的本地证据、队列和字节数，不再硬编码猪场、数量或进度。
- OpenAPI 0.7.0 + Flyway V10 + Spring/管理端/Flutter 实现确认后不可变更正。旧确认版本变为 `superseded`，新版本复用原证据，数据库保证同栏舍/业务日只有一个当前确认版本，幂等与审计证据已覆盖。
- 推理派发器无回调令牌时启动 fail-closed；Spring 加入 Prometheus registry。自定义业务指标与告警仍未完成。
- `/tmp/` 已纳入 Git 忽略，只减少本地工具噪声，没有删除文件。

## 此前完成的阶段

P0 可自动化闭环已收口，必须真人/真机/部署负责人参与的验收被后置但没有被标记通过。

P1 团队权重研究链路已完成：

- 权重 SHA-256、Runner readiness/身份、Provider ROI 二次过滤、MinIO/Worker/Callback、Commit 重放和管理端/Flutter 复核证据展示。
- 验证集 102 张选择阈值 `0.60`，MAE `0.647`、WAPE `3.15%`；固定阈值后测试集 61 张只评估一次，MAE `1.049`、WAPE `3.75%`、±2 内 `93.44%`、最大误差 `3`。
- 研究发布清单绑定真实权重和回归摘要并通过二次校验；本机不可覆盖基线的当前漂移为 0 violation，P95/吞吐比均为 `1.0`。
- `pig-inventory-p1-fault` 验证 Runner 未就绪、Provider 超时、停止、重启和恢复；失败保持空数量并安全转人工复核。
- `pig-inventory-p1-rollback` 验证锚点 -> 候选 -> 损坏 checksum 返回 503 `RUNNER_IDENTITY_MISMATCH` -> 回滚锚点，约 11.4 秒恢复 readiness。该时间只代表 Stub 控制面，不是实际模型加载 RTO。

自动计数从未启用：仍为 `research-http-yolo`、`MODEL_APPROVED=false`、`review_required`，三视图候选不汇总。

P1 失败推理任务查询与管理员幂等重试也已完成：合同、Flyway V9、Spring 权限/应用/Outbox/审计、Next.js 入口、MySQL 并发测试、Python 派发边界和隔离 Compose E2E 均已落地。重试创建新任务而不覆盖原失败任务；同键同理由重放同一后继，不同意图冲突，晚到回调不能降级已确认会话。

P1 已确认盘点 PDF/Excel 导出也已完成：OpenAPI、Spring 组织隔离查询与双格式渲染、Next.js 同源下载入口、中文/拉丁双字体 PDF、公式注入安全和隔离 Compose E2E 均已落地。导出只读同一份已确认快照，候选、失败、未确认、其他组织及模型/媒体内部信息不会进入报表；日期范围最多 366 天、记录最多 10,000 条。

## 早期验证结果（历史记录，以顶部最新基线为准）

- Spring：`mvn verify`，45 tests passed，0 skipped；MySQL 8.4 实际执行 Flyway V1–V10，包含确认后更正、幂等、RBAC 与报表切换。仍有已记录的 Flyway“最新验证至 MySQL 8.1”警告。
- Python inference：33 tests passed。
- 外部 Runner：7 tests passed。
- Flutter：09-09 已重跑 `flutter analyze`、27 tests 和 debug APK 构建通过；当前 LAN APK 哈希见顶部。旧 APK 哈希不再作为交付依据。
- Admin：代理策略与认证轮换 5 tests、`pnpm lint`、`pnpm typecheck`、`pnpm build` 通过；并发 401 只刷新一次、写请求原幂等键重放及失败清除内存会话均有自动化证据。
- OpenAPI、基础/Runner/Fault Compose 配置和 `git diff --check` 通过。
- Docker 完整故障 E2E、版本回滚演练、管理员推理重试和已确认报表导出 E2E 通过；本轮因启动 Docker Desktop 暂停的 P0 原容器已用 `compose start` 恢复，未重建、未停止测试中的 P0，也未重置数据卷。

## 下一项建议任务

若用户在新对话中说“继续”，从顶部“新对话第一项工作”和 `NEXT_STEPS.md` 第一项开始：签名 Release APK 构建与 HTTPS 入口，随后单图 AI 候选计数；人工/实猪验收集中后置。不要再从扩展可观测性开始。

不要直接进入 P2，也不要继续调模型阈值。PDF/Excel 导出已经完成；金蝶、生产模型、硬件与许可继续等待外部输入。

## 本机忽略证据索引

以下文件存在于 `test-assets/generated/`，仅供下一对话读取验证，不是 Git 源文件：

- `team-yolo-regression-summary.json`
- `team-yolo-release-manifest.json`
- `team-yolo-regression-baseline-v3.json`
- `team-yolo-regression-drift-report.json`
- `inference-fault-e2e-summary.json`
- `inference-retry-e2e-summary.json`
- `report-export-e2e-summary.json`
- `report-export-e2e.pdf`
- `report-export-e2e.xlsx`
- `model-rollback-rehearsal-summary.json`
- `admin-runtime/summary.json`（2026-09-08 最终通过）
- `admin-runtime/dashboard.png`
- `callback-auth/summary.json`（2026-09-08 回调双模式鉴权通过）

若这些本机文件缺失，不得根据文档数字重新伪造；应使用外部只读数据与权重重新执行对应脚本生成。
