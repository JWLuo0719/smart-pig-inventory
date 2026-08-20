# 开发工作站基线

更新时间：2026-08-20。适用于“智慧猪场场主”的 Windows 开发机。

## 固定版本与目录

| 项目 | 基线 |
|---|---|
| JDK | 21 |
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

`.env` 仅在本机创建且已被 Git 忽略。脚本产生随机 MySQL/MinIO 密码，不显示密码；不要手动把 `.env` 发到聊天、Issue 或仓库。

## 一键核验

```powershell
.\scripts\verify-development-environment.ps1
```

该命令会检查 Git、Java、Node、pnpm、Python、Docker、Flutter 与 `.env`，并执行 `flutter doctor`。如果 Docker Desktop 首次启动要求接受许可或启用 WSL，按其界面流程完成后再重试。

## 本机验收

完成以下项目才可把“开发环境已就绪”更新为已验证：

1. `flutter doctor` 中 Flutter、Android toolchain 均为可用。
2. `flutter analyze`、`flutter test`、`flutter build apk --debug` 在 `apps/mobile` 成功。
3. `docker compose config --quiet` 与 `docker compose up --build` 成功，MySQL、Redis、MinIO、业务 API、推理 API 和网关健康。
4. `.env` 不含模板密码，MinIO 桶未公开。

## 当前机器的已知运行时问题

Docker Desktop 已完成安装和 D 盘数据根配置，但在第一次 Compose 镜像拉取后重启时，WSL 引擎返回 `DockerDesktop/Wsl/ExecError` / `0xc00000fd`。这不影响 Android 开发环境；在该问题修复并通过 `docker version` 的服务器端检查前，不得把 Compose、Flyway 或 MinIO 的运行验证标为通过。
