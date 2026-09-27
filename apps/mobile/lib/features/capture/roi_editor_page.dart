import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain/roi.dart';

/// 在已拍照片上标注"不计入本栏"的排除区（相邻栏舍、料槽、走道等）。
///
/// 交互：在照片上拖出一个矩形即新增一个排除区；最多 [maxExclusions] 个；
/// 下方列表给出每个排除区的归一化坐标并可单独删除。
/// 保存时组装成合同里的 `Roi`：有效区保持整图（或沿用已有有效区），
/// 没有排除区且最小包含比例为 0 时回调 `null`（表示整图，与历史行为一致）。
class RoiEditorPage extends StatefulWidget {
  const RoiEditorPage({
    super.key,
    required this.image,
    required this.aspectRatio,
    required this.onSave,
    this.initialRoi,
    this.maxExclusions = Roi.maxExclusions,
  });

  final File image;
  final double aspectRatio;
  final Future<void> Function(Roi? roi) onSave;
  final Roi? initialRoi;
  final int maxExclusions;

  @override
  State<RoiEditorPage> createState() => _RoiEditorPageState();
}

class _RoiEditorPageState extends State<RoiEditorPage> {
  /// 小于该边长的拖动视为误触，不产生排除区。
  static const double _minimumExtent = 0.02;

  late final List<RoiRegion> _exclusions;
  late double _minContainment;
  Offset? _dragOrigin;
  Offset? _dragCurrent;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _exclusions = <RoiRegion>[...?widget.initialRoi?.exclusions];
    _minContainment = widget.initialRoi?.minContainment ?? 0;
  }

  Offset _toNormalized(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  RoiRegion? _regionBetween(Offset first, Offset second) {
    final double left = math.min(first.dx, second.dx);
    final double top = math.min(first.dy, second.dy);
    final double width = (first.dx - second.dx).abs();
    final double height = (first.dy - second.dy).abs();
    if (width < _minimumExtent || height < _minimumExtent) return null;
    return RoiRegion(x: left, y: top, width: width, height: height);
  }

  void _beginDrag(Offset local, Size size) {
    setState(() {
      _dragOrigin = _toNormalized(local, size);
      _dragCurrent = _dragOrigin;
      _error = null;
    });
  }

  void _updateDrag(Offset local, Size size) {
    if (_dragOrigin == null) return;
    setState(() => _dragCurrent = _toNormalized(local, size));
  }

  void _commitDrag() {
    final Offset? origin = _dragOrigin;
    final Offset? current = _dragCurrent;
    setState(() {
      _dragOrigin = null;
      _dragCurrent = null;
    });
    if (origin == null || current == null) return;
    final RoiRegion? region = _regionBetween(origin, current);
    if (region == null) return;
    if (_exclusions.length >= widget.maxExclusions) {
      setState(() => _error = '最多只能标注 ${widget.maxExclusions} 个排除区，请先删除一个。');
      return;
    }
    setState(() => _exclusions.add(region));
  }

  Roi? _buildRoi() {
    if (_exclusions.isEmpty && _minContainment == 0) return null;
    final Roi? include = widget.initialRoi;
    return Roi(
      x: include?.x ?? 0,
      y: include?.y ?? 0,
      width: include?.width ?? 1,
      height: include?.height ?? 1,
      exclusions: List<RoiRegion>.unmodifiable(_exclusions),
      minContainment: _minContainment,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_buildRoi());
      if (mounted) Navigator.of(context).pop(true);
    } on StateError {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '这份草稿已经进入上传队列，不能再修改标注。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '标注没有保存成功，请重试。原有草稿没有被删除。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标注不计入本栏的区域')),
      // 画布刻意放在可滚动区域之外：否则在照片上竖直拖动会被列表滚动抢走，
      // 现场就会出现"画面在滚、画不出矩形"。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('在照片上按住并拖出一个矩形，即把相邻栏舍、料槽或走道划为排除区；'
                '压在这类区域里的猪不会计入本栏数量。'),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final Size size = constraints.biggest;
                      return GestureDetector(
                        key: const Key('roi-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (DragStartDetails details) =>
                            _beginDrag(details.localPosition, size),
                        onPanUpdate: (DragUpdateDetails details) =>
                            _updateDrag(details.localPosition, size),
                        onPanEnd: (DragEndDetails details) => _commitDrag(),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Image.file(
                              widget.image,
                              fit: BoxFit.fill,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFFE8EDF1),
                                child: Center(
                                    child: Icon(Icons.image_not_supported_outlined)),
                              ),
                            ),
                            CustomPaint(
                              painter: _RoiOverlayPainter(
                                exclusions: _exclusions,
                                pending: _dragOrigin == null
                                    ? null
                                    : _regionBetween(_dragOrigin!, _dragCurrent!),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                if (_exclusions.isEmpty)
                  const Text('还没有排除区：当前整张照片都算本栏。')
                else
                  ...List<Widget>.generate(_exclusions.length, (int index) {
                    final RoiRegion region = _exclusions[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        '排除区 ${index + 1}：横向 ${(region.x * 100).round()}%–'
                        '${((region.x + region.width) * 100).round()}%，'
                        '纵向 ${(region.y * 100).round()}%–'
                        '${((region.y + region.height) * 100).round()}%',
                      ),
                      trailing: IconButton(
                        tooltip: '删除排除区 ${index + 1}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _saving
                            ? null
                            : () => setState(() => _exclusions.removeAt(index)),
                      ),
                    );
                  }),
                const Divider(height: 24),
                Text('最小包含比例：${(_minContainment * 100).round()}%'),
                Slider(
                  value: _minContainment,
                  divisions: 20,
                  label: '${(_minContainment * 100).round()}%',
                  onChanged: _saving
                      ? null
                      : (double value) =>
                          setState(() => _minContainment = value),
                ),
                const Text('只有落在本栏有效区内的面积达到该比例的猪才计入；'
                    '设为 0% 表示沿用"只看检测框中心点"的口径。'),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存标注'),
          ),
        ),
      ),
    );
  }
}

/// 把排除区（以及正在拖出的矩形）画在照片上。
class _RoiOverlayPainter extends CustomPainter {
  const _RoiOverlayPainter({required this.exclusions, required this.pending});

  final List<RoiRegion> exclusions;
  final RoiRegion? pending;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = const Color(0x66D32F2F);
    final Paint border = Paint()
      ..color = const Color(0xFFD32F2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Paint pendingBorder = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final RoiRegion region in exclusions) {
      final Rect rect = _toCanvas(region, size);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
    }
    final RoiRegion? inProgress = pending;
    if (inProgress != null) {
      canvas.drawRect(_toCanvas(inProgress, size), pendingBorder);
    }
  }

  Rect _toCanvas(RoiRegion region, Size size) => Rect.fromLTWH(
        region.x * size.width,
        region.y * size.height,
        region.width * size.width,
        region.height * size.height,
      );

  @override
  bool shouldRepaint(_RoiOverlayPainter oldDelegate) =>
      oldDelegate.exclusions != exclusions || oldDelegate.pending != pending;
}
