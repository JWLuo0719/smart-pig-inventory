import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';
import 'package:smart_pig_inventory/features/inventory/annotated_evidence.dart';

void main() {
  test('会话 JSON 解析检测框并按置信度分层', () {
    final session = RemoteInventorySession.fromJson(<String, dynamic>{
      'id': 's-1',
      'penId': 'p-1',
      'businessDate': '2026-09-18',
      'status': 'review_required',
      'detections': <dynamic>[
        <String, dynamic>{
          'assetId': 'a-1',
          'bbox': <dynamic>[0.1, 0.2, 0.3, 0.4],
          'confidence': 0.92,
        },
        <String, dynamic>{
          'assetId': 'a-1',
          'bbox': <dynamic>[0.5, 0.5, 0.6, 0.7],
          'confidence': 0.31,
        },
        <String, dynamic>{
          'assetId': 'a-2',
          'bbox': <dynamic>[0.0, 0.0, 1.0, 1.0],
          'confidence': 0.5,
        },
      ],
    });

    expect(session.detections.length, 3);
    final int uncertain = session.detections
        .where((RemoteDetection d) => d.confidence < kUncertainConfidence)
        .length;
    // 0.92 与 0.5（边界值不算低置信）为高置信；0.31 为待核验
    expect(uncertain, 1);
    expect(session.detections.first.bbox, <double>[0.1, 0.2, 0.3, 0.4]);
    expect(session.detections.first.assetId, 'a-1');
  });

  test('无检测字段的会话保持空列表', () {
    final session = RemoteInventorySession.fromJson(<String, dynamic>{
      'id': 's-2',
      'penId': 'p-1',
      'businessDate': '2026-09-18',
      'status': 'review_required',
    });
    expect(session.detections, isEmpty);
  });
}
