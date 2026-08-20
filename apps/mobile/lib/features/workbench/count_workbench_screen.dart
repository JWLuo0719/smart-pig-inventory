import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class CountWorkbenchScreen extends StatelessWidget {
  const CountWorkbenchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: <Widget>[
        Text('开始盘点', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('先确认栏舍，再决定单图或左中右三图。', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 22),
        _StepTile(number: '1', title: '选择栏舍', detail: '最近同步于 08:31，可离线使用', onTap: () => context.push('/pens')),
        const SizedBox(height: 12),
        _StepTile(number: '2', title: '选择采集模式', detail: '单图 / 左中右；三图不会简单相加', onTap: () => context.push('/capture')),
        const SizedBox(height: 12),
        const _StepTile(number: '3', title: '确认有效区域', detail: '排除隔壁栏舍和无效画面'),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: () => context.push('/capture'), icon: const Icon(Icons.camera_alt_outlined), label: const Text('选择栏舍并开始')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.push('/outbox'), icon: const Icon(Icons.cloud_upload_outlined), label: const Text('查看上传队列')),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.title, required this.detail, this.onTap});
  final String number;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: <Widget>[
            Container(width: 38, height: 42, alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.barnBlue, borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10))), child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}
