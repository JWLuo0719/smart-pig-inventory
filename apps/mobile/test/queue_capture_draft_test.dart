import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/create_single_image_draft.dart';
import 'package:smart_pig_inventory/features/capture/application/create_three_view_draft.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';
import 'package:smart_pig_inventory/features/outbox/application/queue_capture_draft.dart';

void main() {
  late Directory sandbox;
  late AppDatabase database;
  late DriftCaptureDraftRepository drafts;
  late MediaMaterializer materializer;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('queue-capture-draft-test');
    database = AppDatabase(
        NativeDatabase(File(path.join(sandbox.path, 'app.sqlite'))));
    drafts = DriftCaptureDraftRepository(database);
    materializer =
        MediaMaterializer(Directory(path.join(sandbox.path, 'documents')));
  });

  tearDown(() async {
    await database.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('queues a complete single capture once with its full manifest',
      () async {
    final File image = File(path.join(sandbox.path, 'single.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final CreatedCaptureDraft draft = await CreateSingleImageDraft(
      materializer: materializer,
      repository: drafts,
      clock: () => DateTime.utc(2026, 8, 20, 9),
    ).execute(
      source: image,
      originalName: 'single.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      penId: 'pen-1',
      businessDate: DateTime.utc(2026, 8, 20),
      capturedAt: DateTime.utc(2026, 8, 20, 1),
      width: 1920,
      height: 1080,
      exif: const <String, Object?>{'orientation': 1},
    );
    final QueueCaptureDraft queue = QueueCaptureDraft(database);

    final QueuedCapturePackage first = await queue.execute(draft.draftId);
    final QueuedCapturePackage replay = await queue.execute(draft.draftId);

    expect(first.wasAlreadyQueued, isFalse);
    expect(replay.wasAlreadyQueued, isTrue);
    expect(replay.packageId, first.packageId);
    expect(replay.idempotencyKey, first.idempotencyKey);
    final OutboxEntry outbox =
        await database.select(database.outboxEntries).getSingle();
    final Map<String, dynamic> manifest =
        jsonDecode(outbox.manifestJson) as Map<String, dynamic>;
    final Map<String, dynamic> asset =
        (manifest['assets'] as List<dynamic>).single as Map<String, dynamic>;
    expect(manifest['captureKind'], 'single');
    expect(asset['assetId'], draft.assetId);
    expect(asset['width'], 1920);
    expect(asset['exif'], <String, dynamic>{'orientation': 1});
    expect(asset['roi'], isNull);
    expect(
        (await database.select(database.uploadAssetEntries).get()).length, 1);
    expect(
      (await database.select(database.captureDrafts).getSingle()).state,
      'queued',
    );
    final restored = await drafts.findLatestForTarget(
      organizationId: 'organization-1',
      penId: 'pen-1',
      businessDate: DateTime.utc(2026, 8, 20),
    );
    expect(restored?.state, 'queued');
    expect(restored?.media.single.assetId, draft.assetId);
  });

  test('rejects an incomplete three-view draft without creating an outbox',
      () async {
    final File image = File(path.join(sandbox.path, 'left.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final CreatedCaptureDraft draft = await CreateThreeViewDraft(
      materializer: materializer,
      repository: drafts,
    ).execute(
      source: image,
      originalName: 'left.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      penId: 'pen-1',
      businessDate: DateTime.utc(2026, 8, 20),
      capturedAt: DateTime.utc(2026, 8, 20, 1),
      width: 100,
      height: 80,
    );

    await expectLater(
      QueueCaptureDraft(database).execute(draft.draftId),
      throwsA(isA<StateError>()),
    );

    expect(await database.select(database.outboxEntries).get(), isEmpty);
    expect(
      (await database.select(database.captureDrafts).getSingle()).state,
      'draft',
    );
  });
}
