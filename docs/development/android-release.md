# Android 签名候选构建

Release 使用独立密钥，不回退到 debug；应用 ID 保持 `com.smartfarm.smart_pig_inventory`，版本来自 `apps/mobile/pubspec.yaml`。签名构建不代表模型批准、服务可用或人工验收通过。当前参赛批次见 [v20 验证记录](competition-verification-20261020.md)。

## 本机密钥

首次执行 `pwsh -NoProfile -File scripts/initialize-release-signing.ps1`。它创建随机密码的 RSA 3072 PKCS12 候选密钥，私钥位于当前用户 LocalAppData 的 `PigInventory/signing/inventory-candidate.p12`，密码仅写入 Git 忽略的 `apps/mobile/android/key.properties`。目录和配置 ACL 限制为当前用户及 SYSTEM；已存在文件时拒绝覆盖。不要重复初始化来解决构建失败，否则会破坏升级身份。

公开证书及 SHA-256 指纹保存在同一 signing 目录。分发前把密钥和 key.properties 存入负责人控制的加密备份；当前未建立异机备份，也未将密码发送到聊天或保存至版本库。若已有正式密钥，参照 `apps/mobile/android/key.properties.example` 配置，不运行初始化脚本。

CI 可注入 `ANDROID_RELEASE_STORE_FILE`、`ANDROID_RELEASE_STORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD`。任一变量存在时全部使用环境变量，不与本机文件混合；空值或部分配置失败。文件相对路径以 `apps/mobile/android/` 为基准，Windows properties 路径使用正斜杠。

## 构建与验证

```powershell
pwsh -NoProfile -File scripts/build-release-apk.ps1 -ApiBaseUrl 'https://<实际域名>' -ExpectedCertificateSha256 '<64位公开证书指纹>'
```

默认要求 HTTPS DNS 地址且健康端点返回 `UP`。Gradle 本身也验证签名私钥、证书有效期、非 Android Debug 证书、唯一显式 `API_BASE_URL`，拒绝 HTTP、未显式启用的 IP 地址、凭据、查询和片段。Release Manifest 显式禁用明文；Debug 的 LAN 策略保持独立。

脚本核验 apksigner 签名及预先选定的证书指纹，读取 APK applicationId/versionName/versionCode、非 debuggable、禁用明文属性，再复制至带时间戳的 `artifacts/android-release/`，附 SHA-256 和 `build-evidence.json`。旧交付目录不覆盖；脚本不安装、不卸载、不操作设备数据。

无部署环境时可显式 `-BuildOnly`，使用保留的 `https://api.pig-inventory.invalid` 验证工程。此域名不会提供业务服务，包名含 `build-only`，证据中 `apiHealthChecked=false`、`runtimeAcceptance=pending`。不得把该包用于人工验收或称为“已接通 AI”。稳定域名、有效 TLS 和真实服务就绪后须重新注入地址构建；不要用电脑 DHCP 地址或临时隧道替代稳定入口。

验证命令：

```powershell
pwsh -NoProfile -File scripts/test-release-configuration.ps1
```

该脚本使用本机签名配置和 Android Debug keystore 验证 Gradle 门禁，日志/摘要写入忽略的 `artifacts/release-gates/`。需要已有本机候选密钥，不会修改密钥或产品数据。新增公网 IP 默认拒绝、显式 HTTPS IP 通过、私网 IP/HTTP 即使显式启用仍拒绝的检查。

## 2026-11-07 安卓小范围试用

用户选择安卓、团队和合作猪场试用。`-PilotBuild` 使用独立的 `com.smartfarm.smart_pig_inventory.pilot` 包名和“智慧猪场场主·试用”名称，可与原安装并存。它读取 `key.pilot.properties`，首次通过 `initialize-release-signing.ps1 -PilotBuild` 生成独立的 LocalAppData/PigInventory/pilot-signing 身份；现有任何密钥均不得覆盖。升级试用包继续使用同一试用签名。

`build-release-apk.ps1 -PilotBuild -AllowHttpsIp` 显式启用公网 IPv4 HTTPS。系统信任链、IP SAN、有效期和实际健康检查照常验证；不允许关闭 TLS 检查或使用 HTTP。该试用入口使用 Let's Encrypt 受信任的短期 IP 证书，服务端须自动续期并重载。默认域名门禁没有放宽。

```powershell
pwsh -NoProfile -File scripts/test-release-configuration.ps1 -PilotBuild
pwsh -NoProfile -File scripts/build-release-apk.ps1 -ApiBaseUrl 'https://123.57.163.6' -ExpectedCertificateSha256 '<原试用证书SHA256>' -PilotBuild -AllowHttpsIp
```

本机 Flutter 3.47.9 / Dart 3.13.7 更新了 SDK 约束的五项锁定依赖；以本次 `pubspec.lock` 为准。2026-11-07 Debug 构建通过，Release 在逐文件校验的 ASCII 构建目录完成，包版本 0.1.0+21。安装包签名、包名、非 debuggable、禁止明文、实际 HTTPS 健康和公网下载哈希均有独立证据；手机安装、拍摄、弱网恢复和实猪效果仍须设备验收。完整试用入口和验收流程见 [阿里云安卓试用](../deployment/aliyun-android-pilot.md)。

## Windows 中文路径的 Release AOT 边界

2026-10-20：当前 Flutter 3.44.7 的 Debug 可以在本仓中文路径构建，但 Release 的 native AOT snapshotter 无法读取实际存在的 app.dill。保留 AGP 路径覆盖仍不能解决该 native 工具限制。已验证的办法是将同一移动端源码及原构建脚本放到独立 ASCII 目录，再运行原签名脚本；不能把 Debug 成功推断为 Release 成功。

干净版本可以使用 ASCII 路径的独立检出。未提交工作树必须先固定逐文件 SHA-256，复制 Git 可见移动源码与 scripts/build-release-apk.ps1，并在构建后复查源文件未变化。不要复制 key.properties、设备草稿、私钥、授权媒体或模型；通过现有四个 ANDROID_RELEASE_* 环境变量引用原签名身份，构建后清除子进程凭据。公开 LAN CA 仍按原脚本传入，不改变 TLS 身份。

原生依赖在冷目录可能重复下载。可复制本机相同锁定版本的 SQLite 原生下载缓存（仅 .so/.dll/.dylib，不复制含绝对路径的 hook 输出），由原包构建钩子重新校验其内置 SHA-256；不能跳过 hash 校验或修改第三方包源码。v20 的 ASCII 构建、119个源文件核对和签名产物证据见上述验证记录。临时目录与本地辅助脚本属于忽略的构建证据，不代替版本化发布脚本。

## Debug 到 Release 的数据保留

同 applicationId、不同证书不能作为普通覆盖升级。现有 Debug 安装和草稿继续保留；不要执行卸载、清数据或盲目 `adb install -r`。统一验收前应先核对草稿/待上传状态和服务端证据，可先在备用设备验收 Release。需要同机迁移时，先实现和验证数据导出/恢复方案，不能将此处说明当作迁移已经通过。

## 官方依据

- [Flutter Android 发布签名配置](https://docs.flutter.dev/deployment/android)：借鉴独立 signingConfigs 和本机 properties，增加本项目缺失即失败边界。
- [Android apksigner](https://developer.android.com/tools/apksigner)：使用 verify/print-certs 验证产物，独立比对证书指纹。

本轮属于现有 Flutter 构建配置落地，未进行架构/框架选型或引入第三方项目代码。Review Hub 签名检索无匹配项，未声称经验改变了结论。
