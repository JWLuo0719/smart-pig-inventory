import 'package:smart_pig_inventory/core/network/device_network_status.dart';
import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_api.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/auth/auth_session_repository.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';

AuthSession _session(String id) => AuthSession(
    accessToken: id,
    refreshToken: '$id-refresh',
    accessTokenExpiresAt: DateTime(2030),
    refreshTokenExpiresAt: DateTime(2030));
AuthenticatedUser _user(String id) => AuthenticatedUser(
    subjectId: id,
    displayName: id,
    activeOrganizationId: '$id-org',
    activeOrganizationCode: 'SYN',
    activeOrganizationName: 'Synthetic',
    roles: const ['REVIEWER'],
    lastVerifiedAt: DateTime.now());

class _Sessions implements AuthSessionRepository {
  AuthSession? value = _session('old');
  @override
  Future<AuthSession?> read() async => value;
  @override
  Future<void> save(AuthSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Api extends AuthApi {
  _Api() : super(baseUrl: 'https://synthetic.invalid');
  Completer<AuthenticatedUser>? oldVerification;
  @override
  Future<AuthenticatedUser> currentUser(String accessToken) async =>
      accessToken == 'old' && oldVerification != null
          ? oldVerification!.future
          : _user(accessToken);
  @override
  Future<AuthSession> login(
          {required String username, required String password}) async =>
      _session(username);
}

void main() {
  test(
      'late reconnect cannot replace a newly logged-in organization or persisted credentials',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final sessions = _Sessions();
    final api = _Api();
    final container = ProviderContainer(overrides: [
      deviceNetworkStatusProvider.overrideWithValue(() async => null),
      appDatabaseProvider.overrideWithValue(db),
      authSessionRepositoryProvider.overrideWithValue(sessions),
      authApiProvider.overrideWithValue(api)
    ]);
    await container.read(authControllerProvider.future);
    api.oldVerification = Completer<AuthenticatedUser>();
    final controller = container.read(authControllerProvider.notifier);
    final oldReconnect = controller.reconnect();
    await Future<void>.delayed(Duration.zero);
    await controller.login(username: 'new', password: 'synthetic');
    api.oldVerification!.complete(_user('old'));
    expect(await oldReconnect, isNull);
    expect(
        container
            .read(authControllerProvider)
            .valueOrNull!
            .user
            .activeOrganizationId,
        'new-org');
    expect(sessions.value!.accessToken, 'new');
    final cached =
        await container.read(authContextRepositoryProvider).readLatest();
    expect(cached!.subjectId, 'new');
    container.dispose();
    await db.close();
  });
}
