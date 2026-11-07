import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class FieldHeader extends StatelessWidget {
  const FieldHeader({
    required this.title,
    required this.subtitle,
    this.offline = false,
    this.onQueue,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool offline;
  final VoidCallback? onQueue;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (onQueue != null)
            IconButton.filledTonal(
              tooltip: offline ? '离线 · 查看待上传' : '查看上传队列',
              onPressed: onQueue,
              icon: Icon(offline
                  ? Icons.cloud_off_outlined
                  : Icons.cloud_upload_outlined),
            ),
        ],
      );
}

class FieldScope extends StatelessWidget {
  const FieldScope({required this.label, this.detail, super.key});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF2F7),
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined,
              size: 18, color: AppColors.barnBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ]),
      );
}
