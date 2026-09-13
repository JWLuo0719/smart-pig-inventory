import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../../core/storage/media_materializer.dart';
import '../domain/capture_draft_repository.dart';
import 'create_single_image_draft.dart';

class CreateVideoDraft {
  CreateVideoDraft({required this.materializer, required this.repository});
  final MediaMaterializer materializer;
  final CaptureDraftRepository repository;
  Future<CreatedCaptureDraft> execute(
      {required File source,
      required String originalName,
      required String organizationId,
      required String penId,
      required DateTime businessDate,
      required int width,
      required int height}) async {
    if (width <= 0 ||
        height <= 0 ||
        !originalName.toLowerCase().endsWith('.mp4')) {
      throw ArgumentError('请选择可解码的 MP4 视频。');
    }
    final draftId = const Uuid().v4(),
        setId = const Uuid().v4(),
        assetId = const Uuid().v4();
    final media = await materializer.materialize(
        source: source,
        organizationId: organizationId,
        draftId: draftId,
        assetId: assetId,
        originalName: originalName);
    final now = DateTime.now().toUtc();
    await repository.createDraft(
        draftId: draftId,
        captureSetId: setId,
        organizationId: organizationId,
        penId: penId,
        captureKind: 'video',
        businessDate: DateTime.utc(
            businessDate.year, businessDate.month, businessDate.day),
        media: CapturedMediaRecord(
            assetId: assetId,
            position: 'video',
            materializedPath: media.file.path,
            originalName: originalName,
            contentType: 'video/mp4',
            byteSize: media.byteSize,
            sha256: media.sha256,
            capturedAt: now,
            width: width,
            height: height,
            exifJson: '{}',
            roiJson: 'null'),
        now: now);
    return CreatedCaptureDraft(
        draftId: draftId,
        captureSetId: setId,
        assetId: assetId,
        materializedFile: media.file);
  }
}
