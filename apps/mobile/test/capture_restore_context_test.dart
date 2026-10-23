import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:smart_pig_inventory/core/auth/auth_controller.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/core/storage/database_provider.dart';
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';
import 'package:smart_pig_inventory/features/capture/application/create_three_view_draft.dart';
import 'package:smart_pig_inventory/features/capture/capture_screen.dart';
import 'package:smart_pig_inventory/features/capture/data/drift_capture_draft_repository.dart';
import 'package:smart_pig_inventory/features/capture/domain/capture_target.dart';
import 'package:smart_pig_inventory/features/capture/roi_editor_page.dart';

import 'support/competition_auth.dart';

class _Picker extends ImagePicker {
  _Picker(this.file, {this.lost = false});
  final XFile file;
  final bool lost;
  @override
  Future<LostDataResponse> retrieveLostData() async =>
      lost ? LostDataResponse(file: file) : LostDataResponse.empty();
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      file;
}

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late File photo;
  late ProviderContainer container;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('capture-context-');
    db = AppDatabase(NativeDatabase.memory());
    photo = File('${sandbox.path}/portrait.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 120)));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await sandbox.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, {bool lost = false}) async {
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authControllerProvider.overrideWith(CompetitionAuthController.new),
      captureImagePickerProvider
          .overrideWithValue(_Picker(XFile(photo.path), lost: lost)),
      captureDocumentsDirectoryProvider.overrideWithValue(() async => sandbox),
    ]);
    await tester.runAsync(() => container.read(authControllerProvider.future));
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: CaptureScreen(
                  target: CaptureTarget(
                      organizationId: 'org-a',
                      penId: 'pen',
                      label: '合成栏',
                      businessDate: DateTime.utc(2026, 10, 23))))));
      // Let the real file existence checks finish outside the test clock.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  testWidgets(
      'fresh portrait left image opens ROI with its actual aspect ratio',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();
    await tester.ensureVisible(find.text('拍摄左侧并保存'));
    await tester.runAsync(() async {
      await tester.tap(find.text('拍摄左侧并保存'));
      for (var i = 0; i < 100; i++) {
        if ((await db.select(db.localMediaAssets).get()).isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('capture did not materialize');
    });
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('左图'));
    await tester.tap(find.text('左图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标注不计入本栏的区域'));
    await tester.pumpAndSettle();
    expect(tester.widget<RoiEditorPage>(find.byType(RoiEditorPage)).aspectRatio,
        80 / 120);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lost middle photo resumes the existing three-view draft',
      (tester) async {
    final draft = await tester.runAsync(() => CreateThreeViewDraft(
            materializer: MediaMaterializer(sandbox),
            repository: DriftCaptureDraftRepository(db))
        .execute(
            source: photo,
            originalName: 'portrait.png',
            contentType: 'image/png',
            organizationId: 'org-a',
            penId: 'pen',
            businessDate: DateTime.utc(2026, 10, 23),
            capturedAt: DateTime.utc(2026, 10, 23),
            width: 80,
            height: 120));
    await pump(tester, lost: true);
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if ((await db.select(db.localMediaAssets).get()).length == 2) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('lost middle view did not finish');
    });
    await tester.pump();
    final rows = await tester.runAsync(() => db.select(db.captureDrafts).get());
    expect(rows, hasLength(1));
    expect(rows!.single.id, draft!.draftId);
    expect(rows.single.captureKind, 'left_center_right');
    final media =
        await tester.runAsync(() => db.select(db.localMediaAssets).get());
    expect(
        media!.map((m) => m.viewPosition), unorderedEquals(['left', 'center']));
    expect(find.textContaining('当前需要：右侧'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
