# Android 局域网 E2E 测试

本流程验证手机端在本机 Docker 服务栈上的“登录—同步—采集—上传—断网恢复”闭环。只允许使用合成组织、栋舍、栏舍和测试图片；禁止使用真实猪场图片、生产凭据、Token 或密钥。

## 安全边界

- `scripts/build-lan-test-apk.ps1` 只构建 **Debug** APK。它的 Android Debug Manifest 允许明文 HTTP，以便开发阶段访问私有局域网网关。
- Release Manifest 不含该权限；发布和试点环境必须使用 HTTPS。
- APK 仅包含传入的 API 地址，不包含管理员密码、刷新 Token、JWT 签名密钥或 `.env` 内容。
- `.env` 被 Git 忽略。不得把它或其中值发送到聊天、工单、截图或提交中。

## 一次性本机准备

全新的本地环境执行：

```powershell
.\scripts\initialize-local-dev.ps1
docker compose up --build -d
```

若旧的本地 MySQL 卷与当前 `.env` 密码不一致，不要使用 `down -v` 删除数据。可创建隔离的临时 E2E 栈：

```powershell
docker compose -p pig-inventory-e2e up --build -d
.\scripts\ensure-lan-e2e-fixtures.ps1 -ComposeProjectName pig-inventory-e2e
```

之后恢复该隔离栈使用 `docker compose -p pig-inventory-e2e up -d`；`build-lan-test-apk.ps1` 不需要项目名。

初始化脚本会在本机生成随机 MySQL、MinIO、初始管理员密码和 Base64 JWT 签名密钥，且不会打印这些值。获授权测试人员只能在开发电脑本地查看自己的 `.env` 以取得登录信息，不能转发或记录到外部。

若 `.env` 在身份功能加入前就已存在，不要直接覆盖。使用以下脚本在本机补齐缺失值并启用认证；它会保留非空既有值、随机生成缺失密码/密钥，且不输出敏感信息：

```powershell
.\scripts\configure-local-e2e-identity.ps1
```

它确保本机存在以下配置：

```text
SECURITY_ENABLED=true
JWT_SIGNING_SECRET=<本机 Base64 密钥，解码后至少 32 字节>
APP_BOOTSTRAP_ADMIN_USERNAME=<本机账号>
APP_BOOTSTRAP_ADMIN_PASSWORD=<至少 8 位的本机随机密码>
APP_BOOTSTRAP_ADMIN_DISPLAY_NAME=<本机显示名>
APP_BOOTSTRAP_ORGANIZATION_CODE=<本机组织编码>
APP_BOOTSTRAP_ORGANIZATION_NAME=<本机合成组织名称>
```

等待网关健康检查返回 HTTP 200：

```powershell
Invoke-WebRequest http://localhost:8088/actuator/health -UseBasicParsing
```

为初始管理员所属组织幂等创建合成测试栋舍和栏舍：

```powershell
.\scripts\ensure-lan-e2e-fixtures.ps1
```

预期夹具编码为 `E2E-B01` 和 `E2E-P01`；重复运行不会产生第二份数据。

## 构建和安装

测试电脑与 Android 设备连接到同一私有局域网。脚本会识别默认网卡 IPv4、检查网关健康，并将该地址写入 Debug APK：

```powershell
.\scripts\build-lan-test-apk.ps1
```

若自动选择的网卡不正确，显式指定网关地址：

```powershell
.\scripts\build-lan-test-apk.ps1 -ApiBaseUrl http://192.168.1.23:8088
```

生成的 APK：

```text
apps/mobile/build/app/outputs/flutter-apk/app-debug.apk
```

用 LocalSend 传送 APK 到手机，或通过 USB 直接安装：

```powershell
.\scripts\build-lan-test-apk.ps1 -Install
```

`-SkipApiHealthCheck` 只用于 Docker 不可用时验证编译；使用它构建不代表已经通过局域网 E2E 前置检查。

## 人工 E2E 清单

1. 打开 APK，使用获授权的本机初始管理员登录。
2. 进入“盘点”并打开栏舍选择，点击同步图标；必须看到 `E2E-B01 / E2E-P01`。
3. 进入该栏舍，保持三图模式关闭，拍摄单图并点击“保存到待上传”；不得显示数量。
4. 进入“上传队列”，联网时点击“重试”；状态必须变为“已提交，等待处理”。
5. 再次采集后打开飞行模式，点击“重试”；确认原图和队列仍保留。
6. 强制关闭 App 后重开；确认队列仍保留。
7. 恢复 Wi-Fi，点击“重试”；确认同一个包最终变为“已提交，等待处理”。
8. 新建一个三图采集包并入队，保持 App 在后台或锁屏，不点击“重试”；等待系统网络约束满足后，确认队列自动进入上传状态并最终变为“已提交，等待处理”。若系统省电策略延迟执行，记录设备型号、系统版本和延迟时间；不得以手动点击代替后台 Worker 证据。

当前推理 Provider 故意不可用。上传提交成功不代表已得到 AI 数量，服务端不得显示伪造数量。

## 反馈证据

反馈设备型号、Android 版本，以及登录、栏舍同步、单图入队、断网保留、重开保留、恢复上传的通过/失败结果；可提供不含敏感信息的状态截图或错误文本。不得提供凭据、Token、JWT 值、`.env` 或完整签名 URL。
