# 私有缩略图增量实现对照（2026-10-23）

需求来自PRD P0的对象存储缩略图，以及功能收口计划的按栏日期图库。审查发现原实现仅有`thumbnail_key`列、列表仍下载原图，因此本轮补充真实派生图；不改变原图、候选、检测坐标和上传合同。以下为GitHub连接器从官方仓库取得的证据，不复制第三方实现。

| 对照 | 已验证事实 | 适用模式与取舍 |
|---|---|---|
| [Immich](https://github.com/immich-app/immich) | [API测试](https://github.com/immich-app/immich/blob/9666eadc5bbf81b91d2f5c10fb2630685dea8be7/e2e/src/specs/server/api/asset.e2e-spec.ts)分别测试带Authorization读取thumbnail和original，并检查派生预览不含GPS；仓库API标注AGPL-3.0，未归档，最近推送2026-10-23 | 仅借鉴私有预览与原图独立、剥离元数据的产品边界；不复制、链接或部署其代码，不引入其数据库/队列/图片栈。直接接入会增加许可、权限映射与运维成本。 |
| [PhotoPrism](https://github.com/photoprism/photoprism) | [缩略图入口](https://github.com/photoprism/photoprism/blob/50886dddafd743023e1f83d19aa146711fe0df66/internal/photoprism/mediafile_thumbs.go)使用命名尺寸及方向生成派生图；仓库API许可为NOASSERTION，未归档，最近推送2026-10-23 | 仅借鉴固定尺寸派生物和缓存，不采纳Go服务、数据库或源码；NOASSERTION不能当作可用于主线的宽松许可。与当前证据不可变模型兼容的只是派生图不替换原图这一独立需求。 |
| [TwelveMonkeys](https://github.com/haraldk/TwelveMonkeys) | [README](https://github.com/haraldk/TwelveMonkeys/blob/57750b651f278aac3dd970804123d7f72ee4c75c/README.md)展示ImageIO读取参数中的subsampling；README与仓库API均标注BSD-3-Clause，未归档，最近推送2026-10-22 | Java接口模式匹配当前Spring/JDK；本轮使用JDK现有JPEG/PNG reader和有界抽样，不新增运行时依赖或额外格式插件。扩展HEIC/RAW会增加native依赖、内存和许可审核成本，当前明确不支持缩略图但保留原图入口。 |

## 本项目决定

兼容新增`GET /media-assets/{assetId}/thumbnail`，固定最长边320像素JPEG，保持比例、不放大、应用JPEG内嵌EXIF方向并移除元数据。每次读取都经当前组织授权和未删除检查；对象仅在私有MinIO缓存，响应不公开对象路径或URL，浏览器使用no-store。缓存沿用既有列，无数据库迁移；派生失败不影响原图上传、确认或原图读取。

原图解码先检查压缩大小、尺寸和像素数，再抽样；限制同时派生任务。视频、HEIC或坏图返回明确不支持/不可解码状态，客户端显示占位和原图入口；存储或负载错误可恢复。列表只用缩略图，复核与检测框继续读原图。以上适配判断为本项目设计推论，成功与性能仍须由本项目合成测试及后置运行验收分别证明。
