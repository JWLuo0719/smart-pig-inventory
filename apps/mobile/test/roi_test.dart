import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/create_single_image_draft.dart';
import 'package:smart_pig_inventory/features/capture/application/update_capture_roi.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';
import 'package:smart_pig_inventory/features/capture/domain/roi.dart';
import 'package:smart_pig_inventory/features/outbox/application/queue_capture_draft.dart';

void main() {
  test('ROI accepts bounds and rejects out-of-image regions', () {
    expect(
      Roi(x: 0.1, y: 0.2, width: 0.7, height: 0.6).toJson(),
      <String, double>{'x': 0.1, 'y': 0.2, 'width': 0.7, 'height': 0.6},
    );
    expect(
      () => Roi(x: 0.8, y: 0, width: 0.3, height: 0.2),
      throwsArgumentError,
    );
    expect(
      () => Roi(x: 0, y: 0, width: 0, height: 1),
      throwsArgumentError,
    );
  });

  test('ROI is persisted only while the capture set is a draft', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp('roi-test');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final AppDatabase database = AppDatabase(
        NativeDatabase(File(path.join(sandbox.path, 'app.sqlite'))));
    addTearDown(database.close);
    final File image = File(path.join(sandbox.path, 'photo.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final CreatedCaptureDraft draft = await CreateSingleImageDraft(
      materializer:
          MediaMaterializer(Directory(path.join(sandbox.path, 'documents'))),
      repository: DriftCaptureDraftRepository(database),
    ).execute(
      source: image,
      originalName: 'photo.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      penId: 'pen-1',
      businessDate: DateTime.utc(2026, 8, 20),
      capturedAt: DateTime.utc(2026, 8, 20, 1),
      width: 100,
      height: 100,
    );
    final UpdateCaptureRoi update = UpdateCaptureRoi(database);
    final Roi roi = Roi(x: 0.1, y: 0.1, width: 0.8, height: 0.8);

    await update.execute(assetId: draft.assetId, roi: roi);
    final LocalMediaAsset asset =
        await database.select(database.localMediaAssets).getSingle();
    expect(jsonDecode(asset.roiJson), roi.toJson());

    await QueueCaptureDraft(database).execute(draft.draftId);
    await expectLater(
      update.execute(assetId: draft.assetId, roi: null),
      throwsA(isA<StateError>()),
    );
  });
}
