# P1 计数 Provider 的 GitHub 对标

日期：2026-08-30
范围：只比较可迁移的数据合同、检测证据和自动化测试模式，不引入第三方源码或权重。

## 结论

当前产品的“外部模型 Runner -> 版本化 HTTP 合同 -> 产品侧安全归一化 -> 人工复核”方向不需要改写。可借鉴的是标准化检测记录与几何测试；AGPL 项目只作研究参考，不复制代码、不链接运行时、不进入专有主线。

| 项目 | 已核实模式 | 可迁移做法 | 许可与采用决定 |
|---|---|---|---|
| [iMoonLab/YOLOv13](https://github.com/iMoonLab/YOLOv13) | README 和 FastAPI 示例返回边界框、置信度、类别与计数 | 外部 Runner 保持窄 HTTP 边界；每次结果携带完整检测证据 | AGPL-3.0；只参考合同形状，不复制源码、依赖或权重 |
| [roboflow/supervision](https://github.com/roboflow/supervision) | `Detections` 统一 `xyxy`、confidence、class 等字段 | 产品合同继续使用归一化 `xyxy`、置信度、类别和媒体 ID，避免只传最终数量 | MIT；当前无需新增依赖，自有小型 DTO 足够，迁移成本最低 |
| [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics) | ObjectCounter 测试对多边形区域、方向和边界行为作确定性断言 | 为 ROI 中心点、边界包含、三视图禁止汇总建立确定性测试 | AGPL-3.0；只借鉴测试思想，不采用实现或整体栈 |

## 与本项目边界的适配

- 数据权威仍在 Spring/MySQL；Runner 无权直接确认业务数量。
- 产品侧必须重新验证模型 key/version/checksum/adapter、框范围、媒体引用和 ROI，不信任外部 Runner 的汇总值。
- 单图研究结果只能成为 `review_required` 候选；三视图在验证过的跨图去重 Provider 出现前不得相加。
- 原图、权重、研究数据和绝对路径不得进入 Git、Docker 构建上下文或 CI。

## 维护与迁移成本

维持自有合同只增加少量 DTO、校验和测试，避免框架级迁移、许可证扩散及模型运行时耦合。若将来替换模型，只要新 Runner 满足相同合同和身份校验，业务与管理端无需重写。
