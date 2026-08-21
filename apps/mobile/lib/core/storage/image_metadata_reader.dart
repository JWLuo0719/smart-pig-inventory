import 'dart:io';
import 'dart:typed_data';

class ImageMetadata {
  const ImageMetadata({
    required this.width,
    required this.height,
    required this.contentType,
    this.exif = const <String, Object?>{},
  });

  final int width;
  final int height;
  final String contentType;
  final Map<String, Object?> exif;
}

class UnsupportedImageFormatException implements Exception {
  const UnsupportedImageFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Extracts dimensions and the JPEG orientation from a bounded header read.
/// It deliberately does not load or decode the whole photo. GPS, owner data
/// and all other EXIF fields are excluded from the capture manifest.
class ImageMetadataReader {
  static const int _maxHeaderBytes = 256 * 1024;

  Future<ImageMetadata> read(File file) async {
    final RandomAccessFile input = await file.open();
    try {
      final int byteCount = await input.length();
      if (byteCount < 4) {
        throw const UnsupportedImageFormatException('图片文件不完整或格式不受支持');
      }
      final Uint8List bytes = await input
          .read(byteCount < _maxHeaderBytes ? byteCount : _maxHeaderBytes);
      if (_isPng(bytes)) return _readPng(bytes);
      if (_isJpeg(bytes)) {
        _jpegOrientation = null;
        return _readJpeg(bytes);
      }
      throw const UnsupportedImageFormatException('仅支持 JPEG 或 PNG 图片');
    } finally {
      await input.close();
    }
  }

  bool _isPng(Uint8List bytes) =>
      bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  ImageMetadata _readPng(Uint8List bytes) {
    final ByteData data = ByteData.sublistView(bytes);
    final int width = data.getUint32(16);
    final int height = data.getUint32(20);
    if (width <= 0 || height <= 0) {
      throw const UnsupportedImageFormatException('PNG 图片尺寸无效');
    }
    return ImageMetadata(
        width: width, height: height, contentType: 'image/png');
  }

  bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8;

  ImageMetadata _readJpeg(Uint8List bytes) {
    int offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xff) {
        offset++;
        continue;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final int marker = bytes[offset++];
      if (marker == 0xd8 ||
          marker == 0xd9 ||
          marker == 0x01 ||
          (marker >= 0xd0 && marker <= 0xd7)) {
        continue;
      }
      if (offset + 1 >= bytes.length) break;
      final int segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
      if (_isStartOfFrame(marker)) {
        if (segmentLength < 8) break;
        int height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        int width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        if (width <= 0 || height <= 0) break;
        final int? orientation = _jpegOrientation;
        if (orientation != null && orientation >= 5) {
          final int originalWidth = width;
          width = height;
          height = originalWidth;
        }
        return ImageMetadata(
          width: width,
          height: height,
          contentType: 'image/jpeg',
          exif: orientation == null
              ? const <String, Object?>{}
              : <String, Object?>{'orientation': orientation},
        );
      }
      if (marker == 0xe1) {
        _jpegOrientation ??=
            _readExifOrientation(bytes, offset + 2, offset + segmentLength);
      }
      offset += segmentLength;
    }
    throw const UnsupportedImageFormatException('无法读取 JPEG 图片尺寸');
  }

  int? _jpegOrientation;

  int? _readExifOrientation(Uint8List bytes, int start, int end) {
    if (start + 14 > end ||
        bytes[start] != 0x45 ||
        bytes[start + 1] != 0x78 ||
        bytes[start + 2] != 0x69 ||
        bytes[start + 3] != 0x66 ||
        bytes[start + 4] != 0 ||
        bytes[start + 5] != 0) {
      return null;
    }
    final int tiff = start + 6;
    final bool littleEndian = bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
    final bool bigEndian = bytes[tiff] == 0x4d && bytes[tiff + 1] == 0x4d;
    if (!littleEndian && !bigEndian) return null;
    if (_u16(bytes, tiff + 2, littleEndian) != 42) return null;
    final int ifd = tiff + _u32(bytes, tiff + 4, littleEndian);
    if (ifd + 2 > end) return null;
    final int entryCount = _u16(bytes, ifd, littleEndian);
    for (int index = 0; index < entryCount; index++) {
      final int entry = ifd + 2 + index * 12;
      if (entry + 12 > end) return null;
      if (_u16(bytes, entry, littleEndian) != 0x0112 ||
          _u16(bytes, entry + 2, littleEndian) != 3 ||
          _u32(bytes, entry + 4, littleEndian) < 1) {
        continue;
      }
      final int orientation = _u16(bytes, entry + 8, littleEndian);
      return orientation >= 1 && orientation <= 8 ? orientation : null;
    }
    return null;
  }

  int _u16(Uint8List bytes, int offset, bool littleEndian) => littleEndian
      ? bytes[offset] | (bytes[offset + 1] << 8)
      : (bytes[offset] << 8) | bytes[offset + 1];

  int _u32(Uint8List bytes, int offset, bool littleEndian) => littleEndian
      ? bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24)
      : (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];

  bool _isStartOfFrame(int marker) =>
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf);
}
