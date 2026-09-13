# Android 签名候选构建

Release 使用独立密钥，不回退到 debug；应用 ID 保持 `com.smartfarm.smart_pig_inventory`，版本来自 `apps/mobile/pubspec.yaml`。本轮为 `0.1.0+4`。签名构建不代表模型批准、服务可用或人工验收通过。

## 本机密钥

首次执行 `pwsh -NoProfile -File scripts/initialize-release-signing.ps1`。它创建随机密码的 RSA 3072 PKCS12 候选密钥，私钥位于当前用户 LocalAppData 的 `PigInventory/signing/inventory-candidate.p12`，密码仅写入 Git 忽略的 `apps/mobile/android/key.properties`。目录和配置 ACL 限制为当前用户及 SYSTEM；已存在文件时拒绝覆盖。不要重复初始化来解决构建失败，否则会破坏升级身份。

公开证书及 SHA-256 指纹保存在同一 signing 目录。分发前把密钥和 key.properties 存入负责人控制的加密备份；当前未建立异机备份，也未将密码发送到聊天或保存至版本库。若已有正式密钥，参照 `apps/mobile/android/key.properties.example` 配置，不运行初始化脚本。

CI 可注入 `ANDROID_RELEASE_STORE_FILE`、`ANDROID_RELEASE_STORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD`。任一变量存在时全部使用环境变量，不与本机文件混合；空值或部分配置失败。文件相对路径以 `apps/mobile/android/` 为基准，Windows properties 路径使用正斜杠。

## 构建与验证

```powershell
pwsh -NoProfile -File scripts/build-release-apk.ps1 -ApiBaseUrl 'https://<实际域名>' -ExpectedCertificateSha256 '<64位公开证书指纹>'
```

默认要求 HTTPS DNS 地址且健康端点返回 `UP`。Gradle 本身也验证签名私钥、证书有效期、非 Android Debug 证书、唯一显式 `API_BASE_URL`，拒绝 HTTP、IP 地址、凭据、查询和片段。Release Manifest 显式禁用明文；Debug 的 LAN 策略保持独立。

脚本核验 apksigner 签名及预先选定的证书指纹，读取 APK applicationId/versionName/versionCode、非 debuggable、禁用明文属性，再复制至带时间戳的 `artifacts/android-release/`，附 SHA-256 和 `build-evidence.json`。旧交付目录不覆盖；脚本不安装、不卸载、不操作设备数据。

无部署环境时可显式 `-BuildOnly`，使用保留的 `https://api.pig-inventory.invalid` 验证工程。此域名不会提供业务服务，包名含 `build-only`，证据中 `apiHealthChecked=false`、`runtimeAcceptance=pending`。不得把该包用于人工验收或称为“已接通 AI”。稳定域名、有效 TLS 和真实服务就绪后须重新注入地址构建；不要用电脑 DHCP 地址或临时隧道替代稳定入口。

验证命令：

```powershell
pwsh -NoProfile -File scripts/test-release-configuration.ps1
```

该脚本使用本机签名配置和 Android Debug keystore 验证九项 Gradle 门禁，日志/摘要写入忽略的 `artifacts/release-gates/`。需要已有本机候选密钥，不会修改密钥或产品数据。

## Debug 到 Release 的数据保留

同 applicationId、不同证书不能作为普通覆盖升级。现有 Debug 安装和草稿继续保留；不要执行卸载、清数据或盲目 `adb install -r`。统一验收前应先核对草稿/待上传状态和服务端证据，可先在备用设备验收 Release。需要同机迁移时，先实现和验证数据导出/恢复方案，不能将此处说明当作迁移已经通过。

## 官方依据

- [Flutter Android 发布签名配置](https://docs.flutter.dev/deployment/android)：借鉴独立 signingConfigs 和本机 properties，增加本项目缺失即失败边界。
- [Android apksigner](https://developer.android.com/tools/apksigner)：使用 verify/print-certs 验证产物，独立比对证书指纹。

本轮属于现有 Flutter 构建配置落地，未进行架构/框架选型或引入第三方项目代码。Review Hub 签名检索无匹配项，未声称经验改变了结论。
