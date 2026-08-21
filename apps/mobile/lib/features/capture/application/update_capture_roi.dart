import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../domain/roi.dart';

class UpdateCaptureRoi {
  UpdateCaptureRoi(this.database);

  final AppDatabase database;

  Future<void> execute({required String assetId, required Roi? roi}) async {
    final LocalMediaAsset asset =
        await (database.select(database.localMediaAssets)
              ..where((entry) => entry.id.equals(assetId)))
            .getSingle();
    final CaptureDraft draft = await (database.select(database.captureDrafts)
          ..where((entry) => entry.id.equals(asset.draftId)))
        .getSingle();
    if (draft.state != 'draft') {
      throw StateError(
          'ROI can only change before the capture set enters the upload queue');
    }
    final DateTime now = DateTime.now().toUtc();
    await database.transaction(() async {
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
