# 开发工作站基线

更新时间：2026-08-21。适用于“智慧猪场场主”的 Windows 开发机。

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

## 一键核验

```powershell
.\scripts\verify-development-environment.ps1
```

该命令会检查 Git、Java、Maven、Node、pnpm、Python、Docker、Flutter 与 `.env`，并执行 `flutter doctor`。如果 Docker Desktop 首次启动要求接受许可或启用 WSL，按其界面流程完成后再重试。

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

该命令必须显示 `9` 项测试、`0` skipped，并实际启动 MySQL 8.4 Testcontainer 完成 Flyway V1/V2。Docker Desktop 的 WSL 引擎、完整 Compose、Flyway、MinIO 私有桶和网关健康均已在本机复验。
