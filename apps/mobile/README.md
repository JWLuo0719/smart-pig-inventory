# Flutter 移动端

Android 首发，结构保持 iOS 可扩展。运行前须安装 Flutter 与 Android SDK，并生成 Drift 代码：

```powershell
flutter create --platforms=android --org com.smartfarm.inventory --project-name smart_pig_inventory .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8088
```

弱网约束：照片先写入 App 私有存储和 Drift Outbox；只有服务端 Commit 成功才标记为已同步。断网或杀死 App 均不得丢失待上传包。

当前仓库尚未在本机生成 Android 原生壳，因为本机没有 Flutter/Android SDK。CI 会临时生成以验证；首次在有完整工具链的工作站执行上述命令后，应评审并提交 `android/`，再删除 CI 中的临时生成步骤。
