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
import '../inventory/session_review_screen.dart';
import '../../shared/widgets/network_status_banner.dart';
import '../local_activity/data/local_activity_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<RemoteInventoryTask>? _tasks;
  RemoteAssistantBrief? _assistant;
  String? _error;

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

  Future<RemoteAssistantBrief?> _loadAssistant(AuthState auth, DateTime today) async {
    try {
      return await ref.read(inventoryRemoteApiProvider).assistantInsights(
          accessToken: auth.session.accessToken, businessDate: today);
    } catch (_) {
      return null; // 研判不可用时静默降级，不阻塞首页
    }
  }

  Future<void> _loadTasks() async {
    final AuthState? auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      if (mounted) {
        setState(() {
          _tasks = null;
          _error = '当前离线，首页只显示本机已经保存的作业。';
        });
      }
      return;
    }
    setState(() {
      _error = null;
      _tasks = null;
      _assistant = null;
    });
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    // 智能体研判与任务并行加载；研判失败不打扰任务展示（静默降级）。
    final Future<RemoteAssistantBrief?> assistantFuture =
        _loadAssistant(auth, today);
    try {
      final List<RemoteInventoryTask> tasks = await retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).tasks(
                  accessToken: accessToken,
                  businessDate: today,
                ),
      );
      final RemoteAssistantBrief? assistant = await assistantFuture;
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _assistant = assistant;
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {

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
                  if (_assistant != null && _assistant!.insights.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 22),
                    _AssistantPanel(brief: _assistant!),
                  ],
                  const SizedBox(height: 22),
                  const _SectionTitle(title: '今日进度', action: '以服务器为准'),
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
              Text('${_todayLabel()} · $organizationCode · $organizationName',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              Text('今日盘点与复核',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        Semantics(
          image: true,
          label: '智慧猪场场主标志',
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

  static String _todayLabel() {
    final DateTime now = DateTime.now();
    const List<String> weekdays = <String>[
      '周一', '周二', '周三', '周四', '周五', '周六', '周日'
    ];
    return '${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}';
  }
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
                ? '今天还没有采集记录'
                : '${value.buildingLabel} · ${value.penLabel}',
            style: const TextStyle(
                color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            value == null
                ? '选择栏舍拍照，几分钟完成一栏盘点'
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
              note: '复核确认后才计入存栏'),
          const Divider(height: 22),
          _ProgressRow(
              label: '本机待上传', value: '$pendingUploads', note: '断网先拍，联网自动补传'),
          const Divider(height: 22),
          _ProgressRow(
              label: '等待复核',
              value: known ? '$reviewRequired' : '—',
              note: '确认数量后锁定证据'),
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

class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel({required this.brief});
  final RemoteAssistantBrief brief;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                const Text('🤖', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('牧数智核 · 今日研判',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800))),
                Text(brief.businessDate.substring(5),
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 6),
              Text(brief.brief,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              const Divider(height: 18),
              ...brief.insights.map((RemoteAssistantInsight insight) =>
                  _insightTile(context, insight)),
            ],
          ),
        ),
      );

  Widget _insightTile(BuildContext context, RemoteAssistantInsight insight) {
    final bool tappable =
        insight.sessionId != null || insight.type == 'PENDING_CAPTURE';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: _severityIcon(insight.severity),
      title: Text(insight.title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(insight.detail,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
      ),
      trailing: tappable
          ? const Icon(Icons.chevron_right, size: 20)
          : null,
      onTap: !tappable
          ? null
          : () => insight.sessionId != null
              ? context.push('/inventory-sessions/${insight.sessionId}')
              : context.push('/pens'),
    );
  }

  static Widget _severityIcon(String severity) => switch (severity) {
        'action' => const Text('⚠️', style: TextStyle(fontSize: 18)),
        'success' => const Text('✅', style: TextStyle(fontSize: 18)),
        'warning' => const Text('⚠️', style: TextStyle(fontSize: 18)),
        _ => const Text('💡', style: TextStyle(fontSize: 18)),
      };
}

