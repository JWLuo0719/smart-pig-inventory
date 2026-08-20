import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({super.key, this.pending = 3, this.offline = true});

  final int pending;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final Color color = offline ? AppColors.straw : AppColors.herdTeal;
    return Semantics(
      label: offline ? '当前离线，有 $pending 个采集包待上传' : '网络正常，上传队列已同步',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: <Widget>[
            Icon(offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                offline ? '离线模式 · $pending 个采集包安全保存在本机' : '网络正常 · 上传队列已同步',
                style: TextStyle(
                    color:
                        offline ? const Color(0xFF805800) : AppColors.herdTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
