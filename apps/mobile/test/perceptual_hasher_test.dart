import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/media/perceptual_hasher.dart';

void main() {
  late Directory sandbox;

  setUp(() async => sandbox =
      await Directory.systemTemp.createTemp('perceptual-hasher-test'));
  tearDown(() async => sandbox.delete(recursive: true));

  test('produces a normalized 64-bit perceptual hash for a decodable image',
      () async {
    final image.Image pixels = image.Image(width: 64, height: 64);
    for (int y = 0; y < pixels.height; y++) {
      for (int x = 0; x < pixels.width; x++) {
        pixels.setPixelRgb(x, y, x * 4, y * 4, (x + y) * 2);
      }
    }
    final File file = File(path.join(sandbox.path, 'capture.png'))
      ..writeAsBytesSync(image.encodePng(pixels));

    final String? result = await PerceptualHasher().hash(file);

    expect(result, matches(RegExp(r'^[a-f0-9]{16}$')));
    expect(await PerceptualHasher().hash(file), result);
  });

  test('keeps all 64 set bits unsigned in a uniform image', () async {
    final image.Image pixels = image.Image(width: 9, height: 8);
    final File file = File(path.join(sandbox.path, 'uniform.png'))
      ..writeAsBytesSync(image.encodePng(pixels));
    expect(await PerceptualHasher().hash(file), 'ffffffffffffffff');
  });

  test('does not treat undecodable bytes as a perceptual hash', () async {
    final File file = File(path.join(sandbox.path, 'invalid.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    expect(await PerceptualHasher().hash(file), isNull);
  });

  test('repairs only legacy signed 64-bit encodings', () {
    expect(PerceptualHasher.normalizeLegacyHash('00000000000000-1'),
        'ffffffffffffffff');
    expect(PerceptualHasher.normalizeLegacyHash('-8000000000000000'),
        '8000000000000000');
    for (final value in [
      '0123456789abcdef',
      'ffffffffffffffff',
      '-8000000000000001',
      'invalid',
      '-0'
    ]) {
      expect(PerceptualHasher.normalizeLegacyHash(value), value);
    }
  });
}
