import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/models/capture_package.dart';

void main() {
  test('capture package keeps UUIDs stable across retry manifests', () async {
    final Directory directory =
        await Directory.systemTemp.createTemp('pig-inventory-test');
    addTearDown(() => directory.delete(recursive: true));
    final File image = File('${directory.path}/photo.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final CapturePackageDraft draft = CapturePackageDraft(
      organizationId: '8e8b6b7f-5b04-4d88-8c74-d2e1a6612c70',
      penId: '33bb3532-afd8-44a0-b357-aa8490e5e3fd',
      businessDate: DateTime(2026, 8, 18),
      kind: CaptureKind.single,
      media: <LocalMediaDraft>[
        LocalMediaDraft(
          file: image,
          position: ViewPosition.single,
          contentType: 'image/jpeg',
          capturedAt: DateTime.utc(2026, 8, 18, 8, 30),
          width: 1920,
          height: 1080,
        )
      ],
    );

    final Map<String, Object?> first = await draft.toManifest();
    final Map<String, Object?> second = await draft.toManifest();
    final Map<String, Object?> firstMedia =
        (first['assets']! as List<Map<String, Object?>>).single;
    final Map<String, Object?> secondMedia =
        (second['assets']! as List<Map<String, Object?>>).single;
    expect(firstMedia['assetId'], secondMedia['assetId']);
    expect(firstMedia['sha256'], secondMedia['sha256']);
    expect(firstMedia['capturedAt'], '2026-08-18T08:30:00.000Z');
    expect(firstMedia['originalName'], 'photo.jpg');
    expect(firstMedia['width'], 1920);
    expect(firstMedia['height'], 1080);
    expect(firstMedia['roi'], isNull);
    expect(first['captureSetId'], second['captureSetId']);
  });
}
