import 'dart:io';

import 'package:flutter/services.dart';

import 'image_metadata_reader.dart';

/// Uses Android's bounds-only decoder and EXIF reader for formats such as HEIC.
/// Non-Android targets retain the bounded JPEG/PNG parser until their native
/// metadata adapter is implemented.
class PlatformImageMetadataReader {
  PlatformImageMetadataReader({ImageMetadataReader? fallback})
      : _fallback = fallback ?? ImageMetadataReader();

  static const MethodChannel _channel =
      MethodChannel('com.smartfarm.inventory/image-metadata');

  final ImageMetadataReader _fallback;

  Future<ImageMetadata> read(File file) async {
    if (!Platform.isAndroid) return _fallback.read(file);
    try {
      final Map<Object?, Object?>? response =
          await _channel.invokeMapMethod<Object?, Object?>(
        'read',
        <String, Object?>{'path': file.path},
      );
      if (response == null) {
        throw const UnsupportedImageFormatException('无法读取图片元数据');
      }
      final Object? width = response['width'];
      final Object? height = response['height'];
      final Object? contentType = response['contentType'];
      if (width is! int ||
          height is! int ||
          width <= 0 ||
          height <= 0 ||
          contentType is! String) {
        throw const UnsupportedImageFormatException('图片尺寸或格式无效');
      }
      final Object? orientation = response['orientation'];
      return ImageMetadata(
        width: width,
        height: height,
        contentType: contentType,
        exif: orientation is int
            ? <String, Object?>{'orientation': orientation}
            : const <String, Object?>{},
      );
    } on MissingPluginException {
      return _fallback.read(file);
    } on PlatformException catch (error) {
      throw UnsupportedImageFormatException(error.message ?? '无法读取图片元数据');
    }
  }
}
