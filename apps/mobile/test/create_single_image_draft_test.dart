import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/create_single_image_draft.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';

void main() {
  test('single image evidence and draft survive database reopen', () async {
    final Directory sandbox =
        await Directory.systemTemp.createTemp('single-draft-test');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final File source = File(path.join(sandbox.path, 'picker-photo.jpg'))
      ..writeAsBytesSync(List<int>.generate(4096, (int index) => index % 251));
    final File databaseFile = File(path.join(sandbox.path, 'app.sqlite'));
    final Directory appFiles = Directory(path.join(sandbox.path, 'documents'));

    AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
    final CreateSingleImageDraft createDraft = CreateSingleImageDraft(
      materializer: MediaMaterializer(appFiles),
      repository: DriftCaptureDraftRepository(database),
      clock: () => DateTime.utc(2026, 8, 20, 9),
    );

    final CreatedCaptureDraft created = await createDraft.execute(
      source: source,
      originalName: 'pen-03.jpg',
      contentType: 'image/jpeg',
      organizationId: '11111111-1111-4111-8111-111111111111',
      penId: '22222222-2222-4222-8222-222222222222',
      businessDate: DateTime(2026, 8, 20, 23, 30),
      capturedAt: DateTime.parse('2026-08-20T09:01:00+08:00'),
      width: 1920,
      height: 1080,
    );
    await database.close();

    database = AppDatabase(NativeDatabase(databaseFile));
    addTearDown(database.close);
    final CaptureDraft draft =
        await database.select(database.captureDrafts).getSingle();
    final CaptureSet captureSet =
        await database.select(database.captureSets).getSingle();
    final LocalMediaAsset media =
        await database.select(database.localMediaAssets).getSingle();
    final restored =
        await DriftCaptureDraftRepository(database).findLatestForTarget(
      organizationId: '11111111-1111-4111-8111-111111111111',
      penId: '22222222-2222-4222-8222-222222222222',
      businessDate: DateTime.utc(2026, 8, 20),
    );

    expect(draft.id, created.draftId);
    expect(draft.state, 'draft');
    expect(draft.businessDate.toUtc(), DateTime.utc(2026, 8, 20));
    expect(captureSet.id, created.captureSetId);
    expect(captureSet.draftId, draft.id);
    expect(media.id, created.assetId);
    expect(media.viewPosition, 'single');
    expect(media.width, 1920);
    expect(media.height, 1080);
    expect(media.capturedAt?.toUtc(), DateTime.utc(2026, 8, 20, 1, 1));
    expect(await File(media.materializedPath).exists(), isTrue);
    expect(restored?.draftId, created.draftId);
    expect(restored?.captureSetId, created.captureSetId);
    expect(restored?.state, 'draft');
    expect(restored?.media.single.materializedPath, media.materializedPath);
  });
}
