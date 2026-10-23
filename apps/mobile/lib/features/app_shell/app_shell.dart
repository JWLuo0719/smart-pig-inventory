import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../gallery/gallery_screen.dart';
import '../home/home_screen.dart';
import '../inventory/inventory_revision.dart';
import '../profile/profile_screen.dart';
import '../tasks/task_list_screen.dart';
import '../workbench/count_workbench_screen.dart';
import '../outbox/data/drift_outbox_repository.dart';
import '../sync/outbox_background_sync.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  final Set<int> _visited = {0};

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    TaskListScreen(),
    CountWorkbenchScreen(),
    GalleryScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Re-arm a durable queue after process restart or an app upgrade, but only
    // when a synchronizable row is actually present. The worker performs its
    // own session check, so an empty queue never causes a token refresh.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scheduleAuthenticatedQueue());
  }

  Future<void> _scheduleAuthenticatedQueue() async {
    if (!mounted) return;
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (auth == null || auth.isOffline) return;
    final repository = ref.read(outboxRepositoryProvider);
    await repository.retryAuthenticationWaiting(
        organizationId: auth.user.activeOrganizationId,
        now: DateTime.now().toUtc());
    if (!mounted) return;
    final current = ref.read(authControllerProvider).valueOrNull;
    if (current?.user.subjectId != auth.user.subjectId ||
        current?.user.activeOrganizationId != auth.user.activeOrganizationId) {
      return;
    }
    final hasWork = await repository.hasSynchronizableWork(
        organizationId: auth.user.activeOrganizationId,
        now: DateTime.now().toUtc());
    if (hasWork) await scheduleOutboxSync();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (after != null &&
          !after.isOffline &&
          (before?.isOffline != false ||
              before?.user.subjectId != after.user.subjectId ||
              before?.user.activeOrganizationId !=
                  after.user.activeOrganizationId)) {
        _scheduleAuthenticatedQueue();
      }
    });
    return Scaffold(
      body: SafeArea(
          child: IndexedStack(
              index: _index,
              children: List.generate(
                  _pages.length,
                  (index) => _visited.contains(index)
                      ? _pages[index]
                      : const SizedBox.shrink()))),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) {
          if (value != _index) {
            ref.read(inventoryRevisionProvider.notifier).state++;
          }
          setState(() {
            _visited.add(value);
            _index = value;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: '任务'),
          NavigationDestination(
              icon: Icon(Icons.center_focus_strong_outlined),
              selectedIcon: Icon(Icons.center_focus_strong),
              label: '盘点'),
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: '图库'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
        ],
      ),
    );
  }
}
