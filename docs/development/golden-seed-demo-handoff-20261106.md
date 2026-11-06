# 金种子杯 Demo 录制取码说明

更新：2026-11-06。此次交付是完整产品源码，手机端版本为 `0.1.0+21`。上传不等于部署、模型批准、真机验收或赛事提交完成。

## 获取本次版本

仓库：<https://github.com/JWLuo0719/smart-pig-inventory>

使用 `codex/competition-code-completion-20261023` 分支；`main` 尚未包含本次完整版本。新目录执行：

```powershell
git clone --branch codex/competition-code-completion-20261023 --single-branch https://github.com/JWLuo0719/smart-pig-inventory.git
cd smart-pig-inventory
git log -1 --oneline
```

已有克隆先保存自己的修改，再 `git fetch origin`，切换上述分支后 `git pull --ff-only`。不要用强制重置覆盖同学的本地工作。记录 `git rev-parse HEAD`，让手机、管理端和后端使用同一源码版本。

## 启动与手机安装

完整准备步骤见[工作站说明](workstation-setup.md)、[Android 局域网 E2E](android-lan-e2e-testing.md)。新环境需要 Docker、Java 21、Flutter/Android SDK、Node 和项目锁定的 pnpm；管理端依赖安装使用 `pnpm install --frozen-lockfile`。

新环境在仓库根目录执行以下命令，生成自己本机的配置并启动服务：

```powershell
.\scripts\initialize-local-dev.ps1
docker compose config --quiet
docker compose up --build -d
```

已有 `.env`、数据库和手机草稿不要覆盖或删除。账号和口令在本机受控获取，不进入仓库、录屏、聊天或字幕。管理端默认入口 `http://localhost:8088`；先检查 `/actuator/health`，再按照局域网指南配置测试身份、合成栏舍和手机联通。

手机与后端电脑连接同一私有局域网，运行 `.\scripts\build-lan-test-apk.ps1`（需要时传入实际 `-ApiBaseUrl`）；APK 位于 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。普通 `flutter build apk --debug` 只证明编译成功，默认地址不能证明另一台手机能连接。保留现有签名身份和手机草稿，不用卸载解决签名冲突。正式 HTTPS/Release 流程见[Android Release](android-release.md)和[局域网验收](lan-real-pig-acceptance.md)。

仓库不附带真实模型权重、现场图片、签名材料、数据库、实际账号或配置。团队需在授权环境分别准备。推理未就绪时如实展示“待复核/未知”，不能添加模拟数量。可选 `/assistant` 只读页面默认关闭外部模型，必须完成凭据配置和最少数据出站授权后才可演示真实回答。

## 建议录屏顺序

1. 登录并同步组织/栏舍，展示首页、任务和图库的实际状态。
2. 选择栏舍，单图采集和 ROI，保存草稿并展示上传队列；可短暂断网展示草稿保留与联网重试。
3. 在已验证的真实模型环境展示服务返回的候选和证据；由有权限的人员人工复核确认。
4. 在管理端查看已确认结果、历史及报表；说明候选与确认值的区别。多视角图不能直接相加。
5. 只有真实模型及 Agent 环境已验收时才展示只读问答和引用。录前走通全过程，失败或未知状态如实说明。

录制使用授权媒体或明确标记的合成测试数据，隐藏账号、Token、对象 URL、终端配置和个人信息。金种子杯的时长、分辨率、匿名及文件要求以该赛事实际通知为准；其他比赛文档中的 6 分钟等限制不自动适用。

## 本次上传前验证

- Spring `mvn test`、`mvn verify` 成功：各 196 项，161 通过、35 因 Docker 环境不可用跳过；真实 MySQL/Flyway 集成尚未验证。
- Admin：41 项测试通过；lint、typecheck、build 通过。
- Flutter：`dart analyze .` 无问题；`flutter test` 96 项通过，1 项 TLS 测试因未提供本地证书目录跳过；`flutter build apk --debug` 成功。构建提示 workmanager_android 的 Kotlin 插件未来兼容性及 Android SDK XML 工具版本警告，本轮未升级依赖。
- Inference：88 项通过。Compose 配置通过；JoyCode 工具 1 项正向、7 项拒绝检查通过。
- 源码检查未发现私钥/常见令牌格式、与本机实际密钥相同的内容或禁止上传的模型/私有媒体/构建包；这不是对所有秘密格式的完备检测。

本轮未连接手机、启动完整业务栈、验证真实模型或录制视频。真实数据、网络、模型与人工确认链路应在录前单独验收。此次任务只上传代码和取码说明，不提交赛事材料。
