import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/image_metadata_reader.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('image-metadata-test');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('reads PNG dimensions from the bounded header', () async {
    final File file = File(path.join(sandbox.path, 'pen.png'))
      ..writeAsBytesSync(<int>[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x07, 0x80, // 1920
        0x00, 0x00, 0x04, 0x38, // 1080
      ]);

    final ImageMetadata metadata = await ImageMetadataReader().read(file);

    expect(metadata.contentType, 'image/png');
    expect(metadata.width, 1920);
    expect(metadata.height, 1080);
  });

  test('reads JPEG dimensions from a start-of-frame segment', () async {
    final File file = File(path.join(sandbox.path, 'pen.jpg'))
      ..writeAsBytesSync(<int>[
        0xff, 0xd8, // SOI
        0xff, 0xc0, // SOF0
        0x00, 0x11, // segment length
        0x08, // precision
        0x04, 0x38, // height 1080
        0x07, 0x80, // width 1920
        0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
      ]);

    final ImageMetadata metadata = await ImageMetadataReader().read(file);

    expect(metadata.contentType, 'image/jpeg');
    expect(metadata.width, 1920);
    expect(metadata.height, 1080);
  });

  test('uses JPEG EXIF orientation for corrected dimensions', () async {
    final File file = File(path.join(sandbox.path, 'rotated.jpg'))
      ..writeAsBytesSync(<int>[
        0xff, 0xd8, // SOI
        0xff, 0xe1, // APP1
        0x00, 0x1e, // length: 30 bytes including this field
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif identifier
        0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF / IFD offset
        0x01, 0x00, // one IFD entry
        0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x06, 0x00, 0x00, 0x00, // orientation 6
        0xff, 0xc0, 0x00, 0x11, 0x08,
        0x04, 0x38, // source height 1080
        0x07, 0x80, // source width 1920
        0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
      ]);

    final ImageMetadata metadata = await ImageMetadataReader().read(file);

    expect(metadata.width, 1080);
    expect(metadata.height, 1920);
    expect(metadata.exif, <String, Object?>{'orientation': 6});
  });

  test('rejects unsupported image signatures', () async {
    final File file = File(path.join(sandbox.path, 'pen.heic'))
      ..writeAsBytesSync(Uint8List(24));

    expect(
      () => ImageMetadataReader().read(file),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
  });
}
