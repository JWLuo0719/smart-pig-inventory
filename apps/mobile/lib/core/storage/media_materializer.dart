import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class MaterializedMedia {
  const MaterializedMedia({
    required this.file,
    required this.byteSize,
    required this.sha256,
    required this.originalName,
  });

  final File file;
  final int byteSize;
  final String sha256;
  final String originalName;
}

/// Copies picker-owned media into application storage while calculating its
/// digest from the same stream. A business draft must only reference the file
/// returned by this service, never the picker URI.
class MediaMaterializer {
  MediaMaterializer(this.rootDirectory);

  final Directory rootDirectory;

  Future<MaterializedMedia> materialize({
    required File source,
    required String organizationId,
    required String draftId,
    required String assetId,
    required String originalName,
  }) async {
    _validatePathSegment(organizationId, 'organizationId');
    _validatePathSegment(draftId, 'draftId');
    _validatePathSegment(assetId, 'assetId');

    final String extension = _supportedExtension(originalName);
    final Directory destinationDirectory = Directory(path.join(
      rootDirectory.path,
      'media',
      organizationId,
      draftId,
    ));
    await destinationDirectory.create(recursive: true);

    final File destination =
        File(path.join(destinationDirectory.path, '$assetId$extension'));
    if (path.equals(source.absolute.path, destination.absolute.path)) {
      throw const FileSystemException(
          'Source media is already the materialized destination');
    }

    // A stable asset UUID makes process-restart recovery idempotent. The
    // database owns the original digest, while this branch safely recovers a
    // file renamed just before a process termination.
    if (await destination.exists()) {
      final _FileDigest existing = await _digest(destination);
      return MaterializedMedia(
        file: destination,
        byteSize: existing.byteSize,
        sha256: existing.sha256,
        originalName: originalName,
      );
    }
    if (!await source.exists()) {
      throw const FileSystemException('Source media does not exist');
    }

    final File partial = File('${destination.path}.partial');
    if (await partial.exists()) await partial.delete();

    final IOSink output = partial.openWrite(mode: FileMode.writeOnly);
    final _DigestSink digestSink = _DigestSink();
    final ByteConversionSink hasher = sha256.startChunkedConversion(digestSink);
    int byteSize = 0;
    bool hasherClosed = false;
    bool outputClosed = false;

    try {
      await for (final List<int> chunk in source.openRead()) {
        byteSize += chunk.length;
        hasher.add(chunk);
        output.add(chunk);
      }
      hasher.close();
      hasherClosed = true;
      await output.flush();
      await output.close();
      outputClosed = true;

      if (byteSize == 0) {
        throw const FileSystemException('Source media is empty');
      }
      final Digest? digest = digestSink.value;
      if (digest == null) {
        throw const FileSystemException('Unable to calculate media digest');
      }

      await partial.rename(destination.path);
      return MaterializedMedia(
        file: destination,
        byteSize: byteSize,
        sha256: digest.toString(),
        originalName: originalName,
      );
    } catch (_) {
      if (!hasherClosed) hasher.close();
      if (!outputClosed) {
        try {
          await output.close();
        } catch (_) {
          // Preserve the original exception; the partial file is removed below.
        }
      }
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<_FileDigest> _digest(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return _FileDigest(await file.length(), digest.toString());
  }

  void _validatePathSegment(String value, String field) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, field, 'Invalid storage path segment');
    }
  }

  String _supportedExtension(String originalName) {
    final String extension = path.extension(originalName).toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' || '.png' || '.heic' => extension,
      _ => throw ArgumentError.value(
          originalName, 'originalName', 'Unsupported image extension'),
    };
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _FileDigest {
  const _FileDigest(this.byteSize, this.sha256);

  final int byteSize;
  final String sha256;
}
