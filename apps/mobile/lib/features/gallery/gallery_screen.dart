import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: <Widget>[
        Text('栏舍图库', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('按栏舍和日期查看原始证据、上传状态和锁定结果。', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18),
        const _MediaRow(title: 'B02-08栏 · 单图', status: '已确认并锁定', color: AppColors.herdTeal, detail: '今天 08:42 · 126头'),
        const SizedBox(height: 10),
        const _MediaRow(title: 'B01-03栏 · 左中右', status: '待上传', color: AppColors.straw, detail: '已保存 2/3 张 · 不会显示数量'),
        const SizedBox(height: 10),
        const _MediaRow(title: 'B02-12栏 · 左中右', status: '需人工复核', color: AppColors.review, detail: '疑似近重复 · 原图未删除'),
      ],
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.title, required this.status, required this.color, required this.detail});
  final String title;
  final String status;
  final Color color;
  final String detail;
  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: <Widget>[
      Container(width: 58, height: 58, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.image_outlined, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ])),
      const Icon(Icons.chevron_right, color: AppColors.muted),
    ])));
  }
}
