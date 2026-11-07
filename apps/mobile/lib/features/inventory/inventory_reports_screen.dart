import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_browse_api.dart';
import '../../core/theme/app_theme.dart';
import '../master_data/data/drift_master_data_repository.dart';
import '../master_data/domain/master_data_changes.dart';

final inventoryReportsApiProvider = Provider<InventoryBrowseApi>(
    (ref) => InventoryBrowseApi(ref.watch(apiBaseUrlProvider)));

class InventoryReportsScreen extends ConsumerStatefulWidget {
  const InventoryReportsScreen({super.key});
  @override
  ConsumerState<InventoryReportsScreen> createState() =>
      _InventoryReportsScreenState();
}

class _InventoryReportsScreenState
    extends ConsumerState<InventoryReportsScreen> {
  DateTime _from = DateUtils.dateOnly(DateTime.now()),
      _to = DateUtils.dateOnly(DateTime.now());
  String? _penId, _error;
  List<Map<String, dynamic>>? _daily;
  Map<String, dynamic>? _aggregate;
  RemoteTrend? _trend;
  bool _loading = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final auth = ref.read(authControllerProvider).valueOrNull;
    final from = _from, to = _to, penId = _penId;
    setState(() {
      _loading = true;
      _error = null;
      _daily = null;
      _aggregate = null;
      _trend = null;
    });
    try {
      if (auth == null || auth.isOffline) {
        throw StateError('联网后可读取已确认报表；离线不显示估算数量。');
      }
      final api = ref.read(inventoryReportsApiProvider);
      final daily = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (token) => api.daily(token, to));
      if (!_isCurrent(auth, generation)) return;
      Map<String, dynamic>? aggregate;
      if (penId != null) {
        aggregate = await retryOnceAfterUnauthorized(
            initialAuth: auth,
            reconnect: () =>
                ref.read(authControllerProvider.notifier).reconnect(),
            request: (token) => api.aggregate(token, penId, from, to));
        if (!_isCurrent(auth, generation)) return;
      }
      RemoteTrend? trend;
      try {
        trend = await retryOnceAfterUnauthorized(
            initialAuth: auth,
            reconnect: () =>
                ref.read(authControllerProvider.notifier).reconnect(),
            request: (token) => api.trend(token, to, days: 14));
      } catch (_) {
        // 趋势缺失不阻塞报表主内容；卡片自动隐藏。
      }
      if (_isCurrent(auth, generation)) {
        setState(() {
          _daily = daily;
          _aggregate = aggregate;
          _trend = trend;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            error is StateError ? error.message.toString() : '无法读取报表，请联网后重试。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _isCurrent(AuthState auth, int generation) {
    if (!mounted || generation != _generation) return false;
    final current = ref.read(authControllerProvider).valueOrNull;
    return current?.user.subjectId == auth.user.subjectId &&
        current?.user.activeOrganizationId == auth.user.activeOrganizationId &&
        current?.isOffline == false;
  }

  Future<void> _range() async {
    final range = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(start: _from, end: _to),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (range == null || !mounted) return;
    if (range.duration.inDays > 365) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('每次最多查询 366 天。')));
      return;
    }
    setState(() {
      _from = range.start;
      _to = range.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.valueOrNull, after = next.valueOrNull;
      if (before?.user.subjectId != after?.user.subjectId ||
          before?.user.activeOrganizationId !=
              after?.user.activeOrganizationId ||
          before?.isOffline != after?.isOffline) {
        _penId = null;
        _load();
      }
    });
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('日报与综合盘点')),
        body: ListView(padding: AppSpacing.page, children: [
          const Text('仅统计人工已确认数量；候选结果不计入周期平均。'),
          OutlinedButton(
              onPressed: _loading ? null : _range,
              child: Text(
                  '${locale.formatMediumDate(_from)} — ${locale.formatMediumDate(_to)}')),
          if (auth != null)
            StreamBuilder<List<PenChoice>>(
                key: ValueKey(auth.user.activeOrganizationId),
                stream: ref
                    .watch(masterDataRepositoryProvider)
                    .watchPens(auth.user.activeOrganizationId),
                builder: (context, snapshot) => DropdownButtonFormField<String>(
                      key:
                          ValueKey('${auth.user.activeOrganizationId}/$_penId'),
                      initialValue: _penId ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '综合盘点栏舍'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('选择栏舍计算跨日平均')),
                        ...?snapshot.data?.map((p) => DropdownMenuItem(
                            value: p.penId,
                            child: Text(
                                '${p.buildingCode} / ${p.penCode} · ${p.penName}',
                                overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: _loading
                          ? null
                          : (value) {
                              setState(
                                  () => _penId = value == '' ? null : value);
                              _load();
                            },
                    )),
          OutlinedButton(
              onPressed: _loading ? null : _load, child: const Text('刷新报表')),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_trend != null) _TrendCard(trend: _trend!, penId: _penId),
          if (_aggregate != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('综合盘点：${_aggregate!['roundedCount'] ?? '—'} 头',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text('原始均值：${_aggregate!['rawMean'] ?? '无已确认样本'}'),
                          Text(
                              '参与日期：${(_aggregate!['includedDates'] as List).join('、')}'),
                        ]))),
          Text('${locale.formatMediumDate(_to)} 日报',
              style: Theme.of(context).textTheme.titleLarge),
          if (_daily != null && _daily!.isEmpty) const Text('当日没有已确认盘点记录。'),
          ...?_daily?.map((row) => ListTile(
              title: Text('${row['buildingCode']} / ${row['penCode']}'),
              trailing: Text('${row['confirmedCount']} 头'),
              onTap: () =>
                  context.push('/inventory-sessions/${row['sessionId']}'))),
        ]));
  }
}

/// 存栏趋势卡：人工确认（青绿实线）与机器候选（橙色细线）双序列，
/// 附最近有数据的「机器提议 vs 人工确认」对照。缺采集日期断线呈现。
/// 选择栏舍时切换为该栏序列（综合盘点下拉联动）。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend, this.penId});

  final RemoteTrend trend;
  final String? penId;

  @override
  Widget build(BuildContext context) {
    final (String label, List<RemoteTrendPoint> points) =
        trend.seriesFor(penId) ?? ('所选栏舍', const []);
    final List<RemoteTrendPoint> comparable = points
        .where((point) => point.confirmed != null || point.candidate != null)
        .toList();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('存栏趋势 · $label（近 14 天）',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 6, children: const [
                _Legend(color: AppColors.barnBlue, label: '人工确认（计入存栏）'),
                SizedBox(width: 12),
                _Legend(color: Color(0xFFFF6D00), label: '机器候选（未确认）'),
              ]),
              if (penId == null)
                Text(
                    '查询时启用栏舍：${trend.scopePenCount ?? '未知'}；各日仅统计有数据栏舍，不比较覆盖不同的合计偏差。'),
              if (penId == null && comparable.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('最近有数据日 ${comparable.last.date}：'
                    '确认覆盖 ${comparable.last.confirmedPenCount ?? '未知'} 栏；'
                    '候选覆盖 ${comparable.last.candidatePenCount ?? '未知'} 栏。'),
                ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('查看每日覆盖栏舍数'),
                    children: points.reversed
                        .map((point) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('${point.date}：确认覆盖 '
                                    '${point.confirmedPenCount ?? '未知'} 栏；候选覆盖 '
                                    '${point.candidatePenCount ?? '未知'} 栏。'))))
                        .toList()),
              ],
              const SizedBox(height: 8),
              SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: Semantics(
                      label: points
                          .map((p) =>
                              '${p.date}，确认${p.confirmed ?? '未知'}，候选${p.candidate ?? '未知'}，覆盖${p.confirmedPenCount ?? '未知'}栏')
                          .join('；'),
                      child:
                          CustomPaint(painter: _TrendPainter(points: points)))),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(trend.from,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45)),
                Text(trend.to,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45)),
              ]),
              const SizedBox(height: 10),
              if (comparable.isEmpty)
                Text(
                    penId == null
                        ? '窗口内暂无已确认记录；完成盘点复核后这里会出现趋势线。'
                        : '该栏舍近 14 天暂无已确认或候选记录。',
                    style:
                        const TextStyle(fontSize: 12.5, color: Colors.black54)),
              if (comparable.isNotEmpty && penId != null) ...[
                const Text('机器提议 vs 人工确认（最近 7 个有数据日）',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ...comparable.toList().reversed.take(7).map(_comparisonRow),
              ],
            ])));
  }

  Widget _comparisonRow(RemoteTrendPoint point) {
    final int? confirmed = point.confirmed;
    final int? candidate = point.candidate;
    final String deviation = (confirmed == null || candidate == null)
        ? '—'
        : confirmed == candidate
            ? '一致'
            : '${confirmed > candidate ? '+' : ''}${confirmed - candidate} 头';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 88,
              child: Text(point.date.substring(5),
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54))),
          Expanded(
              child: Text('机器 ${candidate ?? '—'}',
                  style: const TextStyle(fontSize: 12.5))),
          Expanded(
              child: Text('人工 ${confirmed ?? '—'}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700))),
          SizedBox(
              width: 64,
              child: Text('偏差 $deviation',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                  textAlign: TextAlign.right)),
        ]));
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
      ]);
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.points});
  final List<RemoteTrendPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final List<int> values = points
        .expand((point) => [point.confirmed, point.candidate])
        .whereType<int>()
        .toList();
    if (values.isEmpty) return;
    final double maxValue = math.max(1, values.reduce(math.max)) * 1.15;
    Offset position(int index, int value) => Offset(
        points.length < 2
            ? size.width / 2
            : index / (points.length - 1) * size.width,
        size.height - value / maxValue * size.height * 0.92 - 4);
    void drawSeries(int? Function(RemoteTrendPoint) pick, Color color,
        double strokeWidth, bool dots) {
      final Paint line = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      int? previousValue;
      int? previousIndex;
      for (int i = 0; i < points.length; i++) {
        final int? value = pick(points[i]);
        if (value == null) {
          previousValue = null;
          previousIndex = null;
          continue;
        }
        final Offset current = position(i, value);
        if (previousValue != null && points.length >= 2) {
          canvas.drawLine(
              position(previousIndex!, previousValue), current, line);
        }
        if (dots) {
          canvas.drawCircle(current, strokeWidth + 1, Paint()..color = color);
        }
        previousValue = value;
        previousIndex = i;
      }
    }

    drawSeries((point) => point.candidate, const Color(0xFFFF6D00), 1.6, false);
    drawSeries((point) => point.confirmed, AppColors.barnBlue, 2.4, true);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points;
}
