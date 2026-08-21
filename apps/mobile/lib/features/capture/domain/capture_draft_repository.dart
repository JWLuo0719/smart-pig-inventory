class CapturedMediaRecord {
  const CapturedMediaRecord({
    required this.assetId,
    required this.position,
    required this.materializedPath,
    required this.originalName,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.exifJson,
    required this.roiJson,
  });

  final String assetId;
  final String position;
  final String materializedPath;
  final String originalName;
  final String contentType;
  final int byteSize;
  final String sha256;
  final DateTime capturedAt;
  final int width;
  final int height;
  final String exifJson;
  final String roiJson;
}

abstract interface class CaptureDraftRepository {
  Future<void> addMedia({
    required String draftId,
    required CapturedMediaRecord media,
    required DateTime now,
  });

  Future<List<String>> viewPositions(String draftId);

  Future<void> createDraft({
    required String draftId,
    required String captureSetId,
    required String organizationId,
    required String penId,
    required String captureKind,
    required DateTime businessDate,
    required CapturedMediaRecord media,
    required DateTime now,
  });
}
