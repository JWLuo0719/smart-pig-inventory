import 'package:smart_pig_inventory/core/network/inventory_browse_api.dart';
import 'package:smart_pig_inventory/features/gallery/server_gallery_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';
import 'package:smart_pig_inventory/features/inventory/annotated_evidence.dart';
import 'package:smart_pig_inventory/features/inventory/inventory_revision.dart';
import 'package:smart_pig_inventory/features/inventory/session_review_screen.dart';
import 'support/competition_auth.dart';

class _Auth extends AuthController {
  @override
  Future<AuthState?> build() async => AuthState(
      session: AuthSession(
          accessToken: 'synthetic',
          refreshToken: 'synthetic',
          accessTokenExpiresAt: DateTime(2030),
          refreshTokenExpiresAt: DateTime(2030)),
      user: AuthenticatedUser(
          subjectId: 'reviewer',
          displayName: '合成复核员',
          activeOrganizationId: 'org',
          activeOrganizationCode: 'SYN',
          activeOrganizationName: '合成组织',
          roles: const ['REVIEWER'],
          lastVerifiedAt: DateTime(2026)),
      isOffline: false);
}

class _Api extends InventoryRemoteApi {
  _Api(this.read, {this.onConfirm})
      : super(baseUrl: 'https://synthetic.invalid');
  final FutureOr<RemoteInventorySession> Function() read;
  final Future<RemoteInventorySession> Function()? onConfirm;
  @override
  Future<RemoteInventorySession> confirm(
          {required String accessToken,
          required String sessionId,
          required String idempotencyKey,
          required int confirmedCount,
          String? reason}) =>
      onConfirm!();
  @override
  Future<RemoteInventorySession> session(
          {required String accessToken, required String sessionId}) async =>
      read();
}

class _Gallery extends InventoryBrowseApi {
  _Gallery() : super('https://synthetic.invalid');
  @override
  Future<List<LibraryMedia>> sessionMedia(String token, String id) async => [];
}

void main() {
  testWidgets(
      'changing identity immediately hides the old result while new read is pending',
      (tester) async {
    final pending = Completer<RemoteInventorySession>();
    var reads = 0;
    final api = _Api(() {
      if (++reads > 1) return pending.future;
      return RemoteInventorySession.fromJson({
        'id': 'session',
        'penId': 'pen',
        'businessDate': '2026-10-23',
        'status': 'confirmed',
        'version': 1,
        'rawModelCount': 24,
        'count': 24,
        'detections': [],
        'warnings': [],
      });
    });
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(CompetitionAuthController.new),
      serverGalleryApiProvider.overrideWithValue(_Gallery()),
      inventoryRemoteApiProvider.overrideWithValue(api),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            navigatorObservers: [inventoryRouteObserver],
            home: const SessionReviewScreen(sessionId: 'session'))));
    await tester.pump();
    await tester.pump();
    expect(find.text('24 头'), findsOneWidget);
    (container.read(authControllerProvider.notifier)
            as CompetitionAuthController)
        .switchTo(competitionAuth(org: 'org-b'));
    await tester.pump();
    expect(find.text('24 头'), findsNothing);
    pending.complete(RemoteInventorySession.fromJson({
      'id': 'session',
      'penId': 'pen',
      'businessDate': '2026-10-23',
      'status': 'review_required',
      'version': 1,
      'rawModelCount': null,
      'detections': [],
      'warnings': [],
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('24 头'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  test('status labels preserve every server state and image letterboxing', () {
    for (final state in [
      'submitted',
      'processing',
      'review_required',
      'confirmed',
      'superseded'
    ]) {
      expect(sessionStatusLabel(state), isNot(sessionStatusLabel('unknown')));
    }
    expect(evidenceContainRect(2, const Size(300, 300)),
        const Rect.fromLTWH(0, 75, 300, 150));
    expect(evidenceContainRect(.5, const Size(300, 300)),
        const Rect.fromLTWH(75, 0, 150, 300));
  });

  testWidgets(
      'processing polling is bounded and manual review input survives refresh',
      (tester) async {
    int reads = 0;
    String status = 'processing';
    final api = _Api(() {
      reads++;
      return RemoteInventorySession.fromJson(<String, dynamic>{
        'id': 'session',
        'penId': 'pen',
        'businessDate': '2026-10-18',
        'status': status,
        'version': 1,
        'rawModelCount': null,
        'count':
            72, // A legacy display field must never reconstruct a missing candidate.
        'detections': [],
        'warnings': [],
      });
    });
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      serverGalleryApiProvider.overrideWithValue(_Gallery()),
      inventoryRemoteApiProvider.overrideWithValue(api),
      inventoryClockProvider
          .overrideWithValue(() => tester.binding.clock.now()),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            navigatorObservers: [inventoryRouteObserver],
            home: const SessionReviewScreen(sessionId: 'session'))));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    }
    expect(reads, inInclusiveRange(2, 21));
    final bounded = reads;
    await tester.pump(const Duration(seconds: 30));
    expect(reads, bounded);
    status = 'review_required';
    await tester.tap(find.byTooltip('刷新结果'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('服务器尚无可用候选数量'), findsOneWidget);
    expect(find.text('72 头'), findsNothing);
    final input = find.byType(TextField).first;
    await tester.ensureVisible(input);
    await tester.enterText(input, '24');
    await tester.tap(find.byTooltip('刷新结果'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, '24');
    status = 'confirmed';
    await tester.tap(find.byTooltip('刷新结果'));
    await tester.pump();
    await tester.pump();
    expect(container.read(inventoryRevisionProvider), 1);
    final terminalReads = reads;
    await tester.pump(const Duration(seconds: 12));
    expect(reads, terminalReads);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets(
      'late manual refresh cannot reopen a confirmed result, including at 130 percent text',
      (tester) async {
    RemoteInventorySession result(String status) =>
        RemoteInventorySession.fromJson(<String, dynamic>{
          'id': 'session',
          'penId': 'pen',
          'businessDate': '2026-10-20',
          'status': status,
          'version': 1,
          'rawModelCount': 24,
          'count': 24,
          'warnings': [],
          'detections': [],
        });
    final pending = Completer<RemoteInventorySession>();
    var reads = 0;
    var confirmations = 0;
    final api = _Api(() {
      reads++;
      return reads == 2
          ? pending.future
          : result(reads == 1 ? 'review_required' : 'confirmed');
    }, onConfirm: () async {
      confirmations++;
      return result('confirmed');
    });
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      serverGalleryApiProvider.overrideWithValue(_Gallery()),
      inventoryRemoteApiProvider.overrideWithValue(api)
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            navigatorObservers: [inventoryRouteObserver],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!),
            home: const SessionReviewScreen(sessionId: 'session'))));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '24');
    await tester.tap(find.byTooltip('刷新结果'));
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, '确认并锁定证据');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump();
    pending.complete(result('review_required'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(confirmations, 1);
    expect(find.text('已确认并锁定'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认并锁定证据'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
