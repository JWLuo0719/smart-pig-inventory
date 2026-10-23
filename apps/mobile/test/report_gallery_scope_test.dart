import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/network/inventory_browse_api.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';
import 'package:smart_pig_inventory/features/gallery/server_gallery_screen.dart';
import 'package:smart_pig_inventory/features/inventory/inventory_reports_screen.dart';
import 'package:smart_pig_inventory/features/master_data/data/drift_master_data_repository.dart';
import 'package:smart_pig_inventory/features/master_data/domain/master_data_changes.dart';

import 'support/competition_auth.dart';

class _Master extends DriftMasterDataRepository {
  _Master(super.database);
  @override
  Stream<List<PenChoice>> watchPens(String organizationId,
          {String query = ''}) =>
      Stream.value([
        PenChoice(
            organizationId: organizationId,
            buildingId: 'building',
            buildingCode: 'SYN',
            buildingName: '合成栋',
            penId: 'pen',
            penCode: 'P1',
            penName: '合成栏',
            enabled: true),
        PenChoice(
            organizationId: organizationId,
            buildingId: 'building',
            buildingCode: 'SYN',
            buildingName: '合成栋',
            penId: 'pen-b',
            penCode: 'P2',
            penName: '另一个合成栏',
            enabled: true),
      ]);
}

RemoteTrend _trend() => RemoteTrend.fromJson({
      'from': '2026-10-10',
      'to': '2026-10-23',
      'scopePenCount': 3,
      'total': [
        {
          'date': '2026-10-22',
          'confirmed': 0,
          'candidate': 0,
          'confirmedPenCount': 1,
          'candidatePenCount': 1
        },
        {'date': '2026-10-23', 'confirmed': 100, 'candidate': 88},
      ],
      'pens': <Object>[],
    });

class _Reports extends InventoryBrowseApi {
  _Reports({this.readDaily}) : super('https://synthetic.invalid');
  final Future<List<Map<String, dynamic>>> Function(String)? readDaily;
  final trendTokens = <String>[];
  final dailyDates = <DateTime>[], trendDates = <DateTime>[];
  final aggregateQueries = <(String, DateTime, DateTime)>[];
  @override
  Future<List<Map<String, dynamic>>> daily(String token, DateTime date) async {
    dailyDates.add(date);
    return readDaily == null ? [] : readDaily!(token);
  }

  @override
  Future<Map<String, dynamic>> aggregate(
      String token, String penId, DateTime from, DateTime to) async {
    aggregateQueries.add((penId, from, to));
    return {'roundedCount': null, 'rawMean': null, 'includedDates': <String>[]};
  }

  @override
  Future<RemoteTrend> trend(String token, DateTime to, {int days = 14}) async {
    trendTokens.add(token);
    trendDates.add(to);
    return _trend();
  }
}

LibraryMedia _media() => LibraryMedia.fromJson({
      'assetId': 'asset',
      'sessionId': 'session',
      'penId': 'pen',
      'buildingCode': 'SYN',
      'penCode': 'P1',
      'businessDate': '2026-10-23',
      'viewPosition': 'left',
      'contentType': 'image/jpeg',
      'locked': true,
      'deleted': false,
    });

class _Gallery extends InventoryBrowseApi {
  _Gallery({this.original, this.thumbnailFailure = false})
      : super('https://synthetic.invalid');
  final Future<Uint8List>? original;
  final bool thumbnailFailure;
  int thumbnailReads = 0, originalReads = 0;
  static Uint8List get png =>
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 3)));
  @override
  Future<List<LibraryMedia>> sessionMedia(
          String token, String sessionId) async =>
      [_media()];
  @override
  Future<Uint8List> thumbnail(String token, String assetId) async {
    thumbnailReads++;
    if (thumbnailFailure) {
      throw DioException(
          requestOptions: RequestOptions(path: '/thumbnail'),
          response: Response(
              requestOptions: RequestOptions(path: '/thumbnail'),
              statusCode: 422));
    }
    return png;
  }

  @override
  Future<Uint8List> content(String token, String assetId) async {
    originalReads++;
    return original ?? png;
  }
}

class _QueuedGallery extends InventoryBrowseApi {
  _QueuedGallery() : super('https://synthetic.invalid');
  int queries = 0, originalReads = 0;
  final started = <(String, String)>[];
  final controls = <String, Completer<Uint8List>>{};
  final active = <String, int>{}, peak = <String, int>{};

  @override
  Future<List<LibraryMedia>> sessionMedia(
      String token, String sessionId) async {
    final query = ++queries;
    return List.generate(
        10,
        (index) => LibraryMedia.fromJson({
              'assetId': 'query$query-asset$index',
              'sessionId': sessionId,
              'buildingCode': '查询$query',
              'penCode': 'P$index',
              'viewPosition': 'single',
              'contentType': 'image/jpeg',
              'locked': true,
              'deleted': false,
            }));
  }

  @override
  Future<Uint8List> thumbnail(String token, String assetId) async {
    started.add((token, assetId));
    final group = assetId.split('-').first;
    active[group] = (active[group] ?? 0) + 1;
    if ((active[group] ?? 0) > (peak[group] ?? 0)) peak[group] = active[group]!;
    final pending = controls.putIfAbsent(assetId, Completer<Uint8List>.new);
    try {
      return await pending.future;
    } finally {
      active[group] = active[group]! - 1;
    }
  }

  @override
  Future<Uint8List> content(String token, String assetId) async {
    originalReads++;
    return _Gallery.png;
  }

  void finishIssued() {
    for (final control in controls.values.toList()) {
      if (!control.isCompleted) control.complete(_Gallery.png);
    }
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  Future<void> pump(WidgetTester tester, Widget child,
      {InventoryBrowseApi? reports, InventoryBrowseApi? gallery}) async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authControllerProvider.overrideWith(CompetitionAuthController.new),
      masterDataRepositoryProvider.overrideWithValue(_Master(db)),
      if (reports != null)
        inventoryReportsApiProvider.overrideWithValue(reports),
      if (gallery != null) serverGalleryApiProvider.overrideWithValue(gallery),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() async {
      container.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp(home: Scaffold(body: child))));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'report identity switch drops late daily response before further requests',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final reports = _Reports(
        readDaily: (token) async => token.endsWith('org-a')
            ? pending.future
            : [
                {
                  'buildingCode': '乙组织',
                  'penCode': 'P1',
                  'confirmedCount': 12,
                  'sessionId': 'b-session'
                }
              ]);
    await pump(tester, const InventoryReportsScreen(), reports: reports);
    (container.read(authControllerProvider.notifier)
            as CompetitionAuthController)
        .switchTo(competitionAuth(org: 'org-b'));
    await tester.pump();
    await tester.pump();
    expect(find.text('乙组织 / P1'), findsOneWidget);
    pending.complete([
      {
        'buildingCode': '甲组织',
        'penCode': 'OLD',
        'confirmedCount': 99,
        'sessionId': 'a-session'
      }
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('甲组织 / OLD'), findsNothing);
    expect(reports.trendTokens, ['synthetic-org-b']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'trend makes unknown coverage visible and absent pen stays absent',
      (tester) async {
    await pump(tester, const InventoryReportsScreen(), reports: _Reports());
    expect(find.textContaining('最近有数据日 2026-10-23：确认覆盖 未知 栏'), findsOneWidget);
    await tester.tap(find.text('查看每日覆盖栏舍数'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-22：确认覆盖 1 栏；候选覆盖 1 栏。'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SYN / P1 · 合成栏').last);
    await tester.pumpAndSettle();
    expect(find.text('该栏舍近 14 天暂无已确认或候选记录。'), findsOneWidget);
    expect(find.textContaining('存栏趋势 · 全场合计'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late earlier pen query cannot replace a newer pen projection',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    var queries = 0;
    final reports =
        _Reports(readDaily: (_) async => ++queries == 2 ? pending.future : []);
    await pump(tester, const InventoryReportsScreen(), reports: reports);
    final filter = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    // Retain callbacks already queued by the old frame to exercise generation guards.
    final select = filter.onChanged!;
    select('pen');
    await tester.pump();
    select('pen-b');
    await tester.pump();
    await tester.pump();
    pending.complete([
      {
        'buildingCode': '旧请求',
        'penCode': 'P1',
        'confirmedCount': 99,
        'sessionId': 'old'
      }
    ]);
    await tester.pump();
    await tester.pump();
    expect(reports.aggregateQueries.map((query) => query.$1), ['pen-b']);
    expect(find.text('旧请求 / P1'), findsNothing);
    expect(find.text('SYN / P2 · 另一个合成栏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'date range requests retain their snapshot and late range cannot refill current day',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    var queries = 0;
    final reports =
        _Reports(readDaily: (_) async => ++queries == 2 ? pending.future : []);
    await pump(tester, const InventoryReportsScreen(), reports: reports);
    final chooseRange = tester
        .widget<OutlinedButton>(find.byType(OutlinedButton).first)
        .onPressed!;
    final rangeA = DateTimeRange(
        start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 11));
    final rangeB = DateTimeRange(
        start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    Future<void> completePicker(DateTimeRange range) async {
      chooseRange();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      Navigator.of(tester.element(find.byType(DateRangePickerDialog)))
          .pop(range);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await completePicker(rangeA);
    await completePicker(rangeB);
    pending.complete([
      {
        'buildingCode': '旧日期',
        'penCode': 'P1',
        'confirmedCount': 99,
        'sessionId': 'old'
      }
    ]);
    await tester.pump();
    await tester.pump();
    expect(reports.dailyDates.skip(1), [rangeA.end, rangeB.end]);
    expect(reports.trendDates.last, rangeB.end);
    expect(reports.trendDates, isNot(contains(rangeA.end)));
    expect(find.text('旧日期 / P1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'server thumbnail failure stays a placeholder and original remains readable',
      (tester) async {
    final gallery = _Gallery(thumbnailFailure: true);
    await pump(tester, const ServerGalleryScreen(sessionId: 'session'),
        gallery: gallery);
    expect(gallery.thumbnailReads, 1);
    expect(gallery.originalReads, 0);
    expect(find.text('SYN / P1 · 左图'), findsOneWidget);
    expect(find.text('缩略图暂不可用，可打开原图'), findsOneWidget);
    await tester.tap(find.text('翻阅原图'));
    // The underlying gallery intentionally stays busy while its modal is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(gallery.originalReads, 1);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'server list renders the authenticated thumbnail without loading original',
      (tester) async {
    final gallery = _Gallery();
    await pump(tester, const ServerGalleryScreen(sessionId: 'session'),
        gallery: gallery);
    await tester.pump();
    expect(gallery.thumbnailReads, 1);
    expect(gallery.originalReads, 0);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, _Gallery.png);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'original response cannot open a stale photo after offline identity switch',
      (tester) async {
    final original = Completer<Uint8List>();
    await pump(tester, const ServerGalleryScreen(sessionId: 'session'),
        gallery: _Gallery(original: original.future, thumbnailFailure: true));
    await tester.tap(find.text('翻阅原图'));
    await tester.pump();
    (container.read(authControllerProvider.notifier)
            as CompetitionAuthController)
        .switchTo(competitionAuth(org: 'org-b', offline: true));
    await tester.pump();
    original.complete(_Gallery.png);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('SYN / P1 · 左图'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'gallery thumbnails use two slots and queued work cannot cross identity',
      (tester) async {
    final gallery = _QueuedGallery();
    await pump(tester, const ServerGalleryScreen(sessionId: 'session'),
        gallery: gallery);
    expect(gallery.started, hasLength(2));
    expect(gallery.peak['query1'], 2);
    expect(find.text('缩略图读取中…'), findsWidgets);
    (container.read(authControllerProvider.notifier)
            as CompetitionAuthController)
        .switchTo(competitionAuth(org: 'org-b'));
    await tester.pump();
    await tester.pump();
    // Neither old HTTP request has completed. B still owns two fresh slots.
    expect(gallery.started.where((call) => call.$1 == 'synthetic-org-a'),
        hasLength(2));
    expect(gallery.started.where((call) => call.$1 == 'synthetic-org-b'),
        hasLength(2));
    expect(gallery.started.where((call) => call.$2.startsWith('query1')),
        hasLength(2));
    expect(gallery.peak['query2'], 2);
    expect(gallery.originalReads, 0);
    gallery.controls['query1-asset0']!.complete(_Gallery.png);
    gallery.controls['query1-asset1']!.complete(_Gallery.png);
    await tester.pump();
    await tester.pump();
    expect(gallery.started.where((call) => call.$2.startsWith('query1')),
        hasLength(2));
    expect(find.textContaining('查询1 /'), findsNothing);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
    gallery.finishIssued();
    await tester.pump();
  });

  testWidgets(
      'refresh cancels pending thumbnails and starts a query without awaiting old HTTP',
      (tester) async {
    final gallery = _QueuedGallery();
    await pump(tester, const ServerGalleryScreen(sessionId: 'session'),
        gallery: gallery);
    expect(gallery.started, hasLength(2));
    await tester.tap(find.text('刷新照片'));
    await tester.pump();
    await tester.pump();
    expect(gallery.started.where((call) => call.$2.startsWith('query1')),
        hasLength(2));
    expect(gallery.started.where((call) => call.$2.startsWith('query2')),
        hasLength(2));
    expect(gallery.peak.values, everyElement(2));
    expect(gallery.originalReads, 0);
    expect(find.textContaining('查询1 /'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    gallery.finishIssued();
    await tester.pump();
    // Disposing also prevents any queued HTTP from being issued afterwards.
    expect(gallery.started, hasLength(4));
  });
}
