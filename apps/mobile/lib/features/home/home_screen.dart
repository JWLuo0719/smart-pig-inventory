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
import '../../shared/widgets/insight_icon.dart';
import 'cockpit_widgets.dart';
import '../assistant/assistant_screen.dart';
import '../inventory/session_review_screen.dart';
import '../profile/profile_screen.dart';
import '../tasks/task_list_screen.dart';
import '../local_activity/data/local_activity_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({this.showToolbar = true, super.key});
  final bool showToolbar;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _building;
  bool _sunlight = false;
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
    // The optional panel is independent of the task projection and stays collapsed.
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
                row.draftState != 'abandoned' &&
                (row.isPending || row.draftState == 'draft'))
            .firstOrNull;
        final List<RemoteInventoryTask> tasks =
            _tasks ?? const <RemoteInventoryTask>[];
        final buildings = <String, String>{
          for (final task in tasks)
            task.buildingCode: '${task.buildingCode} ${task.buildingName}',
        };
        final building = buildings.containsKey(_building)
            ? _building
            : buildings.keys.firstOrNull;
        final scoped =
            tasks.where((task) => task.buildingCode == building).toList();
        final confirmed =
            scoped.where((task) => task.status == 'confirmed').toList();
        final heads = _tasks != null &&
                confirmed.every((task) => task.confirmedCount != null)
            ? confirmed.fold<int>(0, (sum, task) => sum + task.confirmedCount!)
            : null;
        final pending = snapshot.hasData && !snapshot.hasError
            ? activities.where((row) => row.isPending).length
            : null;
        final body = RefreshIndicator(
          onRefresh: _loadTasks,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
            children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      border: Border.all(color: cockpitLine),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: cockpitMuted),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(auth.user.activeOrganizationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF475569)))),
                    const Icon(Icons.chevron_right,
                        size: 15, color: cockpitMuted),
                    const SizedBox(width: 6),
                    Flexible(
                        child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                      value: building,
                      isExpanded: true,
                      isDense: true,
                      hint: const Text('栋舍待获取', style: TextStyle(fontSize: 11)),
                      icon: const Icon(Icons.expand_more, size: 16),
                      items: buildings.entries
                          .map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700))))
                          .toList(),
                      onChanged: (value) => setState(() => _building = value),
                    ))),
                  ])),
              const SizedBox(height: 12),
              if (auth.isOffline)
                const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('离线保存 · 联网后上传',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w700))),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _SafeNotice(message: _error!),
              ],
              const SizedBox(height: 12),
              CockpitSummary(
                  scope: _Header._todayLabel(),
                  heads: heads,
                  confirmed: _tasks == null ? null : confirmed.length,
                  total: _tasks == null ? null : scoped.length,
                  review: _tasks == null
                      ? null
                      : scoped
                          .where((task) => task.status == 'review_required')
                          .length,
                  onAssistant: _openAssistant,
                  onReport: _openReports,
                  onHistory: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('历史任务')),
                              body: const TaskListScreen()))),
                  onModules: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('更多能力')),
                              body: ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: const [CockpitModules()]))))),
              const SizedBox(height: 12),
              if (_tasks != null)
                CockpitMatrix(
                    key:
                        ValueKey('${auth.user.activeOrganizationId}/$building'),
                    tasks: scoped,
                    onOpen: _openTask)
              else if (_error == null)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('正在读取今日栏舍任务…'))),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                title: const Text('协同研判',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                children: [
                  if (_assistantLoading)
                    const Padding(
                        padding: EdgeInsets.all(14), child: Text('正在读取今日规则研判…'))
                  else if (_assistantError != null)
                    Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_assistantError!,
                                  style: const TextStyle(fontSize: 12)),
                              TextButton(
                                  onPressed: _retryAssistant,
                                  child: const Text('重新读取研判')),
                            ]))
                  else if (_assistant != null)
                    _AssistantPanel(brief: _assistant!),
                ],
              ),
              if (latest != null) _ContinueCard(activity: latest),
            ],
          ),
        );
        if (!widget.showToolbar) return body;
        return Column(children: [
          CockpitToolbar(
              name: auth.user.displayName,
              offline: auth.isOffline,
              pending: pending,
              onQueue: () => context.push('/outbox'),
              onProfile: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                          body: SafeArea(child: ProfileScreen())))),
              onSunlight: () => setState(() => _sunlight = !_sunlight),
              sunlight: _sunlight),
          Expanded(
              child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_sunlight
                      ? const [
                          1.15,
                          0,
                          0,
                          0,
                          -18,
                          0,
                          1.15,
                          0,
                          0,
                          -18,
                          0,
                          0,
                          1.15,
                          0,
                          -18,
                          0,
                          0,
                          0,
                          1,
                          0
                        ]
                      : const [
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0
                        ]),
                  child: body)),
        ]);
      },
    );
  }

  void _openAssistant() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen()));

  void _openReports() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const InventoryReportsScreen()));

  void _openTask(RemoteInventoryTask task) {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null) return;
    if (task.sessionId != null) {
      context.push('/inventory-sessions/${task.sessionId}');
    } else {
      context.push('/capture',
          extra: CaptureTarget(
            organizationId: auth.user.activeOrganizationId,
            penId: task.penId,
            label:
                '${task.buildingCode} ${task.buildingName} · ${task.penCode} ${task.penName}',
            businessDate: DateUtils.dateOnly(DateTime.now()),
          ));
    }
  }

  String _safeError(DioException error) => switch (error.response?.statusCode) {
        401 => '登录状态已失效；本机证据仍保留，请重新登录。',
        403 || 404 => '当前账号无法读取组织任务。',
        _ => '服务器暂时不可用；本机草稿和上传队列不受影响。',
      };
}

class _Header {
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
    if (value == null) return const SizedBox.shrink();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: const Icon(Icons.history_outlined, color: cockpitInk),
      title: Text('继续作业 · ${value.buildingLabel} · ${value.penLabel}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text('${value.mediaCount} 份证据 · ${_activityState(value)}',
          style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final auth = ref.read(authControllerProvider).valueOrNull;
        if (auth == null) return;
        // Read the actual draft again; recent activity may have changed while the card was visible.
        final db = ref.read(appDatabaseProvider);
        final draft = await (db.select(db.captureDrafts)
              ..where((d) =>
                  d.id.equals(value.draftId) &
                  d.organizationId.equals(auth.user.activeOrganizationId)))
            .getSingleOrNull();
        if (!context.mounted ||
            draft == null ||
            ref.read(authControllerProvider).valueOrNull?.user.subjectId !=
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

class _SafeNotice extends StatelessWidget {
  const _SafeNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.review.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 17, color: AppColors.review),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
              child:
                  Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class _AssistantPanel extends ConsumerWidget {
  const _AssistantPanel({required this.brief});
  final RemoteAssistantBrief brief;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                    child: Text('今日规则研判',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w800, fontSize: 13))),
                const ModelBadge(label: '规则'),
                const SizedBox(width: AppSpacing.xs),
                Text(brief.businessDate.substring(5),
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: AppSpacing.xxs),
              Text(brief.brief,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
              const Divider(height: AppSpacing.lg),
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
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 32,
      leading: SeverityIcon(insight.severity),
      title: Text(insight.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(insight.detail,
              style: const TextStyle(fontSize: 12, height: 1.45)),
          if (insight.basis != null)
            Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding:
                        const EdgeInsets.only(bottom: AppSpacing.xs),
                    visualDensity: VisualDensity.compact,
                    title: Text('查看数据依据',
                        style: Theme.of(context).textTheme.bodySmall),
                    children: [
                      Text(
                          '来源：${switch (insight.basis!['valueSource']) {
                            'confirmed' => '人工确认',
                            'candidate' => '服务端候选',
                            _ => '未知'
                          }}；基线：${insight.basis!['baselineValue'] ?? '未知'}；样本${insight.basis!['sampleCount']}次；${insight.basis!['from'] ?? '—'} 至 ${insight.basis!['to'] ?? '—'}',
                          style: Theme.of(context).textTheme.bodySmall)
                    ])),
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
}
