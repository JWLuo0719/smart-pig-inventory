import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/storage/media_materializer.dart';
import '../domain/capture_draft_repository.dart';

class CreatedCaptureDraft {
  const CreatedCaptureDraft({
    required this.draftId,
    required this.captureSetId,
    required this.assetId,
    required this.materializedFile,
  });

  final String draftId;
  final String captureSetId;
  final String assetId;
  final File materializedFile;
}

class CreateSingleImageDraft {
  CreateSingleImageDraft({
    required MediaMaterializer materializer,
    required CaptureDraftRepository repository,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _materializer = materializer,
        _repository = repository,
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  final MediaMaterializer _materializer;
  final CaptureDraftRepository _repository;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Future<CreatedCaptureDraft> execute({
    required File source,
    required String originalName,
    required String contentType,
    required String organizationId,
    required String penId,
    required DateTime businessDate,
    required DateTime capturedAt,
    required int width,
    required int height,
    Map<String, Object?> exif = const <String, Object?>{},
    Map<String, Object?>? roi,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive');
    }

    final String draftId = _uuid.v4();
    final String captureSetId = _uuid.v4();
    final String assetId = _uuid.v4();
    final MaterializedMedia materialized = await _materializer.materialize(
      source: source,
      organizationId: organizationId,
      draftId: draftId,
      assetId: assetId,
      originalName: originalName,
    );

    try {
      await _repository.createDraft(
        draftId: draftId,
        captureSetId: captureSetId,
        organizationId: organizationId,
        penId: penId,
        captureKind: 'single',
        businessDate: DateTime.utc(
          businessDate.year,
          businessDate.month,
          businessDate.day,
        ),
        media: CapturedMediaRecord(
          assetId: assetId,
          position: 'single',
          materializedPath: materialized.file.path,
          originalName: originalName,
          contentType: contentType,
          byteSize: materialized.byteSize,
          sha256: materialized.sha256,
          capturedAt: capturedAt.toUtc(),
          width: width,
          height: height,
          exifJson: jsonEncode(exif),
          roiJson: jsonEncode(roi),
        ),
        now: _clock().toUtc(),
      );
    } catch (_) {
      if (await materialized.file.exists()) await materialized.file.delete();
      rethrow;
    }

    return CreatedCaptureDraft(
      draftId: draftId,
      captureSetId: captureSetId,
      assetId: assetId,
      materializedFile: materialized.file,
    );
  }
}
