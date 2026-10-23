import 'dart:async';
import 'package:dio/dio.dart';
import 'inventory_revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';
import '../gallery/server_gallery_screen.dart';
import 'annotated_evidence.dart';
import 'density_heatmap.dart';

final inventoryRemoteApiProvider = Provider<InventoryRemoteApi>(
  (ref) => InventoryRemoteApi(baseUrl: ref.watch(apiBaseUrlProvider)),
);

class SessionReviewScreen extends ConsumerStatefulWidget {
  const SessionReviewScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SessionReviewScreen> createState() =>
      _SessionReviewScreenState();
}

class _SessionReviewScreenState extends ConsumerState<SessionReviewScreen>
    with WidgetsBindingObserver
    implements RouteAware {
  final _countController = TextEditingController();
  final _reasonController = TextEditingController();
  RemoteInventorySession? _session;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _reading = false;
  Timer? _poll;
  DateTime? _pollUntil;
  DateTime? _lastRead;
  int _generation = 0;
  String? _intentKey;
  String? _intent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant SessionReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId == widget.sessionId) return;
    _generation++;
    _poll?.cancel();
    _pollUntil = null;
    _session = null;
    _lastRead = null;
    _countController.clear();
    _reasonController.clear();
    unawaited(_load(restart: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) inventoryRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() {}
  @override
  void didPop() {
    _poll?.cancel();
  }

  @override
  void didPushNext() {
    _poll?.cancel();
  }

  @override
  void didPopNext() {
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    inventoryRouteObserver.unsubscribe(this);
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _countController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    final auth = ref.read(authControllerProvider).valueOrNull;
    return auth != null &&
        !auth.isOffline &&
        auth.user.roles.any((String role) =>
            <String>['REVIEWER', 'FARM_ADMIN', 'SYSTEM_ADMIN'].contains(role));
  }

  String _identity(AuthState auth) =>
      '${auth.user.subjectId}/${auth.user.activeOrganizationId}';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poll?.cancel();
    if (state == AppLifecycleState.resumed) _load();
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!mounted ||
        _submitting ||
        !['submitted', 'processing'].contains(_session?.status)) {
      return;
    }
    final now = ref.read(inventoryClockProvider)();
    _pollUntil ??= now.add(const Duration(seconds: 60));
    if (!now.isBefore(_pollUntil!)) return;
    _poll = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  Future<void> _load({bool restart = false}) async {
    if (_reading || _submitting) return;
    if (restart) _pollUntil = null;
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '离线时仅保留本机证据；联网后可重新读取。';
        });
      }
      return;
    }
    final generation = ++_generation;
    final sessionId = widget.sessionId;
    final identity = _identity(auth);
    _reading = true;
    if (mounted) {
      setState(() {
        _loading = _session == null;
        _error = null;
      });
    }
    try {
      final session = await _readSession(auth, sessionId);
      final current = ref.read(authControllerProvider).valueOrNull;
      if (!mounted ||
          generation != _generation ||
          sessionId != widget.sessionId ||
          current == null ||
          identity != _identity(current)) {
        return;
      }
      final previous = _session;
      setState(() {
        _session = session;
        _loading = false;
        _lastRead = DateTime.now();
      });
      if (previous != null &&
          ['confirmed', 'superseded'].contains(session.status) &&
          (previous.status != session.status ||
              previous.version != session.version)) {
        ref.read(inventoryRevisionProvider.notifier).state++;
      }
      _schedulePoll();
    } on DioException catch (error) {
      if (!mounted || generation != _generation) return;
      _poll?.cancel();
      setState(() {
        _loading = false;
        _error = _safeError(error);
      });
    } finally {
      _reading = false;
      if (mounted && generation != _generation) unawaited(_load(restart: true));
    }
  }

  Future<void> _confirm() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final int? count = int.tryParse(_countController.text.trim());
    if (auth == null ||
        auth.isOffline ||
        count == null ||
        count < 0 ||
        count > 2147483647) {
      _show('请输入不小于 0 的确认数量，并保持联网。');
      return;
    }
    final RemoteInventorySession? current = _session;
    final String reason =
        _reasonController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if ((current?.rawModelCount == null || current!.rawModelCount != count) &&
        reason.length < 8) {
      _show('人工确认或修改候选数量时，请填写至少 8 个字符的原因。');
      return;
    }
    setState(() => _submitting = true);
    _generation++; // Invalidate a manual read already in flight before confirming.
    final generation = _generation;
    final sessionId = widget.sessionId;
    _poll?.cancel();
    final intent = '${_identity(auth)}/$sessionId/$count/$reason';
    if (_intent != intent) {
      _intent = intent;
      _intentKey = const Uuid().v4();
    }
    final String idempotencyKey = _intentKey!;
    try {
      final RemoteInventorySession confirmed = await retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).confirm(
                  accessToken: accessToken,
                  sessionId: sessionId,
                  idempotencyKey: idempotencyKey,
                  confirmedCount: count,
                  reason: reason.isEmpty ? null : reason,
                ),
      );
      if (!mounted ||
          generation != _generation ||
          sessionId != widget.sessionId) {
        return;
      }
      final currentAuth = ref.read(authControllerProvider).valueOrNull;
      if (currentAuth == null || _identity(currentAuth) != _identity(auth)) {
        return;
      }
      setState(() => _session = confirmed);
      ref.read(inventoryRevisionProvider.notifier).state++;
      _show('已确认数量，引用原图已锁定并写入审计记录。');
    } on DioException catch (error) {
      if (mounted && generation == _generation) _show(_safeError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        if (generation != _generation) unawaited(_load(restart: true));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before?.user.subjectId != after?.user.subjectId ||
          before?.user.activeOrganizationId !=
              after?.user.activeOrganizationId) {
        _generation++;
        _poll?.cancel();
        setState(() {
          _session = null;
          _loading = true;
          _error = null;
          _countController.clear();
          _reasonController.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(restart: true);
        });
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('盘点复核'), actions: [
        IconButton(
            tooltip: '刷新结果',
            onPressed: _submitting ? null : () => _load(restart: true),
            icon: const Icon(Icons.refresh))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(
                  message: _error!, onRetry: () => _load(restart: true))
              : _session == null
                  ? const Center(child: Text('请重新读取当前账号的会话'))
                  : _body(context, _session!),
    );
  }

  Widget _body(BuildContext context, RemoteInventorySession session) {
    final bool editable = session.requiresReview && _canConfirm;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        if (_lastRead != null) Text('最近读取：${_lastRead!.toLocal()}'),
        if (_error != null) Text(_error!),
        Text('业务日期 ${session.businessDate} · 版本 v${session.version}',
            style: Theme.of(context).textTheme.titleMedium),
        if (session.supersedesSessionId != null) ...<Widget>[
          const SizedBox(height: 4),
          Text('该结果为审计更正版本；原始证据未被覆盖。',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 4),
        Text('栏舍 ID ${session.penId}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        _StatusCard(session: session),
        if (session.detections.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          AnnotatedEvidenceSection(
              sessionId: session.evidenceSessionId ?? session.id,
              detections: session.detections),
          const SizedBox(height: 12),
          ...session.detections.map((d) => d.assetId).toSet().map((assetId) =>
              DensityHeatmapCard(
                  detections: session.detections
                      .where((d) => d.assetId == assetId)
                      .toList())),
        ],
        ServerGalleryScreen(
            key: ValueKey('${session.id}-${session.status}'),
            sessionId: session.id),
        if (session.inferenceStatus == 'failed') ...<Widget>[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Card(
              color: AppColors.review.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('自动计数失败，已安全转人工复核'),
                    const SizedBox(height: 6),
                    Text(session.failureCode ?? 'PROVIDER_ERROR',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(session.failureMessage ?? '推理服务未返回可用结果。'),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (session.requiresReview) ...<Widget>[
          const SizedBox(height: 16),
          Text('复核说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (session.warnings.isEmpty)
            Text(session.rawModelCount == null
                ? '服务器尚无可用候选数量；请核验原始证据后人工清点。确认会锁定引用证据并写入审计。'
                : '机器候选仅供核验；确认数量须由复核员对照原始证据后填写。')
          else
            ...session.warnings.map((String warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $warning'),
                )),
        ],
        if (session.rawModelCount != null &&
            session.requiresReview) ...<Widget>[
          const SizedBox(height: 16),
          _AiSuggestionCard(
            candidateCount: session.rawModelCount!,
            onApply: editable
                ? () => setState(() {
                      _countController.text = session.rawModelCount.toString();
                    })
                : null,
          ),
        ],
        if (editable) ...<Widget>[
          const SizedBox(height: 22),
          Text('人工确认', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('确认后，所有引用原图会锁定；后续更正必须通过管理员审计流程。',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '确认数量（头）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '修正原因',
              hintText: '候选数量为空或与确认数量不同则必填（至少 8 个字符）',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _confirm,
            child: Text(_submitting ? '正在确认…' : '确认并锁定证据'),
          ),
        ] else if (session.requiresReview) ...<Widget>[
          const SizedBox(height: 20),
          const Text('当前账号没有复核权限。请由复核员或猪场管理员确认，原始证据会继续保留。'),
        ],
      ],
    );
  }

  Future<RemoteInventorySession> _readSession(
          AuthState auth, String sessionId) =>
      retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).session(
                  accessToken: accessToken,
                  sessionId: sessionId,
                ),
      );

  String _safeError(DioException error) => switch (error.response?.statusCode) {
        401 => '登录状态已失效，请重新登录。',
        403 || 404 => '无法读取该盘点结果或没有权限。',
        409 => '该盘点状态已变化，请刷新后再操作。',
        _ => '服务器暂时无法完成复核操作；原始证据未受影响。',
      };

  void _show(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.session});

  final RemoteInventorySession session;

  @override
  Widget build(BuildContext context) {
    final bool confirmed = session.confirmed;
    final Color color = confirmed ? AppColors.herdTeal : AppColors.review;
    final String label = sessionStatusLabel(session.status);
    final value = ['confirmed', 'superseded'].contains(session.status)
        ? session.count
        : session.status == 'review_required'
            ? session.rawModelCount
            : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (value == null)
                const Text('尚无可用于确认的数量；可核验原始证据或刷新状态')
              else
                Text('$value 头',
                    style: Theme.of(context).textTheme.displaySmall),
              if (confirmed &&
                  session.rawModelCount != null &&
                  session.rawModelCount != session.count) ...<Widget>[
                const SizedBox(height: 4),
                Text('模型候选：${session.rawModelCount} 头',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({required this.candidateCount, this.onApply});
  final int candidateCount;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.barnBlue.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Text('🤖', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('AI 建议数量：$candidateCount 头',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text(
                '这是服务端返回的候选，模型分数不代表准确率。'
                '请对照标注核验后再确认；如与实际不符，直接修改数量即可。',
                style: Theme.of(context).textTheme.bodySmall),
            if (onApply != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.edit, size: 18),
                label: Text('带入建议数量 $candidateCount'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
          ]),
        ),
      );
}

String sessionStatusLabel(String status) => switch (status) {
      'draft' => '草稿',
      'submitted' => '已提交，等待处理',
      'processing' => '服务器处理中',
      'review_required' => '等待人工复核',
      'confirmed' => '已确认并锁定',
      'superseded' => '历史版本，已被替代',
      _ => '状态未知，请刷新核实',
    };
