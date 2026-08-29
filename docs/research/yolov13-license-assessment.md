# YOLOv13 本机压缩包许可评估

日期：2026-08-27
状态：不准入专有产品主线；保留为本机只读研究输入

## 已核对事实

- `yolov13-official-main.zip` 的根目录 `LICENSE` 是 GNU AGPL v3。
- 其 `pyproject.toml` 声明包名为 `ultralytics`、许可证为 `AGPL-3.0`；压缩包内不含 `.pt`、`.onnx` 或其他可部署权重。
- 上游同样将仓库标记为 AGPL-3.0，并说明企业使用需要另行取得许可证：[Ultralytics 许可证](https://github.com/ultralytics/ultralytics/blob/main/LICENSE)、[上游许可说明](https://github.com/ultralytics/ultralytics/blob/main/CONTRIBUTING.md)。

## 本项目决定

- 不复制压缩包代码、依赖、示例或权重到本仓库、Docker 镜像或生产服务。
- 推理服务仅提供 `http-yolo` Provider：它调用一个**独立部署且已获批准**的 HTTP 模型服务，并只传递版本化 `CountingJobRequest/Result` 合同。
- 默认 Provider 保持 `unavailable`，返回 `review_required`，不生成模拟数量。
- 只有取得书面许可结论、可追溯权重 checksum、模型版本、授权金标集和回归结果后，才能同时配置 `COUNTING_PROVIDER=http-yolo`、`MODEL_APPROVED=true` 并开启该模型服务。

`eg/` 不作为本次实现或模型输入来源；其源码、权重、命名与素材均未读取或复制。
