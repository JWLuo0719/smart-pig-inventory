import 'package:drift/drift.dart' show BooleanExpressionOperators;
import '../capture/domain/capture_target.dart';
import '../../core/storage/database_provider.dart';
import 'dart:async';
import '../inventory/inventory_revision.dart';
import '../inventory/inventory_reports_screen.dart';

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
  int _generation = 0;
  int _assistantGeneration = 0;
  List<RemoteInventoryTask>? _tasks;
  RemoteAssistantBrief? _assistant;
  bool _assistantLoading = false;
  String? _assistantError;
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
      if (after?.isOffline != before?.isOffline ||
          after?.user.subjectId != before?.user.subjectId ||
          after?.user.activeOrganizationId !=
              before?.user.activeOrganizationId) {
        unawaited(_loadTasks());
      }
    });
    ref.listen(inventoryRevisionProvider, (_, __) {
      unawaited(_loadTasks());
    });
    return _buildContent(context);
  }

  bool _isCurrent(AuthState auth, int generation) {
    if (!mounted) return false;
    final current = ref.read(authControllerProvider).valueOrNull;
    return generation == _generation &&
        current?.user.subjectId == auth.user.subjectId &&
        current?.user.activeOrganizationId == auth.user.activeOrganizationId &&
        current?.isOffline == false;
  }

  Future<void> _loadAssistant(
      AuthState auth, DateTime today, int generation) async {
    final assistantGeneration = ++_assistantGeneration;
    if (!_isCurrent(auth, generation)) return;
    setState(() {
      _assistant = null;
      _assistantLoading = true;
      _assistantError = null;
    });
    try {
      final brief = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (token) => ref
              .read(inventoryRemoteApiProvider)
              .assistantInsights(accessToken: token, businessDate: today));
      if (_isCurrent(auth, generation) &&
          assistantGeneration == _assistantGeneration) {
        setState(() => _assistant = brief);
      }
    } catch (_) {
      if (_isCurrent(auth, generation) &&
          assistantGeneration == _assistantGeneration) {
        setState(() => _assistantError = '规则研判暂时不可用，今日任务和本机证据仍可继续使用。');
      }
    } finally {
      if (_isCurrent(auth, generation) &&
          assistantGeneration == _assistantGeneration) {
        setState(() => _assistantLoading = false);
      }
    }
  }

  Future<void> _retryAssistant() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) return;
    await _loadAssistant(auth, DateUtils.dateOnly(DateTime.now()), _generation);
  }

  Future<void> _loadTasks() async {
    final generation = ++_generation;
    final AuthState? auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      if (mounted) {
        setState(() {
          _tasks = null;
          _assistant = null;
          _assistantLoading = false;
          _assistantError = null;
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
    // The optional panel must never hold the task projection behind its request.
    unawaited(_loadAssistant(auth, today, generation));
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
      if (_isCurrent(auth, generation)) {
        setState(() {
          _tasks = tasks;
        });
      }
    } on DioException catch (error) {
      if (_isCurrent(auth, generation)) {
        setState(() => _error = _safeError(error));
      }
    }
  }

  Widget _buildContent(BuildContext context) {
    final AuthState? auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<LocalCaptureActivity>>(
      key: ValueKey(auth.user.activeOrganizationId),
      stream: ref
          .watch(localActivityRepositoryProvider)
          .watchRecent(auth.user.activeOrganizationId, limit: 1000),
      builder: (BuildContext context,
          AsyncSnapshot<List<LocalCaptureActivity>> snapshot) {
        final List<LocalCaptureActivity> activities =
            snapshot.data ?? const <LocalCaptureActivity>[];
        final LocalCaptureActivity? latest = activities
            .where((row) =>
                row.draftState != 'abandoned' && row.outboxState != 'abandoned')
            .firstOrNull;
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
                  if (_assistantLoading ||
                      _assistantError != null ||
                      _assistant != null) ...<Widget>[
                    const SizedBox(height: 22),
                    if (_assistantLoading)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('正在读取今日规则研判…')))
                    else if (_assistantError != null)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_assistantError!),
                                    TextButton(
                                        onPressed: _retryAssistant,
                                        child: const Text('重新读取研判')),
                                  ])))
                    else
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
              Text('今日盘点与复核', style: Theme.of(context).textTheme.headlineSmall),
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
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日'
    ];
    return '${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}';
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.activity});
  final LocalCaptureActivity? activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onPressed: () async {
              final auth = ref.read(authControllerProvider).valueOrNull;
              if (auth == null) return;
              if (value == null) {
                context.push('/pens');
                return;
              }
              // Read the actual draft again; recent activity may have changed while the card was visible.
              final db = ref.read(appDatabaseProvider);
              final draft = await (db.select(db.captureDrafts)
                    ..where((d) =>
                        d.id.equals(value.draftId) &
                        d.organizationId
                            .equals(auth.user.activeOrganizationId)))
                  .getSingleOrNull();
              if (!context.mounted ||
                  draft == null ||
                  ref
                          .read(authControllerProvider)
                          .valueOrNull
                          ?.user
                          .subjectId !=
                      auth.user.subjectId ||
                  ref
                          .read(authControllerProvider)
                          .valueOrNull
                          ?.user
                          .activeOrganizationId !=
                      auth.user.activeOrganizationId) {
                return;
              }
              if (value.sessionId != null) {
                context.push('/inventory-sessions/${value.sessionId}');
              } else if (value.outboxState != null) {
                context.push('/outbox');
              } else if (draft.state == 'draft') {
                context.push('/capture',
                    extra: CaptureTarget(
                        organizationId: draft.organizationId,
                        penId: draft.penId,
                        label: '${value.buildingLabel} · ${value.penLabel}',
                        businessDate: draft.businessDate,
                        draftId: draft.id));
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.straw,
                foregroundColor: AppColors.ink),
            icon: const Icon(Icons.arrow_forward),
            label: Text(value == null
                ? '选择栏舍'
                : value.sessionId != null
                    ? '查看服务器结果'
                    : value.outboxState != null
                        ? '查看上传作业'
                        : '继续本份草稿'),
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

class _AssistantPanel extends ConsumerWidget {
  const _AssistantPanel({required this.brief});
  final RemoteAssistantBrief brief;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
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
                    child: Text('今日规则研判',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800))),
                Text(brief.businessDate.substring(5),
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 6),
              Text(brief.brief,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
              const Divider(height: 18),
              ...brief.insights.map((RemoteAssistantInsight insight) =>
                  _insightTile(context, ref, insight)),
            ],
          ),
        ),
      );

  Widget _insightTile(
      BuildContext context, WidgetRef ref, RemoteAssistantInsight insight) {
    final kind = insight.actionTarget?['kind'] as String?;
    final bool tappable = insight.sessionId != null ||
        ['capture', 'report', 'master_data'].contains(kind);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: _severityIcon(insight.severity),
      title: Text(insight.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(insight.detail, style: const TextStyle(fontSize: 12.5)),
          if (insight.basis != null)
            ExpansionTile(title: const Text('查看数据依据'), children: [
              Text('来源：${switch (insight.basis!['valueSource']) {
                'confirmed' => '人工确认',
                'candidate' => '服务端候选',
                _ => '未知'
              }}；基线：${insight.basis!['baselineValue'] ?? '未知'}；样本${insight.basis!['sampleCount']}次；${insight.basis!['from'] ?? '—'} 至 ${insight.basis!['to'] ?? '—'}')
            ]),
        ]),
      ),
      trailing: tappable ? const Icon(Icons.chevron_right, size: 20) : null,
      onTap: !tappable
          ? null
          : () async {
              if (insight.sessionId != null) {
                context.push('/inventory-sessions/${insight.sessionId}');
                return;
              }
              if (kind == 'report') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const InventoryReportsScreen()));
                return;
              }
              final targetId = insight.actionTarget?['id'] as String?;
              final auth = ref.read(authControllerProvider).valueOrNull;
              if (kind != 'capture' || targetId == null || auth == null) {
                context.push('/pens');
                return;
              }
              final db = ref.read(appDatabaseProvider);
              final pen = await (db.select(db.cachedPens)
                    ..where((p) => p.id.equals(targetId)))
                  .getSingleOrNull();
              if (pen == null || !pen.enabled) {
                if (context.mounted) context.push('/pens');
                return;
              }
              final building = await (db.select(db.cachedBuildings)
                    ..where((b) =>
                        b.id.equals(pen.buildingId) &
                        b.organizationId
                            .equals(auth.user.activeOrganizationId)))
                  .getSingleOrNull();
              final current = ref.read(authControllerProvider).valueOrNull;
              if (!context.mounted ||
                  current?.user.subjectId != auth.user.subjectId ||
                  current?.user.activeOrganizationId !=
                      auth.user.activeOrganizationId) {
                return;
              }
              if (building == null || !building.enabled) {
                context.push('/pens');
                return;
              }
              context.push('/capture',
                  extra: CaptureTarget(
                      organizationId: auth.user.activeOrganizationId,
                      penId: pen.id,
                      label: '${building.code} / ${pen.code} ${pen.name}',
                      businessDate: DateUtils.dateOnly(DateTime.now())));
            },
    );
  }

  static Widget _severityIcon(String severity) => switch (severity) {
        'action' => const Text('⚠️', style: TextStyle(fontSize: 18)),
        'success' => const Text('✅', style: TextStyle(fontSize: 18)),
        'warning' => const Text('⚠️', style: TextStyle(fontSize: 18)),
        _ => const Text('💡', style: TextStyle(fontSize: 18)),
      };
}
