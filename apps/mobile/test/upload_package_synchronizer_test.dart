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

  test('does not delete evidence when the server rejects an upload', () async {
    final synchronizer = UploadPackageSynchronizer(
      api: _FakeUploadGateway(error: 422),
      repository: DriftOutboxRepository(database),
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

AuthState _auth(DateTime now) => AuthState(
      session: AuthSession(
          accessToken: 'access',
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
  _FakeUploadGateway({this.error});
  final int? error;
  void _throwIfRequested() {
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
    _throwIfRequested();
    return const RemoteUploadPackage(
        id: 'server-package-id',
        state: 'awaiting_blobs',
        existingAssets: <String>{});
  }

  @override
  Future<RemoteUploadPackage> package(
          {required String accessToken,
          required String serverPackageId}) async =>
      const RemoteUploadPackage(
          id: 'server-package-id',
          state: 'awaiting_blobs',
          existingAssets: <String>{});
  @override
  Future<void> putBlob(
          {required String accessToken,
          required String idempotencyKey,
          required String serverPackageId,
          required String assetId,
          required String sha256,
          required File file}) async =>
      _throwIfRequested();
  @override
  Future<void> putManifest(
          {required String accessToken,
          required String idempotencyKey,
          required String serverPackageId,
          required Map<String, dynamic> manifest}) async =>
      _throwIfRequested();
  @override
  Future<RemoteCommitResult> commit(
      {required String accessToken,
      required String idempotencyKey,
      required String serverPackageId}) async {
    _throwIfRequested();
    return const RemoteCommitResult(
        sessionId: 'session-id', inferenceJobId: 'job-id');
  }
}
