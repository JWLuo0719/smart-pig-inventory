import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../domain/roi.dart';

class UpdateCaptureRoi {
  UpdateCaptureRoi(this.database);

  final AppDatabase database;

  Future<void> execute(
      {required String organizationId,
      required String assetId,
      required Roi? roi}) async {
    await database.transaction(() async {
      final LocalMediaAsset asset =
          await (database.select(database.localMediaAssets)
                ..where((entry) => entry.id.equals(assetId)))
              .getSingle();
      final CaptureDraft draft = await (database.select(database.captureDrafts)
            ..where((entry) => entry.id.equals(asset.draftId)))
          .getSingle();
      final queued = await (database.select(database.outboxEntries)
            ..where((r) => r.draftId.equals(draft.id)))
          .get();
      if (draft.organizationId != organizationId ||
          draft.state != 'draft' ||
          queued.isNotEmpty) {
        throw StateError(
            'ROI can only change before the capture set enters the upload queue');
      }
      final DateTime now = DateTime.now().toUtc();
      await (database.update(database.localMediaAssets)
            ..where((entry) => entry.id.equals(assetId)))
          .write(LocalMediaAssetsCompanion(
              roiJson: Value<String>(jsonEncode(roi?.toJson()))));
      await (database.update(database.captureDrafts)
            ..where((entry) => entry.id.equals(asset.draftId)))
          .write(CaptureDraftsCompanion(updatedAt: Value<DateTime>(now)));
    });
  }
}
