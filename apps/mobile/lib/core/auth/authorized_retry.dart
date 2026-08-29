import 'package:dio/dio.dart';

import 'auth_session.dart';

/// Retries one idempotent or idempotency-key-protected request after a 401.
/// The caller supplies the refreshed state so this stays usable by foreground
/// review and durable Outbox work without storing tokens in either workflow.
Future<T> retryOnceAfterUnauthorized<T>({
  required AuthState initialAuth,
  required Future<AuthState?> Function() reconnect,
  required Future<T> Function(String accessToken) request,
}) async {
  try {
    return await request(initialAuth.session.accessToken);
  } on DioException catch (error) {
    if (error.response?.statusCode != 401) rethrow;
    final AuthState? refreshed = await reconnect();
    if (refreshed == null || refreshed.isOffline) rethrow;
    return request(refreshed.session.accessToken);
  }
}
