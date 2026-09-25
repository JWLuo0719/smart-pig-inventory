import 'package:flutter/material.dart';

import '../../core/network/inventory_api.dart';
import '../../core/theme/app_theme.dart';

/// 把检测框中心落进 cols×rows 网格，返回每个格子的目标数。
/// bbox 是归一化 xyxy（0~1），中心点 (cx, cy) 决定它属于哪个格子。
List<List<int>> densityGrid(List<RemoteDetection> detections,
    {int columns = 6, int rows = 4}) {
  final grid = List.generate(rows, (_) => List.filled(columns, 0));
  for (final detection in detections) {
    final bbox = detection.bbox;
    if (bbox.length < 4) continue;
    final double cx = (bbox[0] + bbox[2]) / 2;
    final double cy = (bbox[1] + bbox[3]) / 2;
    if (cx < 0 || cx >= 1 || cy < 0 || cy >= 1) continue;
    final int column = (cx * columns).clamp(0, columns - 1).toInt();
    final int row = (cy * rows).clamp(0, rows - 1).toInt();
    grid[row][column] += 1;
  }
  return grid;
}

/// 空间分布热区卡：用颜色深浅呈现“猪集中在栏舍哪个位置”。
/// 数据来自已复核会话的检测框，网格只是视觉聚合，不代表栏舍真实边界。
class DensityHeatmapCard extends StatelessWidget {
  const DensityHeatmapCard({super.key, required this.detections});

  final List<RemoteDetection> detections;

  @override
  Widget build(BuildContext context) {
    final grid = densityGrid(detections);
    final int peak = grid
        .expand((row) => row)
        .fold(0, (max, value) => value > max ? value : max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🗺️ 空间分布 · 共 ${detections.length} 头',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text('颜色越深，该区域目标越密集；最密集区域 $peak 头。网格仅聚合检测位置，不代表栏舍实际边界。',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 6 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                  children: List.generate(grid.length, (row) {
                return Expanded(
                    child: Row(
                        children: List.generate(grid[row].length, (column) {
                  final int value = grid[row][column];
                  return Expanded(
                      child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                              color: value == 0
                                  ? Colors.teal.withValues(alpha: 0.05)
                                  : Colors.teal.withValues(
                                      alpha:
                                          0.15 + 0.2 * (value - 1).clamp(0, 4)),
                              borderRadius: BorderRadius.circular(4)),
                          alignment: Alignment.center,
                          child: value == 0
                              ? null
                              : Text('$value',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.barnBlue))));
                })));
              })),
            ),
          ),
        ]),
      ),
    );
  }
}
