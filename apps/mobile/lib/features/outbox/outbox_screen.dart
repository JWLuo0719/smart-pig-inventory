import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_controller.dart';
import 'application/upload_package_synchronizer.dart';
import 'data/drift_outbox_repository.dart';

class OutboxScreen extends ConsumerStatefulWidget {
  const OutboxScreen({super.key});

  @override
  ConsumerState<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends ConsumerState<OutboxScreen> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(outboxRepositoryProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) {
      return const Scaffold(body: Center(child: Text('请先登录查看当前组织上传队列')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传队列'),
        actions: <Widget>[
          IconButton(
            tooltip: '立即重试',
            onPressed: _syncing ? null : _syncNext,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20, child: CircularProgressIndicator())
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: StreamBuilder<List<UploadQueueItem>>(
        key: ValueKey(auth.user.activeOrganizationId),
        stream: repository.watchCards(auth.user.activeOrganizationId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('队列读取失败，原始证据仍保留；请返回后重试'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('当前组织没有待上传的采集包'));
          return ListView(
              padding: const EdgeInsets.all(16),
              children: rows.map((item) {
                final row = item.entry;
                final leased =
                    row.leaseExpiresAt?.isAfter(DateTime.now().toUtc()) == true;
                return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.penLabel,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(
                                  '${item.businessDate.toIso8601String().substring(0, 10)} · ${item.captureKind == 'video' ? '视频证据' : item.captureKind == 'single' ? '单图' : '左中右三图'}'),
                              const SizedBox(height: 8),
                              if (item.thumbnail != null)
                                Image.file(File(item.thumbnail!),
                                    cacheWidth: 240,
                                    height: 90,
                                    errorBuilder: (_, __, ___) =>
                                        const Text('本机预览暂不可用，原记录保留')),
                              Semantics(
                                  liveRegion: true,
                                  child: Text(_stateLabel(row.state))),
                              Text(
                                  '已上传 ${item.uploadedAssets} / ${item.totalAssets} 份文件'),
                              if (row.error != null) Text(row.error!),
                              if (row.nextAttemptAt != null)
                                Text('下次尝试：${row.nextAttemptAt!.toLocal()}'),
                              if (row.sessionId != null)
                                TextButton(
                                    onPressed: () => context.push(
                                        '/inventory-sessions/${row.sessionId}'),
                                    child: const Text('查看服务器处理结果'))
                              else if (row.state == 'waiting_authentication')
                                const Text('请重新登录后继续，原图仍安全保留')
                              else if (!['synced', 'abandoned']
                                      .contains(row.state) &&
                                  !leased)
                                OutlinedButton(
                                    onPressed: _syncing
                                        ? null
                                        : () => _retry(row.packageId),
                                    child: const Text('立即重试')),
                              ExpansionTile(
                                  title: const Text('诊断详情'),
                                  children: [
                                    SelectableText(
                                        '采集包 ${row.packageId}\n重试 ${row.attemptCount} 次')
                                  ]),
                            ])));
              }).toList());
        },
      ),
    );
  }

  Future<void> _retry(String packageId) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null) return;
    try {
      await ref.read(outboxRepositoryProvider).retryNow(packageId,
          organizationId: auth.user.activeOrganizationId,
          now: DateTime.now().toUtc());
      await _syncNext();
    } on StateError {
      if (mounted) _show('采集包状态已变化，请刷新队列');
    }
  }

  Future<void> _syncNext() async {
    var auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null) {
      _show('请先登录后再上传');
      return;
    }
    setState(() => _syncing = true);
    try {
      // A session restored while the device was offline must be checked again
      // when the operator taps retry after connectivity returns.
      if (auth.isOffline) {
        auth = await ref.read(authControllerProvider.notifier).reconnect();
      }
      if (auth == null) {
        if (mounted) _show('登录状态已失效，请重新登录后再上传');
        return;
      }
      final UploadSyncOutcome outcome = await ref
          .read(uploadPackageSynchronizerProvider)
          .syncNext(auth, leaseOwner: const Uuid().v4());
      if (mounted && outcome != UploadSyncOutcome.synced) {
        _show(_outcomeLabel(outcome));
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  String _stateLabel(String state) => switch (state) {
        'queued' => '等待上传',
        'creating_package' => '正在创建上传包',
        'uploading_blobs' => '正在上传原图',
        'putting_manifest' => '正在校验采集清单',
        'committing' => '正在提交采集包',
        'retry_wait' => '等待自动重试',
        'waiting_authentication' => '等待重新登录',
        'blocked' => '上传已阻止',
        'abandoned' => '已停止重试（原图保留在本机）',
        'synced' => '已提交，等待处理',
        _ => '上传状态未知',
      };

  String _outcomeLabel(UploadSyncOutcome outcome) => switch (outcome) {
        UploadSyncOutcome.nothingToUpload => '没有可上传的采集包',
        UploadSyncOutcome.waitingForNetwork => '当前离线，无法上传',
        UploadSyncOutcome.waitingForAuthentication => '需要重新登录后才能上传',
        UploadSyncOutcome.retryScheduled => '网络暂不可用，已安排自动重试',
        UploadSyncOutcome.blocked => '服务器拒绝此采集包，请查看诊断信息',
        UploadSyncOutcome.synced => '上传已提交',
      };
}
