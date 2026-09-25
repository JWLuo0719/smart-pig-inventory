# 产品设计方案 V2（重构版 · 评审修订）

> 配套需求基线：`docs/requirements-v2.md`（**先读它**：六条公理 A1–A6 与冲突裁决 C1–C8 是本文所有设计的裁判依据）。
> 本文取代 `docs/product-development-plan.md` 与 `docs/v1-technical-development.md` 中与"事件中心 + 单级 barn_id"相关的设计表述。
> **本版为独立评审后的修订版**：新增实现归属表（§2.1）、几何标定域（§1.1）、身份与权限（§1.5）、
> 安全兜底分层（§2.2）、按证据重写的代码映射（§6），并修正了不变量与验收口径（§5、§7）。

---

## 0. 一页总图

**产品定位（一句话）**：以**栏舍（猪圈）为原子单元**的猪场感知—决策—执行闭环；视觉盘点负责**慢变量（头数）的校准**，环境与采食数据驱动**快变量的日常控制**，证据全程可反查、可审计。

```
        ┌──────────────── 中心 / 云：治理与聚合（非实时） ────────────────┐
        │  主数据真源与金蝶对账 · 证据账本 · 盘点聚合 · 复核审计 · 报表   │
        └────────▲────────────────────────────────────▲────────────────┘
                 │ 幂等同步（允许延迟、断点续传）        │ 策略与设定值下发
        ┌────────┴────────────────────────────────────┴────────────────┐
        │  边缘（场内主机）：本地推理 · 证据缓存 · 策略计算 · 本地看板   │
        └────────▲────────────────────────────────────▲────────────────┘
                 │ 局域网 / 离线队列（弱网容忍）        │ 设定值下发（非安全指令）
        ┌────────┴───────────┐            ┌───────────┴──────────────────┐
        │ 端：App / PWA      │            │ PLC / 经认证控制器            │
        │ 扫码·拍照·浏览·确认 │            │ 硬联锁 + SafetyDefault        │
        └────────────────────┘            └───────────┬──────────────────┘
                                                      │ 本地 IO / 总线
                                          ┌───────────┴──────────────────┐
                                          │ 执行器与传感器（按圈粒度）    │
                                          │ 料线·风机·湿帘·水阀·报警      │
                                          └──────────────────────────────┘
```

**三条架构第一原则**：
1. **控制闭环的"策略"在边缘，"安全"在 PLC**——生命安全兜底不依赖通用主机存活（§2.2）；
2. **证据上传失败不得影响控制**（A3 + A6）；
3. **归属、边界、时间三个"真源"必须先立住**，否则计数与控制的输入全是脏的（§1.1、§4）。

---

## 1. 领域模型

### 1.1 主数据与几何标定（强一致，以 `penId` 汇聚一切）

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `Tenant` | `tenantId, name, isolation` | 多租户/数据隔离；隔离级别需在 M10 中定（独立库 / 行级） |
| `Organization` | `orgId, erpCode, name, source=ERP` | 金蝶侧组织，唯一真源在 ERP |
| `Farm` | `farmId, farmCode, name, orgId, timezone, source=ERP\|LOCAL` | `timezone` 是 `businessDate` 判定的依据（M11） |
| `Building` | `buildingId, buildingCode, farmId, source=LOCAL` | 栋级；ERP 通常没有，本地为真源 |
| `Pen` | `penId, penCode, buildingId, capacity, status, source=LOCAL` | **原子单元** |
| `PenTag` | `penId, tagType=QR\|NFC, tagValue` | 栏舍牌；**离线可解析**（标签→penId 映射随主数据缓存下发，见 §2.3） |
| `Device` | `deviceId, penId?, type=camera\|sensor\|actuator, protocol, addr` | 摄像头机位是几何标定的主体之一 |
| **`PenBoundary`** | `boundaryId, penId, deviceId, poseId, polygon[], calibratedBy, calibratedAt, version, validUntil` | **栏舍在画面中的边界（按机位）**；L3 越界过滤、互斥 ROI 分区的几何真源 |
| **`CameraPose`** | `poseId, deviceId, penId, mountDesc, installedAt, driftCheck[]` | 机位姿态；机位变动 → 旧标定失效 |
| `Calibration` | `calibrationId, scope(pen\|camera), version, operator, at, expiresAt, status(active\|expired\|revoked)` | 标定版本；所有计数结果记录所用 `boundaryVersion` |

**新增理由（评审发现 2）**：M5 的越界过滤、C4 的互斥 ROI 分区、P3 的"ROI 裁剪"三条 Must 全部依赖
"栏舍边界在照片坐标系中的位置"，而此前领域模型中**完全没有几何真源**，且 `Asset.roi` 是每图一个矩形，
表达不了多机位、非矩形区域与多段分区。**标定是产品能力，不是现场配合事项**：它必须有责任人、版本、
有效期与失效规则（M13）。

**真源规则（裁决 C7）**：按**字段级**判定——ERP 拥有的字段同步时覆盖本地，本地扩展字段（栋/栏舍、设备、
控制点、几何标定）永不被同步覆盖；每次同步产出**对账报告**（新增/变更/冲突/失效），冲突进人工队列，
不静默取胜。

### 1.2 证据平面（最终一致，append-only）

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `CaptureSession` | `captureSetId, penId, businessDate, captureKind(single\|left_center_right\|video), clientPackageId, deviceId, operator, bindMode(scan\|manual), capturedAt, receivedAt` | 一次"为某个栏舍拍的一组证据"；对齐 App 契约字段名 |
| `Asset` | `assetId, captureSetId, sha256, kind(original\|preview\|frames), viewPosition(single\|left\|center\|right\|video), roi, exif白名单, width/height, byteSize, blobRef, capturedAt` | 单张照片/视频/预览图；`sha256` 全局唯一约束 |
| `AssetRef` | `assetId, refType=inventory\|review\|report, refId, lockedAt` | 证据被引用即锁定；**删除前必须检查引用** |
| `Asset.mutation` | `state(ingested\|referenced\|voided), voidReason, voidBy, voidAt` | 作废是状态转移，不是物理删除 |
| **`AdjudicationItem`** | `itemId, refType=unassignedAsset\|outOfBoundTarget\|conflict, refId, reason, assignee, slaDueAt, status(open\|resolved\|escalated), resolution, closedBy, closedAt` | **待归属池 / 待裁决池的实体化**；此前只有"池"的概念，没有出口（评审发现 10） |

**去重三层**（对应需求 4/8；**去重域在评审后扩大**）：

- **L1 文件级**：`sha256` 全局唯一 → 同一张照片在任何栏舍都只能存在一次；
- **L2 视角级**：同一 `captureSet` 内 `viewPosition` 唯一；**并扩展为 `penId × businessDate` 级**——
  同栏同日多个采集包之间也要保证互斥分区、重叠带只归一段（评审发现 4：长栏舍、补拍遮挡、分两趟拍
  必然产生第二个包，而外部契约一个包最多 `assets[1..3]`）；
- **L3 跨栏舍**：目标框与 `PenBoundary` 求交；越界或跨边界的目标进 `AdjudicationItem`，**不静默计入任何栏舍**。

### 1.3 盘点平面

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `InventorySession` | `sessionId, penId, businessDate, captureSets[], modelVersion, boundaryVersion, status, count, interval, qualityFlags[]` | **一次盘点 = 一个会话**；头数落在栏舍上（A1） |
| `CountResult` | `sessionId, count, lower, upper, perViewCounts[], excludedOutOfBounds, evidenceRefs[]` | 输出**数量 + 波动区间 + 证据**，而非单一数字 |
| `Review` | `sessionId, reviewer, credential, decision(confirm\|correct\|reject), correctedCount, note, at` | 人工签字（A5）；**分级签字**见 §3 P4 |
| `Aggregation` | `aggregationId, penId, period, sessionIds[], method, value, validFrom, validTo` | 综合盘点；**只在无存栏变动区间内聚合**（C3） |
| `HerdChange` | `penId, type(transfer\|exit\|death\|merge), delta, at, source` | 存栏变动事件；聚合的合法性边界由它界定 |

**状态机**：
```
Asset:              ingested ──引用──> referenced ──后台作废──> voided
AdjudicationItem:   open ──处理──> resolved        open ──超时──> escalated
InventorySession:   draft → submitted → computing → review_required → confirmed ──更正──> confirmed(v2)
                                                          └→ rejected
Aggregation:        proposed ──人工确认──> effective ──存栏变动──> superseded
```

### 1.4 控制平面（策略在边缘，安全在 PLC）

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `ControlPoint` | `pointId, penId, actuatorType, riskLevel(low\|medium\|high), whitelisted, protocol, addr, min/max, rateLimit` | **一个控制点 = 一个可独立控制的执行器** |
| `Setpoint` | `penId, pointId, value, source(auto\|suggested\|manual), basis(herdCount\|ageCurve\|sensor), effectiveAt` | `basis` 记录它基于什么算出来，可追溯 |
| `Command` | `commandId, pointId, targetValue, issuedBy, mode(auto\|approved\|manual), status, dispatchedAt, ackAt, result` | 指令与回执（S6） |
| `Interlock` | `interlockId, penId?, inputs[枚举], condition, action, priority, bypassPolicy, hostedBy` | **硬联锁，部署在 PLC/认证控制器**；`inputs` 为**枚举白名单**（不含视觉，见不变量 10） |
| `SafetyDefault` | `scope(pen\|building\|farm), condition(netLost\|controllerLost\|powerLost\|hostLost), action, hostedBy` | fail-safe 默认；**不依赖通用主机存活** |

**安全承载分层（评审发现 7 的修订）**：

| 职责 | 承载方 | 理由 |
|---|---|---|
| 硬联锁、`SafetyDefault`、断电/断网兜底 | **PLC / 经认证控制器** | 生命安全不能依赖一台同时跑推理的通用主机 |
| 策略计算、建议设定值、白名单裁决 | 边缘主机 | 需要数据与算力，但不承担安全兜底 |
| 高风险设定值的人工确认 | 端 + 边缘 | A5 |

**控制模式白名单（A5 + C6）**：

| 风险级 | 动作 | 允许的最高自动化 |
|---|---|---|
| 低 | 照明、报警、清粪定时 | 自动 |
| 中 | 加药泵、水阀、分区降温 | 人工确认后下发 |
| 高 | **通风最小量、下料量** | 长期保留人工确认或仅建议 |

### 1.5 身份与权限（评审发现 6 补充）

| 实体 | 关键字段 | 说明 |
|---|---|---|
| `User` | `userId, tenantId, name, accountSource, status` | 账号来源需在 M10 中定（是否复用 App/Spring 账号体系） |
| `Role` | `roleId, scope(collect\|review\|admin\|control), penScope[]` | 采集 / 复核 / 管理 / 控制，可限定栏舍范围 |
| `Credential` | `userId, deviceKeyId, publicKey, issuedAt, revokedAt` | **离线签字的凭据**：端侧私钥签名 + 服务端时间戳，保证断网确认可追溯到人且防抵赖 |

---

## 2. 架构

### 2.1 三平面隔离 + 实现归属（本文最重要的两张表）

| | 主数据平面 | 证据平面 | 控制平面 |
|---|---|---|---|
| 接口风格 | 批量同步 + 对账 | 幂等上传 + 事件回填 | 本地总线（策略 → PLC） |
| 一致性 | 强一致 | 最终一致 | 本地强一致 |
| 延迟容忍 | 天级 | 分钟~小时 | **秒级** |
| 存储 | 中心库 + 边缘只读副本 | 对象存储 + 元数据库 + 边缘队列 | PLC + 边缘本地库 + 审计流 |
| 失效域与后果 | 同步失败 → **禁止新建采集**（避免孤儿归属） | 上传失败 → 本地保留，不出业务值 | 联锁/控制器不可用 → **进入 fail-safe 默认** |

**实现归属表（评审发现 1：不裁此表必然建出两套真相）**

> 前提：`docs/app-integration-contract.md` 是**外部实测事实**，本仓库不得自行推翻。
> 若沿用其推荐路径 B（App 管交互、Spring 管主数据与账本、本 Agent 管推理），则归属如下。
> **此表需与 Spring/App 团队共同签字确认后再动工**（`requirements-v2.md` §6 第 1 条）。

| 能力 | 端 App | 边缘主机 | 本 Agent（推理 Provider） | Spring/中心 | PLC |
|---|---|---|---|---|---|
| 扫码归属、拍照、浏览 | ✅ 主 | — | — | 主数据支持 | — |
| 采集包 4 步上传与幂等 | 发起 | 缓存转发 | **不实现**（除非选路径 A） | ✅ 主 | — |
| 组织/猪场主数据、金蝶对账 | — | 只读副本 | 只读消费 | ✅ 主 | — |
| 栋/栏舍/标签/设备/标定 | 只读 | 缓存 | 只读消费 | ✅ 主 | — |
| 证据账本（资产/引用/作废） | 本地队列 | 缓存 | 只读引用 | ✅ 主 | — |
| 推理与质量门 | 可选预估 | 调度 | ✅ **主** | 存储结果 | — |
| 盘点会话与聚合 | 展示 | 计算候选 | 提供计数 | ✅ 主 | — |
| 复核与签字 | 采集签字 | 校验 | — | ✅ 主 | — |
| 控制策略与设定值 | 确认 | ✅ 主 | — | 只读同步 | 执行 |
| 硬联锁与 fail-safe | — | 下发 | — | — | ✅ **主** |

**本仓库（Agent）在 R0/R1 的真实交付物**（避免"既做 Provider 又自建账本"的矛盾）：

- **必交**：推理与质量门的契约化（`DetectionResult` 扩展）、按 `penId` + `boundaryVersion` 的 ROI 裁剪与
  越界判定算法、回放门槛扩展、计数区间与质量标志的输出格式；
- **代管（可先做、后迁 Spring）**：主数据三级树与证据账本的最小实现，用于无 Spring 环境下的联调与演示
  （与现有 `tools/fake_upstream.py` 同一性质），**迁走后本仓库不再持有该数据**；
- **不交**：采集包 4 步端点、JWT 身份、对象存储语义（这些在 Spring 侧已有真源）。

### 2.2 端 — 边 — 云职责

| 层 | 必须能做的事 | 明确不做的事 |
|---|---|---|
| 端（App/PWA） | 扫码归属、拍照/录像、本地队列、照片库翻阅、复核确认、控制确认、手动兜底 | 不出业务值；不做需要全局数据的一致性判断 |
| 边缘（场内主机） | 本地推理、证据缓存与重传、策略与设定值计算、本地看板与声光报警触发、断网自治 | **不承担生命安全兜底**（交 PLC）；不做跨场聚合与财务口径 |
| PLC / 认证控制器 | 硬联锁、`SafetyDefault`、断电/断网/主机失联兜底 | 不做业务计算 |
| 中心/云 | 主数据真源与对账、证据账本归档、盘点聚合、审计与报表、模型门槛 | **不参与实时控制回路** |

### 2.3 断网自治矩阵（A6 的可验收形式）

| 能力 | 断网可用 | 降级行为 |
|---|---|---|
| 扫码归属 + 采集 | ✅ | 正常；**标签→penId 映射随主数据缓存下发，离线可解析**；离线期间新建的栏舍/标签不可用（不产生孤儿归属） |
| 照片库翻阅 / 未引用删除 | ✅ | 正常 |
| 端侧预估值 | ✅（可选） | 标注 `preliminary`，**不出业务值** |
| 正式计数 | ⛔ | 入队，标记"待计算" |
| 复核确认 | ✅ | **本地凭证签名**确认 + `pending-sync`，恢复后幂等补账 |
| 主数据变更（新建栋/栏舍） | ⛔ | 只读缓存；离线期间的变更在恢复后走冲突队列（C7） |
| 控制闭环 | ✅ | 策略在边缘、**安全在 PLC**，用最后一次已同步的策略 |
| 远程通知/告警推送 | ⛔ | 本地声光报警必须独立可用 |

**时间口径（评审发现 8）**：`businessDate` **由服务端按 `Farm.timezone` 判定**，端侧时间只作参考；
服务端记录 `receivedAt`；端侧时钟偏移超过阈值（如 ±10 分钟）时，落账时间改用服务端时间并打标
`clockSkewFlag`。理由：`businessDate` 是会话与聚合的主键，一旦被手机时钟污染，跨日会静默错分；
且现有代码 `models.py:67` 的 `utc_now_iso()` 实际取的是**本地时间**（函数名误导），`poller.py:161`
还会回退到**文件 mtime**（复制即变）——这两处在 V2 必须整改。

---

## 3. 六条核心流水线

每条都写清"失败时会发生什么"，因为**失败路径才是产品的真实行为**。

### P1 主数据同步
金蝶 → 校验（编码唯一、层级完整）→ 字段级合并（本地扩展字段保护）→ 对账报告 → 冲突入人工队列
**失败**：同步失败则冻结新建（采集仍可用已有栏舍），不产生孤儿归属。

### P2 采集与归属
扫码（一次扫码进入该栏舍采集会话，**支持连拍，不必每张都扫**）→ 拍照/录像 → 本地写队列 →
计算 `sha256` → **两级上传（预览图优先，原图延后补传）** → 幂等上传（`clientPackageId` + `X-Idempotency-Key`）→
服务端校验（归属存在、`viewPosition` 唯一、`roi` 合法、时间偏移）→ 入账本
**缺 `penId` 一律拒绝入账**并进 `AdjudicationItem`（不变量 2）。**现有代码的 `A01`/`demo` 默认值必须删除**
（`server.py:349/354/355/364/365`、`agent.py:134/136`、`static/index.html:415`、`poller.py:129` 的 `farm_id="edge"`）。
**视频口径**（三选一，需客户定，见 `requirements-v2.md` §6 第 6 条）：① 边缘抽帧并计入同一 session；
② 端侧按 `left/center/right` 上传关键帧；③ 视频仅作证据、不参与计数。
**失败**：重复哈希 → 返回已存在资产（不新建）；归属不存在 → 拒绝入账并提示。

### P3 计数（每 `captureSet` 一次，跨包按 `penId × businessDate` 合并去重）
质量门 → **按 `boundaryVersion` 裁剪到本栏舍** → 检测 → L2 视角去重（互斥分区）→ L3 越界过滤 →
汇总 `count + interval + qualityFlags` + 证据 + `boundaryVersion`

**质量门必须是"真能触发"的（评审发现 3）**：现状是 Mock 的 `coverage` 靠随机数造
（`detector.py:113-119`），而 **real 路径 `coverage=None`**（`detector.py:300`、`:391`），
`state.py:49` 在 `coverage is None` 时直接跳过覆盖率判断，`config.py:153` 的 `min_coverage=0.80`
在真机模式下形同虚设；且 `_probe_image_quality`（`detector.py:306-324`）只判模糊与亮度，**没有遮挡判定**。
因此 V2 的质量门定义必须显式给出：① 覆盖率如何计算（栏舍边界内的有效像素/边界面积）；
② 遮挡判定口径（料槽/墙体固定盲区 + 前景遮挡比例）；③ 阈值与失败动作（`review_required` + 原因码）；
④ 验收要求 **real 模型路径下可触发**。

**失败/不达标**：输出 `review_required` + 原因，**不硬报数字**（M6）。

### P4 复核与锁定（含待裁决排水）
展示证据与区间 → **分级签字**（低风险/低价值批量确认；异常与高风险逐条确认）→ 生成 `Review`（含离线签名凭据）→
引用资产置 `referenced`（锁定）→ 审计；同时**排空 `AdjudicationItem`**：指派 → 处理 → 结论 → 超时升级
**失败**：无人复核时保持 `review_required`，绝不自动转正；待裁决池超过 SLA 时按 §6 第 8 条的决定
（阻塞当日报告 / 仅标注）。

### P5 聚合（综合盘点）
取期间会话 → 检查 `HerdChange` 区间 → 剔除跨越变动日的会话 → 稳健聚合（去极值 + 质量加权 / 中位数）→
输出建议值 + 波动区间 → 人工确认后生效
**失败**：区间内有未记录的变动 → 拒绝聚合并提示先补录变动。

### P6 控制
读取**最近一次已复核**的存栏快照 + 日龄/体重曲线 → 生成 `Setpoint`（记录 `basis`）→ 白名单判断
（自动 / 需确认 / 仅建议）→ **交 PLC 做联锁校验并执行** → 回执 → 反馈修正（采食/环境）
**失败**：PLC 不可用或联锁未通过 → 进入 `SafetyDefault`（通风不停、开窗、报警），禁止下发高风险指令。

---

## 4. 数据契约（关键字段，优先复用 App 现有命名）

为降低与既有 App/Spring 的集成成本，**沿用其字段名**：`organizationId / penId / businessDate / captureKind / viewPosition / roi / sha256 / clientPackageId / X-Idempotency-Key`。

```jsonc
// 采集包（提交清单的核心字段；新增接收时间与时钟偏移标记）
{
  "captureSetId": "uuid", "clientPackageId": "uuid",
  "organizationId": "uuid", "penId": "uuid", "businessDate": "2026-09-25",
  "captureKind": "left_center_right",           // single | left_center_right | video
  "bindMode": "scan",                            // scan | manual
  "capturedBy": "user-id", "capturedAt": "2026-09-25T08:31:00+08:00",
  "receivedAt": "2026-09-25T09:12:44+08:00",     // 服务端接收时间（判 businessDate 的依据）
  "clockSkewFlag": false,                        // 端侧时钟偏移超阈值时置真
  "assets": [{
    "assetId": "uuid", "kind": "original",       // original | preview | frames
    "viewPosition": "left",                      // single|left|center|right|video（组内唯一）
    "sha256": "…64位小写…", "byteSize": 812345, "mediaType": "image/jpeg",
    "width": 4000, "height": 3000,
    "roi": {"x":0.05,"y":0.10,"width":0.90,"height":0.85},   // 拍摄裁剪；null=整图
    "exif": {"orientation":1,"make":"…","model":"…"}          // 白名单，禁 GPS/自由文本
  }]
}
```

> 说明：`Asset.roi` 是**该张照片自身的拍摄裁剪**，与 `PenBoundary`（栏舍在画面中的几何边界，
> 按机位与版本管理）是两个不同的东西，禁止混用同一字段。

```jsonc
// 盘点结果（对外只给"值 + 区间 + 证据"，不给裸数字）
{
  "sessionId": "uuid", "penId": "uuid", "businessDate": "2026-09-25",
  "status": "review_required",                    // computing|review_required|confirmed|rejected
  "count": 187, "lower": 182, "upper": 193,
  "perViewCounts": {"left": 64, "center": 62, "right": 61},
  "excludedOutOfBounds": 5,                       // 越界目标数（进待裁决池）
  "qualityFlags": ["OCCLUSION_TROUGH", "COVERAGE_LOW"],
  "evidenceRefs": ["asset-id-1", "asset-id-2", "asset-id-3"],
  "modelVersion": "dcr-softnms-yolov13-v1",
  "boundaryVersion": "calib-2026-09-20-v3"        // 本次计数所用几何标定版本
}
```

---

## 5. 核心不变量（评审后修订，口径可测）

| # | 不变量 | 验证方式 |
|---|---|---|
| 1 | **不重**：任一目标只能归属一个栏舍，`Σ 栏舍 = 栋 = 场` 无重复计入 | 自动（可测） |
| 1b | **不漏是质量目标**，不是不变量：以"越界待裁决率 + 覆盖率"作为验收指标 | 统计口径验收 |
| 2 | 待归属/待裁决池中的资产不得出现在任何 `CountResult` 中 | 自动 |
| 3 | 任一业务值都能反查到其全部证据、`boundaryVersion` 与 `modelVersion` | 自动 |
| 4 | `referenced` 资产删除必须失败；作废必须带操作者/时间/原因 | 自动 |
| 5 | 同 `clientPackageId`/幂等键重放不产生第二条盘点 | 自动（弱网重放脚本） |
| 6 | 业务值更正产生新版本，历史版本可查 | 自动 |
| 7 | `review_required` 的计数不得写入业务值，**更不得驱动控制** | 自动 |
| 8 | 越界目标必须出现在 `excludedOutOfBounds` 或 `AdjudicationItem` | 自动 |
| 9a | 服务/进程异常时执行 `SafetyDefault`，高风险指令不得下发 | 软件测试 |
| 9b | **断电/主机被杀/磁盘满时联锁仍动作** | **HIL（硬件在环）测试**，纯软件测不了 |
| 10 | `Interlock.inputs` 取自**枚举白名单且不含视觉**，配置加载期校验 | 自动（配置校验） |
| 11 | 同输入 → 同结果，**限定同一 `modelVersion` + `boundaryVersion`**；`preliminary` 预估通道不在此列 | 自动（回放门槛） |
| 12 | 断网期间采集的资产在恢复后 100% 同步且无重复 | 依赖 App/Spring 侧，"本仓库单独不可验证" |

> 口径提醒：MAE 必须写明统计口径——按会话还是按日、是否含三视角叠加、数据集与标注规范。
> 现有基线是"头/图"（`docs/v1-gap-list.md` §5），改为"头/圈"后三视角误差会叠加，**不可直接沿用**。

---

## 6. 与现有代码的映射（按证据重写）

> 评审发现：初版映射表存在三类失真（把需新建说成保留、把已有说成新建、把不等价说成等价）。
> 下表以实际代码为准（行号为写作时核对结果）。

| 现有资产 | 实际现状（证据） | 处置 |
|---|---|---|
| `detector.py` | 三类适配器齐全；但 `DetectionResult` **没有 ROI/裁剪偏移字段**（`detector.py:29-36`），real 路径 `coverage=None`（`:300`、`:391`） | **保留 + 扩展**：新增裁剪偏移字段与覆盖率计算 |
| `evidence.py` | 标注图按 `detection.image_width` 缩放（`evidence.py:101`）；ROI 裁剪后**必然错位** | **必须改造** |
| `replay.py` + 基线 | 全链路回放与门槛可用；夹具命名支持栏舍（`replay.py:60-74`） | 保留；扩展为按栏舍聚合前后对比 |
| `state.py` / `risk.py` | 质量门实际在 `state.py:43-51`（`risk.py:44` 只是消费它）；`risk.py` 是告警规则引擎 | **保留为告警引擎**；质量门**扩展**为可触发；**控制联锁是全新引擎**（与 `risk.py` 无共享语义） |
| `poller.py` | 幂等基于 `name:size:mtime_ns`（`poller.py:214`），与 L1 的 sha256 口径不一致；只接受 `config.barns` 内的栏舍（`:92-94`），未知名直接跳过；`farm_id` 硬编码 `"edge"`（`:129`）；时间回退 mtime（`:161`） | **改造**：内容哈希幂等、`penId` 来自主数据（消除 `config.json` 这一"第二主数据源"）、时间取值规范化 |
| `storage.py` | `audit_log`（`:42`）与 `analyze_requests`（`:52`）**已存在** | 初版"新增审计与幂等表"表述**有误**；实际需新增的是资产账本、盘点会话、标定、待裁决、控制相关表 |
| `models.py` | 有 `farm_id`（`:155`）与 `suggested_actions`（`:162`）；`utc_now_iso()` 实为本地时间（`:67-68`，命名误导） | 扩展：新增 building 级、资产与盘点实体；整改时间取值 |
| ID 规则 | `_ID_PATTERN = ^[\w.:@-]{1,128}$`（`models.py:76`）——**该规则允许连字符，因此 UUID 形式的 `penId` 可以通过**，初版"不接受 UUID"的判断不成立 | 无需改动，仅需放宽长度以容纳复合键 |
| `server.py` / `static/index.html` | `A01` / `demo` 默认值（`server.py:349/354/355/364/365`、`agent.py:134/136`、`index.html:415`） | **删除默认值**，缺失即拒绝入账 |
| 控制相关 | **确认零基础**：`actuator`/`interlock`/`setpoint`/`modbus` 无任何匹配，只有 `suggested_actions` 文本（`models.py:162`、`risk.py` actions_for） | **全新**：执行器适配、联锁（PLC 侧）、指令审计、回执状态机 |
| `config.json` 的 `min_coverage=0.80` | 真机路径下不生效（`config.py:153` + `state.py:49`） | 与质量门改造一并处理 |
| 旧文档 | — | `docs/product-development-plan.md`、`docs/v1-technical-development.md` 部分作废（已加标注） |

---

## 7. 路线图（每阶段有验收与止损点）

| 阶段 | 交付 | 验收 | 止损点 |
|---|---|---|---|
| **R0 单元与归属** | 三级主数据 + `penId` + 扫码归属（离线可解析）+ 待归属池 + 删除 `A01/demo` 默认值 | 未归属率 < 0.1%；编码冲突 0；缺 `penId` 100% 拒绝 | 扫码执行不下去 → 退回强绑定下拉并重估 |
| **R0.5 实现归属裁决** | 与 Spring/App 团队确认 §2.1 归属表并签字 | 归属表无空白格 | **未签字不得进入 R1**（否则返工） |
| **R1 证据账本** | 采集包、L1/L2 去重、状态机、照片/视频库、两级上传 | 同哈希重复 0；锁定后篡改 0；断网 24h 零丢失 | 现场无法接受锁定规则 → 回到 C1 重裁 |
| **R2 栏舍级盘点** | 质量门（**real 路径可触发**）、`PenBoundary` 裁剪、越界过滤、复核与日报 | MAE ≤ 5 头/圈（口径明确）；越界静默计入 = 0 | 质量门拦截率过高 → 先修拍摄规范再谈模型 |
| **R2.5 几何标定** | `PenBoundary`/`CameraPose` 标定流程与工具、版本与失效规则、漂移检测 | 标定后越界判定可复现；机位变动后旧标定自动失效 | 标定成本过高 → 改单视角 + 人工复核（回退方案） |
| **R3 多视角与聚合** | 互斥 ROI 分区、综合盘点、待裁决排除 | 跨视角/跨包重复计入 = 0；聚合保留每日原值 | 分区标定不可行 → 单视角 + 人工复核 |
| **R4 边缘与影子模式** | 边缘推理、控制点建模、建议设定值、异常检测、报警值班链路 | 影子期跑满一个批次；建议 vs 实际对比有改善 | **建议不优于现状 → 不进 R5** |
| **R5 半自动** | 白名单低风险自动 + 高风险人工确认 + PLC 联锁接入 | 指令回执成功率 ≥ 99.9%；误动作率达标 | 误动作超标 → 回退 R4 |
| **R6 闭环** | 通风/下料自动执行 | 联锁测试 100% 通过；**HIL：主机断电/被杀/磁盘满时联锁仍动作**；零安全事故 | 硬件改造未验收 → 不上线 |

**交付节奏的现实预期**：R0–R3 是软件可交付的；**R4 起受硬件与现场条件约束，至少跨一个生产批次**，不是软件迭代能压缩的。

---

## 8. 风险登记册

| # | 风险 | 影响 | 对策 |
|---|---|---|---|
| 1 | 执行器粒度不足（一栋一风机、一条料线管整栋） | **需求不成立** | R0 期完成现场核查，先出硬件改造清单与报价 |
| 2 | **实现归属未裁决**（Agent/Spring 双套真相） | 大面积返工 | R0.5 归属表签字；Agent 侧账本明确为"代管、可迁移" |
| 3 | **几何标定缺失或漂移** | 越界过滤与互斥分区全部失效 | R2.5 独立成阶段；标定版本写入每次计数结果 |
| 4 | 金蝶接口能力未知 | 主数据不可用 | 文件级对账兜底；同步失败冻结新建 |
| 5 | 模型精度不达标（遮挡场景） | 数字不可信 | 质量门 + 区间输出 + 人工复核；先修拍摄规范 |
| 6 | 现场不愿扫码 / 逐条签字太重 | 归属失守、流程被绕过 | 扫码即出栏舍名与上次头数作为即时收益；**分级签字**（低风险批量） |
| 7 | **通用主机承担生命安全兜底** | 事故 | 硬联锁与 `SafetyDefault` 部署在 PLC/认证控制器；HIL 验收 |
| 8 | 带宽与存储超预算（尤其视频） | 弱网上行不可行 | 两级上传（预览优先）；视频口径三选一；M12 预算前置 |
| 9 | 时间口径污染 `businessDate` | 跨日静默错分 | M11：服务端判定 `businessDate` + 时钟偏移标记 |
| 10 | 误控责任无法界定 | 商务不可行 | 影子期 + 白名单 + 合同责任条款 + 保险 |
| 11 | 成本失控（硬件 + 运维） | 项目亏损 | 报价改为"控制点数 × 硬件 + 软件订阅 + 运维"，含安全责任溢价 |

---

## 9. 架构反模式（明确不做）

- ❌ 用同一套接口/同一张表同时承载证据与控制（违反 A3）
- ❌ 云端下发实时控制指令（弱网舍内必挂）
- ❌ **让通用主机承担硬联锁与断电兜底**（违反 A3；安全必须落在 PLC/认证控制器）
- ❌ 视觉计数进安全阈值或联锁输入（违反 C8 / 不变量 10）
- ❌ 物理删除已被引用的证据（违反 A4）
- ❌ 未复核的盘点数写入业务值或驱动控制（违反 A5 / 不变量 7）
- ❌ 主数据未同步成功时允许采集，或缺失 `penId` 用默认值兜底（产生孤儿归属；现存的 `A01`/`demo` 默认值即此反模式）
- ❌ 用同一阈值引擎同时表达"质量门"与"安全联锁"（语义完全不同，必须拆分）
- ❌ 把"手工选栏舍"作为默认归属方式（应扫码，弱绑定只作补充）
- ❌ 把 `Asset.roi`（拍摄裁剪）与 `PenBoundary`（几何边界）混用同一字段
- ❌ 让"待裁决池"只有入口没有出口（无责任人、无时限、无升级）
