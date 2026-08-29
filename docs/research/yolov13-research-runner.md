# YOLOv13 隔离产品测试方案

日期：2026-08-27
状态：本机研究测试；不具备生产/现场启用资格

## 决策

以 iMoonLab YOLOv13 Nano 作为一个可替换的、产品仓库外的本机研究 Runner，验证“提交采集包 -> 推理任务 -> 检测结果 -> 人工复核”的链路。产品保持既有 `CountingJobRequest -> CountingJobResult` HTTP 合同，不引入上游代码、权重或 Python 依赖。

`research-http-yolo` 必须同时设置 `MODEL_RESEARCH_ENABLED=true` 才能启用；即使 Runner 返回成功，产品推理服务也会强制将结果改写为 `review_required` 且 `count=null`。这是一条可观察的产品测试路径，不是猪只自动计数功能。

## GitHub 对比与取舍

| 候选 | 可借鉴的事实 | 许可/兼容性 | 本项目取舍 |
|---|---|---|---|
| [iMoonLab/yolov13](https://github.com/iMoonLab/yolov13) | 提供 YOLOv13 权重、Python 3.11/torch 2.2.2 运行说明及 FastAPI 示例 | 仓库来源于 Ultralytics；仓库内 LICENSE 为 AGPL-3.0，不能进入专有主线 | 用其原始源仓库和 `yolov13n.pt` 仅作本机、独立研究 Runner |
| [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics) | 上游 YOLO 运行时与 Docker 部署模式 | AGPL-3.0；其官方资料还说明商业产品需选择相应许可 | 不复制、不链接、不作为产品依赖；正式落地前由法务评估许可或改用已批准模型 |
| [BentoML/BentoML](https://github.com/bentoml/BentoML) | Apache-2.0 的模型服务封装、打包和多模型运行模式 | 与产品许可边界相容，但引入它会增加当前 P0 运行复杂度 | 不在本轮引入；团队自研模型需多模型调度、可观测性或独立扩缩容时再单独评估 |

结论：本轮只借鉴“模型服务完全可替换”的架构模式，不复用任何上述项目的产品源代码。iMoonLab 与 Ultralytics 的 AGPL 边界是本机研究隔离的原因；BentoML 是未来可评估的服务基础设施，不是当前依赖。

## 部署边界

```text
Spring Outbox -> Python inference-service -> research-http-yolo -> 外部 YOLOv13 Runner
                                                        |                 |
                                                        |                 +-> MinIO 只读对象
                                                        +-> 强制人工复核
```

- 外部目录：`D:\Project\model-research\iMoonLab-yolov13`（上游源码）和 `D:\Project\model-research\yolov13-models`（权重），均不在 Git 产品仓库中。
- Runner 只读 MinIO，对象存储凭据只在启动时以环境变量提供；不得写入镜像、仓库或日志。
- Runner 使用上游 Nano 权重，COCO 类别并非猪只领域金标。因此检测框仅作为技术链路证据，不能用于自动数量或业务确认。
- 测试完成后，可直接切换为团队自研 Runner；只要维持合同、模型身份和回调幂等规则，业务、移动端和管理端不需要改动。

## Agent 迭代预留

Agent 是受限 Sidecar，而不是计算结果或业务事实的来源：只读检索、生成复核建议和编排可重试任务；不得持有推理回调密钥、直写数据库、确认盘点、解锁媒体或替代人类审批。后续能力先以独立 Adapter 版本接入，且保留工具调用审计、权限校验和人类确认点。

## 本机验证记录

- 外部 Runner 使用 `yolov13n.pt`，SHA-256 为 `6653035017b0f111f80ec11ed914874ea85699b104aeac1e46e517d16889d6b7`；容器为 Python 3.11、torch 2.2.2 CPU。此配置只验证合同，不是 GPU 性能基准。
- Runner 已从私有 MinIO 读取一张合成/非业务烟测图片并完成原始模型推理，返回 `review_required`、空计数与检测列表；首个请求约 2.6 秒。
- `pig-inventory-yolo-research` 隔离 Compose 项目已健康启动，Spring 已应用 Flyway V1–V5；产品 Worker 的 `research-http-yolo` Provider 已调用该 Runner，并再次标准化为 `review_required` 与 `count=null`。
- 真实猪场图像、外部研究数据集和人员现场媒体均未复制进产品仓库、镜像上下文或跟踪文件。

## 进入正式模型的门禁

1. 法务确认模型代码、权重、运行时和部署方式的许可。
2. 使用经授权的猪只金标集完成准确率、漏检、重复计数、遮挡、三视图和弱网回归。
3. 固化模型 key/version/checksum、预处理、阈值、硬件和回滚镜像。
4. 管理员批准后才可关闭研究开关并启用 `http-yolo`；随后以版本化适配器逐步替换为团队模型。
