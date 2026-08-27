import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';

class QueuedCapturePackage {
  const QueuedCapturePackage({
    required this.packageId,
    required this.idempotencyKey,
    required this.wasAlreadyQueued,
  });

  final String packageId;
  final String idempotencyKey;
  final bool wasAlreadyQueued;
}

/// Moves a complete local capture set into the durable upload Outbox. No
/// network work occurs here; foreground and background upload use this same
/// persisted operation later.
class QueueCaptureDraft {
  QueueCaptureDraft(this.database,
      {Uuid uuid = const Uuid(), Future<void> Function()? scheduleSync})
      : _uuid = uuid,
        _scheduleSync = scheduleSync;

  final AppDatabase database;
  final Uuid _uuid;
  final Future<void> Function()? _scheduleSync;

  Future<QueuedCapturePackage> execute(String draftId) async {
    final QueuedCapturePackage result = await database.transaction(() async {
      final OutboxEntry? existing =
          await (database.select(database.outboxEntries)
                ..where((entry) => entry.draftId.equals(draftId)))
              .getSingleOrNull();
      if (existing != null) {
        return QueuedCapturePackage(
          packageId: existing.packageId,
          idempotencyKey: existing.idempotencyKey,
          wasAlreadyQueued: true,
        );
      }

      final CaptureDraft draft = await (database.select(database.captureDrafts)
            ..where((entry) => entry.id.equals(draftId)))
          .getSingle();
      if (draft.state != 'draft') {
        throw StateError('Only draft capture sets can enter the upload queue');
      }
      final CaptureSet captureSet = await (database.select(database.captureSets)
            ..where((entry) => entry.draftId.equals(draftId)))
          .getSingle();
      final List<LocalMediaAsset> assets = await (database.select(
        database.localMediaAssets,
      )
            ..where((entry) => entry.draftId.equals(draftId))
            ..orderBy(<OrderingTerm Function(LocalMediaAssets)>[
              (LocalMediaAssets entry) => OrderingTerm.asc(entry.createdAt),
            ]))
          .get();
      _validateCompleteCaptureSet(draft.captureKind, assets);

      final String packageId = _uuid.v4();
      final String idempotencyKey = _uuid.v4();
      final String manifestJson = jsonEncode(<String, Object?>{
        'captureSetId': captureSet.id,
        'captureKind': draft.captureKind,
        'penId': draft.penId,
        'assets': assets.map(_manifestAsset).toList(),
      });
      final DateTime now = DateTime.now().toUtc();
      await database.into(database.outboxEntries).insert(
            OutboxEntriesCompanion.insert(
              packageId: packageId,
              draftId: draftId,
              idempotencyKey: idempotencyKey,
              manifestJson: manifestJson,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database.batch((Batch batch) {
        batch.insertAll(
          database.uploadAssetEntries,
          assets
              .map(
                (LocalMediaAsset asset) => UploadAssetEntriesCompanion.insert(
                  packageId: packageId,
                  assetId: asset.id,
                  updatedAt: now,
                ),
              )
              .toList(),
        );
        batch.update(
          database.captureDrafts,
          CaptureDraftsCompanion(
            state: const Value<String>('queued'),
            updatedAt: Value<DateTime>(now),
          ),
          where: (CaptureDrafts entry) => entry.id.equals(draftId),
        );
      });
      return QueuedCapturePackage(
        packageId: packageId,
        idempotencyKey: idempotencyKey,
        wasAlreadyQueued: false,
      );
    });
    if (!result.wasAlreadyQueued) {
      // Local queue durability is the source of truth. A scheduling failure
      // must not turn a successful local save into a user-visible failure.
      try {
        await _scheduleSync?.call();
      } on Exception {
        // The next app launch or manual retry will schedule the same unique job.
      }
    }
    return result;
  }

  Map<String, Object?> _manifestAsset(LocalMediaAsset asset) {
    if (asset.capturedAt == null ||
        asset.width == null ||
        asset.height == null) {
      throw StateError('Media metadata is incomplete and cannot be uploaded');
    }
    return <String, Object?>{
      'assetId': asset.id,
      'viewPosition': asset.viewPosition,
      'capturedAt': asset.capturedAt!.toUtc().toIso8601String(),
      'originalName': asset.originalName,
      'width': asset.width,
      'height': asset.height,
      'sha256': asset.sha256,
      'byteSize': asset.byteSize,
      'mediaType': asset.contentType,
      'exif': _decodeObject(asset.exifJson, 'exif'),
      'roi': _decodeNullableObject(asset.roiJson, 'roi'),
    };
  }

  Object _decodeObject(String source, String field) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw StateError('$field metadata must be a JSON object');
    }
    return decoded;
  }

  Object? _decodeNullableObject(String source, String field) {
    final Object? decoded = jsonDecode(source);
    if (decoded == null || decoded is Map<String, Object?>) return decoded;
    throw StateError('$field metadata must be null or a JSON object');
  }

  void _validateCompleteCaptureSet(
    String captureKind,
    List<LocalMediaAsset> assets,
  ) {
    final Set<String> positions =
        assets.map((LocalMediaAsset asset) => asset.viewPosition).toSet();
    final Set<String> expected = switch (captureKind) {
      'single' => <String>{'single'},
      'left_center_right' => <String>{'left', 'center', 'right'},
      _ => throw StateError('Unsupported capture kind'),
    };
    if (assets.length != expected.length || !positions.containsAll(expected)) {
      throw StateError(
          'Capture set is incomplete and cannot enter the upload queue');
    }
  }
}
