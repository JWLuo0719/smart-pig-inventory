import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

enum CaptureKind { single, leftCenterRight }

enum ViewPosition { single, left, center, right }

extension CaptureKindWire on CaptureKind {
  String get wireName => switch (this) {
        CaptureKind.single => 'single',
        CaptureKind.leftCenterRight => 'left_center_right',
      };
}

extension ViewPositionWire on ViewPosition {
  String get wireName => name;
}

class LocalMediaDraft {
  LocalMediaDraft({
    required this.file,
    required this.position,
    required this.contentType,
    required this.capturedAt,
    required this.width,
    required this.height,
    this.exif = const <String, Object?>{},
    this.roi,
    String? originalName,
    String? assetId,
  })  : originalName = originalName ?? path.basename(file.path),
        assetId = assetId ?? Uuid().v4();

  final String assetId;
  final File file;
  final ViewPosition position;
  final String contentType;
  final DateTime capturedAt;
  final String originalName;
  final int width;
  final int height;
  final Map<String, Object?> exif;
  final Map<String, Object?>? roi;

  Future<Map<String, Object?>> toManifestEntry() async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    final int byteSize = await file.length();
    return <String, Object?>{
      'asset_id': assetId,
      'view_position': position.wireName,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'original_name': originalName,
      'width': width,
      'height': height,
      'sha256': digest.toString(),
      'byte_size': byteSize,
      'media_type': contentType,
      'exif': exif,
      'roi': roi,
      // pHash is advisory and can be added by a future local plugin; SHA-256 is mandatory.
    };
  }
}

class CapturePackageDraft {
  CapturePackageDraft({
    required this.organizationId,
    required this.penId,
    required this.businessDate,
    required this.kind,
    required this.media,
    String? clientPackageId,
  })  : clientPackageId = clientPackageId ?? Uuid().v4(),
        idempotencyKey = Uuid().v4(),
        captureSetId = Uuid().v4();

  final String clientPackageId;
  final String idempotencyKey;
  final String captureSetId;
  final String organizationId;
  final String penId;
  final DateTime businessDate;
  final CaptureKind kind;
  final List<LocalMediaDraft> media;

  Future<Map<String, Object?>> toManifest() async {
    final List<Map<String, Object?>> entries = await Future.wait(
        media.map((LocalMediaDraft item) => item.toManifestEntry()));
    return <String, Object?>{
      'captureSetId': captureSetId,
      'captureKind': kind.wireName,
      'penId': penId,
      'assets': entries
          .map((Map<String, Object?> entry) => <String, Object?>{
                'assetId': entry['asset_id'],
                'viewPosition': entry['view_position'],
                'capturedAt': entry['captured_at'],
                'originalName': entry['original_name'],
                'width': entry['width'],
                'height': entry['height'],
                'sha256': entry['sha256'],
                'byteSize': entry['byte_size'],
                'mediaType': entry['media_type'],
                'exif': entry['exif'],
                'roi': entry['roi'],
              })
          .toList(),
    };
  }

  Map<String, Object?> createPackageRequest() => <String, Object?>{
        'clientPackageId': clientPackageId,
        'organizationId': organizationId,
        'penId': penId,
        'businessDate': businessDate.toIso8601String().substring(0, 10),
        'captureKind': kind.wireName,
      };

  Future<String> manifestJson() async => jsonEncode(await toManifest());
}
