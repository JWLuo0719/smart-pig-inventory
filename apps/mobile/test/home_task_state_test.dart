import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';
import 'package:smart_pig_inventory/features/app_shell/app_shell.dart';
import 'package:smart_pig_inventory/features/inventory/session_review_screen.dart';
import 'package:smart_pig_inventory/features/local_activity/data/local_activity_repository.dart';

class _Activities extends LocalActivityRepository {
  _Activities(super.database);
  @override
  Stream<List<LocalCaptureActivity>> watchRecent(String organizationId,
          {int limit = 50}) =>
      Stream.value([]);
}

class _Auth extends AuthController {
  @override
  Future<AuthState?> build() async => AuthState(
      session: AuthSession(
          accessToken: 'test',
          refreshToken: 'test',
          accessTokenExpiresAt: DateTime(2030),
          refreshTokenExpiresAt: DateTime(2030)),
      user: AuthenticatedUser(
          subjectId: 'test',
          displayName: 'test',
          activeOrganizationId: 'test',
          activeOrganizationCode: 'test',
          activeOrganizationName: 'test',
          roles: const ['REVIEWER'],
          lastVerifiedAt: DateTime(2026)),
      isOffline: false);
}

class _OfflineThenOnlineAuth extends AuthController {
  static final _session = AuthSession(
      accessToken: 'test',
      refreshToken: 'test',
      accessTokenExpiresAt: DateTime(2030),
      refreshTokenExpiresAt: DateTime(2030));
  static final _user = AuthenticatedUser(
      subjectId: 'test',
      displayName: 'test',
      activeOrganizationId: 'test',
      activeOrganizationCode: 'test',
      activeOrganizationName: 'test',
      roles: const ['REVIEWER'],
      lastVerifiedAt: DateTime(2026));

  @override
  Future<AuthState?> build() async =>
      AuthState(session: _session, user: _user, isOffline: true);

  void goOnline() => state = AsyncData<AuthState?>(
      AuthState(session: _session, user: _user, isOffline: false));
}

class _UnavailableThenOnlineAuth extends _OfflineThenOnlineAuth {
  @override
  Future<AuthState?> build() async => null;
}

void main() {
  testWidgets(
      'failed task load remains unknown; only a successful empty response shows zero',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    var fail = true;
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      if (fail) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 200, data: <dynamic>[]));
      }
    }));
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      appDatabaseProvider.overrideWithValue(database),
      localActivityRepositoryProvider.overrideWithValue(_Activities(database)),
      inventoryRemoteApiProvider.overrideWithValue(
          InventoryRemoteApi(baseUrl: 'https://example.invalid', dio: dio)),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: AppShell())));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('任务状态未知，请联网后下拉重试。'), findsOneWidget);
    expect(find.text('0 / 0'), findsNothing);
    expect(requests, 1,
        reason:
            'Unvisited task and gallery pages must not fetch during startup');
    fail = false;
    await tester.runAsync(() => tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh());
    await tester.pump();
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('任务状态未知，请联网后下拉重试。'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(database.close);
  });

  testWidgets('online auth recovery reloads the home task state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: <dynamic>[]));
    }));
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_OfflineThenOnlineAuth.new),
      appDatabaseProvider.overrideWithValue(database),
      localActivityRepositoryProvider.overrideWithValue(_Activities(database)),
      inventoryRemoteApiProvider.overrideWithValue(
          InventoryRemoteApi(baseUrl: 'https://example.invalid', dio: dio)),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: AppShell())));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('任务状态未知，请联网后下拉重试。'), findsOneWidget);
    expect(requests, 0);
    (container.read(authControllerProvider.notifier) as _OfflineThenOnlineAuth)
        .goOnline();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('任务状态未知，请联网后下拉重试。'), findsNothing);
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(database.close);
  });

  testWidgets('home reloads when auth becomes available after first build',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: <dynamic>[]));
    }));
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_UnavailableThenOnlineAuth.new),
      appDatabaseProvider.overrideWithValue(database),
      localActivityRepositoryProvider.overrideWithValue(_Activities(database)),
      inventoryRemoteApiProvider.overrideWithValue(
          InventoryRemoteApi(baseUrl: 'https://example.invalid', dio: dio)),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: AppShell())));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(requests, 0);
    (container.read(authControllerProvider.notifier)
            as _UnavailableThenOnlineAuth)
        .goOnline();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('任务状态未知，请联网后下拉重试。'), findsNothing);
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(database.close);
  });
}
