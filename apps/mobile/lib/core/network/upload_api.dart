import 'dart:io';

import 'package:dio/dio.dart';

abstract interface class UploadRemoteGateway {
  Future<RemoteUploadPackage> createPackage({
    required String accessToken,
    required String idempotencyKey,
    required String clientPackageId,
    required String organizationId,
    required String penId,
    required DateTime businessDate,
    required String captureKind,
  });
  Future<RemoteUploadPackage> package(
      {required String accessToken, required String serverPackageId});
  Future<void> putBlob({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
    required String assetId,
    required String sha256,
    required File file,
  });
  Future<void> putManifest({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
    required Map<String, dynamic> manifest,
  });
  Future<RemoteCommitResult> commit({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
  });
}

class UploadRemoteApi implements UploadRemoteGateway {
  UploadRemoteApi({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(minutes: 2),
            ));

  final Dio _dio;

  @override
  Future<RemoteUploadPackage> createPackage({
    required String accessToken,
    required String idempotencyKey,
    required String clientPackageId,
    required String organizationId,
    required String penId,
    required DateTime businessDate,
    required String captureKind,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '/api/v1/upload-packages',
      data: <String, Object>{
        'clientPackageId': clientPackageId,
        'organizationId': organizationId,
        'penId': penId,
        'businessDate': businessDate.toIso8601String().substring(0, 10),
        'captureKind': captureKind,
      },
      options: _options(accessToken, idempotencyKey),
    );
    return RemoteUploadPackage.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<RemoteUploadPackage> package({
    required String accessToken,
    required String serverPackageId,
  }) async {
    final Response<dynamic> response = await _dio.get(
      '/api/v1/upload-packages/$serverPackageId',
      options: _options(accessToken),
    );
    return RemoteUploadPackage.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> putBlob({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
    required String assetId,
    required String sha256,
    required File file,
  }) async {
    final int length = await file.length();
    await _dio.put<void>(
      '/api/v1/upload-packages/$serverPackageId/blobs/$assetId',
      data: file.openRead(),
      options: _options(accessToken, idempotencyKey).copyWith(
        headers: <String, Object>{
          'Authorization': 'Bearer $accessToken',
          'X-Idempotency-Key': idempotencyKey,
          Headers.contentTypeHeader: 'application/octet-stream',
          Headers.contentLengthHeader: length,
          'X-Content-SHA256': sha256,
        },
      ),
    );
  }

  @override
  Future<void> putManifest({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
    required Map<String, dynamic> manifest,
  }) =>
      _dio.put<void>(
        '/api/v1/upload-packages/$serverPackageId/manifest',
        data: manifest,
        options: _options(accessToken, idempotencyKey),
      );

  @override
  Future<RemoteCommitResult> commit({
    required String accessToken,
    required String idempotencyKey,
    required String serverPackageId,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '/api/v1/upload-packages/$serverPackageId/commit',
      options: _options(accessToken, idempotencyKey),
    );
    return RemoteCommitResult.fromJson(response.data as Map<String, dynamic>);
  }

  Options _options(String accessToken, [String? idempotencyKey]) => Options(
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
          if (idempotencyKey != null) 'X-Idempotency-Key': idempotencyKey,
        },
      );
}

class RemoteUploadPackage {
  const RemoteUploadPackage({
    required this.id,
    required this.state,
    required this.existingAssets,
  });

  final String id;
  final String state;
  final Set<String> existingAssets;

  factory RemoteUploadPackage.fromJson(Map<String, dynamic> body) =>
      RemoteUploadPackage(
        id: body['id'] as String,
        state: body['state'] as String,
        existingAssets:
            (body['existingAssets'] as List<dynamic>).cast<String>().toSet(),
      );
}

class RemoteCommitResult {
  const RemoteCommitResult({
    required this.sessionId,
    required this.inferenceJobId,
  });

  final String sessionId;
  final String inferenceJobId;

  factory RemoteCommitResult.fromJson(Map<String, dynamic> body) =>
      RemoteCommitResult(
        sessionId: body['sessionId'] as String,
        inferenceJobId: body['inferenceJobId'] as String,
      );
}
