import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/inventory_api.dart';
import '../../shared/widgets/network_status_banner.dart';
import '../../shared/widgets/pen_plate.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final DateTime _businessDate = DateUtils.dateOnly(DateTime.now());
  List<RemoteInventoryTask>? _tasks;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      setState(() {
        _loading = false;
        _error = '离线时无法刷新任务；已保存的采集草稿仍可继续处理。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await InventoryRemoteApi(
        baseUrl: ref.read(apiBaseUrlProvider),
      ).tasks(
        accessToken: auth.session.accessToken,
        businessDate: _businessDate,
      );
      if (mounted) setState(() => _tasks = tasks);
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date =
        MaterialLocalizations.of(context).formatMediumDate(_businessDate);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: <Widget>[
          Text('盘点任务', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('$date · 只显示当前组织已启用栏舍的真实任务状态。',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          NetworkStatusBanner(
            offline: ref.watch(authControllerProvider).valueOrNull?.isOffline,
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _TaskError(message: _error!, onRetry: _load)
          else if (_tasks!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('今天没有启用栏舍任务。')),
            )
          else
            ..._tasks!.map(_taskCard),
        ],
      ),
    );
  }

  Widget _taskCard(RemoteInventoryTask task) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PenPlate(
          building: '${task.buildingCode} ${task.buildingName}',
          pen: task.penCode,
          state: _state(task.status),
          count: task.status == 'confirmed' ? task.confirmedCount : null,
          detail: _detail(task),
          onTap: task.sessionId == null
              ? () => context.push('/pens')
              : () => context.push('/inventory-sessions/${task.sessionId}'),
        ),
      );

  PenWorkState _state(String status) => switch (status) {
        'pending' => PenWorkState.notStarted,
        'submitted' => PenWorkState.queued,
        'processing' => PenWorkState.processing,
        'review_required' => PenWorkState.review,
        'confirmed' => PenWorkState.confirmed,
        _ => PenWorkState.failed,
      };

  String _detail(RemoteInventoryTask task) => switch (task.status) {
        'pending' => '尚未采集，点击选择栏舍开始',
        'submitted' => '上传已提交，等待推理任务领取',
        'processing' => '服务器正在处理原始证据',
        'review_required' => '需要人工复核，原图仍安全保留',
        'confirmed' => '确认结果已锁定引用原图',
        _ => '任务状态异常，请刷新后查看',
      };

  String _safeError(DioException error) => switch (error.response?.statusCode) {
        401 => '登录状态已失效，请重新登录。',
        403 || 404 => '无法读取当前组织的任务。',
        _ => '无法连接服务器；下拉可再次尝试，已保存证据不会丢失。',
      };
}

class _TaskError extends StatelessWidget {
  const _TaskError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
          ]),
        ),
      );
}
