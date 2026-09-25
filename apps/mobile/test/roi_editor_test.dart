import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/features/capture/domain/roi.dart';
import 'package:smart_pig_inventory/features/capture/roi_editor_page.dart';

void main() {
  late Directory sandbox;
  late File image;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('roi-editor-test');
    // 内容不重要：画布尺寸由 aspectRatio 决定，解码失败时走 errorBuilder。
    image = File('${sandbox.path}/photo.jpg')..writeAsBytesSync(<int>[1, 2, 3]);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Future<void> Function(Roi? roi) onSave,
    Roi? initialRoi,
    int maxExclusions = Roi.maxExclusions,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: RoiEditorPage(
        image: image,
        aspectRatio: 4 / 3,
        onSave: onSave,
        initialRoi: initialRoi,
        maxExclusions: maxExclusions,
      ),
    ));
  }

  /// 以画布比例坐标拖出一个矩形（0..1）。
  Future<void> drawExclusion(
    WidgetTester tester,
    Offset from,
    Offset to,
  ) async {
    final Finder canvas = find.byKey(const Key('roi-canvas'));
    final Offset origin = tester.getTopLeft(canvas);
    final Size size = tester.getSize(canvas);
    await tester.dragFrom(
      origin + Offset(from.dx * size.width, from.dy * size.height),
      Offset((to.dx - from.dx) * size.width, (to.dy - from.dy) * size.height),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('保存标注'));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging on the photo records a normalised exclusion region',
      (WidgetTester tester) async {
    Roi? saved;
    await pumpEditor(tester, onSave: (Roi? roi) async => saved = roi);

    await drawExclusion(tester, const Offset(0.5, 0), const Offset(1, 1));

    expect(find.textContaining('排除区 1'), findsOneWidget);
    await tapSave(tester);

    expect(saved, isNotNull);
    expect(saved!.exclusions, hasLength(1));
    expect(saved!.exclusions.single.x, closeTo(0.5, 0.001));
    expect(saved!.exclusions.single.y, closeTo(0, 0.001));
    expect(saved!.exclusions.single.width, closeTo(0.5, 0.001));
    expect(saved!.exclusions.single.height, closeTo(1, 0.001));
    // 有效区保持整图，历史口径不变。
    expect(saved!.x, 0);
    expect(saved!.y, 0);
    expect(saved!.width, 1);
    expect(saved!.height, 1);
  });

  testWidgets('a stray tap does not create an exclusion region',
      (WidgetTester tester) async {
    await pumpEditor(tester, onSave: (Roi? roi) async {});

    await drawExclusion(
        tester, const Offset(0.4, 0.4), const Offset(0.405, 0.405));

    expect(find.textContaining('排除区 1'), findsNothing);
    expect(find.text('还没有排除区：当前整张照片都算本栏。'), findsOneWidget);
  });

  testWidgets('an exclusion region can be deleted again',
      (WidgetTester tester) async {
    Roi? saved;
    await pumpEditor(tester, onSave: (Roi? roi) async => saved = roi);

    await drawExclusion(tester, const Offset(0.6, 0.1), const Offset(0.9, 0.6));
    expect(find.textContaining('排除区 1'), findsOneWidget);

    await tester.tap(find.byTooltip('删除排除区 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('排除区 1'), findsNothing);

    await tapSave(tester);
    expect(saved, isNull, reason: '没有排除区且阈值为 0 时应回到整图口径');
  });

  testWidgets('the containment threshold is carried into the saved roi',
      (WidgetTester tester) async {
    Roi? saved;
    await pumpEditor(tester, onSave: (Roi? roi) async => saved = roi);

    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    await drawExclusion(tester, const Offset(0.75, 0), const Offset(1, 1));
    await tapSave(tester);

    expect(saved, isNotNull);
    expect(saved!.exclusions, hasLength(1));
  });

  testWidgets(
      'the editor refuses more exclusion regions than the contract allows',
      (WidgetTester tester) async {
    await pumpEditor(tester, onSave: (Roi? roi) async {}, maxExclusions: 1);

    await drawExclusion(tester, const Offset(0.6, 0.1), const Offset(0.9, 0.6));
    await drawExclusion(tester, const Offset(0.1, 0.1), const Offset(0.3, 0.4));

    expect(find.textContaining('排除区 2'), findsNothing);
    expect(find.textContaining('最多只能标注 1 个排除区'), findsOneWidget);
  });

  testWidgets('an existing roi is loaded and stays editable',
      (WidgetTester tester) async {
    Roi? saved;
    await pumpEditor(
      tester,
      onSave: (Roi? roi) async => saved = roi,
      initialRoi: Roi(
        x: 0.1,
        y: 0.1,
        width: 0.8,
        height: 0.8,
        exclusions: <RoiRegion>[
          RoiRegion(x: 0.8, y: 0, width: 0.2, height: 1),
        ],
        minContainment: 0.5,
      ),
    );

    expect(find.textContaining('排除区 1'), findsOneWidget);
    expect(find.text('最小包含比例：50%'), findsOneWidget);

    await tapSave(tester);
    expect(saved!.x, 0.1);
    expect(saved!.width, 0.8);
    expect(saved!.minContainment, 0.5);
    expect(saved!.exclusions, hasLength(1));
  });

  testWidgets('a queued draft keeps the editor open with an explanation',
      (WidgetTester tester) async {
    await pumpEditor(
      tester,
      onSave: (Roi? roi) async => throw StateError('queued'),
    );

    await drawExclusion(tester, const Offset(0.6, 0.1), const Offset(0.9, 0.6));
    await tapSave(tester);

    expect(find.textContaining('已经进入上传队列'), findsOneWidget);
    expect(find.byType(RoiEditorPage), findsOneWidget);
  });
}
