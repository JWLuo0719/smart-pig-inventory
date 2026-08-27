import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/database_provider.dart';

final outboxRepositoryProvider = Provider<DriftOutboxRepository>(
  (ref) => DriftOutboxRepository(ref.watch(appDatabaseProvider)),
);

class UploadWork {
  const UploadWork({
    required this.entry,
    required this.draft,
    required this.assets,
  });

  final OutboxEntry entry;
  final CaptureDraft draft;
  final List<LocalMediaAsset> assets;

  Map<String, dynamic> get manifest =>
      jsonDecode(entry.manifestJson) as Map<String, dynamic>;
}

class DriftOutboxRepository {
  DriftOutboxRepository(this._database);
  final AppDatabase _database;

  Stream<List<OutboxEntry>> watch() => _database.watchOutbox();

  Future<UploadWork?> acquireNext({
    required String owner,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 5),
  }) =>
      _database.transaction(() async {
        final List<OutboxEntry> candidates = await (_database.select(
          _database.outboxEntries,
        )
              ..where((OutboxEntries entry) =>
                  entry.state.isIn(<String>[
                    'queued',
                    'retry_wait',
                    'creating_package',
                    'uploading_blobs',
                    'putting_manifest',
                    'committing',
                  ]) &
                  (entry.nextAttemptAt.isNull() |
                      entry.nextAttemptAt.isSmallerOrEqualValue(now)) &
                  (entry.leaseExpiresAt.isNull() |
                      entry.leaseExpiresAt.isSmallerOrEqualValue(now)))
              ..orderBy(<OrderingTerm Function(OutboxEntries)>[
                (OutboxEntries entry) => OrderingTerm.asc(entry.createdAt),
              ])
              ..limit(1))
            .get();
        if (candidates.isEmpty) return null;
        final OutboxEntry entry = candidates.single;
        await (_database.update(_database.outboxEntries)
              ..where(
                  (OutboxEntries row) => row.packageId.equals(entry.packageId)))
            .write(OutboxEntriesCompanion(
          state: const Value<String>('creating_package'),
          leaseOwner: Value<String>(owner),
          leaseExpiresAt: Value<DateTime>(now.add(leaseDuration)),
          error: const Value<String?>(null),
          updatedAt: Value<DateTime>(now),
        ));
        return _load(entry.packageId);
      });

  Future<void> saveServerPackage(String packageId, String serverPackageId,
          {required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            serverPackageId: Value<String>(serverPackageId),
            state: const Value<String>('uploading_blobs'),
            updatedAt: Value<DateTime>(now),
          ));

  Future<void> markAssetUploaded(String packageId, String assetId,
          {required DateTime now}) =>
      (_database.update(_database.uploadAssetEntries)
            ..where((UploadAssetEntries row) =>
                row.packageId.equals(packageId) & row.assetId.equals(assetId)))
          .write(UploadAssetEntriesCompanion(
        state: const Value<String>('uploaded'),
        uploadedAt: Value<DateTime>(now),
        errorCode: const Value<String?>(null),
        updatedAt: Value<DateTime>(now),
      ));

  Future<void> markPhase(String packageId, String phase,
          {required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: Value<String>(phase),
            updatedAt: Value<DateTime>(now),
          ));

  Future<void> retryLater(String packageId,
          {required DateTime now,
          required DateTime nextAttemptAt,
          required String safeError}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: const Value<String>('retry_wait'),
            attemptCount: const Value.absent(),
            error: Value<String?>(safeError),
            nextAttemptAt: Value<DateTime>(nextAttemptAt),
            leaseOwner: const Value<String?>(null),
            leaseExpiresAt: const Value<DateTime?>(null),
            updatedAt: Value<DateTime>(now),
          ),
          incrementAttempts: true);

  Future<void> block(String packageId,
          {required DateTime now, required String safeError}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: const Value<String>('blocked'),
            error: Value<String?>(safeError),
            leaseOwner: const Value<String?>(null),
            leaseExpiresAt: const Value<DateTime?>(null),
            updatedAt: Value<DateTime>(now),
          ));

  Future<void> waitingForAuthentication(String packageId,
          {required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: const Value<String>('waiting_authentication'),
            error: const Value<String?>('需要重新登录后才能上传'),
            leaseOwner: const Value<String?>(null),
            leaseExpiresAt: const Value<DateTime?>(null),
            updatedAt: Value<DateTime>(now),
          ));

  Future<void> retryNow(String packageId, {required DateTime now}) => _update(
      packageId,
      OutboxEntriesCompanion(
        state: const Value<String>('queued'),
        error: const Value<String?>(null),
        nextAttemptAt: const Value<DateTime?>(null),
        leaseOwner: const Value<String?>(null),
        leaseExpiresAt: const Value<DateTime?>(null),
        updatedAt: Value<DateTime>(now),
      ));

  Future<void> retryAuthenticationWaiting({required DateTime now}) =>
      _database.transaction(() async {
        await (_database.update(_database.outboxEntries)
              ..where((OutboxEntries row) =>
                  row.state.equals('waiting_authentication')))
            .write(OutboxEntriesCompanion(
          state: const Value<String>('queued'),
          error: const Value<String?>(null),
          nextAttemptAt: const Value<DateTime?>(null),
          leaseOwner: const Value<String?>(null),
          leaseExpiresAt: const Value<DateTime?>(null),
          updatedAt: Value<DateTime>(now),
        ));
      });

  Future<void> markSynced(String packageId,
          {required String sessionId,
          required String inferenceJobId,
          required DateTime now}) =>
      _database.transaction(() async {
        final OutboxEntry entry = await (_database
                .select(_database.outboxEntries)
              ..where((OutboxEntries row) => row.packageId.equals(packageId)))
            .getSingle();
        await _update(
            packageId,
            OutboxEntriesCompanion(
              state: const Value<String>('synced'),
              sessionId: Value<String>(sessionId),
              inferenceJobId: Value<String>(inferenceJobId),
              error: const Value<String?>(null),
              nextAttemptAt: const Value<DateTime?>(null),
              leaseOwner: const Value<String?>(null),
              leaseExpiresAt: const Value<DateTime?>(null),
              updatedAt: Value<DateTime>(now),
            ));
        await (_database.update(_database.captureDrafts)
              ..where((CaptureDrafts row) => row.id.equals(entry.draftId)))
            .write(CaptureDraftsCompanion(
          state: const Value<String>('synced'),
          updatedAt: Value<DateTime>(now),
        ));
      });

  Future<UploadWork> _load(String packageId) async {
    final OutboxEntry entry = await (_database.select(_database.outboxEntries)
          ..where((OutboxEntries row) => row.packageId.equals(packageId)))
        .getSingle();
    final CaptureDraft draft = await (_database.select(_database.captureDrafts)
          ..where((CaptureDrafts row) => row.id.equals(entry.draftId)))
        .getSingle();
    final List<LocalMediaAsset> assets = await (_database.select(
      _database.localMediaAssets,
    )
          ..where((LocalMediaAssets row) => row.draftId.equals(entry.draftId))
          ..orderBy(<OrderingTerm Function(LocalMediaAssets)>[
            (LocalMediaAssets row) => OrderingTerm.asc(row.createdAt),
          ]))
        .get();
    return UploadWork(entry: entry, draft: draft, assets: assets);
  }

  Future<void> _update(String packageId, OutboxEntriesCompanion values,
      {bool incrementAttempts = false}) async {
    if (incrementAttempts) {
      await _database.customStatement(
        'UPDATE outbox_entries SET state = ?, error = ?, next_attempt_at = ?, '
        'lease_owner = NULL, lease_expires_at = NULL, updated_at = ?, '
        'attempt_count = attempt_count + 1 WHERE package_id = ?',
        <Object?>[
          values.state.value,
          values.error.value,
          values.nextAttemptAt.value,
          values.updatedAt.value,
          packageId,
        ],
      );
      return;
    }
    await (_database.update(_database.outboxEntries)
          ..where((OutboxEntries row) => row.packageId.equals(packageId)))
        .write(values);
  }
}
