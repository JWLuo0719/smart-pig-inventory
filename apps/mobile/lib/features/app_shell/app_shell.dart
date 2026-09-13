import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gallery/gallery_screen.dart';
import '../home/home_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool hasWork = await ref
          .read(outboxRepositoryProvider)
          .hasSynchronizableWork(now: DateTime.now().toUtc());
      if (hasWork) await scheduleOutboxSync();
    });
  }

  @override
  Widget build(BuildContext context) {
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
        onDestinationSelected: (int value) => setState(() {
          _visited.add(value);
          _index = value;
        }),
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
