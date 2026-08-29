import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';

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

class _SessionReviewScreenState extends ConsumerState<SessionReviewScreen> {
  final _countController = TextEditingController();
  final _reasonController = TextEditingController();
  RemoteInventorySession? _session;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      setState(() {
        _loading = false;
        _error = '离线时仅保留本机证据；连接服务器后才能读取复核结果。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final RemoteInventorySession session = await _readSession(auth);
      if (!mounted) return;
      setState(() {
        _session = session;
        _countController.text = session.count?.toString() ?? '';
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _safeError(error);
      });
    }
  }

  Future<void> _confirm() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final int? count = int.tryParse(_countController.text.trim());
    if (auth == null || auth.isOffline || count == null || count < 0) {
      _show('请输入不小于 0 的确认数量，并保持联网。');
      return;
    }
    final RemoteInventorySession? current = _session;
    final String reason = _reasonController.text.trim();
    if ((current?.rawModelCount == null || current!.rawModelCount != count) &&
        reason.length < 8) {
      _show('人工确认或修改候选数量时，请填写至少 8 个字符的原因。');
      return;
    }
    setState(() => _submitting = true);
    final String idempotencyKey = const Uuid().v4();
    try {
      final RemoteInventorySession confirmed = await retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).confirm(
                  accessToken: accessToken,
                  sessionId: widget.sessionId,
                  idempotencyKey: idempotencyKey,
                  confirmedCount: count,
                  reason: reason.isEmpty ? null : reason,
                ),
      );
      if (!mounted) return;
      setState(() => _session = confirmed);
      _show('已确认数量，引用原图已锁定并写入审计记录。');
    } on DioException catch (error) {
      if (mounted) _show(_safeError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('盘点复核')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _body(context, _session!),
    );
  }

  Widget _body(BuildContext context, RemoteInventorySession session) {
    final bool editable = session.requiresReview && _canConfirm;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('业务日期 ${session.businessDate}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('栏舍 ID ${session.penId}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        _StatusCard(session: session),
        if (session.requiresReview) ...<Widget>[
          const SizedBox(height: 16),
          Text('复核说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (session.warnings.isEmpty)
            const Text(
                '自动计数已安全停用：服务器没有返回可用候选数量。请核验原始证据后人工输入数量；确认会锁定引用原图并写入审计记录。')
          else
            ...session.warnings.map((String warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $warning'),
                )),
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

  Future<RemoteInventorySession> _readSession(AuthState auth) =>
      retryOnceAfterUnauthorized(
        initialAuth: auth,
        reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
        request: (String accessToken) =>
            ref.read(inventoryRemoteApiProvider).session(
                  accessToken: accessToken,
                  sessionId: widget.sessionId,
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
    final String label = confirmed ? '已确认并锁定' : '等待人工复核';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (session.count == null)
                const Text('服务器未返回可用候选数量')
              else
                Text('${session.count} 头',
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
