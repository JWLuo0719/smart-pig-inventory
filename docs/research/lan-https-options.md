# 局域网 HTTPS 方案比较

2026-09-11，通过 GitHub 仓库搜索（local https certificates、multicast dns javascript）及官方 README、许可和仓库元数据核验。目标是保留现有 nginx/Flutter/版本化推理契约，支持同网验收；无公网服务器资源，不进行架构替换。

| 候选 | 仓库证据与许可 | 可借鉴点、边界与代价 |
|---|---|---|
| [mkcert](https://github.com/FiloSottile/mkcert) | README 本机 CA 工作流，BSD-3-Clause；核验时最近 push 2024-08-13 | 借鉴私有 CA；不安装工具/系统根证书。仅验收 App 信任指定 CA，避免扩大系统信任。自行管理有效期，换 CA 需要重建候选包。 |
| [Caddy](https://github.com/caddyserver/caddy) | README 自动 HTTPS，Apache-2.0；最近 push 2026-09-09 | 借鉴内部 TLS 管理理念；现有 nginx 足够，不引入新网关及证书存储生命周期。没有复制其代码。 |
| [multicast-dns](https://github.com/mafintosh/multicast-dns) | README query/respond/interface、MIT；最近 push 2024-06-14 | 仅在本机验收工具采用固定 7.2.5 与 lockfile，保留依赖许可。A 记录替代 APK 内固定 IP；mDNS 不是认证，真正的服务器身份由 TLS 保证。需 UDP5353 与组播支持，旧设备/AP 隔离有兼容成本。 |

本机客户端实测专用 CA、正确域名通过，错误 CA/主机名失败。不是手机兼容性证据。[Android 官方 DNS Resolver 文档](https://source.android.com/docs/core/ota/modular-system/dns-resolver)说明 .local mDNS 支持仍与设备实现有关，现场必须核验。Flutter 使用 [Dart SecurityContext](https://api.dart.dev/dart-io/SecurityContext-class.html)，无证书错误绕过。公开 CA 可随 APK 分发，服务私钥受限保存在忽略目录；真实研究图片不进入工具源码或仓库。

以上选择是基于本项目现有栈的工程判断；没有整栈集成或拷贝外部实现。Review Hub 本次未检索到相关经验，不能声称知识改变了结论。
