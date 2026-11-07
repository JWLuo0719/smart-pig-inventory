import 'package:flutter/material.dart';

import '../../core/network/inventory_api.dart';
import '../tasks/pen_task_board.dart';

const cockpitInk = Color(0xFF0F172A);
const cockpitMuted = Color(0xFF64748B);
const cockpitLine = Color(0xFFE2E8F0);
const cockpitGreen = Color(0xFF059669);

double cockpitToolbarHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final height = (scaler.scale(12) + scaler.scale(10)) * 1.15 + 8;
  return height > 48 ? height : 48;
}

class CockpitToolbar extends StatelessWidget {
  const CockpitToolbar(
      {required this.name,
      required this.offline,
      required this.pending,
      required this.onQueue,
      required this.onProfile,
      required this.onSunlight,
      this.sunlight = false,
      super.key});
  final String name;
  final bool offline;
  final int? pending;
  final VoidCallback onQueue;
  final VoidCallback onProfile;
  final VoidCallback onSunlight;
  final bool sunlight;

  @override
  Widget build(BuildContext context) => Container(
        height: cockpitToolbarHeight(context),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: cockpitLine))),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: cockpitInk, borderRadius: BorderRadius.circular(8)),
              child: const Text('🐷',
                  style: TextStyle(fontSize: 18, fontFamilyFallback: [
                    'Noto Color Emoji',
                    'Segoe UI Emoji'
                  ]))),
          const SizedBox(width: 8),
          const Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Smart Swine Field Agent',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: cockpitInk)),
                Text('栏舍采集 · 盘点与复核',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10, height: 1.15, color: cockpitMuted)),
              ])),
          const SizedBox(width: 6),
          Semantics(
              button: true,
              label: '上传队列',
              child: InkWell(
                  onTap: onQueue,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(offline ? Icons.wifi_off : Icons.wifi,
                            size: 16,
                            color: offline
                                ? const Color(0xFFD97706)
                                : cockpitGreen),
                        const SizedBox(width: 4),
                        Text(
                            offline
                                ? '离线'
                                : pending != null && pending! > 0
                                    ? '$pending 待传'
                                    : '在线',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: offline || (pending ?? 0) > 0
                                    ? const Color(0xFFB45309)
                                    : cockpitGreen)),
                      ])))),
          InkWell(
              onTap: onProfile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_outline,
                        size: 16, color: cockpitMuted),
                    const SizedBox(width: 3),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 42),
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: cockpitInk))),
                  ]))),
          IconButton(
              tooltip: '阳光显示',
              onPressed: onSunlight,
              visualDensity: VisualDensity.compact,
              icon: Icon(sunlight ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                  size: 18, color: cockpitMuted)),
        ]),
      );
}

class FieldAgentNavigation extends StatelessWidget {
  const FieldAgentNavigation(
      {required this.index, required this.onSelected, super.key});
  final int index;
  final ValueChanged<int> onSelected;

  static const labels = ['工作台', '盘点', '证据', '我的'];
  static const icons = [
    Icons.auto_awesome_outlined,
    Icons.camera_alt_outlined,
    Icons.photo_library_outlined,
    Icons.manage_accounts_outlined
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: cockpitLine))),
        child: SafeArea(
            top: false,
            child: Row(children: [
              for (var item = 0; item < labels.length; item++)
                Expanded(
                    child: Semantics(
                        selected: item == index,
                        button: true,
                        child: InkWell(
                          onTap: () => onSelected(item),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 34,
                                        height: 32,
                                        decoration: BoxDecoration(
                                            color: item == index
                                                ? cockpitInk
                                                : const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                        child: Icon(icons[item],
                                            size: 18,
                                            color: item == index
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFF475569))),
                                    const SizedBox(height: 4),
                                    Text(labels[item],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: item == index
                                                ? cockpitInk
                                                : cockpitMuted,
                                            fontWeight: item == index
                                                ? FontWeight.w800
                                                : FontWeight.w500)),
                                  ])),
                        ))),
            ])),
      );
}

class CockpitTabs extends StatelessWidget {
  const CockpitTabs(
      {required this.labels,
      required this.index,
      required this.onChanged,
      super.key});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
                child: Semantics(
                    selected: i == index,
                    button: true,
                    child: InkWell(
                      onTap: () => onChanged(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                          constraints: const BoxConstraints(minHeight: 34),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 6),
                          decoration: BoxDecoration(
                              color: i == index
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == index
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: i == index
                                      ? cockpitInk
                                      : const Color(0xFF475569)))),
                    ))),
        ]),
      );
}

class CockpitSummary extends StatelessWidget {
  const CockpitSummary(
      {required this.scope,
      required this.heads,
      required this.confirmed,
      required this.total,
      required this.review,
      required this.onAssistant,
      required this.onReport,
      required this.onHistory,
      required this.onModules,
      super.key});
  final String scope;
  final int? heads;
  final int? confirmed;
  final int? total;
  final int? review;
  final VoidCallback onAssistant;
  final VoidCallback onReport;
  final VoidCallback onHistory;
  final VoidCallback onModules;

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(scope,
              style: const TextStyle(fontSize: 11, color: cockpitMuted)),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(
                child: Text('今日栏舍任务',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cockpitInk))),
            PopupMenuButton<String>(
                tooltip: '更多作业',
                onSelected: (value) =>
                    value == 'history' ? onHistory() : onModules(),
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'history', child: Text('历史任务')),
                      PopupMenuItem(value: 'modules', child: Text('更多能力')),
                    ]),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final width = (constraints.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              _metric(width, '已确认合计', heads == null ? '—' : '$heads 头', '人工确认'),
              _metric(width, '确认覆盖',
                  confirmed == null ? '—' : '$confirmed / $total', '栏'),
            ]);
          }),
          const SizedBox(height: 8),
          Text('待复核 ${review?.toString() ?? '—'} 栏',
              style: const TextStyle(fontSize: 12, color: cockpitMuted)),
          if (confirmed == null)
            const Text('等待服务器盘点数据',
                style: TextStyle(fontSize: 11, color: cockpitMuted)),
          if (confirmed != null && confirmed != total)
            const Text('部分覆盖 · 合计仅含已确认栏舍',
                style: TextStyle(fontSize: 10, color: cockpitMuted)),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
                onPressed: onAssistant,
                icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                label: const Text('询问助手',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            const Spacer(),
            TextButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.assessment_outlined, size: 15),
                label: const Text('查看报告',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          ])
        ]),
      ));

  Widget _metric(double width, String label, String value, String note) =>
      SizedBox(
          width: width,
          child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(9)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            const TextStyle(fontSize: 10, color: cockpitMuted)),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(value,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: cockpitInk)),
                          Text(note,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: note == '待接入'
                                      ? cockpitMuted
                                      : cockpitGreen)),
                        ]),
                  ])));
}

/// Uses real pens only. Groups are explicitly an encoding layout, not a survey.
class CockpitMatrix extends StatefulWidget {
  const CockpitMatrix({required this.tasks, required this.onOpen, super.key});
  final List<RemoteInventoryTask> tasks;
  final ValueChanged<RemoteInventoryTask> onOpen;

  @override
  State<CockpitMatrix> createState() => _CockpitMatrixState();
}

class _CockpitMatrixState extends State<CockpitMatrix> {
  int _mode = 0;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final pens = [...widget.tasks]
      ..sort((a, b) => a.penCode.compareTo(b.penCode));
    final selected =
        pens.where((pen) => pen.penId == _selectedId).firstOrNull ??
            pens.firstOrNull;
    final visible = pens
        .where((pen) => switch (_mode) {
              1 => pen.status == 'review_required',
              2 => pen.status == 'pending',
              3 => pen.status == 'confirmed',
              _ => true,
            })
        .toList();
    final active =
        visible.where((pen) => pen.penId == selected?.penId).firstOrNull ??
            visible.firstOrNull;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.explore_outlined,
                    size: 16, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('栏舍任务 (${pens.length}栏)',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 10),
              CockpitTabs(
                  labels: const ['全部栏舍', '待复核', '待采集', '已确认'],
                  index: _mode,
                  onChanged: (value) => setState(() => _mode = value)),
              const Divider(height: 24),
              if (visible.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('当前筛选条件下暂无栏舍。',
                        style: TextStyle(fontSize: 12, color: cockpitMuted)))
              else
                LayoutBuilder(builder: (context, constraints) {
                  final enlarged =
                      MediaQuery.textScalerOf(context).scale(12) > 16;
                  final columns = enlarged
                      ? 2
                      : constraints.maxWidth >= 650
                          ? 8
                          : 4;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 6) / columns;
                  return Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final pen in visible)
                      SizedBox(
                          width: width,
                          child: _pen(pen, pen.penId == active?.penId)),
                  ]);
                }),
              const SizedBox(height: 10),
              const Text('按栏舍编码排列',
                  style: TextStyle(fontSize: 9, color: cockpitMuted)),
              if (active != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: Text('当前栏舍 ${active.penCode}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700))),
                  TextButton(
                      onPressed: () => widget.onOpen(active),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF4F46E5),
                          backgroundColor: const Color(0xFFEEF2FF),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      child: const Text('打开栏舍任务 →',
                          style: TextStyle(fontSize: 11))),
                ]),
              ],
            ])));
  }

  Widget _pen(RemoteInventoryTask pen, bool selected) {
    final confirmed = pen.status == 'confirmed';
    final color = confirmed
        ? cockpitGreen
        : pen.status == 'review_required'
            ? const Color(0xFF6366F1)
            : cockpitMuted;
    final count =
        confirmed && pen.confirmedCount != null ? '${pen.confirmedCount}' : '—';
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${pen.penCode}，${taskStatusLabel(pen.status)}，${confirmed ? '$count 头' : '数量待确认'}',
      child: Material(
          color: confirmed ? const Color(0xFFF0FDF8) : const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                  color: selected
                      ? cockpitInk
                      : confirmed
                          ? const Color(0xFF34D399)
                          : cockpitLine,
                  width: selected ? 2.5 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: () => setState(() => _selectedId = pen.penId),
              child: Container(
                  constraints: const BoxConstraints(minHeight: 88),
                  padding: const EdgeInsets.all(7),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  pen.penCode.endsWith('栏')
                                      ? pen.penCode
                                      : '${pen.penCode}栏',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800))),
                          if (confirmed)
                            Icon(Icons.check_circle_outline,
                                size: 12, color: color)
                          else if (pen.status == 'review_required')
                            Icon(Icons.circle, size: 6, color: color),
                        ]),
                        const SizedBox(height: 10),
                        Text('$count 头',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 9),
                        Text(taskStatusLabel(pen.status),
                            style: TextStyle(fontSize: 9, color: color)),
                      ])))),
    );
  }
}

class CockpitModalities extends StatefulWidget {
  const CockpitModalities({super.key});
  @override
  State<CockpitModalities> createState() => _CockpitModalitiesState();
}

class _CockpitModalitiesState extends State<CockpitModalities> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CockpitTabs(
                labels: const ['行为与姿态', '3D估重', '环境与声学生物联动'],
                index: _index,
                onChanged: (value) => setState(() => _index = value)),
            const SizedBox(height: 12),
            Text(['姿态识别与行为分类', '3D体尺与生长趋势', '环控传感与声学监测'][_index],
                style: const TextStyle(fontSize: 11, color: cockpitMuted)),
            const Divider(height: 20),
            Center(
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(children: [
                      Icon(
                          [
                            Icons.accessibility_new_outlined,
                            Icons.view_in_ar_outlined,
                            Icons.sensors_outlined
                          ][_index],
                          size: 28,
                          color: const Color(0xFF94A3B8)),
                      const SizedBox(height: 8),
                      const Text('待接入对应模型或设备',
                          style: TextStyle(fontSize: 12, color: cockpitMuted)),
                    ]))),
          ])));
}

class CockpitModules extends StatelessWidget {
  const CockpitModules({super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('智能体能力模块',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final module in const [
              ('视觉盘点', '服务器候选检测 · 人工复核'),
              ('盘点证据工具', '任务、记录、报表查询'),
              ('3D体尺估重', '待接入'),
              ('姿态与行为', '待接入'),
              ('环境与声学', '待接入'),
            ])
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.extension_outlined,
                        size: 17, color: cockpitMuted),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(module.$1,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700))),
                    Flexible(
                        child: Text(module.$2,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontSize: 10, color: cockpitMuted))),
                  ])),
          ])));
}
