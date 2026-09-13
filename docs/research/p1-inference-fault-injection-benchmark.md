# P1 推理故障注入方案对比

日期：2026-08-31
状态：已用于本机隔离 E2E 设计

## 对比结论

| 候选 | 已核实能力 | 适配与维护成本 | 本项目取舍 |
|---|---|---|---|
| [Shopify Toxiproxy](https://github.com/Shopify/toxiproxy) | 独立 TCP 代理、HTTP 控制面，可确定性注入延迟、超时、断连等故障 | 需要增加镜像、代理拓扑和测试控制客户端；MIT 许可 | 借鉴“独立测试控制面”和确定性故障模式，本阶段不引入依赖 |
| [WireMock](https://github.com/wiremock/wiremock) | 容器/独立服务运行，支持 HTTP Stub、延迟、故障和有状态响应；Apache-2.0 | Java 运行时和完整匹配系统超出当前单一 Provider 边界需求 | 借鉴有状态 Stub；不引入整个框架 |
| [Chaos Mesh](https://github.com/chaos-mesh/chaos-mesh) | 面向 Kubernetes 的 Pod、网络、HTTP、IO 等故障编排；Apache-2.0 | 当前项目是单机 Docker Compose，引入 Kubernetes/特权组件不符合试点基线 | 留作未来 Kubernetes 部署评估，不用于当前阶段 |

采用最小增量方案：`docker-compose.fault-e2e.yml` 中运行仅供测试的 Python 标准库 Stub，通过本机回环端口控制 `not_ready`、`timeout` 和 `ready` 状态。它不进入生产 Compose，不读取权重或媒体，不改变推理合同。

## 已验证边界

- 推理 API 只有在外部 Runner readiness 返回 200、`ready=true` 且模型身份与产品配置一致时才返回 ready。
- 默认 Unavailable Provider 仍可使 P0 服务启动，但明确返回 `counting_available=false`。
- Provider 超时形成 `PROVIDER_TIMEOUT` 终态结果；会话保持 `review_required`，业务数量和候选数量均为空。
- Runner 容器停止后 readiness 返回 503 或不可连接，两者均为 fail-closed；恢复后必须重新明确返回 ready 才放行。
- 故障和恢复场景各使用独立本机测试媒体哈希，遵守组织内 SHA-256 精确去重规则。
- 实验只允许使用 `pig-inventory-p1-fault` 项目名；成功后移除该项目容器和网络，不删除卷，也不操作 `pig-inventory-p0`。

本方案只验证产品边界行为，不代替真实权重的冷启动时长、GPU 资源、业务准确率或生产告警平台验收。
