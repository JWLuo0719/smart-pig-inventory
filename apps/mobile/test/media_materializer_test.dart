import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_pig_inventory/core/storage/media_materializer.dart';

void main() {
  late Directory sandbox;
  late Directory sourceDirectory;
  late Directory appDirectory;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('media-materializer-test');
    sourceDirectory = Directory(path.join(sandbox.path, 'picker'))
      ..createSync(recursive: true);
    appDirectory = Directory(path.join(sandbox.path, 'app'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('materializes a 10MB image and hashes without changing bytes', () async {
    final File source = File(path.join(sourceDirectory.path, 'capture.jpg'));
    final List<int> block =
        List<int>.generate(1024, (int index) => index % 251);
    final IOSink writer = source.openWrite();
    for (int index = 0; index < 10 * 1024; index++) {
      writer.add(block);
    }
    await writer.close();

    final MediaMaterializer materializer = MediaMaterializer(appDirectory);
    final MaterializedMedia result = await materializer.materialize(
      source: source,
      organizationId: 'organization-1',
      draftId: 'draft-1',
      assetId: 'asset-1',
      originalName: 'capture.jpg',
    );

    expect(result.byteSize, 10 * 1024 * 1024);
    expect(
        result.sha256, (await sha256.bind(source.openRead()).first).toString());
    expect(await result.file.readAsBytes(), await source.readAsBytes());
    expect(result.file.path, contains(path.join('organization-1', 'draft-1')));
    expect(await File('${result.file.path}.partial').exists(), isFalse);
  });

  test('reuses a completed stable asset after process-restart recovery',
      () async {
    final File source = File(path.join(sourceDirectory.path, 'capture.png'))
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final MediaMaterializer materializer = MediaMaterializer(appDirectory);

    final MaterializedMedia first = await materializer.materialize(
      source: source,
      organizationId: 'organization-1',
      draftId: 'draft-1',
      assetId: 'asset-1',
      originalName: 'capture.png',
    );
    await source.delete();

    // A picker source can disappear after Android reclaims the activity. A
    // retry with the stable asset identity must recover the completed file.
    final MaterializedMedia recovered = await materializer.materialize(
      source: source,
      organizationId: 'organization-1',
      draftId: 'draft-1',
      assetId: 'asset-1',
      originalName: 'capture.png',
    );

    expect(recovered.file.path, first.file.path);
    expect(recovered.sha256, first.sha256);
    expect(await recovered.file.readAsBytes(), <int>[1, 2, 3, 4]);
  });

  test('rejects path traversal and unsupported media extensions', () async {
    final File source = File(path.join(sourceDirectory.path, 'capture.gif'))
      ..writeAsBytesSync(<int>[1]);
    final MediaMaterializer materializer = MediaMaterializer(appDirectory);

    expect(
      () => materializer.materialize(
        source: source,
        organizationId: '../other',
        draftId: 'draft-1',
        assetId: 'asset-1',
        originalName: 'capture.gif',
      ),
      throwsArgumentError,
    );
    expect(
      () => materializer.materialize(
        source: source,
        organizationId: 'organization-1',
        draftId: 'draft-1',
        assetId: 'asset-1',
        originalName: 'capture.gif',
      ),
      throwsArgumentError,
    );
  });
}
