import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Network state is deliberately nullable: callers must not present a guessed
/// offline state or a fabricated queue count as factual information.
class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({super.key, this.pending, this.offline});

  final int? pending;
  final bool? offline;

  @override
  Widget build(BuildContext context) {
    final bool knownOffline = offline == true;
    final bool knownOnline = offline == false;
    final Color color = knownOffline ? AppColors.straw : AppColors.herdTeal;
    final String message = knownOffline
        ? pending == null
            ? '离线模式已确认 · 本机草稿会继续保留'
            : '离线模式 · $pending 个采集包安全保存在本机'
        : knownOnline
            ? '网络连接已验证 · 可同步服务器数据'
            : '网络状态尚未验证 · 本机草稿会安全保留';
    return Semantics(
      label: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: <Widget>[
          Icon(
            knownOffline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: knownOffline
                        ? const Color(0xFF805800)
                        : AppColors.herdTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
