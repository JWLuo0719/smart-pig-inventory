import 'dart:async';
import 'dart:convert';
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
    reconnect: () => ref.read(authControllerProvider.notifier).reconnect(),
  ),
);

class UploadPackageSynchronizer {
  UploadPackageSynchronizer({
    required UploadRemoteGateway api,
    required DriftOutboxRepository repository,
    required Future<AuthState?> Function() reconnect,
    DateTime Function()? clock,
    Random? random,
  })  : _api = api,
        _repository = repository,
        _reconnect = reconnect,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure();

  final UploadRemoteGateway _api;
  final DriftOutboxRepository _repository;
  final Future<AuthState?> Function() _reconnect;
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
      if (error.response?.statusCode == 401) {
        final AuthState? refreshed = await _reconnect();
        if (refreshed != null && !refreshed.isOffline) {
          try {
            // Every server write has the same stable idempotency key, so replaying
            // the package after a token refresh cannot create duplicate evidence.
            await _sync(work, refreshed);
            return UploadSyncOutcome.synced;
          } on DioException catch (retryError) {
            await _handleDioFailure(work, retryError);
            return _outcomeFor(retryError);
          }
        }
      }
      await _handleDioFailure(work, error);
      return _outcomeFor(error);
    } on SocketException {
      await _handleTransientFailure(work);
      return UploadSyncOutcome.retryScheduled;
    } on HandshakeException {
      await _handleTransientFailure(work);
      return UploadSyncOutcome.retryScheduled;
    } on TimeoutException {
      await _handleTransientFailure(work);
      return UploadSyncOutcome.retryScheduled;
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

  Future<void> _handleTransientFailure(UploadWork work) =>
      _repository.retryLater(
        work.entry.packageId,
        now: _clock(),
        nextAttemptAt: _clock().add(_retryDelay(work.entry.attemptCount + 1)),
        safeError: '网络或服务器暂时不可用，将自动重试',
      );

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
    if (_isDeterministicRejection(status)) {
      await _repository.block(work.entry.packageId,
          now: _clock(), safeError: _rejectionMessage(error));
      return;
    }
    // 408/425/429 等超时、限流状态不是业务拒绝,按退避重试而不是永久封存。
    final int attempt = work.entry.attemptCount + 1;
    await _repository.retryLater(
      work.entry.packageId,
      now: _clock(),
      nextAttemptAt: _clock().add(_retryDelay(attempt)),
      safeError: '网络或服务器暂时不可用，将自动重试',
    );
  }

  /// 仅确定性业务拒绝永久封存(400/403/409/422);408/425/429 与其余状态
  /// 都是可恢复的,统一走 retryLater 退避。
  bool _isDeterministicRejection(int? status) =>
      status == 400 || status == 403 || status == 409 || status == 422;

  /// 4xx 拒绝不会再重试，把农场员能自己处理的错误码翻成可行动的提示；
  /// 其余保持通用文案。problem+json 在 Dio 里可能以 Map 或原始字符串到达。
  String _rejectionMessage(DioException error) {
    Object? data = error.response?.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = null;
      }
    }
    final String? code = data is Map ? data['code'] as String? : null;
    return switch (code) {
      'EXACT_DUPLICATE_IMAGE' =>
        '该照片已存在于本场证据库，同一张照片不会重复计数；请在复核页查看已有记录，或换一张照片拍摄。',
      'DELETED_DUPLICATE_IMAGE' => '这张照片之前上传过、后来被删除；同一张照片不能重复上传，请重新拍摄一张新照片。',
      _ => '服务器拒绝此采集包，请查看诊断信息',
    };
  }

  UploadSyncOutcome _outcomeFor(DioException error) {
    final int? status = error.response?.statusCode;
    if (status == 401) {
      return UploadSyncOutcome.waitingForAuthentication;
    }
    if (_isDeterministicRejection(status)) {
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
