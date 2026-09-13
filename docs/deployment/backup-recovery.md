# 一致性备份与隔离恢复

`scripts/inventory_snapshot.py` 使用 Python 3.11+ 标准库和 Docker CLI，支持当前单机 Compose 的 MySQL、Redis、MinIO 三个命名卷。无需新依赖；使用本机 `redis:7.4-alpine` 中的 tar，并解析到镜像 ID 后执行，不自动拉取。

## 备份

安排停写窗口，暂停监管器/自动重启/外部部署，先停入口和业务写入者，再优雅停止该项目全部容器。仅停止目标项目，不能停止整台 Docker 主机。脚本检查全部已停止、卷标签与项目一致、没有其他运行容器挂载源卷；它不会代替操作者停服务。运行过程中不可另行启动服务。

```
python scripts/inventory_snapshot.py backup --project pig-inventory-production --output <受保护介质上的新目录>
python scripts/inventory_snapshot.py verify --snapshot <快照目录>
```

输出目录必须不存在。只读复制 mysql_data、redis_data、minio_data，排除可重建的顶层 mysql.sock；记录实际服务镜像 ID、每卷字节数/SHA-256。数据库、媒体、Redis 队列来自同一停写窗口，原证据不改变。归档完整读取通过后才写 manifest.json；失败产物保留，无 manifest 不可恢复。成功后按原配置有序恢复源服务并检查健康。

快照包含数据库账号哈希、会话、媒体和内部存储信息，属于敏感备份；不能放入发布 ZIP、Git 或共享目录。当前是未加密的本地归档，必须由权限受限的加密磁盘/备份介质保护；配置和密钥须独立加密保管。哈希提供损坏检测，不提供对抗恶意篡改的真实性证明，只恢复可信介质。

## 恢复

```
python scripts/inventory_snapshot.py restore --snapshot <可信快照目录> --target-project pig-inventory-restore-20260912
```

目标必须与来源不同、没有任何目标容器，三个目标卷均不得存在；脚本不覆盖、不清理旧卷。先完整验证哈希与 tar 路径/文件类型，再创建新卷。拒绝链接、设备、绝对路径和父目录跳转。失败时保留部分恢复卷供排查，改用新的目标名重试。

只恢复卷不会启动服务。先把快照清单中的原镜像保存到目标机器，并在隔离 Compose overlay 中将所有服务固定为记录的原镜像；使用与备份对应的配置/密钥、禁用外部流量和推理派发，仅映射回环验收端口。物理 MySQL/MinIO 数据不支持盲目跨版本恢复，先使用原镜像启动。核对 Flyway、登录与组织、历史/当前确认值、审计、媒体 SHA-256、锁定删除、Redis 后再安排业务切换。恢复带回的会话和队列须按实际灾备计划处置，不默认让旧推理请求重放到生产。

## 自动演练

```
python scripts/test_inventory_snapshot.py
python scripts/run_snapshot_e2e.py
```

演练只使用随机后缀的 `pig-inventory-recovery-source-*` 与 `pig-inventory-recovery-target-*`，回环 8096、合成账号/PNG、已验证的功能候选镜像；不读取产品 .env，不访问 P0 卷。模拟手工确认 17 后更正 19，再停写、备份、全新恢复，检查历史及媒体锁定。成功后只移除测试容器和网络，卷与生成证据保留。失败现场在 test-assets/generated/snapshot-recovery 下；禁止把该脚本指向生产。

设计对照见 [备份模式研究](../research/backup-recovery-patterns.md)。目标生产环境的加密异地备份、密钥恢复、容量/RTO、主机重启和真实切换仍需独立验收。
