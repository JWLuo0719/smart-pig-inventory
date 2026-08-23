import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
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
              child: Text(auth.user.displayName.substring(0, 1)),
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
              subtitle: const Text('同步栏舍后可离线选择'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pens'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('上传队列'),
              subtitle: const Text('提交成功前原图不会清理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/outbox'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ]),
        ),
      ],
    );
  }
}
