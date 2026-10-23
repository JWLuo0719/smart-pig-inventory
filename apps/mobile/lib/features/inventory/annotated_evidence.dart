import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/inventory_browse_api.dart'
    show InventoryBrowseApi, LibraryMedia;

/// Historical compatibility constant; model scores are never labelled accuracy.
const double kUncertainConfidence = 0.5;

/// Original evidence and numbered model detections share one image transform.
class AnnotatedEvidenceSection extends ConsumerStatefulWidget {
  const AnnotatedEvidenceSection({
    super.key,
    required this.sessionId,
    required this.detections,
  });

  final String sessionId;
  final List<RemoteDetection> detections;

  @override
  ConsumerState<AnnotatedEvidenceSection> createState() =>
      _AnnotatedEvidenceSectionState();
}

class _AnnotatedEvidenceSectionState
    extends ConsumerState<AnnotatedEvidenceSection> {
  List<LibraryMedia>? _media;
  final Map<String, List<RemoteDetection>> _byAsset = {};
  String? _error;

  InventoryBrowseApi get _api =>
      InventoryBrowseApi(ref.read(apiBaseUrlProvider));

  @override
  void initState() {
    super.initState();
    _indexDetections();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnnotatedEvidenceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _indexDetections();
    if (oldWidget.sessionId != widget.sessionId) {
      _media = null;
      _load();
    }
  }

  void _indexDetections() {
    _byAsset.clear();
    for (final RemoteDetection detection in widget.detections) {
      _byAsset
          .putIfAbsent(detection.assetId, () => <RemoteDetection>[])
          .add(detection);
    }
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      if (mounted) {
        setState(() => _error = '离线时暂不能加载标注证据，联网后自动恢复。');
      }
      return;
    }
    setState(() => _error = null);
    final sessionId = widget.sessionId;
    try {
      final rows = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (String token) =>
              _api.sessionMedia(token, widget.sessionId));
      final current = ref.read(authControllerProvider).valueOrNull;
      if (!mounted ||
          sessionId != widget.sessionId ||
          current?.user.subjectId != auth.user.subjectId ||
          current?.user.activeOrganizationId !=
              auth.user.activeOrganizationId) {
        return;
      }
      setState(() => _media = rows);
    } on DioException {
      if (mounted) setState(() => _error = '证据图片暂时无法加载。');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.valueOrNull?.user.activeOrganizationId !=
              next.valueOrNull?.user.activeOrganizationId ||
          previous?.valueOrNull?.user.subjectId !=
              next.valueOrNull?.user.subjectId) {
        _media = null;
        _error = '账号已变化，请重新打开证据';
      }
    });
    final int total = widget.detections.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Text('🎯', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('证据标注 · AI 检测 $total 处',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('编号用于逐目标核验；模型分数不是准确率，所有候选均需人工复核。'),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child:
                    TextButton(onPressed: _load, child: Text('$_error 点击重试')),
              )
            else if (_media == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._media!
                  .where((LibraryMedia item) =>
                      !_isVideo(item) && _byAsset.containsKey(item.assetId))
                  .map((LibraryMedia item) => _AnnotatedImage(
                      media: item, detections: _byAsset[item.assetId]!)),
          ],
        ),
      ),
    );
  }

  static bool _isVideo(LibraryMedia media) => media.contentType == 'video/mp4';
}

class _AnnotatedImage extends ConsumerStatefulWidget {
  const _AnnotatedImage({required this.media, required this.detections});
  final LibraryMedia media;
  final List<RemoteDetection> detections;

  @override
  ConsumerState<_AnnotatedImage> createState() => _AnnotatedImageState();
}

class _AnnotatedImageState extends ConsumerState<_AnnotatedImage> {
  Uint8List? _bytes;
  double? _aspect; // 原图宽高比，解码后确定
  String? _error;

  InventoryBrowseApi get _api =>
      InventoryBrowseApi(ref.read(apiBaseUrlProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null) return;
    setState(() => _error = null);
    try {
      final Uint8List bytes = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (String token) => _api.content(token, widget.media.assetId));
      if (!mounted) return;
      // 先解码拿原始宽高（归一化坐标映射的基准），再触发一次重建
      final image = await decodeImageFromList(bytes);
      final current = ref.read(authControllerProvider).valueOrNull;
      if (mounted &&
          current?.user.subjectId == auth.user.subjectId &&
          current?.user.activeOrganizationId ==
              auth.user.activeOrganizationId) {
        setState(() {
          _bytes = bytes;
          _aspect = image.width / image.height;
        });
      }
      image.dispose();
    } catch (_) {
      if (mounted) setState(() => _error = '该张证据加载失败。');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextButton(onPressed: _load, child: Text('$_error 点击重试')),
      );
    }
    final Uint8List? bytes = _bytes;
    final double? aspect = _aspect;
    if (bytes == null || aspect == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
                aspectRatio: 4 / 3,
                child: AnnotatedEvidenceViewer(
                    bytes: bytes,
                    aspect: aspect,
                    detections: widget.detections)),
            TextButton.icon(
                onPressed: () {
                  final auth = ref.read(authControllerProvider).valueOrNull;
                  if (auth == null) return;
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => Consumer(builder: (context, ref, _) {
                            final current =
                                ref.watch(authControllerProvider).valueOrNull;
                            final permitted = current?.user.subjectId ==
                                    auth.user.subjectId &&
                                current?.user.activeOrganizationId ==
                                    auth.user.activeOrganizationId;
                            return Scaffold(
                                appBar: AppBar(title: const Text('原图与检测标注')),
                                body: permitted
                                    ? AnnotatedEvidenceViewer(
                                        bytes: bytes,
                                        aspect: aspect,
                                        detections: widget.detections)
                                    : const Center(
                                        child: Text('账号已变化，请重新打开当前组织证据')));
                          })));
                },
                icon: const Icon(Icons.fullscreen),
                label: const Text('全屏核验')),
            const SizedBox(height: 4),
            Text(
                '${evidencePositionLabel(widget.media.position)} · ${widget.detections.length} 处检测',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
    );
  }
}

class AnnotatedEvidenceViewer extends StatefulWidget {
  const AnnotatedEvidenceViewer(
      {super.key,
      required this.bytes,
      required this.aspect,
      required this.detections});
  final Uint8List bytes;
  final double aspect;
  final List<RemoteDetection> detections;
  @override
  State<AnnotatedEvidenceViewer> createState() =>
      _AnnotatedEvidenceViewerState();
}

class _AnnotatedEvidenceViewerState extends State<AnnotatedEvidenceViewer> {
  final _transform = TransformationController();
  bool _annotations = true;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Wrap(spacing: 12, children: [
          TextButton(
              onPressed: () => setState(() => _annotations = !_annotations),
              child: Text(_annotations ? '查看原图' : '显示标注')),
          TextButton(
              onPressed: () => _transform.value = Matrix4.identity(),
              child: const Text('重置缩放')),
          TextButton(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SafeArea(
                          child: ListView.builder(
                        itemCount: widget.detections.length,
                        itemBuilder: (_, index) => ListTile(
                            title: Text('目标 ${index + 1}'),
                            subtitle: Text(
                                '模型分数 ${(widget.detections[index].confidence * 100).toStringAsFixed(1)}% · 不代表准确率')),
                      ))),
              child: const Text('检测编号与分数')),
        ]),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final fitted = evidenceContainRect(
              widget.aspect, Size(constraints.maxWidth, constraints.maxHeight));
          return InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 8,
              child: Stack(children: [
                Positioned.fromRect(
                    rect: fitted,
                    child: Image.memory(widget.bytes, fit: BoxFit.fill)),
                if (_annotations)
                  ...widget.detections.indexed.map((entry) {
                    final d = entry.$2;
                    if (d.bbox.length != 4) return const SizedBox.shrink();
                    return Positioned(
                        left: fitted.left + d.bbox[0] * fitted.width,
                        top: fitted.top + d.bbox[1] * fitted.height,
                        width: (d.bbox[2] - d.bbox[0]) * fitted.width,
                        height: (d.bbox[3] - d.bbox[1]) * fitted.height,
                        child: Semantics(
                            label:
                                '目标${entry.$1 + 1}，模型分数${(d.confidence * 100).toStringAsFixed(1)}%',
                            button: true,
                            child: GestureDetector(
                                onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                            title: Text('目标 ${entry.$1 + 1}'),
                                            content: Text(
                                                '模型分数 ${(d.confidence * 100).toStringAsFixed(1)}%\n分数不代表准确率，请对照原始证据核验。'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('返回核验'))
                                            ])),
                                child: Container(
                                    decoration: BoxDecoration(
                                        border: Border.all(
                                            color: AppColors.herdTeal,
                                            width: 2)),
                                    alignment: Alignment.topLeft,
                                    child: Text('${entry.$1 + 1}',
                                        style: const TextStyle(
                                            backgroundColor: Colors.white,
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.bold))))));
                  }),
              ]));
        })),
      ]);
}

Rect evidenceContainRect(double aspect, Size size) {
  if (size.width / size.height > aspect) {
    final width = size.height * aspect;
    return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
  }
  final height = size.width / aspect;
  return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
}

String evidencePositionLabel(String position) => switch (position) {
      'single' => '单图',
      'left' => '左侧',
      'center' => '中间',
      'right' => '右侧',
      'video' => '视频',
      _ => '原始证据'
    };
