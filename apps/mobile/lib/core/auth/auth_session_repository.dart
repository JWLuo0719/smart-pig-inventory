import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

abstract interface class AuthSessionRepository {
  Future<AuthSession?> read();
  Future<void> save(AuthSession session);
  Future<void> clear();
}

class SecureAuthSessionRepository implements AuthSessionRepository {
  SecureAuthSessionRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _accessToken = 'auth.access-token';
  static const String _refreshToken = 'auth.refresh-token';
  static const String _accessExpiry = 'auth.access-expiry';
  static const String _refreshExpiry = 'auth.refresh-expiry';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final Map<String, String> values = await _storage.readAll();
    final String? accessToken = values[_accessToken];
    final String? refreshToken = values[_refreshToken];
    final String? accessExpiry = values[_accessExpiry];
    final String? refreshExpiry = values[_refreshExpiry];
    if (accessToken == null ||
        refreshToken == null ||
        accessExpiry == null ||
        refreshExpiry == null) {
      return null;
    }
    try {
      return AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: DateTime.parse(accessExpiry).toUtc(),
        refreshTokenExpiresAt: DateTime.parse(refreshExpiry).toUtc(),
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) async {
    await Future.wait(<Future<void>>[
      _storage.write(key: _accessToken, value: session.accessToken),
      _storage.write(key: _refreshToken, value: session.refreshToken),
      _storage.write(
          key: _accessExpiry,
          value: session.accessTokenExpiresAt.toUtc().toIso8601String()),
      _storage.write(
          key: _refreshExpiry,
          value: session.refreshTokenExpiresAt.toUtc().toIso8601String()),
    ]);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}
