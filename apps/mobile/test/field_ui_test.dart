import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';
import 'package:smart_pig_inventory/core/theme/app_theme.dart';
import 'package:smart_pig_inventory/features/home/home_screen.dart';
import 'package:smart_pig_inventory/features/home/cockpit_widgets.dart';
import 'package:smart_pig_inventory/features/inventory/session_review_screen.dart';
import 'package:smart_pig_inventory/features/local_activity/data/local_activity_repository.dart';
import 'package:smart_pig_inventory/features/tasks/pen_task_board.dart';
import 'package:smart_pig_inventory/features/workbench/count_workbench_screen.dart';

import 'support/competition_auth.dart';

class _Activities extends LocalActivityRepository {
  _Activities(super.database);
  @override
  Stream<List<LocalCaptureActivity>> watchRecent(String organizationId,
          {int limit = 50}) =>
      Stream.value(const []);
}

const _tasks = [
  RemoteInventoryTask(
      penId: 'a',
      buildingCode: 'B1',
      buildingName: '示意1栋',
      penCode: '01',
      penName: '示意01栏',
      businessDate: '2026-11-07',
      sessionId: 'session-a',
      status: 'confirmed',
      confirmedCount: 23),
  RemoteInventoryTask(
      penId: 'b',
      buildingCode: 'B1',
      buildingName: '示意1栋',
      penCode: '02',
      penName: '示意02栏',
      businessDate: '2026-11-07',
      sessionId: 'session-b',
      status: 'review_required',
      confirmedCount: 999),
  RemoteInventoryTask(
      penId: 'c',
      buildingCode: 'B1',
      buildingName: '示意1栋',
      penCode: '03',
      penName: '示意03栏',
      businessDate: '2026-11-07',
      sessionId: null,
      status: 'pending',
      confirmedCount: null),
];

class _Api extends InventoryRemoteApi {
  _Api() : super(baseUrl: 'https://synthetic.invalid');
  @override
  Future<List<RemoteInventoryTask>> tasks(
          {required String accessToken,
          required DateTime businessDate}) async =>
      _tasks;
  @override
  Future<RemoteAssistantBrief> assistantInsights(
          {required String accessToken,
          required DateTime businessDate}) async =>
      const RemoteAssistantBrief(
          businessDate: '2026-11-07', brief: '示意数据 · 以原始证据为依据', insights: []);
}

void main() {
  testWidgets(
      'field dashboard counts confirmed rows only and fits a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      localActivityRepositoryProvider.overrideWithValue(_Activities(database)),
      authControllerProvider.overrideWith(CompetitionAuthController.new),
      inventoryRemoteApiProvider.overrideWithValue(_Api()),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await database.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.runAsync(() => container.read(authControllerProvider.future));
    var theme = AppTheme.light();
    if (Platform.environment['FIELD_UI_SCREENSHOTS'] != null) {
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons');
        icons.addFont(File(
                r'D:\pig-farm-agent\.tools\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
        await icons.load();
        final emojiFile = File(r'C:\Windows\Fonts\seguiemj.ttf');
        if (await emojiFile.exists()) {
          final emoji = FontLoader('Segoe UI Emoji');
          emoji.addFont(emojiFile
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
          await emoji.load();
        }
        final font = File(r'C:\Windows\Fonts\msyh.ttc');
        if (await font.exists()) {
          final loader = FontLoader('FieldPreview');
          loader.addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
          theme = theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'FieldPreview'),
              chipTheme: theme.chipTheme.copyWith(
                  labelStyle: theme.chipTheme.labelStyle
                      ?.copyWith(fontFamily: 'FieldPreview')));
        }
      });
    }
    final boundary = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: theme,
            home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                    body: const SafeArea(child: HomeScreen()),
                    bottomNavigationBar:
                        FieldAgentNavigation(index: 0, onSelected: (_) {}))))));
    await tester.pump();
    await tester.pump();
    expect(find.text('23 头'), findsWidgets);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('态势大屏'), findsNothing);
    expect(find.text('盘点台账'), findsNothing);
    expect(find.text('更多分析'), findsNothing);
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('盘点'), findsOneWidget);
    expect(find.text('证据'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
    expect(find.text('示意数据 · 以原始证据为依据'), findsNothing);
    expect(tester.takeException(), isNull);

    // Optional local visual evidence uses synthetic data and stays outside Git.
    final output = Platform.environment['FIELD_UI_SCREENSHOTS'];
    if (output != null) {
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/branding/smart-pig-farm-owner-logo-v1.png'),
          tester.element(find.byType(HomeScreen))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/workbench.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.drag(find.byType(ListView).first, const Offset(0, -230));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/pen-matrix.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
    await tester.ensureVisible(find.byTooltip('更多作业'));
    await tester.tap(find.byTooltip('更多作业'));
    await tester.pumpAndSettle();
    expect(find.text('历史任务'), findsOneWidget);
    await tester.tap(find.text('更多能力'));
    await tester.pumpAndSettle();
    expect(find.text('智能体能力模块'), findsOneWidget);
    expect(find.text('待接入'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cockpit keeps four pen columns and opens the selected real pen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasks = List.generate(
        16,
        (i) => RemoteInventoryTask(
            penId: 'pen-$i',
            buildingCode: 'B1',
            buildingName: '示意1栋',
            penCode: '${i + 1}'.padLeft(2, '0'),
            penName: '示意栏',
            businessDate: '2026-11-07',
            sessionId: null,
            status: i == 0 ? 'confirmed' : 'pending',
            confirmedCount: i == 0 ? 23 : null));
    String? opened;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: CockpitMatrix(
                    tasks: tasks, onOpen: (task) => opened = task.penId)))));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('01栏'));
    final fourth = tester.getTopLeft(find.text('04栏'));
    final fifth = tester.getTopLeft(find.text('05栏'));
    expect(first.dy, fourth.dy);
    expect(fourth.dx, greaterThan(first.dx));
    expect(fifth.dy, greaterThan(first.dy));
    await tester.tap(find.text('04栏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开栏舍任务 →'));
    expect(opened, 'pen-3');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pen board filters real rows and never displays unconfirmed counts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? opened;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MediaQuery(
                    data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.5)),
                    child: PenTaskBoard(
                        tasks: _tasks,
                        onOpen: (task) => opened = task.penId))))));
    await tester.pumpAndSettle();
    expect(find.text('23 头'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '待复核'));
    await tester.pumpAndSettle();
    expect(find.text('01'), findsNothing);
    expect(find.text('02'), findsOneWidget);
    await tester.tap(find.text('02'));
    expect(opened, 'b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact toolbar accommodates enlarged phone text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: CockpitToolbar(
                    name: '合成盘点人员',
                    offline: false,
                    pending: 2,
                    onQueue: () {},
                    onProfile: () {},
                    onSunlight: () {})))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture entry fits enlarged text on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: const CountWorkbenchScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('选择栏舍并开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
