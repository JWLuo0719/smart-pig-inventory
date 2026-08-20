import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    this.roi = const <String, Object?>{},
    String? assetId,
  }) : assetId = assetId ?? Uuid().v4();

  final String assetId;
  final File file;
  final ViewPosition position;
  final String contentType;
  final Map<String, Object?> roi;

  Future<Map<String, Object?>> toManifestEntry() async {
    final List<int> bytes = await file.readAsBytes();
    return <String, Object?>{
      'asset_id': assetId,
      'view_position': position.wireName,
      'sha256': sha256.convert(bytes).toString(),
      'byte_size': bytes.length,
      'media_type': contentType,
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
                'sha256': entry['sha256'],
                'byteSize': entry['byte_size'],
                'mediaType': entry['media_type'],
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
