# P1 确认盘点报表导出方案对比

更新时间：2026-09-01

## 结论

在现有 Spring 业务主干内增量加入 Apache PDFBox 3.0.8 与 Apache POI 5.5.1，不引入独立报表平台，也不让浏览器重新拼装业务报表。两种格式共享同一个组织内、仅 `confirmed` 状态的数据投影；导出范围最多 366 个自然日、最多 10,000 条记录，超过边界明确拒绝。

## 已核实候选

| 候选 | 仓库证据与许可 | 可迁移模式 | 当前项目判断 |
|---|---|---|---|
| [Apache POI](https://github.com/apache/poi) | Apache-2.0；官方 Java Office OOXML 实现，包含 XSSF/SXSSF | 类型化单元格、样式、冻结窗格、筛选与公式 | 采用 5.5.1。当前上限 10,000 行，无需先承担流式写入的额外复杂度 |
| [Apache PDFBox](https://github.com/apache/pdfbox) | Apache-2.0；官方能力覆盖 PDF 创建、操作和文本提取 | 直接绘制可分页表格、嵌入字体、生成后文本回读 | 采用 3.0.8。适合当前固定版式和较少依赖的服务端实现 |
| [fastexcel](https://github.com/dhatim/fastexcel) | Apache-2.0；README 明确偏低内存写入并支持基础样式 | 大数据量顺序流式写出 | 暂不采用。若未来上限显著超过 10,000 行，可在保持投影合同不变的前提下替换 XLSX 渲染器 |
| [JasperReports](https://github.com/Jaspersoft/jasperreports) | LGPL-3.0；完整报表引擎与模板体系 | 模板驱动、复杂分页、跨格式输出 | 拒绝。当前需求不需要报表服务器/模板运行时，许可审查、模板迁移和运维成本高于收益 |
| [OpenPDF](https://github.com/LibrePDF/OpenPDF) | MPL-2.0 或 LGPL-2.1；可创建 PDF | 高层文档 API | 暂不采用。能力足够，但项目可用 PDFBox 获得更简单的 Apache-2.0 依赖边界 |

## 与本项目的适配

- 数据权威：查询从 `inventory_session` 出发，强制 `status = 'confirmed'` 并按当前认证组织过滤；不导出候选数、失败信息、模型身份、媒体标识或内部对象 URL。
- 权限：沿用现有报表查看权限 `assertCanView`。更细 RBAC 是后续独立任务，不在只读导出中提前改变现有授权语义。
- 隐私与安全：文件名只使用日期；业务字符串以 XLSX 文本单元格写入，绝不解析为公式；响应添加下载内容类型与 UTF-8 Content-Disposition。
- 可维护性：PDF 与 XLSX 渲染器只消费同一不可变快照。未来替换库或增加模板不会改变查询和权限边界。
- 中文字体：容器安装 Apache 许可的 Droid Sans Fallback，路径由 `REPORT_PDF_FONT_PATH` 显式配置；Windows 本地开发可探测系统中文字体。找不到可嵌入字体时失败关闭，不生成乱码文件。
- 语义：摘要只展示“确认记录数”，不跨日期累加猪只数量，避免把多日同一栏舍盘点误当存量总和。

## 实施边界

1. OpenAPI 先定义 `GET /inventory-reports/exports/{format}?from=&to=`，格式限定为 `pdf` 或 `xlsx`。
2. 应用服务校验日期顺序、366 天上限和 10,000 行上限，再把同一快照交给两个渲染器。
3. PDF 使用 A4 分页、重复表头和页码；XLSX 使用“摘要”“已确认盘点”两张表、类型化日期/数量、冻结首行与自动筛选。
4. 自动化同时验证组织隔离、状态过滤、字段白名单、公式注入边界、PDF 文本可提取、XLSX 结构与响应头。

## 迁移与回退

该实现不需要 Flyway 迁移，也不改变现有日报/综合报表响应。若依赖或版式出现问题，可只撤回导出端点和渲染器；原报表 API、确认流程及数据库权威不受影响。
