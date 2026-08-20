import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum PenWorkState { notStarted, queued, processing, review, confirmed, failed }

class PenPlate extends StatelessWidget {
  const PenPlate({
    required this.building,
    required this.pen,
    required this.state,
    required this.detail,
    this.count,
    this.onTap,
    super.key,
  });

  final String building;
  final String pen;
  final PenWorkState state;
  final String detail;
  final int? count;
  final VoidCallback? onTap;

  Color get _color => switch (state) {
        PenWorkState.notStarted => AppColors.muted,
        PenWorkState.queued => AppColors.straw,
        PenWorkState.processing => AppColors.barnBlueLight,
        PenWorkState.review => AppColors.review,
        PenWorkState.confirmed => AppColors.herdTeal,
        PenWorkState.failed => AppColors.alert,
      };

  String get _label => switch (state) {
        PenWorkState.notStarted => '未开始',
        PenWorkState.queued => '待上传',
        PenWorkState.processing => '处理中',
        PenWorkState.review => '需复核',
        PenWorkState.confirmed => '已确认',
        PenWorkState.failed => '失败',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$building $pen，$_label，${count == null ? '暂无确认数量' : '确认 $count 头'}，$detail',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(width: 6, color: _color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(child: Text(building, style: Theme.of(context).textTheme.bodySmall)),
                            Text(pen, style: const TextStyle(color: AppColors.barnBlue, fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_label, style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Text(count?.toString() ?? '—', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            const SizedBox(width: 5),
                            const Text('头', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(detail, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

