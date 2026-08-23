import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/auth/auth_session_repository.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';

import 'package:smart_pig_inventory/main.dart';

void main() {
  testWidgets('mounts the unauthenticated product application shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        authSessionRepositoryProvider
            .overrideWithValue(_EmptyAuthSessionRepository()),
      ],
      child: const PigInventoryApp(),
    ));
    await tester.pump();

    expect(find.byType(PigInventoryApp), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}

class _EmptyAuthSessionRepository implements AuthSessionRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> save(AuthSession session) async {}
}
