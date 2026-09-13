import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/network_status_banner.dart';
import '../../shared/widgets/pen_plate.dart';
import '../inventory/session_review_screen.dart';
import '../local_activity/data/local_activity_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<RemoteInventoryTask>? _tasks;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState?>>(authControllerProvider,
        (AsyncValue<AuthState?>? previous, AsyncValue<AuthState?> next) {
      final AuthState? before = previous?.valueOrNull;
      final AuthState? after = next.valueOrNull;
      if (after?.isOffline == false && before?.isOffline != false) {
        unawaited(_loadTasks());
      }
    });
    return _buildContent(context);
  }

  Future<void> _loadTasks() async {
    final AuthState? auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      if (mounted) {
        setState(() {
          _loading = false;
          _tasks = null;
          _error = '当前离线，首页只显示本机已经保存的作业。';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _tasks = null;
    });
    try {
      final List<RemoteInventoryTask> tasks = await retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).tasks(
                  accessToken: accessToken,
                  businessDate: DateUtils.dateOnly(DateTime.now()),
                ),
      );
      if (mounted) setState(() => _tasks = tasks);
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildContent(BuildContext context) {
    final AuthState? auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<LocalCaptureActivity>>(
      stream: ref
          .watch(localActivityRepositoryProvider)
          .watchRecent(auth.user.activeOrganizationId, limit: 1000),
      builder: (BuildContext context,
          AsyncSnapshot<List<LocalCaptureActivity>> snapshot) {
        final List<LocalCaptureActivity> activities =
            snapshot.data ?? const <LocalCaptureActivity>[];
        final LocalCaptureActivity? latest =
            activities.isEmpty ? null : activities.first;
        final List<RemoteInventoryTask> tasks =
            _tasks ?? const <RemoteInventoryTask>[];
        final int confirmed = tasks
            .where((RemoteInventoryTask row) => row.status == 'confirmed')
            .length;
        final int review = tasks
            .where((RemoteInventoryTask row) => row.status == 'review_required')
            .length;
        final int pendingUploads = activities
            .where((LocalCaptureActivity row) => row.isPending)
            .length;

        return RefreshIndicator(
          onRefresh: _loadTasks,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                sliver: SliverList.list(children: <Widget>[
                  _Header(
                    organizationCode: auth.user.activeOrganizationCode,
                    organizationName: auth.user.activeOrganizationName,
                  ),
                  const SizedBox(height: 16),
                  NetworkStatusBanner(offline: auth.isOffline),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _SafeNotice(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  _ContinueCard(activity: latest),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    title: '今日真实任务',
                    action: '下拉刷新',
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_tasks == null)
                    const _EmptyCard(message: '任务状态未知，请联网后下拉重试。')
                  else if (tasks.isEmpty)
                    const _EmptyCard(message: '服务器没有返回可见任务；不会显示推测数量。')
                  else
                    ...tasks.take(4).map(_taskCard),
                  const SizedBox(height: 22),
                  const _SectionTitle(title: '今日进度', action: '真实状态'),
                  const SizedBox(height: 10),
                  _ProgressCard(
                    known: _tasks != null,
                    completed: confirmed,
                    total: tasks.length,
                    pendingUploads: pendingUploads,
                    reviewRequired: review,
                  ),
                  const SizedBox(height: 28),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _taskCard(RemoteInventoryTask task) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PenPlate(
          building: '${task.buildingCode} ${task.buildingName}',
          pen: task.penCode,
          state: _state(task.status),
          count: task.status == 'confirmed' ? task.confirmedCount : null,
          detail: _detail(task.status),
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

  String _detail(String status) => switch (status) {
        'pending' => '尚未采集',
        'submitted' => '已提交，等待处理',
        'processing' => '服务器处理中',
        'review_required' => '需要人工复核',
        'confirmed' => '确认结果和证据已锁定',
        _ => '状态异常，请刷新',
      };

  String _safeError(DioException error) => switch (error.response?.statusCode) {
        401 => '登录状态已失效；本机证据仍保留，请重新登录。',
        403 || 404 => '当前账号无法读取组织任务。',
        _ => '服务器暂时不可用；本机草稿和上传队列不受影响。',
      };
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.organizationCode, required this.organizationName});
  final String organizationCode;
  final String organizationName;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$organizationCode · $organizationName',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              Text('今天先完成现场采集',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        Semantics(
          image: true,
          label: '智慧猪场场主初版标志',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/branding/smart-pig-farm-owner-logo-v1.png',
              width: 42,
              height: 42,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ]);
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.activity});
  final LocalCaptureActivity? activity;

  @override
  Widget build(BuildContext context) {
    final LocalCaptureActivity? value = activity;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.barnBlue, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('本机最近作业',
              style: TextStyle(
                  color: Color(0xFFB9CFDC),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            value == null
                ? '尚未保存采集草稿'
                : '${value.buildingLabel} · ${value.penLabel}',
            style: const TextStyle(
                color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            value == null
                ? '选择栏舍后开始采集'
                : '${value.mediaCount} 张原始证据 · ${_activityState(value)}',
            style: const TextStyle(color: Color(0xFFD9E5EB), fontSize: 12),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: () => value?.sessionId == null
                ? context.push('/pens')
                : context.push('/inventory-sessions/${value!.sessionId}'),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.straw,
                foregroundColor: AppColors.ink),
            icon: const Icon(Icons.arrow_forward),
            label: Text(value?.sessionId == null ? '选择栏舍' : '查看服务器结果'),
          ),
        ],
      ),
    );
  }

  static String _activityState(LocalCaptureActivity value) =>
      switch (value.outboxState) {
        null => '草稿未入队',
        'synced' => '已提交服务器',
        'blocked' => '上传被阻止',
        'retry_wait' => '等待自动重试',
        _ => '等待或正在上传',
      };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        Text(action, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.known,
    required this.completed,
    required this.total,
    required this.pendingUploads,
    required this.reviewRequired,
  });
  final int completed;
  final bool known;
  final int total;
  final int pendingUploads;
  final int reviewRequired;

  @override
  Widget build(BuildContext context) {
    final double? progress = !known
        ? null
        : total == 0
            ? 0
            : completed / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              color: AppColors.herdTeal,
              backgroundColor: const Color(0xFFE4ECEF),
            ),
          ),
          const SizedBox(height: 15),
          _ProgressRow(
              label: '已确认任务',
              value: known ? '$completed / $total' : '—',
              note: '仅服务器真实状态'),
          const Divider(height: 22),
          _ProgressRow(
              label: '本机待上传', value: '$pendingUploads', note: '草稿原图继续保留'),
          const Divider(height: 22),
          _ProgressRow(
              label: '等待复核',
              value: known ? '$reviewRequired' : '—',
              note: '候选数量不进入报表'),
        ]),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(
      {required this.label, required this.value, required this.note});
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(note, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.barnBlue)),
      ]);
}

class _SafeNotice extends StatelessWidget {
  const _SafeNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.review.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message),
        ),
      );
}
