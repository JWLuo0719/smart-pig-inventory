import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_api.dart';
import 'package:smart_pig_inventory/core/auth/auth_context_repository.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/auth/auth_session_repository.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';
import 'package:smart_pig_inventory/features/outbox/data/drift_outbox_repository.dart';

void main() {
  late AppDatabase database;
  late DriftOutboxRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftOutboxRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('puts waiting authentication packages back into the queue after login',
      () async {
    await _seedOutbox(database, 'pkg-waiting-1');
    await _seedOutbox(database, 'pkg-waiting-2');
    await _seedOutbox(database, 'pkg-blocked', state: 'blocked');
    final ProviderContainer container = _openContainer(
      database: database,
      api: _FakeAuthApi(session: _session('access'), user: _user()),
    );
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login(username: 'owner', password: 'secret');

    final List<OutboxEntry> entries =
        await database.select(database.outboxEntries).get();
    for (final OutboxEntry entry in entries) {
      if (entry.packageId == 'pkg-blocked') {
        expect(entry.state, 'blocked');
        continue;
      }
      expect(entry.state, 'queued');
      expect(entry.error, equals(null));
      expect(entry.nextAttemptAt, equals(null));
    }
  });

  test('puts waiting authentication packages back into the queue after reconnect',
      () async {
    final ProviderContainer container = _openContainer(
      database: database,
      api: _FakeAuthApi(session: _session('access'), user: _user()),
      storedSession: _session('access'),
    );
    await container.read(authControllerProvider.future);
    await _seedOutbox(database, 'pkg-waiting');

    await container.read(authControllerProvider.notifier).reconnect();

    final OutboxEntry entry =
        await database.select(database.outboxEntries).getSingle();
    expect(entry.state, 'queued');
    expect(entry.error, equals(null));
    expect(entry.nextAttemptAt, equals(null));
  });

  test('releases waiting packages after a refreshed token on reconnect',
      () async {
    final ProviderContainer container = _openContainer(
      database: database,
      api: _FakeAuthApi(
        session: _session('access'),
        user: _user(),
        // 恢复会话时校验通过;重连时 401,只能靠刷新拿到新令牌。
        unauthorizedOnVerifyCall: 2,
        refreshSession: _session('refreshed'),
      ),
      storedSession: _session('access'),
    );
    await container.read(authControllerProvider.future);
    await _seedOutbox(database, 'pkg-waiting');

    final AuthState? state =
        await container.read(authControllerProvider.notifier).reconnect();

    expect(state?.session.accessToken, 'refreshed');
    final OutboxEntry entry =
        await database.select(database.outboxEntries).getSingle();
    expect(entry.state, 'queued');
  });

  test('keeps waiting packages parked while the session is offline', () async {
    await AuthContextRepository(database).save(_user());
    final ProviderContainer container = _openContainer(
      database: database,
      api: _FakeAuthApi(
        session: _session('access'),
        user: _user(),
        networkFailure: true,
      ),
      storedSession: _session('access'),
    );
    final AuthState? restored =
        await container.read(authControllerProvider.future);
    expect(restored?.isOffline, isTrue);
    await _seedOutbox(database, 'pkg-waiting');

    final AuthState? state =
        await container.read(authControllerProvider.notifier).reconnect();

    expect(state?.isOffline, isTrue);
    final OutboxEntry entry =
        await database.select(database.outboxEntries).getSingle();
    expect(entry.state, 'waiting_authentication');
  });

  test('counts waiting authentication packages as synchronizable work',
      () async {
    await _seedOutbox(database, 'pkg-waiting');

    // 计入待办后才能在启动时重新布防 worker。
    expect(
        await repository.hasSynchronizableWork(now: DateTime.utc(2026, 8, 23)),
        isTrue);
    // 但登录前仍不能被领走上传,必须先由 retryAuthenticationWaiting 放行。
    expect(
        await repository.acquireNext(
            owner: 'test', now: DateTime.utc(2026, 8, 23)),
        equals(null));

    await database.delete(database.outboxEntries).go();
    expect(
        await repository.hasSynchronizableWork(now: DateTime.utc(2026, 8, 23)),
        isFalse);
  });
}

ProviderContainer _openContainer({
  required AppDatabase database,
  required AuthApi api,
  AuthSession? storedSession,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      authApiProvider.overrideWithValue(api),
      authSessionRepositoryProvider
          .overrideWithValue(_InMemoryAuthSessionRepository(storedSession)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _seedOutbox(AppDatabase database, String packageId,
    {String state = 'waiting_authentication'}) async {
  await database.into(database.outboxEntries).insert(
      OutboxEntriesCompanion.insert(
          packageId: packageId,
          draftId: 'draft-$packageId',
          idempotencyKey: 'key-$packageId',
          manifestJson: '{}',
          state: Value<String>(state),
          createdAt: DateTime.utc(2026, 8, 23),
          updatedAt: DateTime.utc(2026, 8, 23)));
}

AuthSession _session(String accessToken) => AuthSession(
      accessToken: accessToken,
      refreshToken: 'refresh-$accessToken',
      accessTokenExpiresAt: DateTime.utc(2026, 8, 23, 13),
      refreshTokenExpiresAt: DateTime.utc(2026, 8, 30),
    );

AuthenticatedUser _user() => AuthenticatedUser(
      subjectId: 'subject',
      displayName: 'Operator',
      activeOrganizationId: 'org-id',
      activeOrganizationCode: 'O',
      activeOrganizationName: 'Org',
      roles: const <String>['OPERATOR'],
      lastVerifiedAt: DateTime.now().toUtc(),
    );

class _InMemoryAuthSessionRepository implements AuthSessionRepository {
  _InMemoryAuthSessionRepository(this._session);

  AuthSession? _session;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> save(AuthSession session) async {
    _session = session;
  }
}

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({
    required this.session,
    required this.user,
    this.unauthorizedOnVerifyCall,
    this.refreshSession,
    this.networkFailure = false,
  });

  final AuthSession session;
  final AuthenticatedUser user;

  /// 第几次 currentUser 校验返回 401;null 表示永远通过。
  final int? unauthorizedOnVerifyCall;
  final AuthSession? refreshSession;
  final bool networkFailure;
  int _verifyCalls = 0;

  @override
  Future<AuthSession> login(
      {required String username, required String password}) async {
    return session;
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final AuthSession? refreshed = refreshSession;
    if (refreshed == null) {
      throw DioException(requestOptions: RequestOptions(path: '/refresh'));
    }
    return refreshed;
  }

  @override
  Future<AuthenticatedUser> currentUser(String accessToken) async {
    if (networkFailure) {
      throw DioException(
          requestOptions: RequestOptions(path: '/me'),
          type: DioExceptionType.connectionError);
    }
    _verifyCalls++;
    if (_verifyCalls == unauthorizedOnVerifyCall) {
      throw DioException(
          requestOptions: RequestOptions(path: '/me'),
          response: Response<void>(
              requestOptions: RequestOptions(path: '/me'), statusCode: 401));
    }
    return user;
  }

  @override
  Future<void> logout(
      {required String accessToken, required String refreshToken}) async {}
}
