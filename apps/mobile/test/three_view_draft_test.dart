import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/add_capture_view.dart';
import 'package:smart_pig_inventory/features/capture/application/create_three_view_draft.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';

void main() {
  test('three views share one draft and reject a duplicate direction',
      () async {
    final Directory sandbox =
        await Directory.systemTemp.createTemp('three-view-draft-test');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final File left = File(path.join(sandbox.path, 'left.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final File center = File(path.join(sandbox.path, 'center.jpg'))
      ..writeAsBytesSync(<int>[4, 5, 6]);
    final File right = File(path.join(sandbox.path, 'right.jpg'))
      ..writeAsBytesSync(<int>[7, 8, 9]);
    final AppDatabase database = AppDatabase(
        NativeDatabase(File(path.join(sandbox.path, 'app.sqlite'))));
    addTearDown(database.close);
    final DriftCaptureDraftRepository repository =
        DriftCaptureDraftRepository(database);
    final MediaMaterializer materializer =
        MediaMaterializer(Directory(path.join(sandbox.path, 'documents')));
    final CreateThreeViewDraft start = CreateThreeViewDraft(
      materializer: materializer,
      repository: repository,
      clock: () => DateTime.utc(2026, 8, 20),
    );
    final created = await start.execute(
      source: left,
      originalName: 'left.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      penId: 'pen-1',
      businessDate: DateTime.utc(2026, 8, 20),
      capturedAt: DateTime.utc(2026, 8, 20, 1),
      width: 100,
      height: 80,
    );
    final AddCaptureView append = AddCaptureView(
      materializer: materializer,
      repository: repository,
      clock: () => DateTime.utc(2026, 8, 20, 1),
    );

    await append.execute(
      source: center,
      originalName: 'center.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      draftId: created.draftId,
      assetId: 'asset-center',
      position: 'center',
      capturedAt: DateTime.utc(2026, 8, 20, 2),
      width: 100,
      height: 80,
    );
    await append.execute(
      source: right,
      originalName: 'right.jpg',
      contentType: 'image/jpeg',
      organizationId: 'organization-1',
      draftId: created.draftId,
      assetId: 'asset-right',
      position: 'right',
      capturedAt: DateTime.utc(2026, 8, 20, 3),
      width: 100,
      height: 80,
    );

    await expectLater(
      append.execute(
        source: center,
        originalName: 'retry-center.jpg',
        contentType: 'image/jpeg',
        organizationId: 'organization-1',
        draftId: created.draftId,
        assetId: 'asset-duplicate',
        position: 'center',
        capturedAt: DateTime.utc(2026, 8, 20, 4),
        width: 100,
        height: 80,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await repository.viewPositions(created.draftId),
        containsAll(<String>['left', 'center', 'right']));
    expect(
      (await database.select(database.localMediaAssets).get()).length,
      3,
    );
  });
}
