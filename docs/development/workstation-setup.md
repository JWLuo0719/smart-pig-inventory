# 开发工作站基线

更新时间：2026-08-30。适用于“智慧猪场场主”的 Windows 开发机。

2026-09-12 构建补充：本机 16 GB 内存同时执行 Docker/MySQL 集成测试与 Android Release 曾出现 CoreCLR/Dart 内存分配失败及 Gradle JVM 原生内存崩溃（原默认堆 8 GB）。项目 Gradle 改为 2 GB 堆、1 GB Metaspace、最多 2 个 Worker；重型 Release 与 Maven 全量验证串行运行。不要通过结束用户应用或清理数据卷回收内存。Docker 引擎内部错误和构建失败必须恢复后重验，不能把旧产物当成成功。

## 固定版本与目录

| 项目 | 基线 |
|---|---|
| JDK | 21 |
| Maven | 3.9.11，`D:\ProgrammingLanguage\apache-maven-3.9.11\bin\mvn.cmd` |
| Flutter | 3.44.7 stable，`D:\ProgrammingLanguage\Flutter\flutter` |
| Node.js | 已安装的 LTS；使用仓库锁定的 pnpm |
| 容器运行时 | Docker Desktop 4.87.0 per-user + WSL 2 Linux containers；数据根 `D:\DockerDesktop\wsl-data` |
| 服务端 | Spring Boot/Maven、Python 虚拟环境、Docker Compose |

Flutter SDK 必须放在没有空格、非管理员权限的目录。首次打开新终端后执行：

```powershell
flutter --version
flutter doctor
```

Android Studio/SDK 安装后，在 Flutter 中接受 Android SDK 许可证并重新运行 `flutter doctor`。仅在确认 Android toolchain 可用后，才生成、审查和提交 `apps/mobile/android/` 原生壳。

## 初始化本地服务

```powershell
.\scripts\initialize-local-dev.ps1
docker compose config --quiet
docker compose up --build
```

`.env` 仅在本机创建且已被 Git 忽略。脚本产生随机 MySQL/MinIO 密码、初始管理员密码和 JWT 签名密钥，且不显示密码或密钥；不要手动把 `.env` 发到聊天、Issue 或仓库。Android 局域网真机 E2E 步骤见 `docs/development/android-lan-e2e-testing.md`。

## Docker Hub 超时与本机代理

本机网络若能通过 Clash 代理访问 Docker Hub、但直连 `auth.docker.io` 超时，先在 Docker Desktop 的 `Settings -> Resources -> Proxies` 将 Docker Desktop proxy 设为 `Manual configuration`，HTTP 与 HTTPS 都填写 Clash 当前的 HTTP/Mixed 监听地址（本机验证值为 `http://127.0.0.1:7897`）。不要批量添加来历不明的镜像站，也不要为 Docker Hub 开启 `insecure-registries`。

Docker Desktop 代理可修复普通 `docker pull`；当前 Docker Desktop/Buildx 组合仍需让发起构建的 PowerShell 进程显式继承代理，才能避免 Buildx OAuth 请求绕过代理：

```powershell
$env:HTTP_PROXY = 'http://127.0.0.1:7897'
$env:HTTPS_PROXY = $env:HTTP_PROXY
$env:http_proxy = $env:HTTP_PROXY
$env:https_proxy = $env:HTTPS_PROXY
$env:NO_PROXY = 'localhost,127.0.0.1,host.docker.internal'
$env:no_proxy = $env:NO_PROXY
docker compose up --build
```

先用 `docker pull docker/dockerfile:1.7` 和实际 `docker compose build` 验证。只有显式代理仍失败且确需让不支持代理的进程统一接管流量时，才评估 Clash TUN；不要把 TUN 作为首选修复。

## 一键核验

```powershell
.\scripts\verify-development-environment.ps1
```

该命令会检查 Git、Java、Maven、Node、pnpm、Python、Docker、Flutter 与 `.env`，并执行 `flutter doctor`。如果 Docker Desktop 首次启动要求接受许可或启用 WSL，按其界面流程完成后再重试。

## 推理故障注入

P1 推理边界可在独立 Compose 项目中验证未就绪、超时、Runner 停止/重启和恢复；测试成功后只清理隔离容器与网络，不删除卷：

```powershell
.\scripts\run-inference-fault-e2e.ps1 -ImagePath '<local-test-jpeg>'
```

脚本固定项目名为 `pig-inventory-p1-fault`，不允许指向 `pig-inventory-p0`。若构建阶段再次命中 Docker Hub OAuth 直连超时，先按上一节为当前 PowerShell 设置显式代理后重试；无需开启 Clash TUN。

## 已确认报表导出 E2E

```powershell
.\scripts\run-report-export-e2e.ps1
```

脚本固定使用隔离项目 `pig-inventory-p1-report-export`，生成的 PDF/XLSX 与摘要只写入被忽略的 `test-assets/generated/`。它验证本组织 confirmed-only 数据、跨组织/未确认排除、422 参数边界、下载头和文件签名；成功后清理隔离容器与网络但保留卷。修改 PDF/XLSX 渲染或布局后还必须做文本、公式错误和视觉复核，禁止把脚本改指向 `pig-inventory-p0`。

## 本机验收

完成以下项目才可把“开发环境已就绪”更新为已验证：

1. `flutter doctor` 中 Flutter、Android toolchain 均为可用。
2. `flutter analyze`、`flutter test`、`flutter build apk --debug` 在 `apps/mobile` 成功。
3. `docker compose config --quiet` 与 `docker compose up --build` 成功，MySQL、Redis、MinIO、业务 API、推理 API 和网关健康。
4. `.env` 不含模板密码，MinIO 桶未公开。

## Docker Java/Testcontainers 兼容性

Docker Desktop 29.7 的 Windows npipe 拒绝 Testcontainers 默认协商的旧 Docker API，曾导致集成测试被跳过。项目通过 `services/business-api/src/test/resources/docker-java.properties` 固定 Docker Java 客户端 API 至 `1.44`；这是测试 classpath 内的项目级配置，不修改 Docker Desktop 或系统全局环境。

验证 Spring 时执行：

```powershell
cd services/business-api
mvn verify
```

该命令必须全部通过、`0` skipped，并实际启动 MySQL 8.4 Testcontainer 完成 Flyway V1–V11；2026-09-08 最新执行为 61 项测试。Docker Desktop 的 WSL 引擎、完整 Compose、Flyway、MinIO 私有桶和网关健康均已在本机复验。

## 回调鉴权自动回归

```powershell
pwsh -NoProfile -File scripts/run-callback-auth-e2e.ps1
```

固定隔离项目 `pig-inventory-p0-callback-auth`、仅本机 `127.0.0.1:8094`，不读取产品 `.env`，不修改 P0。默认重建业务/推理 API 镜像，使用回调专用合成数据库记录，不上传真实图片、不执行 Worker 或模型。分别验证用户认证开/关时的 401 拒绝及无写入、合法服务密钥首次 204/重放 200/冲突 409，并验证未配置服务密钥时仍拒绝访问。成功后清理该隔离容器和网络、保留三个卷；失败保留栈供诊断。

摘要在本机忽略的 `test-assets/generated/callback-auth/summary.json`；`status=passed` 才代表回归成功。`-SkipBuild` 只用于镜像已含当前源码的复跑；`-KeepStack` 可保留成功测试栈。模板中的测试口令不能用于部署。`INFERENCE_CALLBACK_TOKEN` 空值仍允许关闭派发器后的应用启动，但所有回调均返回 401；不要通过关闭 `SECURITY_ENABLED` 绕过。

## 业务可观测性自动回归

执行 `pwsh -NoProfile -File scripts/run-observability-e2e.ps1`，固定 `pig-inventory-p0-observability`、loopback 8095。规则通过只读挂载的 promtool 校验；摘要位于忽略的 `test-assets/generated/observability/summary.json`。成功仅清理该测试容器/网络、保留卷，不读取或修改 P0。

监控端点认证已收紧为独立 `MONITORING_SERVICE_KEY`；之前使用用户 Bearer Token 的监控请求需改用 `X-Monitoring-Service-Key`，空值即禁止访问（包括用户认证关闭时）。指标口径、合成夹具边界与后续采集器缺口见 `docs/development/business-observability.md`。
