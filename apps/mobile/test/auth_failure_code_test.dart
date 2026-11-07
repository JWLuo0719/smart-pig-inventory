import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/main.dart';

class _FailedRestore extends AuthController {
  _FailedRestore(this.error);
  final Object error;
  int attempts = 0;
  @override
  Future<AuthState?> build() async {
    attempts++;
    throw error;
  }
}

void main() {
  for (final scenario in <String, Object>{
    'AUTH-LOCAL-PLATFORM': PlatformException(
        code: 'synthetic',
        message: 'synthetic-secret-do-not-display',
        details: {'token': 'synthetic-secret-do-not-display'}),
    'AUTH-NET-UNKNOWN-TLS': DioException(
        requestOptions: RequestOptions(
            path: '/synthetic-secret-do-not-display',
            headers: {'Authorization': 'synthetic-secret-do-not-display'}),
        error: const HandshakeException('synthetic-secret-do-not-display')),
  }.entries) {
    testWidgets(
        'cold-start failure shows safe ${scenario.key} and retries restoration',
        (tester) async {
      final auth = _FailedRestore(scenario.value);
      final container = ProviderContainer(
          overrides: [authControllerProvider.overrideWith(() => auth)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const MaterialApp(home: AuthGate())));
      await tester.pump();
      expect(find.text('问题编号：${scenario.key}'), findsOneWidget);
      expect(
          find.textContaining('synthetic-secret-do-not-display'), findsNothing);
      expect(auth.attempts, 1);
      await tester.ensureVisible(find.text('重试恢复已有登录'));
      await tester.tap(find.text('重试恢复已有登录'));
      await tester.pump();
      await tester.pump();
      expect(auth.attempts, 2);
      expect(find.text('问题编号：${scenario.key}'), findsOneWidget);
    });
  }
}
