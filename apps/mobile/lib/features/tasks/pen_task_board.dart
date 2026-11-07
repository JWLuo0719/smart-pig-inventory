import 'package:flutter/material.dart';

import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';

String taskStatusLabel(String status) => switch (status) {
      'pending' => '待采集',
      'submitted' => '已提交',
      'processing' => '检测中',
      'review_required' => '待复核',
      'confirmed' => '已确认',
      _ => '需处理',
    };

Color taskStatusColor(String status) => switch (status) {
      'confirmed' => AppColors.herdTeal,
      'review_required' => AppColors.review,
      'processing' || 'submitted' => AppColors.barnBlue,
      'pending' => AppColors.muted,
      _ => AppColors.alert,
    };

/// Displays only server task facts. No physical pen positions are inferred.
class PenTaskBoard extends StatefulWidget {
  const PenTaskBoard({required this.tasks, required this.onOpen, super.key});

  final List<RemoteInventoryTask> tasks;
  final ValueChanged<RemoteInventoryTask> onOpen;

  @override
  State<PenTaskBoard> createState() => _PenTaskBoardState();
}

class _PenTaskBoardState extends State<PenTaskBoard> {
  String? _building;
  String? _status;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final buildings = <String, String>{
      for (final task in widget.tasks)
        task.buildingCode: '${task.buildingCode} ${task.buildingName}',
    };
    final selected = buildings.containsKey(_building) ? _building : null;
    final scoped = widget.tasks
        .where((task) => selected == null || task.buildingCode == selected)
        .toList();
    final visible = scoped.where((task) {
      final matchesState = _status == null || task.status == _status;
      final text = '${task.penCode} ${task.penName} ${task.buildingName}';
      return matchesState && text.toLowerCase().contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) {
        final building = a.buildingCode.compareTo(b.buildingCode);
        return building != 0 ? building : a.penCode.compareTo(b.penCode);
      });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.grid_view_outlined,
                size: 18, color: AppColors.barnBlue),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('栏舍作业矩阵',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Text('${scoped.length} 栏',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(selected),
            initialValue: selected ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: '栋舍范围', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('全部栋舍')),
              ...buildings.entries.map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (value) => setState(() => _building = value),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索栏舍编码或名称',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final entry in const <String?, String>{
              null: '全部',
              'pending': '待采集',
              'review_required': '待复核',
              'confirmed': '已确认',
            }.entries)
              FilterChip(
                label: Text(entry.value),
                selected: _status == entry.key,
                onSelected: (_) => setState(() => _status = entry.key),
              ),
          ]),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('当前范围没有符合条件的栏舍。'))
          else
            LayoutBuilder(builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              final columns = largeText
                  ? 1
                  : constraints.maxWidth >= 540
                      ? 3
                      : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final task in visible)
                  SizedBox(
                    width: width,
                    child:
                        _TaskTile(task: task, onTap: () => widget.onOpen(task)),
                  ),
              ]);
            }),
          const SizedBox(height: 12),
          Text('按栋舍、栏舍编码排列 · 仅已确认记录显示正式数量',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onTap});
  final RemoteInventoryTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = taskStatusColor(task.status);
    final confirmed = task.status == 'confirmed';
    return Material(
      color: color.withValues(alpha: 0.045),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.35))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(task.penCode,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              Icon(confirmed ? Icons.verified_outlined : Icons.circle_outlined,
                  size: 16, color: color),
            ]),
            const SizedBox(height: 4),
            Text('${task.buildingName} · ${task.penName}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
                confirmed && task.confirmedCount != null
                    ? '${task.confirmedCount} 头'
                    : '数量待确认',
                style: TextStyle(
                    fontSize: confirmed ? 22 : 14,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(taskStatusLabel(task.status),
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
