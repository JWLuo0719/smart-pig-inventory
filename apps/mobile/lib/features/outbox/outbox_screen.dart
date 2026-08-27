import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/storage/app_database.dart';
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
      body: StreamBuilder<List<OutboxEntry>>(
        stream: repository.watch(),
        builder:
            (BuildContext context, AsyncSnapshot<List<OutboxEntry>> snapshot) {
          final List<OutboxEntry> rows = snapshot.data ?? const <OutboxEntry>[];
          if (rows.isEmpty) return const Center(child: Text('没有待上传的采集包'));
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final OutboxEntry row = rows[index];
              return ListTile(
                title: Text(_stateLabel(row.state)),
                subtitle: Text(row.error ?? '采集包 ${row.packageId}'),
                trailing: row.state == 'synced'
                    ? const Icon(Icons.check_circle_outline)
                    : TextButton(
                        onPressed:
                            _syncing ? null : () => _retry(row.packageId),
                        child: const Text('重试'),
                      ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _retry(String packageId) async {
    await ref
        .read(outboxRepositoryProvider)
        .retryNow(packageId, now: DateTime.now().toUtc());
    await _syncNext();
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
