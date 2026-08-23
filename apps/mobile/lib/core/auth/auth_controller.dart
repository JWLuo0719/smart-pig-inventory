import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database_provider.dart';
import 'auth_api.dart';
import 'auth_context_repository.dart';
import 'auth_session.dart';
import 'auth_session_repository.dart';

final apiBaseUrlProvider =
    Provider<String>((ref) => const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:8088',
        ));

final authSessionRepositoryProvider =
    Provider<AuthSessionRepository>((ref) => SecureAuthSessionRepository());
final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(baseUrl: ref.watch(apiBaseUrlProvider)));
final authContextRepositoryProvider = Provider<AuthContextRepository>(
  (ref) => AuthContextRepository(ref.watch(appDatabaseProvider)),
);
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState?> {
  static const Duration _offlineSessionLimit = Duration(days: 7);

  AuthSessionRepository get _sessions =>
      ref.read(authSessionRepositoryProvider);
  AuthContextRepository get _contexts =>
      ref.read(authContextRepositoryProvider);
  AuthApi get _api => ref.read(authApiProvider);

  @override
  Future<AuthState?> build() => _restore();

  Future<void> login(
      {required String username, required String password}) async {
    state = const AsyncLoading<AuthState?>();
    state = await AsyncValue.guard(() async {
      final AuthSession session =
          await _api.login(username: username, password: password);
      try {
        final AuthenticatedUser user =
            await _api.currentUser(session.accessToken);
        await _sessions.save(session);
        await _contexts.save(user);
        return AuthState(session: session, user: user, isOffline: false);
      } catch (_) {
        await _sessions.clear();
        rethrow;
      }
    });
  }

  Future<void> logout() async {
    final AuthState? current = state.valueOrNull;
    try {
      if (current != null && !current.isOffline) {
        await _api.logout(
            accessToken: current.session.accessToken,
            refreshToken: current.session.refreshToken);
      }
    } finally {
      await _sessions.clear();
      await _contexts.clear();
      state = const AsyncData<AuthState?>(null);
    }
  }

  Future<AuthState?> _restore() async {
    final AuthSession? session = await _sessions.read();
    if (session == null) return null;
    try {
      return await _verify(session);
    } on DioException catch (error) {
      if (_isUnauthorized(error)) {
        try {
          final AuthSession refreshed =
              await _api.refresh(session.refreshToken);
          final AuthenticatedUser user =
              await _api.currentUser(refreshed.accessToken);
          await _sessions.save(refreshed);
          await _contexts.save(user);
          return AuthState(session: refreshed, user: user, isOffline: false);
        } on DioException catch (refreshError) {
          if (_isNetworkFailure(refreshError)) return _offlineFallback(session);
          await _clearLocalSession();
          return null;
        }
      }
      if (_isNetworkFailure(error)) return _offlineFallback(session);
      rethrow;
    }
  }

  Future<AuthState?> _verify(AuthSession session) async {
    final AuthenticatedUser user = await _api.currentUser(session.accessToken);
    await _contexts.save(user);
    return AuthState(session: session, user: user, isOffline: false);
  }

  Future<AuthState?> _offlineFallback(AuthSession session) async {
    final AuthenticatedUser? user = await _contexts.readLatest();
    if (user == null ||
        DateTime.now().toUtc().difference(user.lastVerifiedAt) >
            _offlineSessionLimit) {
      return null;
    }
    return AuthState(session: session, user: user, isOffline: true);
  }

  Future<void> _clearLocalSession() async {
    await _sessions.clear();
    await _contexts.clear();
  }

  bool _isUnauthorized(DioException error) => error.response?.statusCode == 401;

  bool _isNetworkFailure(DioException error) => switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          true,
        _ => false,
      };
}
