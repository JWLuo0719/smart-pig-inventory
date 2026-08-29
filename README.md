# 智慧猪场场主

路线 B+ 的全新实现：保留学长 App 的业务流程启发，但不复制其源码、数据库、接口、文案或视觉素材。主业务采用团队更熟悉的 Spring Boot/MySQL；模型通过独立、版本化的 Python 推理服务接入。

## 当前阶段

当前是 `Development Readiness / Not Release Ready`。已完成 P0 上传、推理安全降级、人工复核、管理端审核与合成 RBAC Fixture；仍须完成全部人工验收、安全运行与模型准入门禁。工程按以下边界独立演进：

| 目录 | 责任 | 状态 |
|---|---|---|
| `apps/mobile/` | Flutter Android 现场采集、离线草稿和 Outbox | 页面框架与本地表结构草案 |
| `apps/admin-web/` | Next.js 管理、审核、报表与运维入口 | 现场态势页面框架 |
| `services/business-api/` | Spring Boot 业务规则、权限、幂等和审计 | 数据库基线与领域策略骨架 |
| `services/inference-service/` | FastAPI/Celery 推理适配层 | 版本化合同与安全降级 Provider |
| `services/backend/` | 早期 Django 验证原型 | 冻结，仅作行为参考 |
| `eg/` | 学长项目本地参照物 | Git 忽略、只读、不可复制 |

推理服务未接入经过验收的模型时只返回 `review_required`，不会生成模拟盘点数量。

## 权威文档

- 产品与需求：[`docs/product/PRD.md`](docs/product/PRD.md)
- 边界：[`docs/product/scope-and-boundaries.md`](docs/product/scope-and-boundaries.md)
- 非功能需求：[`docs/product/non-functional-requirements.md`](docs/product/non-functional-requirements.md)
- 验收：[`docs/product/acceptance-criteria.md`](docs/product/acceptance-criteria.md)
- 需求追踪：[`docs/product/requirements-traceability.md`](docs/product/requirements-traceability.md)
- 架构：[`docs/architecture.md`](docs/architecture.md)
- 视觉与页面：[`docs/design/visual-system.md`](docs/design/visual-system.md)、[`docs/design/information-architecture.md`](docs/design/information-architecture.md)
- 开发规范：[`docs/development/standards.md`](docs/development/standards.md)
- App 完整开发顺序：[`docs/development/mobile-development-sequence.md`](docs/development/mobile-development-sequence.md)
- 开放决策：[`docs/product/open-decisions.md`](docs/product/open-decisions.md)
- 工作站准备：[`docs/development/workstation-setup.md`](docs/development/workstation-setup.md)
- 测试数据边界：[`docs/development/test-data-governance.md`](docs/development/test-data-governance.md)
- 外部人工验收：[`docs/development/p0-external-manual-test-guide.md`](docs/development/p0-external-manual-test-guide.md)
- 当前状态：[`PROJECT_STATUS.md`](PROJECT_STATUS.md)、[`NEXT_STEPS.md`](NEXT_STEPS.md)

## 本地启动

需要 Docker Desktop。执行初始化脚本生成本机随机口令后运行：

```powershell
.\scripts\initialize-local-dev.ps1
docker compose up --build
```

管理端入口为 `http://localhost:8088`，业务健康检查为 `http://localhost:8088/actuator/health`。`dev` Profile 会关闭业务 API 鉴权，只能用于本机；任何共享或生产环境必须启用 OIDC/JWT。

单独验证各工程：

```powershell
cd services/business-api
mvn test

cd ..\inference-service
python -m pip install -r requirements.txt
python -m pytest

cd ..\..\apps\admin-web
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm build

cd ..\mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Android 模拟器调用地址可通过 `--dart-define=API_BASE_URL=http://10.0.2.2:8088` 配置；局域网真机使用 `./scripts/build-lan-test-apk.ps1` 一键构建。完整步骤见 [`docs/development/android-lan-e2e-testing.md`](docs/development/android-lan-e2e-testing.md)。版本锁定、提交规则和分支约束以开发规范为准。

## 开源许可与公开边界

原创产品源码以 [Apache-2.0](LICENSE) 发布。模型权重、外部研究数据、现场媒体、`.env`、测试报告产物和 `eg/` 参照物不属于公开内容；完整边界见 [LICENSES.md](LICENSES.md) 与测试数据治理规则。

## 尚需产品确认

- 首批试点猪场和边缘服务器配置。
- 低端 Android 验收机是否采购 REDMI Note 14 5G（6GB+128GB）作为候选设备。
- 金蝶正式接口文档，以及可上线 YOLO 权重的版本、许可证和基准结果。
