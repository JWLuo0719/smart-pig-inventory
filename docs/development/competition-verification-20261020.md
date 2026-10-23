# 参赛开发验证记录（2026-10-20）

实现入口：[工作包追踪](../product/competition-development-plan.md)。状态：代码批次已落地，候选尚未冻结；运行、真机和模型批准分开登记。所有数字仅对应下列实际执行，未执行/跳过不计作通过。

## 已取得的证据

| 检查 | 结果 | 本地忽略证据 |
|---|---|---|
| Flutter 静态分析 | 最新源码无问题 | artifacts/competition-analyze-final.log |
| Flutter 全量测试 | 71通过、1跳过（真实 LAN TLS 需单独环境）；身份竞态、ROI painter、重拍事务、轮询、确认后的迟到读回和旧 display count 不回退均覆盖 | artifacts/competition-flutter-final.log |
| Android Debug | 最终移动源码构建成功 | artifacts/competition-debug-build.log |
| Release 配置 | 11项通过，含缺密钥/Debug证书/HTTP/IP/重复地址/私有CA边界 | artifacts/competition-release-gates.log；artifacts/release-gates/20261020-174943-718/summary.json |
| 三个工具契约 | 2项通过，全部夹具为合成数据，无 Agent 执行 | artifacts/competition-contracts.log |
| 合同与配置 | OpenAPI0.10.0严格解析无重复键，146个本地引用均可解析；交付文档本地链接及Compose配置检查通过 | 本轮只读检查；git diff --check通过（仅CRLF提示） |
| Spring test | 19:18完成：106通过、0失败、0错误、0跳过，实际Testcontainers/MySQL与13条迁移均运行；旧环境跳过/中断结果不作为本轮证据 | artifacts/competition-mvn-test-final.log |
| Spring verify | 19:22完成：106通过、0失败、0错误、0跳过，退出0；已替代旧内存中断结果 | artifacts/competition-mvn-verify-final.log |
| Admin 门禁 | 最终源码26测试、lint、typecheck和生产构建通过 | artifacts/competition-admin-test.log；artifacts/competition-admin-lint.log；artifacts/competition-admin-types.log；artifacts/competition-admin-build.log |
| Admin 固定运行栈 | 未通过：首轮Compose构建中断；引擎恢复后，独立后台进程先单独构建后端，Maven打包期间再次收到Docker RPC EOF。未启动浏览器，无最终语义读回；新增人工确认0场景仅通过Runner语法检查 | artifacts/competition-admin-runtime-final.log；artifacts/competition-runtime-backend-build.log；artifacts/competition-admin-runtime-native-result.json |
| 真机 | ADB未发现已连接设备，本轮没有安装/卸载、清草稿或真实猪只操作 | 本轮设备列表为空 |

本机 Flutter 使用 Windows SDK 3.44.7 / Dart 3.12.2。资源紧张时直接运行 SDK 的 `dart.exe analyze .` 与 `dart.exe <Flutter>/bin/cache/flutter_tools.snapshot test --no-pub --concurrency=1`，避免 `.bat` 入口在内存不足时启动额外 PowerShell 失败；实际执行的仍是同一套 Dart/Flutter 检查。最后一次样式括号整理不改变业务行为。

## 构建边界与环境问题

原中文仓库路径的 Debug 可成功；Release 的 AOT 工具却无法读取确实存在的约48MB `app.dill`，报路径读取失败。签名门禁已经通过，此问题不能通过换 Debug 密钥解决。最终源码在临时 ASCII 目录构建，逐文件 SHA-256 核对；只复制 Git 可见的移动源码及原构建脚本，不复制 key.properties、私钥、设备草稿、授权原图或模型。原签名凭据仅经构建子进程环境使用，公开 CA 仍限 pig-inventory.local。APK 的源码清单随构建证据保存。

签名构建使用 BuildOnly，保留原 LAN HTTPS 地址和公开 CA。它只证明签名、版本、不可调试与禁明文策略；服务端尚未按本轮源码部署读回，不构成联网候选或真实 AI 验收，不能安装覆盖现有草稿来解决签名差异。

Windows 提交内存曾接近上限，Java/Node/PowerShell 均出现 native memory/heap 初始化失败。临时构建进程限制 CPU 为2，Gradle heap 768MB、metaspace384MB、code cache96MB、禁 daemon；未改系统页文件或关闭其他应用。Docker 引擎多次返回500/连接中断，部分测试在恢复后才运行。旧 Maven3.9.9基础镜像 `/bin/sh` 返回 exec format error，3.9.11可执行，业务 Dockerfile 已升级，仍需要镜像与运行证据。

Admin 运行只使用 pig-inventory-p0-admin-runtime/8093；未删卷或切到P0。19:23 Compose构建中断后，Docker日志显示引擎running→stopping、WSL进程退出，具体原因未定。限时正常restart返回超时，旧进程随后退出；进程身份校验拒绝了终止操作，没有强杀其他进程。重新以普通用户上下文启动后，docker info恢复29.7.2。19:30独立后台进程改为先单独构建后端，再构建前端；19:33后端Maven打包时再次收到 `rpc error: code = Unavailable ... EOF`，结果JSON明确failed。本轮失败在up/浏览器之前，没有新合成会话或最终summary。没有用SkipBuild复用旧镜像来掩盖新源码未构建，也未把EOF归因为已证实的产品缺陷或已证实的OOM。

## 尚未通过的出口

必须完成：Admin 固定栈语义读回；图框横/竖/EXIF四角像素核对；同版本真机上传、人工确认/锁图/更正/报表、Provider故障和弱网；签名候选部署/迁移/模型身份清单；授权样本、130%字体/强光/无障碍和连续三次彩排。按 [验收脚本](competition-acceptance-runbook.md) 留证。130%字体已覆盖复核页的定向 widget 回归，不能替代整机可用性验收。

模型未在本轮修改或批准，未开启自动入账、三图自动去重或视频自动计数。在线 Agent/受限评审账号/公网入口/报名缴费提交属于后续独立里程碑。Review Hub 审计 audit-20261018032718-c4c255e3 保持实施中：命中仅 informational，没有证据证明改变方案；不能因构建成功关闭整个运行验收审计。

## 最终收尾读回

签名 Release `0.1.0+20`：`artifacts/android-release/20261020-181139-073/inventory-release-build-only.apk`，70,495,052字节。SHA-256：`5a2157ca2ec465a81507fd79bbd5f6e74f950ea3f1ac2651b6264f29894ccc01`；证书 SHA-256：`4d658496b8074bc391fa4f6cac97f577e534c94daf5c7ac2d072e0ad3102fdd6`。同目录 `source-manifest.json` 中119个移动源码与构建脚本哈希已逐文件核对，产物哈希与 `build-evidence.json` 一致。保留原 HTTPS 地址与 CA，`buildOnly=true`、`apiHealthChecked=false`、`runtimeAcceptance=pending`。

主线源码基线 `artifacts/competition-source-baseline-20261020.json` 记录HEAD、310个源码/合同/脚本/配置文件哈希及同一签名APK证据。工作树尚未提交，`candidateFrozen=false`；部署、设备与模型身份运行读回均单列待验，清单不能替代冻结或运行验收。

Docker Desktop 启动失败经本地只读对照定位到启动上下文：代理进程读取 `sailor-ingest.sock` 返回1920，普通当前用户进程读取同一路径可得到 reparse tag `0x80000023`。仅停止本任务创建且已崩溃的进程树，再以普通用户上下文启动同一已安装程序后，`docker info` 返回29.7.2；没有删除套接字、重置 Docker、改 WSL/页文件或删除卷。对照证据：`artifacts/competition-docker-socket-agent.log`、`artifacts/competition-docker-socket-native.log`、`artifacts/competition-docker-current.log`。引擎恢复只代表测试环境可用，后端与 Admin 出口仍以各自最终结果为准。

19:34构建EOF之后，独立10秒 `docker info` 探针超时，已仅停止该探针客户端。本轮不再重复构建；当前引擎/P0服务可用性未恢复验证，不能将“未修改P0源码或卷”表述为“P0服务持续健康”。下一轮先恢复并读回工作站环境，再按新源码重建固定隔离栈。不会通过清卷、清草稿、换签名或打开自动计数开关解决环境问题。
