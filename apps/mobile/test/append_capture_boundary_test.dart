import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/add_capture_view.dart';
import 'package:smart_pig_inventory/features/capture/application/create_three_view_draft.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';

class _InterleavedMaterializer extends MediaMaterializer {
  _InterleavedMaterializer(super.rootDirectory, this.afterCopy);
  final Future<void> Function() afterCopy;
  @override
  Future<MaterializedMedia> materialize(
      {required File source,
      required String organizationId,
      required String draftId,
      required String assetId,
      required String originalName}) async {
    final media = await super.materialize(
        source: source,
        organizationId: organizationId,
        draftId: draftId,
        assetId: assetId,
        originalName: originalName);
    await afterCopy();
    return media;
  }
}

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late File source;
  late DriftCaptureDraftRepository repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('append-boundary-');
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftCaptureDraftRepository(db);
    source = File('${sandbox.path}/synthetic.jpg')..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() async {
    await db.close();
    await sandbox.delete(recursive: true);
  });

  Future<String> create() async => (await CreateThreeViewDraft(
              materializer:
                  MediaMaterializer(Directory('${sandbox.path}/media')),
              repository: repository)
          .execute(
              source: source,
              originalName: 'synthetic.jpg',
              contentType: 'image/jpeg',
              organizationId: 'org',
              penId: 'pen',
              businessDate: DateTime.utc(2026, 10, 23),
              capturedAt: DateTime.utc(2026, 10, 23),
              width: 80,
              height: 120))
      .draftId;

  Future<String> append(String draftId,
          {String org = 'org',
          String assetId = 'center',
          MediaMaterializer? materializer}) =>
      AddCaptureView(
              materializer: materializer ??
                  MediaMaterializer(Directory('${sandbox.path}/media')),
              repository: repository)
          .execute(
              source: source,
              originalName: 'synthetic.jpg',
              contentType: 'image/jpeg',
              organizationId: org,
              draftId: draftId,
              assetId: assetId,
              position: 'center',
              capturedAt: DateTime.utc(2026, 10, 23),
              width: 80,
              height: 120);

  test('another organization cannot append to an existing draft', () async {
    final id = await create();
    await expectLater(append(id, org: 'other'), throwsStateError);
    expect(await repository.viewPositions(id), ['left']);
    expect(await db.select(db.localMediaAssets).get(), hasLength(1));
  });

  for (final state in ['queued', 'abandoned']) {
    test('draft becoming $state during copy rejects append and keeps old image',
        () async {
      final id = await create();
      final old = await db.select(db.localMediaAssets).getSingle();
      final materializer = _InterleavedMaterializer(
          Directory('${sandbox.path}/media'), () async {
        await (db.update(db.captureDrafts)..where((d) => d.id.equals(id)))
            .write(CaptureDraftsCompanion(state: Value(state)));
      });
      await expectLater(
          append(id, materializer: materializer), throwsStateError);
      expect(await repository.viewPositions(id), ['left']);
      expect(await File(old.materializedPath).exists(), isTrue);
      expect(
          await File('${sandbox.path}/media/media/org/$id/center.jpg').exists(),
          isFalse);
    });
  }

  test('an Outbox row forbids append even when draft status has not advanced',
      () async {
    final id = await create();
    final now = DateTime.utc(2026, 10, 23);
    await db.into(db.outboxEntries).insert(OutboxEntriesCompanion.insert(
        packageId: 'package',
        draftId: id,
        idempotencyKey: 'stable-key',
        manifestJson: '{}',
        createdAt: now,
        updatedAt: now));
    await expectLater(append(id), throwsStateError);
    expect(await repository.viewPositions(id), ['left']);
    expect((await db.select(db.outboxEntries).getSingle()).idempotencyKey,
        'stable-key');
  });

  test('concurrent direction writes commit only one immutable media row',
      () async {
    final id = await create();
    final outcomes = await Future.wait([
      append(id, assetId: 'one').then((_) => true, onError: (_) => false),
      append(id, assetId: 'two').then((_) => true, onError: (_) => false),
    ]);
    expect(outcomes.where((success) => success), hasLength(1));
    expect(await repository.viewPositions(id),
        unorderedEquals(['left', 'center']));
  });
}
