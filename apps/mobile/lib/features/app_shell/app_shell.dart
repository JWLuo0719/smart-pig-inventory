import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../gallery/gallery_screen.dart';
import '../home/home_screen.dart';
import '../home/cockpit_widgets.dart';
import '../local_activity/data/local_activity_repository.dart';
import '../inventory/inventory_revision.dart';
import '../profile/profile_screen.dart';
import '../workbench/count_workbench_screen.dart';
import '../outbox/data/drift_outbox_repository.dart';
import '../outbox/outbox_screen.dart';
import '../sync/outbox_background_sync.dart';

final _pendingUploadsProvider = StreamProvider.autoDispose<int?>((ref) {
  final auth = ref.watch(authControllerProvider).valueOrNull;
  if (auth == null) return Stream.value(null);
  return ref
      .watch(localActivityRepositoryProvider)
      .watchRecent(auth.user.activeOrganizationId, limit: 1000)
      .map((rows) => rows.where((row) => row.isPending).length);
});

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _sunlight = false;
  final Set<int> _visited = {0};

  static const List<Widget> _pages = <Widget>[
    HomeScreen(showToolbar: false),
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
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final pending = ref.watch(_pendingUploadsProvider).valueOrNull;
    final scaffold = Scaffold(
      appBar: PreferredSize(
          preferredSize: Size.fromHeight(cockpitToolbarHeight(context)),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.dark,
              child: SafeArea(
                  bottom: false,
                  child: CockpitToolbar(
                      name: auth?.user.displayName ?? '账号',
                      offline: auth?.isOffline ?? true,
                      pending: pending,
                      onQueue: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const OutboxScreen())),
                      onProfile: () => _select(3),
                      sunlight: _sunlight,
                      onSunlight: () =>
                          setState(() => _sunlight = !_sunlight))))),
      body: SafeArea(
          top: false,
          child: IndexedStack(
              index: _index,
              children: List.generate(
                  _pages.length,
                  (index) => _visited.contains(index)
                      ? _pages[index]
                      : const SizedBox.shrink()))),
      bottomNavigationBar:
          FieldAgentNavigation(index: _index, onSelected: _select),
    );
    return ColorFiltered(
        colorFilter: ColorFilter.matrix(_sunlight
            ? const [
                1.15,
                0,
                0,
                0,
                -18,
                0,
                1.15,
                0,
                0,
                -18,
                0,
                0,
                1.15,
                0,
                -18,
                0,
                0,
                0,
                1,
                0
              ]
            : const [
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0
              ]),
        child: scaffold);
  }

  void _select(int value) {
    if (value != _index) ref.read(inventoryRevisionProvider.notifier).state++;
    setState(() {
      _visited.add(value);
      _index = value;
    });
  }
}
