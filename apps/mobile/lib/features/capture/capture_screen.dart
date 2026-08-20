import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/network_status_banner.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selected = <XFile>[];
  bool _threeView = false;

  Future<void> _pick(ImageSource source) async {
    final XFile? result =
        await _picker.pickImage(source: source, imageQuality: 92);
    if (result != null && mounted) setState(() => _selected.add(result));
  }

  @override
  Widget build(BuildContext context) {
    final int expected = _threeView ? 3 : 1;
    final List<String> directionLabels =
        _threeView ? <String>['左侧', '中间', '右侧'] : <String>['单图'];
    return Scaffold(
      appBar: AppBar(title: const Text('B01 育肥一栋 · 03栏')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: <Widget>[
          const NetworkStatusBanner(),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              value: _threeView,
              onChanged: (bool value) => setState(() {
                _threeView = value;
                _selected.clear();
              }),
              title: const Text('左 / 中 / 右三图模式',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('三张图属于同一采集组，算法未验证前不自动相加。'),
            ),
          ),
          const SizedBox(height: 18),
          Text('采集方向', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
              '当前需要：${directionLabels[_selected.length.clamp(0, expected - 1).toInt()]}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(
            children: List<Widget>.generate(expected, (int index) {
              final bool done = index < _selected.length;
              final bool current = index == _selected.length;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index == expected - 1 ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.herdTeal.withValues(alpha: .12)
                        : current
                            ? AppColors.straw.withValues(alpha: .15)
                            : Colors.white,
                    border: Border.all(
                        color: done
                            ? AppColors.herdTeal
                            : current
                                ? AppColors.straw
                                : AppColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: <Widget>[
                    Icon(done ? Icons.check_circle : Icons.camera_alt_outlined,
                        color: done
                            ? AppColors.herdTeal
                            : current
                                ? AppColors.straw
                                : AppColors.muted),
                    const SizedBox(height: 5),
                    Text(directionLabels[index],
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
              onPressed: _selected.length < expected
                  ? () => _pick(ImageSource.camera)
                  : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_selected.length < expected
                  ? '拍摄${directionLabels[_selected.length]}'
                  : '图片已集齐')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _selected.length < expected
                  ? () => _pick(ImageSource.gallery)
                  : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从图库导入')),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line)),
            child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.shield_outlined,
                      color: AppColors.barnBlue, size: 20),
                  SizedBox(width: 9),
                  Expanded(
                      child: Text(
                          '拍摄后先复制到本机持久目录，再计算 SHA-256 并写入草稿。服务器确认 Commit 前不会清理原图。')),
                ]),
          ),
        ],
      ),
    );
  }
}
