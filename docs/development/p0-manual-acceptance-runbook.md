# P0 人工验收运行手册

本手册用于补齐自动化测试不能证明的真机、网络、浏览器和运行环境证据。仅可使用本机生成的合成组织、栏舍和照片；不得使用真实猪场原图、生产账号、Token、`.env` 或签名 URL。供外部测试人员执行的逐步说明、角色分工和报告模板见 [`p0-external-manual-test-guide.md`](p0-external-manual-test-guide.md)。

> **通过规则**：每一项记录“通过/失败/阻塞”、设备或浏览器版本、开始结束时间、截图/日志文件名和操作者。出现失败即停止把版本标记为 P0 通过；不能用人工绕过替代修复。

## 当前验收记录（2026-08-27）

- realme GT 7 Pro 已通过 AC-01 的完整三视图强制停止恢复：左/中/右图片保存为同一采集组，重开后 3/3 缩略图可查看且不显示数量。
- 一个完整三视图包已在联网状态自动完成 Commit 并进入 `已提交，等待处理`；复核页因 Access Token 过期暴露未自动刷新缺陷。修复包含在 Flutter v`0.1.0+3`，待更新 APK 后回归，故 AC-06/AC-08/AC-09 尚未由本轮实机签署。
- 管理端 LAN HTTP 登录发现 `crypto.randomUUID` 不可用；代码已改为兼容 fallback，待重建 `admin-web` 后回归。

## 0. 安全启动测试环境

不要重置已有默认 MySQL 卷。使用隔离 Compose 项目：

```powershell
# 仅首次且不存在 .env 时执行；不会显示或提交生成的口令。
.\scripts\initialize-local-dev.ps1

# 已存在 .env 但缺认证配置时使用；不要用 -Force 覆盖。
.\scripts\configure-local-e2e-identity.ps1

# 新建独立的 Docker 卷/容器，避免影响默认开发数据。
# 默认 8088 已被其它隔离栈占用时，使用一个未占用端口（本次为 8089）。
$env:GATEWAY_PORT = '8089'
docker compose -p pig-inventory-p0 up --build -d
.\scripts\ensure-lan-e2e-fixtures.ps1 -ComposeProjectName pig-inventory-p0
Invoke-WebRequest http://localhost:$env:GATEWAY_PORT/actuator/health -UseBasicParsing
```

在测试电脑本地（不要截图或发送）查看 `.env` 的 `APP_BOOTSTRAP_ADMIN_USERNAME` 和 `APP_BOOTSTRAP_ADMIN_PASSWORD`。确认 `SECURITY_ENABLED=true`、`INFERENCE_DISPATCHER_ENABLED=true`、`INFERENCE_CALLBACK_TOKEN` 非空。管理端同源代理不要求把 Token 放到浏览器配置中。

若需关闭隔离环境，只执行：

```powershell
docker compose -p pig-inventory-p0 down
```

不得对未知卷执行 `down -v`。

## 1. Android 真机：AC-01、AC-02、AC-06、AC-08、AC-09

在主流机 **realme GT 7 Pro / Android 15** 与低端机 **REDMI Note 14 5G（或同等 Android 14+、6GB/128GB 设备）** 各完成一次。手机与电脑必须在同一私有 LAN。

```powershell
.\scripts\build-lan-test-apk.ps1 -ApiBaseUrl "http://<测试电脑LAN-IP>:$env:GATEWAY_PORT" -Install
```

1. 登录本机 bootstrap 管理员；同步栏舍，确认能看到 `E2E-B01 / E2E-P01`。
2. 单图采集，保存到待上传：确认采集页、队列页均**不显示数量**。
3. 打开飞行模式，入队一个三图采集组；拍左图后强制停止 App，重开后继续中图、右图。确认栏舍、三个方向、ROI、原图和“待上传”完整恢复（AC-01）。
4. 联网并点击重试；在第一个 Blob 已成功后立刻关 Wi-Fi/飞行模式。确认已上传 Blob 不丢失、队列仍在；恢复网络后重试，最终仅续传未完成 Blob，并成为“已提交，等待处理”（AC-02）。
5. 再建一个三图包，锁屏/后台，不手点重试；恢复网络后记录 WorkManager 自动开始上传的时间。若被系统省电延迟，记录延迟而不是手工补点。
6. 当前 Provider 为 `unavailable`：提交后在 Outbox 打开会话复核页，必须为 `review_required`，有明确不可用原因，数量为空（AC-06）；三图不得显示三张相加的自动数量（AC-08）。
7. 以 `11`、理由不少于 8 个字符确认。确认后检查“已确认/证据锁定”状态。普通删除必须显示冲突；管理员覆盖删除必须填写理由并成功，随后刷新会话仍可见删除状态/锁定提示（AC-09）。

为避免泄露原图，截图只截取状态文本、设备型号与时间；不要上传照片本身。

## 2. Android 近重复：AC-05

1. 用同一合成测试物体拍摄两张视觉相近但字节不同的 JPG/PNG（例如同一打印测试卡轻微移动后再拍）。不要复用完全相同文件，完全相同应走 AC-04。
2. 分别作为两个单图采集包提交；两张图都应正常保留。
3. 在管理端登录后确认“近重复告警”出现，包含汉明距离；不得出现自动删除或自动覆盖。
4. 再上传同一物体明显不同的照片，确认没有把所有图片都误报为近重复。

若相似图未产生告警，记录手机型号、图片格式、大小与尺寸（不要上传图片）。大于 8 MiB、超过 600 万像素、HEIC 或无法解码的图片会安全跳过本地 dHash；这应记录为兼容性/性能缺陷，不能计作 AC-05 通过。

## 3. 管理端：登录、真实数据、键盘与复核边界

浏览器访问 `http://localhost:$env:GATEWAY_PORT`，使用本机 bootstrap 管理员登录。

1. 登录后，今日栏舍数量、已确认数和近重复告警必须与 Android/数据库测试产生的数据一致；未登录不得展示演示数据或可读业务数据。
2. 用 Tab、Shift+Tab、Enter 操作登录、刷新和卡片；焦点必须可见。将浏览器字体缩放到 130%，核心文字和按钮不得截断。
3. DevTools Network 确认浏览器仅访问同源 `/api/backend/...`，且没有 Token 出现在 URL、localStorage 或 sessionStorage。
4. 用不同浏览器隐私窗口重新打开，确认需要重新登录（令牌仅存在内存）。

管理端现已接入会话受限媒体预览、网页端人工确认、近重复带理由解决、日报/综合报表和审计浏览；对象存储 URL 不会下发到浏览器。上述功能已通过 Next lint/build，仍须在 `pig-inventory-p0` 隔离 Compose 环境完成浏览器人工验收后才可签通过。

## 4. 精确重复与组织隔离：AC-03、AC-04、AC-11

- AC-03：对同一个已入队包连续点击重试/在两台设备同时恢复网络，检查只形成一个服务端上传包、一个会话和一个推理任务；不允许多媒体记录。
- AC-04：需要同一合成组织至少两个栏舍。将完全相同的本地图片提交至第二栏舍，必须被拒绝；响应不得泄露第一栏舍名称、路径或图片。不同组织中使用同一图片不得泄露或阻断对方。
- AC-11：需要三个**不同的合成账号**和组织成员关系：`OPERATOR`、`REVIEWER`、`FARM_ADMIN`，另加第二组织账号。分别验证：
  - OPERATOR 可采集/上传/看本组织任务，不能确认或管理员覆盖删除；
  - REVIEWER 可确认，不能管理员覆盖删除；
  - FARM_ADMIN 可确认和填写原因的软删除；
  - 第二组织账号用猜测到的 UUID、媒体 ID、会话 ID 请求时得到不可发现结果，不能读取或修改数据。

运行 `./scripts/ensure-lan-e2e-fixtures.ps1 -ComposeProjectName pig-inventory-p0` 会仅为隔离项目启用合成 fixture：`e2e-operator`、`e2e-reviewer`、`e2e-farm-admin`、`e2e-second-operator`，以及主/第二组织的合成栋舍和栏舍。四个账号共用本机 `.env` 中生成的 fixture 口令；脚本绝不输出该口令，也不会重置任何卷。AC-04/AC-11 仍须按本节执行浏览器/真机人工 E2E，不能用管理员账号替代角色测试。

## 5. AC-10、AC-12 与发布环境

### AC-10 综合盘点

为同栏舍在至少三天创建确认数量（如 10、11、13），并留一个 `review_required` 会话。日报和综合报告必须只用已确认项，原始均值为 `11.333...`、展示值为 `11`，并列出参与日期；待复核项不得计入。

后端 API 与管理端报表页面均已实现；仍须用本节的三天合成确认数据完成网页人工验收。

### AC-12 安全与运行

由部署负责人完成并留存非敏感证据：

1. TLS 终端证书、HSTS、HTTP 到 HTTPS 重定向和明确 `CORS_ALLOWED_ORIGINS` 白名单；生产不能使用本地 HTTP Debug APK。
2. `.env` 无模板/默认口令，MinIO 桶策略为私有；尝试匿名对象 URL 必须拒绝。
3. 抽检业务、网关和推理日志：不得含密码、JWT、刷新 Token、MinIO 密钥或原图内容。
4. 将一份**合成**已确认会话备份，恢复到干净隔离环境，验证会话、审计和对象引用一致。
5. 提供运行时依赖许可证清单；未获批准的 AGPL/GPL 不得进入专有产品运行路径。当前 YOLOv13 仅为隔离研究，不能用于正式自动计数。

## 6. 提交验收结果

请按以下模板反馈，不要包含任何秘密：

```text
环境：pig-inventory-p0；日期；操作者
主流机：型号 / Android 版本；低端机：型号 / Android 版本
AC-01：通过|失败，证据文件名
...
AC-12：通过|失败|阻塞，证据文件名
失败/阻塞：复现步骤、非敏感错误文本、相关时间
```

只有 AC-01 至 AC-12 全部有可复现自动化或人工证据，且没有“阻塞/失败”，才能签署 P0 现场试用通过。
