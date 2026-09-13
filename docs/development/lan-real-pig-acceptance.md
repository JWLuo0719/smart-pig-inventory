# 局域网实猪验收准备

> 最新运行证据（2026-09-12）：签名联网候选 v9 已在 Redmi K60 完成一轮授权实猪单图。会话 `bdc21fd6-e194-4ace-9673-560dac993aa3` 的候选为 19，独立人工确认 24，媒体已锁定且确认审计已写入。该轮验证上传、研究候选、人工纠正与证据闭环；候选低估 5 头，单一样本不构成精度通过或模型批准。下文旧版本号仅为历史证据，当前测试使用 `artifacts/android-release/20260911-205429-813/inventory-release-lan-acceptance.apk`，继续保持研究候选和人工复核边界。

2026-09-11：本机服务及签名候选包已配置，手机与现场人工验收尚未执行。此入口依赖电脑开机、用户登录和同一可互访局域网，不是公网生产部署。

## 当前候选与验证

- APK：`artifacts/android-release/20260911-112011-947/inventory-release-lan-acceptance.apk`，版本 `0.1.0+5`，SHA-256 `eb19857cfc7395634b66a1136db8b629bb3b2dec0fa9e16904b323efbaf58553`。
- API：`https://pig-inventory.local:8443`。mDNS 随本机网卡地址更新；没有把 DHCP 地址固化进 APK。
- Release 使用原独立签名；禁用明文和调试。验收 CA 只注入此域名的客户端，验证证书链、有效期和主机名，禁止跨源请求及重定向，没有跳过证书验证，也没有安装系统 CA。
- Flutter analyze、29 tests（含实际 TLS、错误 CA/主机名及跨源拒绝）通过。HTTPS 上传、Commit 重放、研究推理、权限拒绝、确认重放、报表和媒体锁定检查通过。
- 本次研究图候选 **29**，独立 fixture 标注 **28**，复核角色自动化确认 **28**，报表读回 **28**。这是工作流回归，不是人工验收或精度通过；自动化代码曾把响应 `count` 写成 `confirmedCount`，修正后以数据库保存的原幂等键续验，未重建/删除原记录。详细证据只存忽略目录。

## 还需要完成的配置

在本机“以管理员身份运行”的 PowerShell 执行一次：

```powershell
pwsh -NoProfile -File "D:\Project\app-yolo\scripts\enable-lan-acceptance-firewall.ps1"
```

脚本只允许 Private 网络、本地子网 TCP 8443 与 UDP 5353。2026-09-11 已由管理员成功执行，并已回读为启用的入站 Allow/Private 规则（TCP 8443、UDP 5353）。网络须为可信专用网络。校园网/AP 客户端隔离、组播限制仍可能使同 Wi-Fi 无法互访；届时改用可互访的可信路由器网络，再复核手机连接，不能以本机健康检查代替手机证据。

手机现有 Debug 应用和草稿必须保留。Release 与 Debug 签名不同，不能直接覆盖；不要卸载或清数据。优先用没有旧安装的备用 Android 手机；使用原手机前另行落实草稿导出/迁移方案。浏览器未安装私有 CA 时可能提示不信任，不能据此关闭 TLS 校验；本 APK 已内置仅供验收的公开 CA。

## 运行与恢复

`scripts/configure-lan-acceptance.ps1` 已登记当前用户登录启动项 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\PigInventoryLanAcceptance`。配置可重复运行，读取忽略的 `artifacts/lan-acceptance/runtime.json`，复用原 Runner、镜像和证书；只替换本工具监管/mDNS 进程。实际系统重启恢复尚未验收；登录前不会运行。Docker Desktop 必须能够启动，电脑不可休眠。

状态见 `artifacts/lan-acceptance/status.json`，日志同目录。监管器检查 Docker、原研究模型身份/阈值及 HTTPS 健康；异常时状态为 waiting。Compose 使用 `docker-compose.yml` + `docker-compose.runner-local.yml` + `docker-compose.lan-acceptance.yml`；当前业务镜像为已核对源码 JAR 的 `pig-inventory-functional-business-api:20260912-v13`。手动调用时须同进程设置 `GATEWAY_PORT=8089`、`LAN_BUSINESS_IMAGE` 和 `LAN_TLS_DIRECTORY`，不要误启旧镜像。数据库 V1–V13，P0 卷保留。

TLS 原件在当前用户 LocalAppData/PigInventory/lan-tls，Docker 挂载副本在 ACL 限制的忽略目录 artifacts/lan-acceptance/tls（本机 Docker 无法读取用户 C 盘挂载，已验证 D 盘副本可用）。服务证书有效 90 天；CA 签发私钥未保留，换证须受控生成新身份并重建 APK，不能静默覆盖。初始化脚本拒绝覆盖原身份。

签名原件和 key.properties 保留，另有当前 Windows 用户 DPAPI 加密本机备份且解密回读通过。它依赖此用户/机器，不是异机灾备；独立介质备份仍待落实，不能通过重建密钥替代。

## 集中人工验收

先核对图片/现场数据授权、独立人工真值和预先约定的通过阈值，再使用冻结模型测试：实猪单图、空栏、遮挡、不同光照/数量、人工纠正、报表、弱网续传、后台恢复、三图不相加。记录设备、版本、样本编号、人工数、候选数、确认数、耗时及失败详情。真实图片/标注仅入授权受控存储，不入 Git，评估集不用于调参。

手机安装、端到端联网、系统重启、弱网与实猪精度均待人工执行。继续保持 MODEL_APPROVED=false、强制复核，未完成负责人/模型/依赖准入，不宣布发布通过。旧人工手册中的 synthetic/unavailable 步骤只适用于其原测试场景。

设计依据见 [局域网 HTTPS 比较](../research/lan-https-options.md)。
