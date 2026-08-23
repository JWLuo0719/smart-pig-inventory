# Flutter 移动端

Android 首发，结构保持 iOS 可扩展。Android 原生工程已经提交；运行前须安装 Flutter 与 Android SDK，并生成 Drift 代码：

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8088
```

真机须将 `API_BASE_URL` 指向电脑在同一局域网内的 HTTP 地址，例如
`http://192.168.x.x:8088`；不得将账号、密码、JWT 或刷新令牌写入 `--dart-define`、源码或 Git。登录会把令牌保存在 Android 系统安全存储，并在网络不可用时仅在最近一次服务器验证后的 7 天内恢复本机草稿和已缓存栏舍：离线期间不能同步。


弱网约束：照片先写入 App 私有存储和 Drift Outbox；只有服务端 Commit 成功才标记为已同步。断网或杀死 App 均不得丢失待上传包。

完整实现顺序、阶段门禁和人工决策点见 `docs/development/mobile-development-sequence.md` 与 `docs/product/open-decisions.md`。当前页面仍是开发框架，采集媒体必须先物化到私有持久目录后才能进入草稿和 Outbox。
