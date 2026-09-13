# P1 模型发布清单、漂移门禁与回滚演练

更新时间：2026-08-31

## 结论

当前项目不引入完整 MLOps 平台。P1 使用轻量、可审计的研究候选清单：模型身份由 `model_key + model_version + model_checksum + adapter_version` 唯一确定，权重文件和回归摘要分别校验 SHA-256，基线只允许显式创建且不可自动覆盖。清单不会改变产品安全状态，始终要求 `MODEL_APPROVED=false`、自动计数关闭、人工复核开启。

本阶段没有解决、也没有绕过三项人工准入：模型/代码许可、授权业务金标准入、负责人批准自动计数。任何一项未完成时，清单仍是 `research_candidate`，不能作为生产发布批准。

## GitHub 对比

| 项目 | 已核实模式 | 可迁移做法 | 本项目取舍 |
| --- | --- | --- | --- |
| [MLflow](https://github.com/mlflow/mlflow) | Model Registry 使用不可变版本、标签和可重新指向的 alias 表达 candidate/champion 等部署意图；Apache-2.0 | 将“模型身份”与“当前部署指针”分离，回滚指向已验证版本 | 采用数据契约思想；不引入 Registry 服务和数据库 |
| [BentoML](https://github.com/bentoml/BentoML) | 将模型、代码和依赖配置组成可复现部署单元，并支持版本化模型存储；Apache-2.0 | 发布证据同时记录权重、阈值、运行时和适配器版本 | 采用清单字段；不复制代码、不替换当前 HTTP Runner 边界 |
| [DVC](https://github.com/treeverse/dvc) | 版本化数据/模型并比较实验参数、指标与产物；Apache-2.0 | 固定一个不可覆盖的本机基线，以明确容差比较新摘要 | 采用 JSON 基线/差异门禁；暂不引入 DVC 仓库或远端存储 |
| [Seldon Core](https://github.com/SeldonIO/seldon-core) | 支持候选、A/B、影子流量、漂移组件和多模型服务；Business Source License | 候选异常必须 fail-closed，再切回已知健康版本 | 仅采用回滚验证思路；Kubernetes 体系和许可/运维成本与当前试点不匹配 |

以上只借鉴数据合同和验证流程，没有复制第三方源代码，也没有改变项目现有 Flutter + Spring + Python HTTP Provider 架构。

## 已实现门禁

`contracts/model-release-manifest.schema.json` 固定研究候选合同，`scripts/model_release_gate.py` 提供四个命令：

- `build-manifest`：重新计算权重 SHA-256，核对回归摘要的权重身份、文件名、val 选阈值和 test 留出评估，生成本机忽略清单。
- `validate-manifest`：结构校验，并可再次绑定真实权重和回归摘要；拒绝绝对/相对目录进入 artifact 字段。
- `create-baseline`：显式创建版本化本机基线；目标存在时拒绝覆盖。
- `compare`：同一模型身份、图像尺寸、IoU 和阈值下比较 MAE、WAPE、±2 比例、最大误差、稳态 P95 和吞吐。

默认容差是工程回归报警线，不是业务准入线：val/test MAE 最多增加 0.25，WAPE 最多增加 1 个百分点，test ±2 比例最多下降 3 个百分点，最大绝对误差最多增加 1，稳态 P95 不得超过 1.5 倍，吞吐不得低于 0.67 倍。任何模型 checksum、图像尺寸、IoU 或选定阈值变化都会直接失败，要求新建候选版本和显式基线，不能沿用旧基线掩盖变化。

`scripts/run-team-yolo-regression.ps1` 已可在完成 val/test 全量回归后串联生成清单并执行现有基线比较。它不会自动创建或更新基线，避免一次坏结果把门禁自身覆盖掉。

## 本机证据

- 团队候选权重 SHA-256：`1bc862842aa69a744f8c75d6180b714738cc413c693a2b954e7d3882065aec39`。
- 当前全量摘要已生成本机忽略清单 `team-yolo-release-manifest.json`，再次绑定真实权重和摘要校验通过。
- 当前摘要已显式提升为本机忽略基线 `team-yolo-regression-baseline-v3.json`；立即比较结果通过，P95 与吞吐比值均为 `1.0`，无 violation。
- 旧对话留下的历史模型标识没有对应的可复现 val/test 摘要；本机同名下载权重的 SHA-256 也与旧记录不同，因此没有伪造跨模型“历史漂移通过”。旧结果仅保留为信息性对照。

## 隔离回滚演练

`scripts/run-model-rollback-rehearsal.ps1` 仅允许 Compose 项目名 `pig-inventory-p1-rollback`。演练使用两份均已通过清单校验、来自同一真实回归证据的逻辑版本；Runner 是确定性 Stub，不读取真实权重，也不访问业务数据库。

2026-08-31 实测顺序：

1. 回滚锚点身份启动，推理 readiness 为 200。
2. 同时切换 Runner、API 和 Worker 到候选身份，readiness 为 200。
3. 将 Runner 报告的候选 checksum 改为错误值，产品侧返回 503，原因严格为 `RUNNER_IDENTITY_MISMATCH`。
4. 将配置和 Runner 一起回滚到锚点，约 11.4 秒恢复 readiness 200。
5. 成功后删除隔离容器和网络、保留隔离卷；`pig-inventory-p0` 服务未停止，业务数据未被访问。

该时间包含容器重建和健康检查，只证明本机 Stub 控制面回滚机制，不代表真实权重 GPU/CPU 加载时间或生产 RTO。

## 后续边界

下一次更换权重、阈值、运行时或依赖时，必须重新跑完整 val/test 回归，生成新版本清单，并先与旧基线比较。只有负责人另行确认许可、业务金标和自动计数审批后，才可以设计生产 alias/部署指针；本阶段不创建该指针。
