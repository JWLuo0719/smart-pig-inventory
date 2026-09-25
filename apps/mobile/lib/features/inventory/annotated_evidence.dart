import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/authorized_retry.dart';
import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/inventory_browse_api.dart'
    show InventoryBrowseApi, LibraryMedia;

/// 不确定目标的判定阈值：低于该置信度的检测框以鲜艳橙色高亮，供人工重点核验。
const double kUncertainConfidence = 0.5;

/// 证据标注视图：在原始照片上叠加 AI 检测框。
///
/// 高置信目标用沉稳的青绿描边；模型不确定的目标（置信度低于阈值）用
/// 鲜艳橙色粗描边，引导复核员优先核验——机器把"看不准的"明确交给
/// 人，而不是默默给一个数字。
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
    for (final RemoteDetection detection in widget.detections) {
      _byAsset
          .putIfAbsent(detection.assetId, () => <RemoteDetection>[])
          .add(detection);
    }
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) {
      if (mounted) {
        setState(() => _error = '离线时暂不能加载标注证据，联网后自动恢复。');
      }
      return;
    }
    try {
      final rows = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (String token) =>
              _api.sessionMedia(token, widget.sessionId));
      if (!mounted) return;
      setState(() => _media = rows);
    } on DioException {
      if (mounted) setState(() => _error = '证据图片暂时无法加载。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final int uncertain =
        widget.detections.where(_isUncertain).length;
    final int total = widget.detections.length;
    final int confident = total - uncertain;
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
            Wrap(spacing: 14, children: <Widget>[
              _LegendSwatch(
                  color: AppColors.herdTeal, label: '高置信 $confident'),
              _LegendSwatch(
                  color: const Color(0xFFFF6D00), label: '待核验 $uncertain'),
            ]),
            if (uncertain > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '橙色框是模型不确定的目标（置信度低于 50%），请重点核验后再确认数量。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child:
                    Text(_error!, style: Theme.of(context).textTheme.bodySmall),
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

  static bool _isUncertain(RemoteDetection detection) =>
      detection.confidence < kUncertainConfidence;

  static bool _isVideo(LibraryMedia media) => media.contentType == 'video/mp4';
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
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
    try {
      final Uint8List bytes = await retryOnceAfterUnauthorized(
          initialAuth: auth,
          reconnect: () =>
              ref.read(authControllerProvider.notifier).reconnect(),
          request: (String token) =>
              _api.content(token, widget.media.assetId));
      if (!mounted) return;
      // 先解码拿原始宽高（归一化坐标映射的基准），再触发一次重建
      final ui.Image image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _aspect = image.width / image.height;
        });
      }
    } on DioException {
      if (mounted) setState(() => _error = '该张证据加载失败。');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
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
              child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                final Rect fitted = _containRect(aspect, constraints);
                return Stack(children: <Widget>[
                  Positioned.fill(
                      child: FittedBox(
                          fit: BoxFit.contain, child: Image.memory(bytes))),
                  ...widget.detections.map((RemoteDetection detection) =>
                      _detectionBox(detection, fitted)),
                ]);
              }),
            ),
            const SizedBox(height: 4),
            Text(
                '${widget.media.position} · ${widget.detections.length} 处检测',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
    );
  }

  /// FittedBox(contain) 下图片在容器内的实际区域（居中留边）。
  static Rect _containRect(double aspect, BoxConstraints constraints) {
    final double boxAspect = constraints.maxWidth / constraints.maxHeight;
    if (aspect > boxAspect) {
      final double height = constraints.maxWidth / aspect;
      final double top = (constraints.maxHeight - height) / 2;
      return Rect.fromLTWH(0, top, constraints.maxWidth, height);
    }
    final double width = constraints.maxHeight * aspect;
    final double left = (constraints.maxWidth - width) / 2;
    return Rect.fromLTWH(left, 0, width, constraints.maxHeight);
  }

  Widget _detectionBox(RemoteDetection detection, Rect fitted) {
    final bool uncertain = detection.confidence < kUncertainConfidence;
    return Positioned(
      left: fitted.left + detection.bbox[0] * fitted.width,
      top: fitted.top + detection.bbox[1] * fitted.height,
      width: (detection.bbox[2] - detection.bbox[0]) * fitted.width,
      height: (detection.bbox[3] - detection.bbox[1]) * fitted.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: uncertain ? const Color(0xFFFF6D00) : AppColors.herdTeal,
            width: uncertain ? 3 : 1.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
