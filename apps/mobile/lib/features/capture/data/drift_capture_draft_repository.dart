import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../domain/capture_draft_repository.dart';

class DriftCaptureDraftRepository implements CaptureDraftRepository {
  DriftCaptureDraftRepository(this.database);

  final AppDatabase database;

  @override
  Future<void> addMedia({
    required String draftId,
    required CapturedMediaRecord media,
    required DateTime now,
  }) {
    return database.into(database.localMediaAssets).insert(
          LocalMediaAssetsCompanion.insert(
            id: media.assetId,
            draftId: draftId,
            viewPosition: media.position,
            materializedPath: media.materializedPath,
            originalName: media.originalName,
            contentType: media.contentType,
            byteSize: media.byteSize,
            sha256: media.sha256,
            roiJson: Value<String>(media.roiJson),
            exifJson: Value<String>(media.exifJson),
            capturedAt: Value<DateTime>(media.capturedAt),
            width: Value<int>(media.width),
            height: Value<int>(media.height),
            createdAt: now,
          ),
        );
  }

  @override
  Future<List<String>> viewPositions(String draftId) async {
    final List<LocalMediaAsset> assets = await (database.select(
      database.localMediaAssets,
    )..where((asset) => asset.draftId.equals(draftId)))
        .get();
    return assets.map((LocalMediaAsset asset) => asset.viewPosition).toList();
  }

  @override
  Future<void> createDraft({
    required String draftId,
    required String captureSetId,
    required String organizationId,
    required String penId,
    required String captureKind,
    required DateTime businessDate,
    required CapturedMediaRecord media,
    required DateTime now,
  }) {
    return database.transaction(() async {
      await database.into(database.captureDrafts).insert(
            CaptureDraftsCompanion.insert(
              id: draftId,
              organizationId: organizationId,
              penId: penId,
              captureKind: captureKind,
              businessDate: businessDate,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database.into(database.captureSets).insert(
            CaptureSetsCompanion.insert(
              id: captureSetId,
              draftId: draftId,
              kind: captureKind,
              createdAt: now,
            ),
          );
      await database.into(database.localMediaAssets).insert(
            LocalMediaAssetsCompanion.insert(
              id: media.assetId,
              draftId: draftId,
              viewPosition: media.position,
              materializedPath: media.materializedPath,
              originalName: media.originalName,
              contentType: media.contentType,
              byteSize: media.byteSize,
              sha256: media.sha256,
              roiJson: Value<String>(media.roiJson),
              exifJson: Value<String>(media.exifJson),
              capturedAt: Value<DateTime>(media.capturedAt),
              width: Value<int>(media.width),
              height: Value<int>(media.height),
              createdAt: now,
            ),
          );
    });
  }
}
