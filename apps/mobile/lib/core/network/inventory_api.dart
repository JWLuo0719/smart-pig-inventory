import 'package:dio/dio.dart';

abstract interface class InventoryRemoteGateway {
  Future<List<RemoteInventoryTask>> tasks({
    required String accessToken,
    required DateTime businessDate,
  });

  Future<RemoteInventorySession> session({
    required String accessToken,
    required String sessionId,
  });

  Future<RemoteInventorySession> confirm({
    required String accessToken,
    required String sessionId,
    required String idempotencyKey,
    required int confirmedCount,
    String? reason,
  });
}

class InventoryRemoteApi implements InventoryRemoteGateway {
  InventoryRemoteApi({required String baseUrl, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;

  Options _options(String token, [String? idempotencyKey]) => Options(
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          if (idempotencyKey != null) 'X-Idempotency-Key': idempotencyKey,
        },
      );

  @override
  Future<List<RemoteInventoryTask>> tasks({
    required String accessToken,
    required DateTime businessDate,
  }) async {
    final Response<dynamic> response = await _dio.get(
      '/api/v1/inventory-tasks',
      queryParameters: <String, String>{
        'businessDate': businessDate.toIso8601String().substring(0, 10),
      },
      options: _options(accessToken),
    );
    return (response.data as List<dynamic>)
        .map((dynamic value) =>
            RemoteInventoryTask.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<RemoteInventorySession> session({
    required String accessToken,
    required String sessionId,
  }) async {
    final Response<dynamic> response = await _dio.get(
      '/api/v1/inventory-sessions/$sessionId',
      options: _options(accessToken),
    );
    return RemoteInventorySession.fromJson(
        response.data as Map<String, dynamic>);
  }

  @override
  Future<RemoteInventorySession> confirm({
    required String accessToken,
    required String sessionId,
    required String idempotencyKey,
    required int confirmedCount,
    String? reason,
  }) async {
    final Response<dynamic> response = await _dio.post(
      '/api/v1/inventory-sessions/$sessionId/confirm',
      data: <String, Object?>{
        'confirmedCount': confirmedCount,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      options: _options(accessToken, idempotencyKey),
    );
    return RemoteInventorySession.fromJson(
        response.data as Map<String, dynamic>);
  }
}

class RemoteInventoryTask {
  const RemoteInventoryTask({
    required this.penId,
    required this.buildingCode,
    required this.buildingName,
    required this.penCode,
    required this.penName,
    required this.businessDate,
    required this.sessionId,
    required this.status,
    required this.confirmedCount,
  });

  final String penId;
  final String buildingCode;
  final String buildingName;
  final String penCode;
  final String penName;
  final String businessDate;
  final String? sessionId;
  final String status;
  final int? confirmedCount;

  factory RemoteInventoryTask.fromJson(Map<String, dynamic> body) =>
      RemoteInventoryTask(
        penId: body['penId'] as String,
        buildingCode: body['buildingCode'] as String,
        buildingName: body['buildingName'] as String,
        penCode: body['penCode'] as String,
        penName: body['penName'] as String,
        businessDate: body['businessDate'] as String,
        sessionId: body['sessionId'] as String?,
        status: body['status'] as String,
        confirmedCount: body['confirmedCount'] as int?,
      );
}

class RemoteInventorySession {
  const RemoteInventorySession({
    required this.id,
    required this.penId,
    required this.businessDate,
    required this.status,
    required this.count,
    required this.rawModelCount,
    required this.inferenceSource,
    required this.warnings,
  });

  final String id;
  final String penId;
  final String businessDate;
  final String status;
  final int? count;
  final int? rawModelCount;
  final String? inferenceSource;
  final List<String> warnings;

  bool get requiresReview => status == 'review_required';
  bool get confirmed => status == 'confirmed';

  factory RemoteInventorySession.fromJson(Map<String, dynamic> body) =>
      RemoteInventorySession(
        id: body['id'] as String,
        penId: body['penId'] as String,
        businessDate: body['businessDate'] as String,
        status: body['status'] as String,
        count: body['count'] as int?,
        rawModelCount: body['rawModelCount'] as int?,
        inferenceSource: body['inferenceSource'] as String?,
        warnings: (body['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .cast<String>(),
      );
}
