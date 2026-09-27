import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';
import 'package:smart_pig_inventory/features/inventory/density_heatmap.dart';

RemoteDetection detection(double x1, double y1, double x2, double y2) =>
    RemoteDetection(assetId: 'a', bbox: [x1, y1, x2, y2], confidence: 0.9);

void main() {
  test('places detection centers into the right grid cells', () {
    final grid = densityGrid([
      detection(0.0, 0.0, 0.2, 0.2), // 左上角格子
      detection(0.05, 0.05, 0.15, 0.15), // 同一左上格
      detection(0.95, 0.9, 1.0, 1.0), // 右下角格子
    ], columns: 6, rows: 4);
    expect(grid[0][0], 2);
    expect(grid[3][5], 1);
    expect(grid.expand((row) => row).reduce((a, b) => a + b), 3);
  });

  test('ignores malformed boxes and keeps an empty grid otherwise', () {
    expect(densityGrid(const []), everyElement(everyElement(0)));
    final grid = densityGrid([
      RemoteDetection(assetId: 'a', bbox: [0.5], confidence: 1)
    ]);
    expect(grid.expand((row) => row).reduce((a, b) => a + b), 0);
  });
}
