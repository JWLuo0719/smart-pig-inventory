# 许可证与权属边界

本文件是依赖准入规则，不替代各依赖自身许可证。

## 项目源码

- 本仓库原创产品源码按根目录 [`LICENSE`](LICENSE) 的 Apache-2.0 许可发布；不包含任何模型权重、外部研究数据、真实媒体、口令或生产配置。
- `eg/` 属于学长项目参照物，已申请软件著作权。不得提交、发布、复制实现或在其上直接二次开发。
- 当前主干采用 clean-room 方式：只吸收经重新表述的需求、信息层级和业务规则，代码、数据库迁移、接口命名、文案和视觉素材均独立实现。
- 用户提供但权属未明确的模型权重、数据集和品牌资产不得进入公开制品。

## 依赖准入

- 可评估：Spring Boot（Apache-2.0）、MyBatis（Apache-2.0）、MySQL Community（GPLv2/FOSS 例外，部署前复核发行方式）、Flutter（BSD-3-Clause）、Drift（MIT）、Next.js（MIT）、FastAPI（MIT）、Celery（BSD-3-Clause）、Redis（按所锁版本复核）、MinIO（AGPLv3，当前仅作为可替换的独立对象存储服务）。
- AGPL/GPL 组件不得以源码复制、链接库或不可替换的产品内嵌方式进入主干，除非完成专项法务评估。
- Ultralytics 及相关 Flutter Demo 只能在隔离 PoC 中评估，不作为默认产品依赖。
- 任何 Apache-2.0 代码移植必须保留许可证、版权和修改说明；当前主干没有移植第三方源码。

## 发布前门禁

CI 应输出 Java、Node、Python 和 Flutter 依赖清单；发布负责人复核许可证、模型权重来源、数据授权和 `NOTICE`。许可证不明确时默认拒绝发布，而不是推测许可。
