# 试点设备与部署基线

状态：推荐基线，待模型实测后锁定  
日期：2026-08-20

## 移动端验收

| 层级 | 设备 | 作用 |
|---|---|---|
| 主流机 | realme GT 7 Pro | Android 15、高端相机、高刷屏与大内存路径 |
| 低端机 | REDMI Note 14 5G 6GB+128GB | 6GB 内存、UFS 2.2 和中低端 SoC 下的离线草稿、上传与内存压力 |

GT 7 Pro 是项目成员现有设备，确定为主流验收机。它有 Snapdragon 8 至尊版、最高 16GB+1TB 与 Android 15，适合验证高端路径，但不能代表弱性能设备。[realme 官方规格](https://www.realme.com/cn/realme-gt-7-pro/specs)

REDMI Note 14 5G 的 6GB+128GB、LPDDR4X/UFS 2.2 与 Dimensity 7025-Ultra 使其成为低端压力候选；采购前以实际地区机型、系统版本为准。[Xiaomi 官方规格](https://www.mi.com/global/product/redmi-note-14-5g/specs/)

两台设备都须完成 AC-01、AC-02、AC-06、AC-07、AC-08 实机验证，并记录 Android/厂商系统版本、可用存储、网络条件和结果。性能结论只能来自实测。

## 首个猪场试点边缘服务器

适用假设：1 个猪场、1–10 名并发现场人员、照片优先、单图服务端推理、视频计数未启用。超出时必须重新压测。

| 部件 | 推荐下限 | 理由 |
|---|---|---|
| CPU | 8 个现代 x86 逻辑核心 | Spring、MySQL、MinIO、Redis、Nginx、Worker 并行 |
| 内存 | 32GB | 数据库页缓存、对象服务、容器和推理余量 |
| GPU | NVIDIA RTX 4060 Ti 16GB | 优先 16GB，降低模型、输入尺寸和并发的显存风险 |
| 存储 | 1TB NVMe SSD | 容器、数据库、日志与热数据；数据增长后扩容或拆分 MinIO |
| 网络 | 千兆有线 + 采集区稳定 Wi-Fi | 文件上传可靠性优先 |
| 供电 | UPS + 自动重启策略 | 降低断电造成的服务中断 |
| 系统 | Ubuntu Server LTS + Docker Compose | 与当前编排一致 |

RTX 4060 Ti 存在 16GB GDDR6 版本，官方列出 4352 CUDA cores。选型旨在留出未验证模型的显存余量，并不承诺具体吞吐量。[NVIDIA 官方规格](https://www.nvidia.com/en-in/geforce/graphics-cards/40-series/rtx-4060-4060ti/)

## MinIO 与扩容门槛

- MinIO 保持私有桶，只通过短期签名 URL 访问。
- 至少每日增量备份到另一物理介质或受控对象存储；同一硬盘副本不构成备份。
- 推理 GPU 长期超过 70%、磁盘超过 70%、需要视频/多模型并发或恢复演练不达标时，拆分业务存储与推理节点。
- 采购前须用真实 YOLO 权重跑金标集，记录显存、单图延迟、并发和失败率；通过后才锁定数量和是否分拆。
