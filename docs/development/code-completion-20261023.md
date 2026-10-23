# 代码收口记录（2026-10-23）

目标：完成当前有效开发计划的全部代码、必要自动检查和可回退分支提交；用户明确整体验收后置。范围依据[当前开发计划](../product/competition-development-plan.md)、[功能收口计划](../product/functional-release-plan.md)、PRD P0及本轮逐项源码审计。这里的代码完成不表示部署、模型批准、真机或参赛交付验收通过。

## 本轮补齐

| 要求 | 实际实现与验证入口 |
|---|---|
| 数量不得被默认/截断 | Confirm/Correction的Integer+NotNull及局部严格JSON整数绑定；缺失/null/负值422，非整数/字符串/bool/溢出400，合法0保留；MockMvc5项含20种非法token且业务未被调用 |
| Admin身份与迟到请求 | JSON/Blob读取后再次校验会话；登录、刷新、会话、报表和操作代次隔离；旧身份结果不能回填；延迟body真实Deferred测试 |
| 复核与中文 | 同屏候选/人工/有符号差值/理由与版本预览；任务、历史、证据方向状态使用集中中文映射，未知不伪造合法状态 |
| 研判失败可恢复 | 首页任务不等待研判；研判独立加载/失败/重试；离线与身份切换清除旧依据 |
| 三图追加/恢复 | 追加在事务内检查组织、草稿状态、方向、未入队；首图使用真实尺寸；picker中图恢复回原组而非新单图 |
| 手机报表/图库隔离 | 主体、组织、日期、栏舍和请求代次快照；切换清旧结果/旧媒体；该栏缺失不得回退全场，覆盖数在界面可见且未知不补0 |
| 真正缩略图 | OpenAPI0.11.0新增受认证GET；私有MinIO确定性缓存与已有thumbnail_key；JPEG/PNG保持比例≤320，EXIF/eXIf方向1—8，剥离元数据，原图不改；两端列表使用缩略图，核验仍原图 |
| 派生资源边界 | 压缩20MiB/20000边/4000万像素，先检查并subsample，最多2次派生，缓存读取512KiB；坏图/不支持422，繁忙/存储故障503；每次重新授权/删除检查，缓存缺失损坏重建，无长DB事务 |
| 列表负载与取消 | 两端按查询生命周期限制2个缩略图在途请求；翻页/刷新/换身份取消等待任务，启动HTTP前复查身份/代次；新查询不等待旧挂起HTTP，原图入口保留 |
| 原有效计划其余代码 | 主数据、离线/上传、去重复核、候选/人工边界、确认锁定/更正/删除、历史/综合/导出、视频人工证据、安全诊断、签名/生产配置/恢复工具、三个工具契约均已核对实际实现；未扩大到明确后置域 |

新增缩略图没有业务数据库迁移，不改变模型/推理合同、Drift v6、原媒体、签名或TLS。HEIC/视频没有缩略图编码器，显示占位和原图入口，不能冒充预览成功。

## 本轮自动检查

| 检查 | 实际结果 | 忽略目录证据 |
|---|---|---|
| Spring `mvn test` | 执行成功；128项中94通过、34因Docker不可用跳过、0失败/错误 | artifacts/code-20261023-mvn-test.log |
| Spring `mvn verify` | 执行及打包成功；同样94通过/34跳过；不是完整数据库集成门禁通过 | artifacts/code-20261023-mvn-verify.log |
| 数量HTTP定向 | 5项通过；缺失/null/负值与严格token边界、合法0 | artifacts/competition-20261023-review-strict-integer.log |
| 缩略图定向 | 16项通过；JPEG/PNG各8方向×2端序、CRC/坏数据/限额、缓存与组织/删除、并发、503与HTTP | artifacts/thumbnail-unit-20261023.log |
| Admin | 最终35项通过、lint/typecheck及Next生产构建通过 | artifacts/code-20261023-admin-tests-final.log；artifacts/code-20261023-admin-lint-final.log；artifacts/code-20261023-admin-typecheck-final.log；artifacts/code-20261023-admin-build-final.log |
| Flutter格式/分析 | 最终96个文件格式无变更，`dart analyze .`无问题 | artifacts/code-20261023-mobile-format-final.log；artifacts/code-20261023-mobile-analyze-final.log |
| Flutter全量 | 最终96通过、1真实LAN TLS环境跳过；包括身份/日期/队列取消与旧挂起请求不阻塞新查询 | artifacts/code-20261023-mobile-test-final.log；artifacts/competition-thumbnail-queue-20261023.log |
| Android Debug v21 | 最终构建成功；aapt读回versionCode21/versionName0.1.0 | artifacts/code-20261023-mobile-debug-final.log |
| 三个只读工具 | 36个合成夹具、2项检查通过，不执行Agent | scripts/test_assistant_tool_contracts.py |
| OpenAPI/Compose | 0.11.0严格YAML无重复键、本地引用可解析；`docker compose config --quiet`成功 | 本轮只读命令；最终交付清单 |

34个Spring跳过项的XML原因全部为`disabledWithoutDocker is true and Docker is not available`，覆盖上传/身份/主数据/确认/更正/导出/JWT角色/监控快照/迁移，以及新增ThumbnailRepositoryIntegrationTest。它们仍待Docker环境运行；没有使用skipTests隐藏失败，没有重启Docker或删除卷来换取绿色结果。

## 后置项与交付边界

固定Admin栈的浏览器/真实HTTP、缩略图真实MinIO传输与MySQL缓存、部署镜像/迁移/模型身份读回、EXIF图框像素、真机/弱网/后台恢复、130%字体/强光/无障碍、授权实猪与独立真值、连续三次彩排全部保留待验。按用户指令，这些不阻断本轮无关代码完成；未来冻结与发布仍须执行原验收门槛。

没有部署P0、安装/卸载手机或清数据，没有模型批准/计数开关变化，没有外部报名/缴费/提交。旧v20签名BuildOnly只证明10/20源码；新v21 Debug不可冒充Release或联网候选。在线Agent仍仅交付版本化契约及夹具，真实交互案例、公网评审与受限账号属于独立后续里程碑。

## 分支与最终产物

分支`codex/competition-code-completion-20261023`，逐批提交见[回退清单](competition-code-recovery.md)。最终产品源码提交`7d8710b`；之后只有文档收口。Debug APK位于`apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`，SHA-256为`536763e040f41ff14c1239f960161edad2f1b424b563ba52227d0e4c23a1e4d3`。最终本地源码/检查/Debug快照清单保存于`artifacts/code-completion-20261023-final/manifest.json`，它明确标注runtimeAcceptance=deferred，不是联网候选；早先`code-completion-20261023`目录为并发补丁前的快照，不能代表最终代码。

Review Hub本次`audit-20261023132935-e1f05cd9`检索成功、0匹配，方案未因检索改变；按既有项目规则和当前请求推进。10/18旧运行验收审计仍不作为本次代码完成证明。
