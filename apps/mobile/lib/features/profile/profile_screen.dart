import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../local_activity/data/local_activity_repository.dart';
import '../../shared/widgets/field_header.dart';
import '../master_data/data/drift_master_data_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    final String organizationId = auth.user.activeOrganizationId;
    return StreamBuilder<LocalActivityStats>(
      key: ValueKey(organizationId),
      stream:
          ref.watch(localActivityRepositoryProvider).watchStats(organizationId),
      builder:
          (BuildContext context, AsyncSnapshot<LocalActivityStats> snapshot) {
        final LocalActivityStats? stats =
            snapshot.hasError ? null : snapshot.data;
        return ListView(
          padding: AppSpacing.page,
          children: <Widget>[
            const FieldHeader(title: '我的作业空间', subtitle: '账号、同步与本机证据'),
            const SizedBox(height: 12),
            if (snapshot.hasError) const Text('本机作业统计暂不可读取，请重新打开页面重试'),
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
            const SizedBox(height: 12),
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
                      '${stats?.mediaCount ?? '未知'} 张原图 · ${stats == null ? '未知' : _bytes(stats.mediaBytes)} · ${stats?.draftCount ?? '未知'} 个作业'),
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
                    '${stats?.pendingUploadCount ?? '未知'} 个待处理 · '
                    '${stats?.blockedUploadCount ?? '未知'} 个被阻止；提交前原图不会清理',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/outbox'),
                ),
                const Divider(height: 1),
                const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('现场作业版 0.2.4'),
                    subtitle: Text('工作台 · 栏舍任务 · 证据与复核')),
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
