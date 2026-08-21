import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:workmanager/workmanager.dart';

import 'core/storage/app_database.dart';
import 'core/storage/database_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/app_shell/app_shell.dart';
import 'features/capture/capture_screen.dart';
import 'features/capture/domain/capture_target.dart';
import 'features/outbox/outbox_screen.dart';
import 'features/pens/pen_picker_screen.dart';
import 'features/sync/outbox_background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(outboxCallbackDispatcher);
  final database = await AppDatabase.open();
  runApp(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const PigInventoryApp()));
}

class PigInventoryApp extends StatelessWidget {
  const PigInventoryApp({super.key});

  static final GoRouter _router = GoRouter(routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const AppShell()),
    GoRoute(
        path: '/pens', builder: (context, state) => const PenPickerScreen()),
    GoRoute(
      path: '/capture',
      builder: (context, state) {
        final CaptureTarget? target = state.extra as CaptureTarget?;
        if (target == null) return const PenPickerScreen();
        return CaptureScreen(target: target);
      },
    ),
    GoRoute(path: '/outbox', builder: (context, state) => const OutboxScreen()),
  ]);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '智慧猪场场主',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}
