import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../local_activity/data/local_activity_repository.dart';
import '../master_data/data/drift_master_data_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    final String organizationId = auth.user.activeOrganizationId;
    return StreamBuilder<LocalActivityStats>(
      stream:
          ref.watch(localActivityRepositoryProvider).watchStats(organizationId),
      builder:
          (BuildContext context, AsyncSnapshot<LocalActivityStats> snapshot) {
        final LocalActivityStats stats = snapshot.data ??
            const LocalActivityStats(
              draftCount: 0,
              pendingUploadCount: 0,
              blockedUploadCount: 0,
              mediaCount: 0,
              mediaBytes: 0,
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: <Widget>[
            Text('我的', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.barnBlue,
                  foregroundColor: Colors.white,
                  child: Text(_initial(auth.user.displayName)),
                ),
                title: Text(auth.user.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${auth.user.activeOrganizationCode} · ${auth.user.activeOrganizationName}'),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('主数据同步'),
                  subtitle: FutureBuilder<DateTime?>(
                    future: ref
                        .watch(masterDataRepositoryProvider)
                        .lastSyncedAt(organizationId),
                    builder: (BuildContext context,
                        AsyncSnapshot<DateTime?> syncSnapshot) {
                      final DateTime? value = syncSnapshot.data;
                      return Text(value == null
                          ? '尚无可验证的同步记录'
                          : '上次同步 ${_time(context, value)}');
                    },
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pens'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('本机证据存储'),
                  subtitle: Text(
                      '${stats.mediaCount} 张原图 · ${_bytes(stats.mediaBytes)} · ${stats.draftCount} 个作业'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.network_check),
                  title: const Text('网络与后台策略'),
                  subtitle: Text(auth.isOffline
                      ? '当前离线；连接任意网络后继续安全续传'
                      : '当前在线；任意已连接网络可执行后台续传'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('上传队列与诊断'),
                  subtitle: Text(
                    '${stats.pendingUploadCount} 个待处理 · '
                    '${stats.blockedUploadCount} 个被阻止；提交前原图不会清理',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/outbox'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('退出登录'),
                  subtitle: const Text('本机采集证据不会因退出而删除'),
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  static String _initial(String value) {
    final String normalized = value.trim();
    return normalized.isEmpty ? '?' : normalized.characters.first;
  }

  static String _time(BuildContext context, DateTime value) {
    final DateTime local = value.toLocal();
    final MaterialLocalizations localizations =
        MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(local)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
