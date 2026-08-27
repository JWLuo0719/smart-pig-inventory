import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';
import '../capture/domain/capture_target.dart';
import '../master_data/application/sync_master_data.dart';
import '../master_data/data/drift_master_data_repository.dart';
import '../master_data/domain/master_data_changes.dart';

class PenPickerScreen extends ConsumerStatefulWidget {
  const PenPickerScreen({super.key});

  @override
  ConsumerState<PenPickerScreen> createState() => _PenPickerScreenState();
}

class _PenPickerScreenState extends ConsumerState<PenPickerScreen> {
  String _query = '';
  bool _syncing = false;
  String? _syncError;

  @override
  Widget build(BuildContext context) {
    final AuthState? auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final DriftMasterDataRepository repository =
        ref.watch(masterDataRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择栏舍'),
        actions: <Widget>[
          IconButton(
            tooltip: '同步栏舍',
            onPressed: _syncing || auth.isOffline ? null : () => _sync(auth),
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20, child: CircularProgressIndicator())
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (auth.isOffline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D8),
                border: Border.all(color: const Color(0xFFEAD39A)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('当前离线：仅显示上次同步的栏舍，不能同步。'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: TextField(
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索栋舍、栏舍编码或名称',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
            ),
          ),
          if (_syncError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child:
                  Text(_syncError!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: StreamBuilder<List<PenChoice>>(
              stream: repository.watchPens(auth.user.activeOrganizationId,
                  query: _query),
              builder: (BuildContext context,
                  AsyncSnapshot<List<PenChoice>> snapshot) {
                final List<PenChoice> pens =
                    snapshot.data ?? const <PenChoice>[];
                if (pens.isEmpty) {
                  return const Center(child: Text('暂无已同步栏舍。连接网络后点击右上角同步。'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  itemCount: pens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) => _PenChoice(
                    choice: pens[index],
                    onTap: () => _openCapture(context, pens[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sync(AuthState auth) async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await ref.read(masterDataSynchronizerProvider).sync(auth);
    } on MasterDataSyncUnavailable {
      if (mounted) setState(() => _syncError = '当前离线，无法同步栏舍。');
    } catch (_) {
      if (mounted) setState(() => _syncError = '栏舍同步失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _openCapture(BuildContext context, PenChoice choice) {
    if (!choice.enabled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该栏舍已禁用，不能创建新草稿。')));
      return;
    }
    final DateTime now = DateTime.now();
    context.push(
      '/capture',
      extra: CaptureTarget(
        organizationId: choice.organizationId,
        penId: choice.penId,
        label:
            '${choice.buildingCode} ${choice.buildingName} · ${choice.penCode} ${choice.penName}',
        businessDate: DateTime(now.year, now.month, now.day),
      ),
    );
  }
}

class _PenChoice extends StatelessWidget {
  const _PenChoice({required this.choice, required this.onTap});
  final PenChoice choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          enabled: choice.enabled,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.barnBlue,
              borderRadius: BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(10)),
            ),
            child: Text(choice.penCode,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          title: Text(
              '${choice.buildingCode} ${choice.buildingName} · ${choice.penCode} ${choice.penName}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(choice.enabled ? '可创建采集草稿' : '已禁用：可恢复已有草稿，但不能新建'),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
