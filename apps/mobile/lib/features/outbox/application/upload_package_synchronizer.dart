import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/network/upload_api.dart';
import '../data/drift_outbox_repository.dart';

final uploadRemoteApiProvider = Provider<UploadRemoteApi>(
  (ref) => UploadRemoteApi(baseUrl: ref.watch(apiBaseUrlProvider)),
);
final uploadPackageSynchronizerProvider = Provider<UploadPackageSynchronizer>(
  (ref) => UploadPackageSynchronizer(
    api: ref.watch(uploadRemoteApiProvider),
    repository: ref.watch(outboxRepositoryProvider),
  ),
);

class UploadPackageSynchronizer {
  UploadPackageSynchronizer({
    required UploadRemoteGateway api,
    required DriftOutboxRepository repository,
    DateTime Function()? clock,
    Random? random,
  })  : _api = api,
        _repository = repository,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure();

  final UploadRemoteGateway _api;
  final DriftOutboxRepository _repository;
  final DateTime Function() _clock;
  final Random _random;

  Future<UploadSyncOutcome> syncNext(AuthState auth,
      {required String leaseOwner}) async {
    if (auth.isOffline) return UploadSyncOutcome.waitingForNetwork;
    final UploadWork? work = await _repository.acquireNext(
      owner: leaseOwner,
      now: _clock(),
    );
    if (work == null) return UploadSyncOutcome.nothingToUpload;
    try {
      await _sync(work, auth);
      return UploadSyncOutcome.synced;
    } on DioException catch (error) {
      await _handleDioFailure(work, error);
      return _outcomeFor(error);
    } on FileSystemException {
      await _repository.block(work.entry.packageId,
          now: _clock(), safeError: '本机原图不可读取，不能上传');
      return UploadSyncOutcome.blocked;
    } on FormatException {
      await _repository.block(work.entry.packageId,
          now: _clock(), safeError: '本机清单损坏，不能上传');
      return UploadSyncOutcome.blocked;
    }
  }

  Future<void> _sync(UploadWork work, AuthState auth) async {
    final String serverPackageId;
    Set<String> existingAssets;
    if (work.entry.serverPackageId == null) {
      final RemoteUploadPackage remote = await _api.createPackage(
        accessToken: auth.session.accessToken,
        idempotencyKey: work.entry.idempotencyKey,
        clientPackageId: work.entry.packageId,
        organizationId: work.draft.organizationId,
        penId: work.draft.penId,
        businessDate: work.draft.businessDate,
        captureKind: work.draft.captureKind,
      );
      serverPackageId = remote.id;
      existingAssets = remote.existingAssets;
      await _repository.saveServerPackage(work.entry.packageId, serverPackageId,
          now: _clock());
    } else {
      serverPackageId = work.entry.serverPackageId!;
      final RemoteUploadPackage remote = await _api.package(
        accessToken: auth.session.accessToken,
        serverPackageId: serverPackageId,
      );
      existingAssets = remote.existingAssets;
      await _repository.markPhase(work.entry.packageId, 'uploading_blobs',
          now: _clock());
    }

    for (final asset in work.assets) {
      if (!await File(asset.materializedPath).exists()) {
        throw FileSystemException(
            'Local evidence is missing', asset.materializedPath);
      }
      if (!existingAssets.contains(asset.id)) {
        await _api.putBlob(
          accessToken: auth.session.accessToken,
          idempotencyKey: work.entry.idempotencyKey,
          serverPackageId: serverPackageId,
          assetId: asset.id,
          sha256: asset.sha256,
          file: File(asset.materializedPath),
        );
      }
      await _repository.markAssetUploaded(work.entry.packageId, asset.id,
          now: _clock());
    }

    await _repository.markPhase(work.entry.packageId, 'putting_manifest',
        now: _clock());
    await _api.putManifest(
      accessToken: auth.session.accessToken,
      idempotencyKey: work.entry.idempotencyKey,
      serverPackageId: serverPackageId,
      manifest: work.manifest,
    );
    await _repository.markPhase(work.entry.packageId, 'committing',
        now: _clock());
    final RemoteCommitResult result = await _api.commit(
      accessToken: auth.session.accessToken,
      idempotencyKey: work.entry.idempotencyKey,
      serverPackageId: serverPackageId,
    );
    await _repository.markSynced(
      work.entry.packageId,
      sessionId: result.sessionId,
      inferenceJobId: result.inferenceJobId,
      now: _clock(),
    );
  }

  Future<void> _handleDioFailure(UploadWork work, DioException error) async {
    final int? status = error.response?.statusCode;
    if (status == 401) {
      await _repository.waitingForAuthentication(work.entry.packageId,
          now: _clock());
      return;
    }
    if (status != null && status >= 400 && status < 500) {
      await _repository.block(work.entry.packageId,
          now: _clock(), safeError: '服务器拒绝此采集包，请查看诊断信息');
      return;
    }
    final int attempt = work.entry.attemptCount + 1;
    await _repository.retryLater(
      work.entry.packageId,
      now: _clock(),
      nextAttemptAt: _clock().add(_retryDelay(attempt)),
      safeError: '网络或服务器暂时不可用，将自动重试',
    );
  }

  UploadSyncOutcome _outcomeFor(DioException error) {
    if (error.response?.statusCode == 401) {
      return UploadSyncOutcome.waitingForAuthentication;
    }
    if (error.response?.statusCode case final int status
        when status >= 400 && status < 500) {
      return UploadSyncOutcome.blocked;
    }
    return UploadSyncOutcome.retryScheduled;
  }

  Duration _retryDelay(int attempt) {
    final int cappedExponent = min(attempt, 8);
    final int baseSeconds = min(15 * (1 << cappedExponent), 15 * 60);
    final int jitterMilliseconds = _random.nextInt(5000);
    return Duration(seconds: baseSeconds, milliseconds: jitterMilliseconds);
  }
}

enum UploadSyncOutcome {
  synced,
  nothingToUpload,
  waitingForNetwork,
  waitingForAuthentication,
  retryScheduled,
  blocked,
}
