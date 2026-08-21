# Flutter 移动端

Android 首发，结构保持 iOS 可扩展。Android 原生工程已经提交；运行前须安装 Flutter 与 Android SDK，并生成 Drift 代码：

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8088
```

弱网约束：照片先写入 App 私有存储和 Drift Outbox；只有服务端 Commit 成功才标记为已同步。断网或杀死 App 均不得丢失待上传包。

完整实现顺序、阶段门禁和人工决策点见 `docs/development/mobile-development-sequence.md` 与 `docs/product/open-decisions.md`。当前页面仍是开发框架，采集媒体必须先物化到私有持久目录后才能进入草稿和 Outbox。
