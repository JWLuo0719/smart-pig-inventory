import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'auth_session.dart';

class AuthApi {
  AuthApi({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30)));

  final Dio _dio;

  Future<AuthSession> login(
      {required String username, required String password}) async {
    final Response<dynamic> response = await _dio.post(
      '/api/v1/auth/login',
      data: <String, String>{'username': username, 'password': password},
      options: _idempotentOptions(),
    );
    return _sessionFrom(response.data as Map<String, dynamic>);
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final Response<dynamic> response = await _dio.post(
      '/api/v1/auth/refresh',
      data: <String, String>{'refreshToken': refreshToken},
      options: _idempotentOptions(),
    );
    return _sessionFrom(response.data as Map<String, dynamic>);
  }

  Future<AuthenticatedUser> currentUser(String accessToken) async {
    final Response<dynamic> response =
        await _dio.get('/api/v1/me', options: _authorizedOptions(accessToken));
    final Map<String, dynamic> body = response.data as Map<String, dynamic>;
    final String activeOrganizationId = body['activeOrganizationId'] as String;
    final List<Map<String, dynamic>> memberships =
        (body['memberships'] as List<dynamic>).cast<Map<String, dynamic>>();
    final Map<String, dynamic> activeMembership = memberships.firstWhere(
      (Map<String, dynamic> membership) =>
          membership['organizationId'] == activeOrganizationId,
    );
    return AuthenticatedUser(
      subjectId: body['subjectId'] as String,
      displayName: body['displayName'] as String,
      activeOrganizationId: activeOrganizationId,
      activeOrganizationCode: activeMembership['organizationCode'] as String,
      activeOrganizationName: activeMembership['organizationName'] as String,
      roles: (activeMembership['roles'] as List<dynamic>).cast<String>(),
      lastVerifiedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> logout(
          {required String accessToken, required String refreshToken}) =>
      _dio.post<void>(
        '/api/v1/auth/logout',
        data: <String, String>{'refreshToken': refreshToken},
        options:
            _authorizedOptions(accessToken).copyWith(headers: <String, dynamic>{
          'Authorization': 'Bearer $accessToken',
          'X-Idempotency-Key': const Uuid().v4(),
        }),
      );

  Options _idempotentOptions() => Options(
      headers: <String, String>{'X-Idempotency-Key': const Uuid().v4()});

  Options _authorizedOptions(String accessToken) => Options(
      headers: <String, String>{'Authorization': 'Bearer $accessToken'});

  AuthSession _sessionFrom(Map<String, dynamic> body) => AuthSession(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
        accessTokenExpiresAt:
            DateTime.parse(body['accessTokenExpiresAt'] as String).toUtc(),
        refreshTokenExpiresAt:
            DateTime.parse(body['refreshTokenExpiresAt'] as String).toUtc(),
      );
}
