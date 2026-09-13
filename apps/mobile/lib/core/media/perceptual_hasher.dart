import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Calculates a deterministic 64-bit difference hash from a small grayscale
/// thumbnail. The work is isolated from the UI and intentionally degrades to
/// null for unsupported/corrupt media: SHA-256 upload integrity remains valid,
/// while the server simply cannot create a perceptual warning for that asset.
class PerceptualHasher {
  /// Repairs only the signed hexadecimal encoding emitted by older native
  /// clients. Such values could never pass the server manifest validation.
  static String normalizeLegacyHash(String value) {
    if (!RegExp(r'^0*-[0-9a-f]{1,16}$').hasMatch(value)) return value;
    final BigInt signed =
        BigInt.parse(value.substring(value.indexOf('-')), radix: 16);
    if (signed >= BigInt.zero || signed < -(BigInt.one << 63)) return value;
    return signed.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  // A decoded image uses four bytes per pixel. These limits keep the isolated
  // thumbnail operation below the 40 MB 10 MB-upload memory budget; larger
  // media still uploads normally but does not receive a local dHash.
  static const int _maximumInputBytes = 8 * 1024 * 1024;
  static const int _maximumPixels = 6 * 1000 * 1000;

  Future<String?> hash(File file) async {
    if (!await file.exists() || await file.length() > _maximumInputBytes) {
      return null;
    }
    final Uint8List bytes = await file.readAsBytes();
    return Isolate.run<String?>(() => _fromBytes(bytes));
  }

  static String? _fromBytes(Uint8List bytes) {
    try {
      final image.Decoder? decoder = image.findDecoderForData(bytes);
      final image.DecodeInfo? info = decoder?.startDecode(bytes);
      if (info == null || info.width * info.height > _maximumPixels) {
        return null;
      }
      final image.Image? decoded = decoder!.decodeFrame(0);
      if (decoded == null) {
        return null;
      }
      // A 9x8 image yields 8 adjacent horizontal comparisons per row.
      final image.Image thumbnail =
          image.copyResize(decoded, width: 9, height: 8);
      BigInt bits = BigInt.zero;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final image.Pixel left = thumbnail.getPixel(x, y);
          final image.Pixel right = thumbnail.getPixel(x + 1, y);
          final double leftLuma =
              0.299 * left.r + 0.587 * left.g + 0.114 * left.b;
          final double rightLuma =
              0.299 * right.r + 0.587 * right.g + 0.114 * right.b;
          bits =
              (bits << 1) | (leftLuma >= rightLuma ? BigInt.one : BigInt.zero);
        }
      }
      return bits.toUnsigned(64).toRadixString(16).padLeft(16, '0');
    } on Object {
      return null;
    }
  }
}
