import 'dart:io';

import 'package:dio/dio.dart';

import '../models/capture_package.dart';

class UploadApi {
  UploadApi({required String baseUrl, required String accessToken})
      : _dio = Dio(BaseOptions(
            baseUrl: baseUrl,
            headers: <String, String>{'Authorization': 'Bearer $accessToken'}));

  final Dio _dio;

  Future<void> upload(CapturePackageDraft draft) async {
    final Map<String, Object?> manifest = await draft.toManifest();
    final List<Map<String, Object?>> media =
        List<Map<String, Object?>>.from(manifest['assets']! as List<Object?>);
    final Options idempotent = Options(
        headers: <String, String>{'X-Idempotency-Key': draft.idempotencyKey});
    final Response<dynamic> package = await _dio.post(
      '/api/v1/upload-packages',
      data: draft.createPackageRequest(),
      options: idempotent,
    );
    final String serverPackageId = package.data['id'] as String;
    final Set<String> uploaded = <String>{
      for (final Object? item
          in package.data['existingAssets'] as List<Object?>)
        item as String,
    };
    for (int index = 0; index < media.length; index++) {
      final Map<String, Object?> item = media[index];
      if (uploaded.contains(item['assetId'])) continue;
      final File file = draft.media[index].file;
      await _dio.put(
        '/api/v1/upload-packages/$serverPackageId/blobs/${item['assetId']}',
        data: await file.readAsBytes(),
        options: Options(headers: <String, String>{
          'Content-Type': 'application/octet-stream',
          'X-Idempotency-Key': draft.idempotencyKey,
          'X-Content-SHA256': item['sha256']! as String,
        }),
      );
    }
    await _dio.put('/api/v1/upload-packages/$serverPackageId/manifest',
        data: manifest, options: idempotent);
    await _dio.post('/api/v1/upload-packages/$serverPackageId/commit',
        options: idempotent);
  }
}
