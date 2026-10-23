import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/create_single_image_draft.dart';
import 'package:smart_pig_inventory/features/capture/application/abandon_unqueued_capture_draft.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';
import 'package:smart_pig_inventory/features/outbox/application/queue_capture_draft.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late File source;
  Future<CreatedCaptureDraft> capture(
          {String? replacing, String org = 'org'}) =>
      CreateSingleImageDraft(
        materializer: MediaMaterializer(Directory('${sandbox.path}/media')),
        repository: DriftCaptureDraftRepository(db, replaceDraftId: replacing),
      ).execute(
          source: source,
          originalName: 'synthetic.jpg',
          contentType: 'image/jpeg',
          organizationId: org,
          penId: 'pen',
          businessDate: DateTime.utc(2026, 10, 18),
          capturedAt: DateTime.utc(2026, 10, 18),
          width: 2,
          height: 2);
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('synthetic-recapture-');
    db = AppDatabase(NativeDatabase.memory());
    source = File('${sandbox.path}/synthetic.jpg')..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() async {
    await db.close();
    await sandbox.delete(recursive: true);
  });
  test(
      'replacement keeps old evidence and changes UUID only after successful new materialization',
      () async {
    final old = await capture();
    final fresh = await capture(replacing: old.draftId);
    expect(fresh.draftId, isNot(old.draftId));
    expect(await old.materializedFile.exists(), isTrue);
    final rows = await db.select(db.captureDrafts).get();
    expect(rows.firstWhere((r) => r.id == old.draftId).state, 'abandoned');
    expect(rows.firstWhere((r) => r.id == fresh.draftId).state, 'draft');
    expect(
        (await DriftCaptureDraftRepository(db).findLatestForTarget(
                organizationId: 'org',
                penId: 'pen',
                businessDate: DateTime.utc(2026, 10, 18),
                draftId: fresh.draftId))
            ?.draftId,
        fresh.draftId);
  });
  test('queued race and other organization cannot replace or abandon evidence',
      () async {
    final old = await capture();
    await expectLater(
        capture(replacing: old.draftId, org: 'other'), throwsStateError);
    await expectLater(
        AbandonUnqueuedCaptureDraft(db)
            .execute(old.draftId, organizationId: 'other'),
        throwsStateError);
    final queued =
        await QueueCaptureDraft(db).execute(old.draftId, organizationId: 'org');
    await expectLater(capture(replacing: old.draftId), throwsStateError);
    await expectLater(
        AbandonUnqueuedCaptureDraft(db)
            .execute(old.draftId, organizationId: 'org'),
        throwsStateError);
    expect((await db.select(db.captureDrafts).getSingle()).state, 'queued');
    expect((await db.select(db.outboxEntries).getSingle()).idempotencyKey,
        queued.idempotencyKey);
    expect(await old.materializedFile.exists(), isTrue);
  });
  test(
      'failed new media preserves original draft; explicit abandonment preserves bytes',
      () async {
    final old = await capture();
    await source.delete();
    await expectLater(
        capture(replacing: old.draftId), throwsA(isA<FileSystemException>()));
    expect((await db.select(db.captureDrafts).getSingle()).state, 'draft');
    await AbandonUnqueuedCaptureDraft(db)
        .execute(old.draftId, organizationId: 'org');
    expect((await db.select(db.captureDrafts).getSingle()).state, 'abandoned');
    expect(await old.materializedFile.exists(), isTrue);
  });
}
