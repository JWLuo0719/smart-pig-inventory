import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_browse_api.dart';
import '../master_data/data/drift_master_data_repository.dart';
import '../master_data/domain/master_data_changes.dart';

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
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    setState(() {
      _loading = true;
      _error = null;
      _daily = null;
      _aggregate = null;
    });
    try {
      if (auth == null || auth.isOffline) {
        throw StateError('联网后可读取已确认报表；离线不显示估算数量。');
      }
      final api = InventoryBrowseApi(ref.read(apiBaseUrlProvider));
      final daily = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (token) => api.daily(token, _to));
      Map<String, dynamic>? aggregate;
      if (_penId != null) {
        final latest = ref.read(authControllerProvider).valueOrNull ?? auth;
        aggregate = await retryOnceAfterUnauthorized(
            initialAuth: latest,
            reconnect: () =>
                ref.read(authControllerProvider.notifier).reconnect(),
            request: (token) => api.aggregate(token, _penId!, _from, _to));
      }
      if (mounted) {
        setState(() {
          _daily = daily;
          _aggregate = aggregate;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error is StateError ? error.message.toString() : '无法读取报表，请联网后重试。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('日报与综合盘点')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('只统计人工已确认数量；未确认结果不计入平均。'),
          OutlinedButton(
              onPressed: _loading ? null : _range,
              child: Text(
                  '${locale.formatMediumDate(_from)} — ${locale.formatMediumDate(_to)}')),
          if (auth != null)
            StreamBuilder<List<PenChoice>>(
                stream: ref
                    .watch(masterDataRepositoryProvider)
                    .watchPens(auth.user.activeOrganizationId),
                builder: (context, snapshot) => DropdownButtonFormField<String>(
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
