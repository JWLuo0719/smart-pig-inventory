import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/features/local_activity/data/local_activity_repository.dart';

void main() {
  late AppDatabase database;
  late LocalActivityRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LocalActivityRepository(database);
  });
  tearDown(() => database.close());

  test('projects only the active organization local evidence and real state',
      () async {
    final DateTime now = DateTime.utc(2026, 9, 4, 8, 30);
    await _seedMasterData(database, now);
    await _seedDraft(database,
        id: 'draft-a', organizationId: 'org-a', now: now, byteSize: 2048);
    await _seedDraft(database,
        id: 'draft-b', organizationId: 'org-b', now: now, byteSize: 4096);

    final List<LocalCaptureActivity> rows =
        await repository.watchRecent('org-a').first;
    final LocalActivityStats stats = await repository.watchStats('org-a').first;

    expect(rows, hasLength(1));
    expect(rows.single.draftId, 'draft-a');
    expect(rows.single.buildingLabel, 'B01 育肥栋');
    expect(rows.single.penLabel, 'P01栏 · 一号栏');
    expect(rows.single.outboxState, 'retry_wait');
    expect(rows.single.mediaCount, 1);
    expect(rows.single.totalBytes, 2048);
    expect(stats.draftCount, 1);
    expect(stats.pendingUploadCount, 1);
    expect(stats.blockedUploadCount, 0);
    expect(stats.mediaCount, 1);
    expect(stats.mediaBytes, 2048);
  });

  test(
      'preview is scoped and abandoned uploads keep evidence without pending counts',
      () async {
    final now = DateTime.utc(2026, 9, 12);
    await _seedDraft(database,
        id: 'abandoned', organizationId: 'org-a', now: now, byteSize: 128);
    await (database.update(database.outboxEntries)
          ..where((row) => row.draftId.equals('abandoned')))
        .write(const OutboxEntriesCompanion(state: Value('abandoned')));
    expect(await repository.mediaForDraft('org-a', 'abandoned'), hasLength(1));
    await expectLater(
        repository.mediaForDraft('org-b', 'abandoned'), throwsStateError);
    final stats = await repository.watchStats('org-a').first;
    expect(stats.pendingUploadCount, 0);
    expect(stats.mediaCount, 1);
    expect((await repository.watchRecent('org-a').first).single.isPending,
        isFalse);
  });
}

Future<void> _seedMasterData(AppDatabase database, DateTime now) async {
  await database.into(database.cachedOrganizations).insert(
        CachedOrganizationsCompanion.insert(
          id: 'org-a',
          code: 'A',
          name: '甲场',
          syncedAt: now,
        ),
      );
  await database.into(database.cachedBuildings).insert(
        CachedBuildingsCompanion.insert(
          id: 'building-a',
          organizationId: 'org-a',
          code: 'B01',
          name: '育肥栋',
        ),
      );
  await database.into(database.cachedPens).insert(
        CachedPensCompanion.insert(
          id: 'pen-a',
          buildingId: 'building-a',
          code: 'P01',
          name: '一号栏',
        ),
      );
}

Future<void> _seedDraft(
  AppDatabase database, {
  required String id,
  required String organizationId,
  required DateTime now,
  required int byteSize,
}) async {
  await database.into(database.captureDrafts).insert(
        CaptureDraftsCompanion.insert(
          id: id,
          organizationId: organizationId,
          penId: organizationId == 'org-a' ? 'pen-a' : 'pen-b',
          captureKind: 'single',
          businessDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database.into(database.localMediaAssets).insert(
        LocalMediaAssetsCompanion.insert(
          id: 'media-$id',
          draftId: id,
          viewPosition: 'single',
          materializedPath: 'C:/evidence/$id.jpg',
          originalName: '$id.jpg',
          contentType: 'image/jpeg',
          byteSize: byteSize,
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          createdAt: now,
        ),
      );
  await database.into(database.outboxEntries).insert(
        OutboxEntriesCompanion.insert(
          packageId: 'package-$id',
          draftId: id,
          idempotencyKey: 'key-$id',
          state: const Value<String>('retry_wait'),
          manifestJson: '{}',
          createdAt: now,
          updatedAt: now,
        ),
      );
}
