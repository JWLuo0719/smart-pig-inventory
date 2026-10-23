import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../domain/capture_draft_repository.dart';

class DriftCaptureDraftRepository implements CaptureDraftRepository {
  DriftCaptureDraftRepository(this.database, {this.replaceDraftId});
  final String? replaceDraftId;

  final AppDatabase database;

  @override
  Future<void> addMedia({
    required String organizationId,
    required String draftId,
    required CapturedMediaRecord media,
    required DateTime now,
  }) {
    return database.transaction(() async {
      // Recheck after materialization: another action may have queued or
      // abandoned the draft while the new file was being copied.
      final draft = await (database.select(database.captureDrafts)
            ..where((entry) => entry.id.equals(draftId)))
          .getSingle();
      final outbox = await (database.select(database.outboxEntries)
            ..where((entry) => entry.draftId.equals(draftId)))
          .getSingleOrNull();
      final positions = await viewPositions(draftId);
      if (draft.organizationId != organizationId ||
          draft.state != 'draft' ||
          draft.captureKind != 'left_center_right' ||
          outbox != null ||
          !const {'left', 'center', 'right'}.contains(media.position) ||
          positions.contains(media.position)) {
        throw StateError('只有当前组织尚未入队的三图草稿可补充新方向');
      }
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
      await (database.update(database.captureDrafts)
            ..where((entry) => entry.id.equals(draftId)))
          .write(CaptureDraftsCompanion(updatedAt: Value(now)));
    });
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
  Future<CaptureDraftSnapshot?> findLatestForTarget({
    required String organizationId,
    required String penId,
    required DateTime businessDate,
    String? draftId,
  }) async {
    final DateTime normalizedBusinessDate = DateTime.utc(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    final CaptureDraft? draft = await (database.select(database.captureDrafts)
          ..where((entry) =>
              entry.organizationId.equals(organizationId) &
              entry.penId.equals(penId) &
              (draftId == null
                  ? const Constant(true)
                  : entry.id.equals(draftId)) &
              entry.businessDate.equals(normalizedBusinessDate) &
              entry.state.isIn(<String>['draft', 'queued']))
          ..orderBy(<OrderingTerm Function(CaptureDrafts)>[
            (CaptureDrafts entry) => OrderingTerm.desc(entry.updatedAt),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (draft == null) return null;

    final CaptureSet captureSet = await (database.select(database.captureSets)
          ..where((entry) => entry.draftId.equals(draft.id)))
        .getSingle();
    final List<LocalMediaAsset> assets = await (database.select(
      database.localMediaAssets,
    )
          ..where((entry) => entry.draftId.equals(draft.id))
          ..orderBy(<OrderingTerm Function(LocalMediaAssets)>[
            (LocalMediaAssets entry) => OrderingTerm.asc(entry.createdAt),
          ]))
        .get();
    return CaptureDraftSnapshot(
      draftId: draft.id,
      captureSetId: captureSet.id,
      captureKind: draft.captureKind,
      state: draft.state,
      media: assets
          .map(
            (LocalMediaAsset asset) => CapturedMediaRecord(
              assetId: asset.id,
              position: asset.viewPosition,
              materializedPath: asset.materializedPath,
              originalName: asset.originalName,
              contentType: asset.contentType,
              byteSize: asset.byteSize,
              sha256: asset.sha256,
              capturedAt: asset.capturedAt ?? asset.createdAt,
              width: asset.width ?? 0,
              height: asset.height ?? 0,
              exifJson: asset.exifJson,
              roiJson: asset.roiJson,
            ),
          )
          .toList(growable: false),
    );
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
      if (replaceDraftId != null) {
        final old = await (database.select(database.captureDrafts)
              ..where((r) => r.id.equals(replaceDraftId!)))
            .getSingle();
        final queued = await (database.select(database.outboxEntries)
              ..where((r) => r.draftId.equals(old.id)))
            .get();
        if (old.organizationId != organizationId ||
            old.penId != penId ||
            !old.businessDate.isAtSameMomentAs(businessDate) ||
            old.state != 'draft' ||
            queued.isNotEmpty) {
          throw StateError('只有当前组织尚未入队的草稿可重新采集');
        }
        await (database.update(database.captureDrafts)
              ..where((r) => r.id.equals(old.id)))
            .write(CaptureDraftsCompanion(
                state: const Value('abandoned'), updatedAt: Value(now)));
      }
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
