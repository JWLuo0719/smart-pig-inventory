import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_api.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/auth/auth_session_repository.dart';
import 'package:smart_pig_inventory/core/network/device_network_status.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';

class _Api extends AuthApi {
  _Api() : super(baseUrl: 'https://synthetic.invalid');
  Object? failure;
  int verifications = 0;
  DateTime verifiedAt = DateTime.now().toUtc();
  @override
  Future<AuthSession> login(
          {required String username, required String password}) async =>
      AuthSession(
        accessToken: 'synthetic-access',
        refreshToken: 'synthetic-refresh',
        accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
        refreshTokenExpiresAt: DateTime.now().add(const Duration(days: 14)),
      );
  @override
  Future<AuthenticatedUser> currentUser(String accessToken) async {
    verifications++;
    if (failure != null) throw failure!;
    return AuthenticatedUser(
        subjectId: 'synthetic-user',
        displayName: 'Synthetic',
        activeOrganizationId: 'synthetic-org',
        activeOrganizationCode: 'SYN',
        activeOrganizationName: 'Synthetic',
        roles: const ['OPERATOR'],
        lastVerifiedAt: verifiedAt);
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async => throw failure!;
}

DioException _failure(DioExceptionType type, {Object? error, int? status}) {
  final options = RequestOptions(path: '/api/v1/me');
  return DioException(
      requestOptions: options,
      type: type,
      error: error,
      response: status == null
          ? null
          : Response<void>(requestOptions: options, statusCode: status));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Android reports no network: cold start restores bounded cache without HTTPS',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.login();
    final verifications = fixture.api.verifications;
    fixture.deviceNetwork = false;
    fixture.api.failure = _failure(DioExceptionType.unknown,
        error: const HandshakeException('unreachable network'));
    await fixture.restart();
    expect(
        (await fixture.container.read(authControllerProvider.future))
            ?.isOffline,
        isTrue);
    expect(fixture.api.verifications, verifications);
  });
  test('known offline does not admit an expired cache or a new installation',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    fixture.deviceNetwork = false;
    expect(await fixture.container.read(authControllerProvider.future), isNull);
    fixture.api.verifiedAt = DateTime.now().subtract(const Duration(days: 8));
    await fixture.login();
    final verifications = fixture.api.verifications;
    await fixture.restart();
    expect(await fixture.container.read(authControllerProvider.future), isNull);
    expect(fixture.api.verifications, verifications);
  });
  for (final scenario in <String, DioException>{
    'connection loss': _failure(DioExceptionType.connectionError),
    'socket loss after connection': _failure(DioExceptionType.unknown,
        error: const SocketException('Network is unreachable')),
    'send timeout': _failure(DioExceptionType.sendTimeout),
    'receive timeout': _failure(DioExceptionType.receiveTimeout),
  }.entries) {
    test('login, cold start with ${scenario.key}, preserve drafts, reconnect',
        () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.login();
      await fixture.database.into(fixture.database.captureDrafts).insert(
          CaptureDraftsCompanion.insert(
              id: 'synthetic-draft',
              organizationId: 'synthetic-org',
              penId: 'synthetic-pen',
              captureKind: 'single',
              state: const Value('queued'),
              businessDate: DateTime.now(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now()));
      await fixture.database.into(fixture.database.outboxEntries).insert(
          OutboxEntriesCompanion.insert(
              packageId: 'synthetic-package',
              draftId: 'synthetic-draft',
              idempotencyKey: 'synthetic-idempotency',
              manifestJson: '{"synthetic":true}',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now()));
      fixture.api.failure = scenario.value;
      await fixture.restart();
      final offline =
          await fixture.container.read(authControllerProvider.future);
      expect(offline?.isOffline, isTrue);
      expect(offline?.user.activeOrganizationId, 'synthetic-org');
      expect(
          (await fixture.database.select(fixture.database.captureDrafts).get())
              .single
              .state,
          'queued');
      final queued =
          (await fixture.database.select(fixture.database.outboxEntries).get())
              .single;
      expect(queued.state, 'queued');
      expect(queued.idempotencyKey, 'synthetic-idempotency');
      expect(
          (await fixture.container
                  .read(authControllerProvider.notifier)
                  .reconnect())
              ?.isOffline,
          isTrue);
      fixture.api.failure = null;
      expect(
          (await fixture.container
                  .read(authControllerProvider.notifier)
                  .reconnect())
              ?.isOffline,
          isFalse);
    });
  }
  test(
      'expired cache cannot restore offline, but keeps credentials for an online retry',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    fixture.api.verifiedAt = DateTime.now().subtract(const Duration(days: 8));
    await fixture.login();
    fixture.api.failure = _failure(DioExceptionType.connectionError);
    await fixture.restart();
    expect(await fixture.container.read(authControllerProvider.future), isNull);
    expect(await SecureAuthSessionRepository().read(), isNotNull);
  });
  for (final scenario in <String, DioException>{
    'TLS failure': _failure(DioExceptionType.unknown,
        error: const HandshakeException('certificate rejected')),
    'bad certificate': _failure(DioExceptionType.badCertificate),
    'malformed response': _failure(DioExceptionType.unknown,
        error: const FormatException('invalid')),
    'forbidden account': _failure(DioExceptionType.badResponse, status: 403),
  }.entries) {
    test('${scenario.key} cannot become an offline login', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.login();
      fixture.api.failure = scenario.value;
      await fixture.restart();
      await expectLater(fixture.container.read(authControllerProvider.future),
          throwsA(isA<DioException>()));
    });
  }
  test('revoked refresh is cleared; a later offline restart cannot recover it',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.login();
    fixture.api.failure = _failure(DioExceptionType.badResponse, status: 401);
    await fixture.restart();
    expect(await fixture.container.read(authControllerProvider.future), isNull);
    fixture.api.failure = _failure(DioExceptionType.connectionError);
    await fixture.restart();
    expect(await fixture.container.read(authControllerProvider.future), isNull);
  });
  test('explicit offline logout cannot recover on a cold start', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.login();
    fixture.api.failure = _failure(DioExceptionType.connectionError);
    await fixture.restart();
    await fixture.container.read(authControllerProvider.future);
    await fixture.container.read(authControllerProvider.notifier).logout();
    await fixture.restart();
    expect(await fixture.container.read(authControllerProvider.future), isNull);
  });
}

class _Fixture {
  _Fixture(this.directory);
  final Directory directory;
  final _Api api = _Api();
  bool? deviceNetwork;
  late AppDatabase database;
  late ProviderContainer container;
  static Future<_Fixture> create() async {
    FlutterSecureStorage.setMockInitialValues({});
    final fixture =
        _Fixture(await Directory.systemTemp.createTemp('pig-auth-cold-start-'));
    fixture._open();
    return fixture;
  }

  void _open() {
    database =
        AppDatabase(NativeDatabase(File('${directory.path}/trial.sqlite')));
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      authApiProvider.overrideWithValue(api),
      deviceNetworkStatusProvider.overrideWithValue(() async => deviceNetwork),
    ]);
  }

  Future<void> login() async {
    expect(await container.read(authControllerProvider.future), isNull);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'synthetic', password: 'synthetic-password');
    expect(
        container.read(authControllerProvider).valueOrNull?.isOffline, isFalse);
  }

  Future<void> restart() async {
    container.dispose();
    await database.close();
    _open();
  }

  Future<void> close() async {
    container.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}
