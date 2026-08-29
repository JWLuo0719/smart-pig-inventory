import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/auth/auth_session.dart';
import 'package:smart_pig_inventory/core/network/upload_api.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/features/outbox/application/upload_package_synchronizer.dart';
import 'package:smart_pig_inventory/features/outbox/data/drift_outbox_repository.dart';

void main() {
  late AppDatabase database;
  late Directory sandbox;
  late DateTime now;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    sandbox = await Directory.systemTemp.createTemp('outbox-sync-test');
    now = DateTime.utc(2026, 8, 23, 12);
    await _insertQueuedPackage(database, sandbox, now);
  });
  tearDown(() async {
    await database.close();
    await sandbox.delete(recursive: true);
  });

  test('marks evidence synced only after a persisted commit response',
      () async {
    final synchronizer = UploadPackageSynchronizer(
      api: _FakeUploadGateway(),
      repository: DriftOutboxRepository(database),
      reconnect: () async => _auth(now),
      clock: () => now,
    );

    expect(await synchronizer.syncNext(_auth(now), leaseOwner: 'foreground'),
        UploadSyncOutcome.synced);
    final OutboxEntry outbox =
        await database.select(database.outboxEntries).getSingle();
    final CaptureDraft draft =
        await database.select(database.captureDrafts).getSingle();
    final UploadAssetEntry asset =
        await database.select(database.uploadAssetEntries).getSingle();
    expect(outbox.state, 'synced');
    expect(outbox.sessionId, 'session-id');
    expect(draft.state, 'synced');
    expect(asset.state, 'uploaded');
  });

  test(
      'resumes an interrupted intermediate state without creating a package again',
      () async {
    await (database.update(database.outboxEntries)
          ..where(
              (OutboxEntries row) => row.packageId.equals('client-package-id')))
        .write(const OutboxEntriesCompanion(
            state: Value<String>('uploading_blobs'),
            serverPackageId: Value<String>('server-package-id')));
    final gateway = _FakeUploadGateway();
    final synchronizer = UploadPackageSynchronizer(
      api: gateway,
      repository: DriftOutboxRepository(database),
      reconnect: () async => _auth(now),
      clock: () => now,
    );

    expect(await synchronizer.syncNext(_auth(now), leaseOwner: 'foreground'),
        UploadSyncOutcome.synced);
    expect(gateway.createCalls, 0);
    expect(gateway.packageCalls, 1);
    expect(gateway.uploadedAssetIds, <String>['asset-id']);
  });

  test(
      'three-view retry skips a server-confirmed blob and commits one capture set',
      () async {
    await _replaceWithThreeViewAssets(database, sandbox, now);
    final gateway =
        _FakeUploadGateway(existingAssets: const <String>{'left-id'});
    final synchronizer = UploadPackageSynchronizer(
      api: gateway,
      repository: DriftOutboxRepository(database),
      reconnect: () async => _auth(now),
      clock: () => now,
    );

    expect(await synchronizer.syncNext(_auth(now), leaseOwner: 'foreground'),
        UploadSyncOutcome.synced);
    expect(gateway.uploadedAssetIds, <String>['center-id', 'right-id']);
    expect(gateway.commitCalls, 1);
    final OutboxEntry outbox =
        await database.select(database.outboxEntries).getSingle();
    expect(outbox.state, 'synced');
  });

  test('retries an idempotent upload package after access token refresh',
      () async {
    final gateway = _FakeUploadGateway(unauthorizedOnce: true);
    int reconnects = 0;
    final synchronizer = UploadPackageSynchronizer(
      api: gateway,
      repository: DriftOutboxRepository(database),
      reconnect: () async {
        reconnects++;
        return _auth(now, accessToken: 'refreshed-access');
      },
      clock: () => now,
    );

    expect(await synchronizer.syncNext(_auth(now), leaseOwner: 'foreground'),
        UploadSyncOutcome.synced);
    expect(reconnects, 1);
    expect(
        gateway.accessTokens.take(2), <String>['access', 'refreshed-access']);
    expect((await database.select(database.outboxEntries).getSingle()).state,
        'synced');
  });

  test('does not delete evidence when the server rejects an upload', () async {
    final synchronizer = UploadPackageSynchronizer(
      api: _FakeUploadGateway(error: 422),
      repository: DriftOutboxRepository(database),
      reconnect: () async => _auth(now),
      clock: () => now,
    );

    expect(await synchronizer.syncNext(_auth(now), leaseOwner: 'foreground'),
        UploadSyncOutcome.blocked);
    final OutboxEntry outbox =
        await database.select(database.outboxEntries).getSingle();
    final LocalMediaAsset asset =
        await database.select(database.localMediaAssets).getSingle();
    expect(outbox.state, 'blocked');
    expect(await File(asset.materializedPath).exists(), isTrue);
  });
}

Future<void> _insertQueuedPackage(
    AppDatabase database, Directory sandbox, DateTime now) async {
  final File evidence = File('${sandbox.path}/evidence.jpg')
    ..writeAsBytesSync(<int>[1, 2, 3]);
  await database.into(database.captureDrafts).insert(
      CaptureDraftsCompanion.insert(
          id: 'draft-id',
          organizationId: 'org-id',
          penId: 'pen-id',
          captureKind: 'single',
          state: const Value<String>('queued'),
          businessDate: now,
          createdAt: now,
          updatedAt: now));
  await database.into(database.localMediaAssets).insert(
      LocalMediaAssetsCompanion.insert(
          id: 'asset-id',
          draftId: 'draft-id',
          viewPosition: 'single',
          materializedPath: evidence.path,
          originalName: 'evidence.jpg',
          contentType: 'image/jpeg',
          byteSize: 3,
          sha256: 'a' * 64,
          createdAt: now));
  await database.into(database.outboxEntries).insert(OutboxEntriesCompanion.insert(
      packageId: 'client-package-id',
      draftId: 'draft-id',
      idempotencyKey: 'key',
      manifestJson:
          '{"captureSetId":"set-id","captureKind":"single","penId":"pen-id","assets":[]}',
      createdAt: now,
      updatedAt: now));
  await database.into(database.uploadAssetEntries).insert(
      UploadAssetEntriesCompanion.insert(
          packageId: 'client-package-id', assetId: 'asset-id', updatedAt: now));
}

Future<void> _replaceWithThreeViewAssets(
    AppDatabase database, Directory sandbox, DateTime now) async {
  await (database.update(database.captureDrafts)
        ..where((CaptureDrafts row) => row.id.equals('draft-id')))
      .write(const CaptureDraftsCompanion(
          captureKind: Value<String>('left_center_right')));
  await database.delete(database.uploadAssetEntries).go();
  await database.delete(database.localMediaAssets).go();
  await (database.update(database.outboxEntries)
        ..where(
            (OutboxEntries row) => row.packageId.equals('client-package-id')))
      .write(const OutboxEntriesCompanion(
          manifestJson: Value<String>(
              '{"captureSetId":"set-id","captureKind":"left_center_right","penId":"pen-id","assets":[]}')));
  for (final String position in <String>['left', 'center', 'right']) {
    final String assetId = '$position-id';
    final File evidence = File('${sandbox.path}/$assetId.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    await database.into(database.localMediaAssets).insert(
        LocalMediaAssetsCompanion.insert(
            id: assetId,
            draftId: 'draft-id',
            viewPosition: position,
            materializedPath: evidence.path,
            originalName: '$assetId.jpg',
            contentType: 'image/jpeg',
            byteSize: 3,
            sha256: 'a' * 64,
            createdAt: now));
    await database.into(database.uploadAssetEntries).insert(
        UploadAssetEntriesCompanion.insert(
            packageId: 'client-package-id', assetId: assetId, updatedAt: now));
  }
}

AuthState _auth(DateTime now, {String accessToken = 'access'}) => AuthState(
      session: AuthSession(
          accessToken: accessToken,
          refreshToken: 'refresh',
          accessTokenExpiresAt: now,
          refreshTokenExpiresAt: now),
      user: AuthenticatedUser(
          subjectId: 'subject',
          displayName: 'Operator',
          activeOrganizationId: 'org-id',
          activeOrganizationCode: 'O',
          activeOrganizationName: 'Org',
          roles: const <String>['OPERATOR'],
          lastVerifiedAt: now),
      isOffline: false,
    );

class _FakeUploadGateway implements UploadRemoteGateway {
  _FakeUploadGateway({
    this.error,
    this.existingAssets = const <String>{},
    this.unauthorizedOnce = false,
  });
  final int? error;
  final Set<String> existingAssets;
  final bool unauthorizedOnce;
  final List<String> uploadedAssetIds = <String>[];
  final List<String> accessTokens = <String>[];
  bool _returnedUnauthorized = false;
  int createCalls = 0;
  int packageCalls = 0;
  int commitCalls = 0;
  void _recordAndThrowIfRequested(String accessToken) {
    accessTokens.add(accessToken);
    if (unauthorizedOnce && !_returnedUnauthorized) {
      _returnedUnauthorized = true;
      throw DioException(
          requestOptions: RequestOptions(path: '/upload'),
          response: Response<void>(
              requestOptions: RequestOptions(path: '/upload'),
              statusCode: 401));
    }
    if (error != null) {
      throw DioException(
          requestOptions: RequestOptions(path: '/upload'),
          response: Response<void>(
              requestOptions: RequestOptions(path: '/upload'),
              statusCode: error));
    }
  }

  @override
  Future<RemoteUploadPackage> createPackage(
      {required String accessToken,
      required String idempotencyKey,
      required String clientPackageId,
      required String organizationId,
      required String penId,
      required DateTime businessDate,
      required String captureKind}) async {
    _recordAndThrowIfRequested(accessToken);
    createCalls++;
    return RemoteUploadPackage(
        id: 'server-package-id',
        state: 'awaiting_blobs',
        existingAssets: existingAssets);
  }

  @override
  Future<RemoteUploadPackage> package(
      {required String accessToken, required String serverPackageId}) async {
    _recordAndThrowIfRequested(accessToken);
    packageCalls++;
    return RemoteUploadPackage(
        id: 'server-package-id',
        state: 'awaiting_blobs',
        existingAssets: existingAssets);
  }

  @override
  Future<void> putBlob(
      {required String accessToken,
      required String idempotencyKey,
      required String serverPackageId,
      required String assetId,
      required String sha256,
      required File file}) async {
    _recordAndThrowIfRequested(accessToken);
    uploadedAssetIds.add(assetId);
  }

  @override
  Future<void> putManifest(
          {required String accessToken,
          required String idempotencyKey,
          required String serverPackageId,
          required Map<String, dynamic> manifest}) async =>
      _recordAndThrowIfRequested(accessToken);
  @override
  Future<RemoteCommitResult> commit(
      {required String accessToken,
      required String idempotencyKey,
      required String serverPackageId}) async {
    _recordAndThrowIfRequested(accessToken);
    commitCalls++;
    return const RemoteCommitResult(
        sessionId: 'session-id', inferenceJobId: 'job-id');
  }
}
