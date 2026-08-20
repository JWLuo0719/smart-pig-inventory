import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: <Widget>[
        Text('我的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Card(
            child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: AppColors.barnBlue,
                    foregroundColor: Colors.white,
                    child: Text('盘')),
                title: Text('现场盘点员',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('F001 · 示范猪场'))),
        const SizedBox(height: 14),
        Card(
            child: Column(children: <Widget>[
          ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('主数据同步'),
              subtitle: const Text('今天 08:31'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}),
          const Divider(height: 1),
          ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('上传队列'),
              subtitle: const Text('3 个采集包待上传'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/outbox')),
          const Divider(height: 1),
          ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('本机存储'),
              subtitle: const Text('原图确认提交前不会清理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}),
        ])),
      ],
    );
  }
}
