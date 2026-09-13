import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/storage/app_database.dart';
import '../../shared/widgets/local_video_player.dart';
import '../local_activity/data/local_activity_repository.dart';

class LocalEvidenceScreen extends ConsumerStatefulWidget {
  const LocalEvidenceScreen({required this.activity, super.key});
  final LocalCaptureActivity activity;
  @override
  ConsumerState<LocalEvidenceScreen> createState() =>
      _LocalEvidenceScreenState();
}

class _LocalEvidenceScreenState extends ConsumerState<LocalEvidenceScreen> {
  late final Future<List<LocalMediaAsset>> _media;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider).valueOrNull;
    _media = ref.read(localActivityRepositoryProvider).mediaForDraft(
        auth?.user.activeOrganizationId ?? '', widget.activity.draftId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(
                '${widget.activity.buildingLabel} / ${widget.activity.penLabel}')),
        body: FutureBuilder<List<LocalMediaAsset>>(
            future: _media,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('无法读取本机证据，原文件未改动。'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) return const Center(child: Text('这份草稿没有本机照片。'));
              return Column(children: [
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        '${_page + 1} / ${rows.length} · ${rows[_page].viewPosition} · 左右滑动翻阅，可双指缩放')),
                Expanded(
                    child: PageView.builder(
                        itemCount: rows.length,
                        onPageChanged: (index) => setState(() => _page = index),
                        itemBuilder: (context, index) => rows[index]
                                .contentType
                                .startsWith('video/')
                            ? LocalVideoPlayer(
                                file: File(rows[index].materializedPath))
                            : InteractiveViewer(
                                minScale: 0.5,
                                maxScale: 8,
                                child: Center(
                                    child: Image.file(
                                        File(rows[index].materializedPath),
                                        errorBuilder: (_, __, ___) =>
                                            const Text('本机文件暂不可读取或格式不支持。')))))),
                if (widget.activity.sessionId != null)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                          onPressed: () => context.push(
                              '/inventory-sessions/${widget.activity.sessionId}'),
                          child: const Text('读取服务器盘点结果'))),
              ]);
            }),
      );
}
