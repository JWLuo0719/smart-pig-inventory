import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/assistant_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/field_header.dart';
import '../inventory/inventory_reports_screen.dart';

final assistantApiProvider = Provider<AssistantApi>(
    (ref) => AssistantApi(baseUrl: ref.watch(apiBaseUrlProvider)));

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen(
      {this.penId,
      this.sessionId,
      this.businessDate,
      this.scopeLabel,
      super.key});
  final String? penId;
  final String? sessionId;
  final DateTime? businessDate;
  final String? scopeLabel;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _message = TextEditingController();
  CancelToken _cancel = CancelToken();
  int _generation = 0;
  bool? _enabled;
  bool _busy = false;
  String? _error;
  AssistantReply? _reply;
  String? _owner;

  String? _identity(AuthState? auth) => auth == null
      ? null
      : '${auth.user.subjectId}/${auth.user.activeOrganizationId}';

  @override
  void initState() {
    super.initState();
    _owner = _identity(ref.read(authControllerProvider).valueOrNull);
    _loadStatus();
  }

  @override
  void dispose() {
    _cancel.cancel();
    _message.dispose();
    super.dispose();
  }

  bool _current(AuthState auth, int generation) {
    final current = ref.read(authControllerProvider).valueOrNull;
    return mounted &&
        generation == _generation &&
        current?.isOffline == false &&
        current?.user.subjectId == auth.user.subjectId &&
        current?.user.activeOrganizationId == auth.user.activeOrganizationId;
  }

  int _reset() {
    _cancel.cancel();
    _cancel = CancelToken();
    _reply = null;
    _error = null;
    return ++_generation;
  }

  Future<void> _loadStatus() async {
    final generation = _reset();
    final auth = ref.read(authControllerProvider).valueOrNull;
    setState(() {
      _enabled = null;
      _busy = false;
    });
    if (auth == null || auth.isOffline || _identity(auth) != _owner) return;
    final cancel = _cancel;
    try {
      final enabled = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (token) =>
              ref.read(assistantApiProvider).enabled(token, cancel));
      if (_current(auth, generation)) setState(() => _enabled = enabled);
    } catch (error) {
      if (_current(auth, generation)) {
        setState(() => _error = _errorText(error));
      }
    }
  }

  Future<void> _ask() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final message = _message.text.trim();
    if (_busy ||
        _enabled != true ||
        auth == null ||
        auth.isOffline ||
        _identity(auth) != _owner ||
        message.isEmpty) {
      return;
    }
    final generation = _reset();
    final cancel = _cancel;
    setState(() => _busy = true);
    try {
      final reply = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (token) => ref.read(assistantApiProvider).ask(
              token: token,
              message: message,
              date: widget.businessDate ?? DateUtils.dateOnly(DateTime.now()),
              penId: widget.penId,
              sessionId: widget.sessionId,
              cancel: cancel));
      if (_current(auth, generation)) setState(() => _reply = reply);
    } catch (error) {
      if (_current(auth, generation)) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (_current(auth, generation)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before?.user.subjectId != after?.user.subjectId ||
          before?.user.activeOrganizationId !=
              after?.user.activeOrganizationId ||
          before?.isOffline != after?.isOffline) {
        _message.clear();
        _loadStatus();
      }
    });
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (_identity(auth) != _owner) {
      return Scaffold(
          appBar: AppBar(title: const Text('盘点助手')),
          body: const Center(child: Text('账号或组织已切换，请返回后重新选择查询范围。')));
    }
    final offline = auth == null || auth.isOffline;
    final date = (widget.businessDate ?? DateTime.now())
        .toIso8601String()
        .substring(0, 10);
    final reply = _reply;
    return Scaffold(
      appBar: AppBar(title: const Text('盘点助手'), actions: [
        IconButton(
            tooltip: '重新检查可用状态',
            onPressed: _busy ? null : _loadStatus,
            icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(padding: AppSpacing.page, children: [
        FieldScope(
            label: auth?.user.activeOrganizationName ?? '请先登录',
            detail: '${widget.scopeLabel ?? '当前组织'} · $date'),
        const SizedBox(height: 16),
        const Text('让每个结论都有依据',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('查询盘点任务、栏舍历史与原始记录，核对结果后进入对应作业。'),
        const SizedBox(height: 16),
        Card(
            child: Padding(
                padding: AppSpacing.card,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.auto_awesome_outlined,
                            color: _enabled == true
                                ? AppColors.herdTeal
                                : AppColors.muted),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                offline
                                    ? '联网后可查询助手'
                                    : _enabled == true
                                        ? '智能问答可用'
                                        : _enabled == false
                                            ? '智能问答尚未启用'
                                            : _error == null
                                                ? '正在检查问答能力…'
                                                : '暂时无法读取问答状态',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          _enabled == false
                              ? '问答模型待配置。工作台可查看真实任务及规则研判，证据库可查看原图。'
                              : '助手只查询和解释。数量确认及证据更正在业务页面按权限完成。',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]))),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final question in [
            '所选日期哪些栏舍还没确认？',
            if (widget.sessionId != null) '这次盘点的候选和确认数量分别是多少？',
            if (widget.penId != null) '这个栏舍最近七天的确认数量如何变化？',
          ])
            ActionChip(
                label: Text(question),
                onPressed: _busy
                    ? null
                    : () {
                        _message.text = question;
                      }),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: _message,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            enabled: !offline && _enabled == true && !_busy,
            decoration: const InputDecoration(hintText: '输入要查询的盘点问题')),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: !offline && _enabled == true && !_busy ? _ask : null,
            icon: Icon(_busy ? Icons.hourglass_top : Icons.arrow_upward),
            label: Text(_busy ? '正在查询授权业务数据…' : '查询并查看依据')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.alert)),
        ],
        if (reply != null) ...[
          const SizedBox(height: 20),
          Text(_replyLabel(reply.status),
              style: Theme.of(context).textTheme.titleMedium),
          if (reply.answer != null) ...[
            const SizedBox(height: 8),
            Card(
                child: Padding(
                    padding: AppSpacing.card,
                    child: SelectableText(reply.answer!))),
          ],
          for (final fact in reply.facts) _FactCard(fact: fact),
          for (final evidence in reply.evidence) _evidenceTile(evidence),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const InventoryReportsScreen())),
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('查看已确认盘点报告')),
      ]),
    );
  }

  Widget _evidenceTile(Map<String, dynamic> evidence) {
    final id = evidence['id'];
    if (evidence['kind'] != 'session' ||
        id is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(id)) {
      return const SizedBox.shrink();
    }
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.fact_check_outlined),
        title: const Text('打开来源记录'),
        subtitle: Text(evidence['businessDate'] is String
            ? evidence['businessDate'] as String
            : ''),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/inventory-sessions/$id'));
  }

  String _replyLabel(String status) => switch (status) {
        'ok' => '解释与数据依据',
        'insufficient_evidence' => '证据不足，请补充记录或范围',
        'answer_rejected' => '解释未通过核对，请查看事实',
        'limit_reached' => '本次查询已达上限，请缩小范围',
        _ => '模型暂不可用，可查看已取得事实',
      };

  String _errorText(Object error) {
    if (error is DioException) {
      return switch (error.response?.statusCode) {
        401 => '登录已失效，请重新登录后查询。',
        403 || 404 => '当前账号无法访问所选范围。',
        429 => '当前查询较多，请稍后重试。',
        503 => '智能问答暂不可用，可继续查看任务和证据。',
        _ => '查询未完成，请检查网络后重试。',
      };
    }
    return '暂时无法读取回答，请重新查询。';
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.fact});
  final Map<String, dynamic> fact;

  String _count(Object? value) => value is int && value >= 0 ? '$value' : '未知';

  @override
  Widget build(BuildContext context) {
    final data = fact['data'];
    if (data is! Map || fact['status'] != 'ok') return const SizedBox.shrink();
    final lines = switch (fact['tool']) {
      'inspect_session' => [
          'AI 候选 ${_count(data['candidateCount'])} 头',
          '人工确认 ${_count(data['confirmedCount'])} 头',
        ],
      'get_day_overview' => [
          '已确认合计 ${_count(data['confirmedHeads'])} 头',
          '覆盖 ${_count(data['confirmedPenCount'])} / ${_count(data['scopePenCount'])} 栏',
          if (data['hasMore'] == true) '明细有截断，请缩小查询范围',
        ],
      'get_pen_history' => [
          for (final point in (data['points'] as List? ?? const []))
            if (point is Map)
              '${point['date']} · ${_count(point['confirmedCount'])} 头',
        ],
      _ => <String>[],
    };
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: Padding(
              padding: AppSpacing.card,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('系统事实',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final line in lines) Text(line),
                  ])),
        ));
  }
}
