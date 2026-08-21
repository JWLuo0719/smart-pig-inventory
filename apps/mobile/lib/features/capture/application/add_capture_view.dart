import 'dart:convert';
import 'dart:io';

import '../../../core/storage/media_materializer.dart';
import '../domain/capture_draft_repository.dart';

class AddCaptureView {
  AddCaptureView({
    required MediaMaterializer materializer,
    required CaptureDraftRepository repository,
    DateTime Function()? clock,
  })  : _materializer = materializer,
        _repository = repository,
        _clock = clock ?? DateTime.now;

  final MediaMaterializer _materializer;
  final CaptureDraftRepository _repository;
  final DateTime Function() _clock;

  Future<String> execute({
    required File source,
    required String originalName,
    required String contentType,
    required String organizationId,
    required String draftId,
    required String assetId,
    required String position,
    required DateTime capturedAt,
    required int width,
    required int height,
    Map<String, Object?> exif = const <String, Object?>{},
    Map<String, Object?>? roi,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive');
    }
    if (!const <String>{'left', 'center', 'right'}.contains(position)) {
      throw ArgumentError.value(
          position, 'position', 'Invalid three-view position');
    }
    final List<String> existingPositions =
        await _repository.viewPositions(draftId);
    if (existingPositions.contains(position)) {
      throw StateError('This capture direction already has media');
    }

    final MaterializedMedia materialized = await _materializer.materialize(
      source: source,
      organizationId: organizationId,
      draftId: draftId,
      assetId: assetId,
      originalName: originalName,
    );
    try {
      await _repository.addMedia(
        draftId: draftId,
        media: CapturedMediaRecord(
          assetId: assetId,
          position: position,
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
    return assetId;
  }
}
