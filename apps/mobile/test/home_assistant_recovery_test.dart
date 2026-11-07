import 'dart:async';

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
import 'package:smart_pig_inventory/features/home/home_screen.dart';
import 'package:smart_pig_inventory/features/inventory/session_review_screen.dart';
import 'package:smart_pig_inventory/features/local_activity/data/local_activity_repository.dart';

class _Activities extends LocalActivityRepository {
  _Activities(super.database);
  @override
  Stream<List<LocalCaptureActivity>> watchRecent(String organizationId,
          {int limit = 50}) =>
      Stream.value(const []);
}

AuthState _identity({String org = 'org-a', bool offline = false}) => AuthState(
    session: AuthSession(
        accessToken: 'synthetic-$org',
        refreshToken: 'synthetic-$org',
        accessTokenExpiresAt: DateTime(2030),
        refreshTokenExpiresAt: DateTime(2030)),
    user: AuthenticatedUser(
        subjectId: 'user-$org',
        displayName: '合成账号',
        activeOrganizationId: org,
        activeOrganizationCode: org,
        activeOrganizationName: '合成组织',
        roles: const ['REVIEWER'],
        lastVerifiedAt: DateTime(2026)),
    isOffline: offline);

class _Auth extends AuthController {
  @override
  Future<AuthState?> build() async => _identity();

  void switchTo(AuthState auth) => state = AsyncData(auth);
}

class _Api extends InventoryRemoteApi {
  _Api(this.read) : super(baseUrl: 'https://synthetic.invalid');
  final Future<RemoteAssistantBrief> Function() read;

  @override
  Future<RemoteAssistantBrief> assistantInsights(
          {required String accessToken, required DateTime businessDate}) =>
      read();

  @override
  Future<List<RemoteInventoryTask>> tasks(
          {required String accessToken,
          required DateTime businessDate}) async =>
      const [
        RemoteInventoryTask(
            penId: 'pen',
            buildingCode: 'SYN',
            buildingName: '合成栋',
            penCode: 'P1',
            penName: '合成栏',
            businessDate: '2026-10-23',
            sessionId: 'session',
            status: 'confirmed',
            confirmedCount: 7)
      ];
}

const _brief = RemoteAssistantBrief(
    businessDate: '2026-10-23', brief: '甲组织的合成研判', insights: []);

void main() {
  Future<ProviderContainer> pumpHome(
      WidgetTester tester, InventoryRemoteApi api) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      localActivityRepositoryProvider.overrideWithValue(_Activities(database)),
      authControllerProvider.overrideWith(_Auth.new),
      inventoryRemoteApiProvider.overrideWithValue(api),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await database.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomeScreen()))));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('协同研判'));
    await tester.pump(const Duration(milliseconds: 250));
    return container;
  }

  testWidgets('slow optional insight never holds confirmed task progress',
      (tester) async {
    final pending = Completer<RemoteAssistantBrief>();
    await pumpHome(tester, _Api(() => pending.future));
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('正在读取今日规则研判…'), findsOneWidget);
    pending.complete(_brief);
    await tester.pump();
    await tester.pump();
    expect(find.text(_brief.brief), findsOneWidget);
    expect(find.text('正在读取今日规则研判…'), findsNothing);
  });

  testWidgets('insight failure has a local retry that restores empty success',
      (tester) async {
    var attempts = 0;
    await pumpHome(tester, _Api(() async {
      if (++attempts == 1) {
        throw DioException(requestOptions: RequestOptions(path: '/insights'));
      }
      return _brief;
    }));
    expect(find.textContaining('规则研判暂时不可用'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    await tester.ensureVisible(find.text('重新读取研判'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新读取研判'));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.text(_brief.brief), findsOneWidget);
    expect(find.text('重新读取研判'), findsNothing);
  });

  testWidgets('offline identity switch hides old insight and drops late reads',
      (tester) async {
    final pending = Completer<RemoteAssistantBrief>();
    var attempts = 0;
    final container = await pumpHome(tester, _Api(() async {
      return ++attempts == 1 ? _brief : pending.future;
    }));
    expect(find.text(_brief.brief), findsOneWidget);
    // First hide already displayed evidence when identity changes offline.
    final auth = container.read(authControllerProvider.notifier) as _Auth;
    auth.switchTo(_identity(org: 'org-b', offline: true));
    await tester.pump();
    expect(find.text(_brief.brief), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
    // A pending response from A must also remain hidden after switching to B.
    auth.switchTo(_identity());
    await tester.pump();
    expect(attempts, 2);
    auth.switchTo(_identity(org: 'org-b', offline: true));
    await tester.pump();
    pending.complete(_brief);
    await tester.pump();
    await tester.pump();
    expect(find.text(_brief.brief), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
