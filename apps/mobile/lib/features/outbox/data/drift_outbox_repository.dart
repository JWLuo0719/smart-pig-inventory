import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/media/perceptual_hasher.dart';
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

  Map<String, dynamic> get manifest {
    final result = jsonDecode(entry.manifestJson) as Map<String, dynamic>;
    // Keep persisted evidence and idempotency identities intact. Old negative
    // dHashes were rejected before storage; repair only that wire encoding.
    for (final asset in result['assets'] as List<dynamic>) {
      final value = asset['perceptualHash'];
      if (value is String) {
        asset['perceptualHash'] = PerceptualHasher.normalizeLegacyHash(value);
      }
    }
    return result;
  }
}

class DriftOutboxRepository {
  DriftOutboxRepository(this._database);
  final AppDatabase _database;

  Expression<bool> _scope(String organizationId) => _database
      .outboxEntries.draftId
      .isInQuery(_database.selectOnly(_database.captureDrafts)
        ..addColumns([_database.captureDrafts.id])
        ..where(_database.captureDrafts.organizationId.equals(organizationId)));

  Stream<List<OutboxEntry>> watch({required String organizationId}) =>
      (_database.select(_database.outboxEntries)
            ..where((row) => _scope(organizationId)))
          .watch();

  Stream<List<UploadQueueItem>> watchCards(String organizationId) => _database
      .customSelect(
        """SELECT o.*, d.business_date AS business_day, d.capture_kind,
      CASE WHEN b.id IS NULL THEN '未同步栏舍' ELSE b.code || ' / ' || p.code || ' ' || p.name END AS pen_label,
      (SELECT COUNT(*) FROM upload_asset_entries a WHERE a.package_id=o.package_id) AS total_assets,
      (SELECT COUNT(*) FROM upload_asset_entries a WHERE a.package_id=o.package_id AND a.state='uploaded') AS uploaded_assets,
      (SELECT m.materialized_path FROM local_media_assets m WHERE m.draft_id=d.id AND m.content_type LIKE 'image/%' ORDER BY m.created_at LIMIT 1) AS thumbnail
      FROM outbox_entries o JOIN capture_drafts d ON d.id=o.draft_id
      LEFT JOIN cached_pens p ON p.id=d.pen_id
      LEFT JOIN cached_buildings b ON b.id=p.building_id AND b.organization_id=d.organization_id
      WHERE d.organization_id=? ORDER BY o.updated_at DESC""",
        variables: [Variable.withString(organizationId)],
        readsFrom: {
          _database.outboxEntries,
          _database.captureDrafts,
          _database.uploadAssetEntries,
          _database.localMediaAssets,
          _database.cachedPens,
          _database.cachedBuildings
        },
      )
      .watch()
      .map((rows) => rows
          .map((row) => UploadQueueItem(
              entry: _database.outboxEntries.map(row.data),
              penLabel: row.read<String>('pen_label'),
              businessDate: DateTime.fromMillisecondsSinceEpoch(
                  row.read<int>('business_day') * 1000,
                  isUtc: true),
              captureKind: row.read<String>('capture_kind'),
              totalAssets: row.read<int>('total_assets'),
              uploadedAssets: row.read<int>('uploaded_assets'),
              thumbnail: row.readNullable<String>('thumbnail')))
          .toList());

  /// Avoid refreshing credentials from a background worker that has no work.
  /// This matters when the foreground isolate is restoring a rotated session.
  Future<bool> hasSynchronizableWork(
      {required String organizationId, required DateTime now}) async {
    final OutboxEntry? entry = await (_database.select(_database.outboxEntries)
          ..where((OutboxEntries row) =>
              _scope(organizationId) &
              row.state.isIn(<String>[
                'queued',
                'retry_wait',
                'creating_package',
                'uploading_blobs',
                'putting_manifest',
                'committing',
              ]) &
              (row.nextAttemptAt.isNull() |
                  row.nextAttemptAt.isSmallerOrEqualValue(now)) &
              (row.leaseExpiresAt.isNull() |
                  row.leaseExpiresAt.isSmallerOrEqualValue(now)))
          ..limit(1))
        .getSingleOrNull();
    return entry != null;
  }

  Future<UploadWork?> acquireNext({
    required String organizationId,
    required String owner,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 5),
  }) =>
      _database.transaction(() async {
        final List<OutboxEntry> candidates = await (_database.select(
          _database.outboxEntries,
        )
              ..where((OutboxEntries entry) =>
                  _scope(organizationId) &
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
        return _load(entry.packageId, organizationId);
      });

  Future<void> saveServerPackage(String packageId, String serverPackageId,
          {required String organizationId, required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            serverPackageId: Value<String>(serverPackageId),
            state: const Value<String>('uploading_blobs'),
            updatedAt: Value<DateTime>(now),
          ),
          organizationId: organizationId);

  Future<void> markAssetUploaded(String packageId, String assetId,
          {required String organizationId, required DateTime now}) =>
      _database.transaction(() async {
        await _load(packageId, organizationId);
        await (_database.update(_database.uploadAssetEntries)
              ..where((row) =>
                  row.packageId.equals(packageId) &
                  row.assetId.equals(assetId)))
            .write(UploadAssetEntriesCompanion(
                state: const Value('uploaded'),
                uploadedAt: Value(now),
                errorCode: const Value(null),
                updatedAt: Value(now)));
      });

  Future<void> markPhase(String packageId, String phase,
          {required String organizationId, required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: Value<String>(phase),
            updatedAt: Value<DateTime>(now),
          ),
          organizationId: organizationId);

  Future<void> retryLater(String packageId,
          {required String organizationId,
          required DateTime now,
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
          incrementAttempts: true,
          organizationId: organizationId);

  Future<void> block(String packageId,
          {required String organizationId,
          required DateTime now,
          required String safeError}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: const Value<String>('blocked'),
            error: Value<String?>(safeError),
            leaseOwner: const Value<String?>(null),
            leaseExpiresAt: const Value<DateTime?>(null),
            updatedAt: Value<DateTime>(now),
          ),
          organizationId: organizationId);

  Future<void> waitingForAuthentication(String packageId,
          {required String organizationId, required DateTime now}) =>
      _update(
          packageId,
          OutboxEntriesCompanion(
            state: const Value<String>('waiting_authentication'),
            error: const Value<String?>('需要重新登录后才能上传'),
            leaseOwner: const Value<String?>(null),
            leaseExpiresAt: const Value<DateTime?>(null),
            updatedAt: Value<DateTime>(now),
          ),
          organizationId: organizationId);

  Future<void> retryNow(String packageId,
          {required String organizationId, required DateTime now}) =>
      _database.transaction(() async {
        final work = await _load(packageId, organizationId);
        if (['synced', 'abandoned'].contains(work.entry.state) ||
            work.entry.leaseExpiresAt?.isAfter(now) == true) {
          throw StateError('当前采集包不可重试');
        }
        await _update(
            packageId,
            OutboxEntriesCompanion(
                state: const Value('queued'),
                error: const Value(null),
                nextAttemptAt: const Value(null),
                leaseOwner: const Value(null),
                leaseExpiresAt: const Value(null),
                updatedAt: Value(now)),
            organizationId: organizationId);
      });

  Future<void> retryAuthenticationWaiting(
          {required String organizationId, required DateTime now}) =>
      _database.transaction(() async {
        await (_database.update(_database.outboxEntries)
              ..where((OutboxEntries row) =>
                  row.state.equals('waiting_authentication') &
                  _scope(organizationId)))
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
          {required String organizationId,
          required String sessionId,
          required String inferenceJobId,
          required DateTime now}) =>
      _database.transaction(() async {
        final OutboxEntry entry =
            await (_database.select(_database.outboxEntries)
                  ..where((OutboxEntries row) =>
                      row.packageId.equals(packageId) & _scope(organizationId)))
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
            ),
            organizationId: organizationId);
        await (_database.update(_database.captureDrafts)
              ..where((CaptureDrafts row) => row.id.equals(entry.draftId)))
            .write(CaptureDraftsCompanion(
          state: const Value<String>('synced'),
          updatedAt: Value<DateTime>(now),
        ));
      });

  Future<UploadWork> _load(String packageId, String organizationId) async {
    final OutboxEntry entry = await (_database.select(_database.outboxEntries)
          ..where((OutboxEntries row) =>
              row.packageId.equals(packageId) & _scope(organizationId)))
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
      {required String organizationId, bool incrementAttempts = false}) async {
    if (incrementAttempts) {
      await _database.transaction(() async {
        final OutboxEntry entry =
            await (_database.select(_database.outboxEntries)
                  ..where((OutboxEntries row) =>
                      row.packageId.equals(packageId) & _scope(organizationId)))
                .getSingle();
        await (_database.update(_database.outboxEntries)
              ..where((OutboxEntries row) =>
                  row.packageId.equals(packageId) & _scope(organizationId)))
            .write(values.copyWith(
          attemptCount: Value<int>(entry.attemptCount + 1),
        ));
      });
      return;
    }
    await (_database.update(_database.outboxEntries)
          ..where((OutboxEntries row) =>
              row.packageId.equals(packageId) & _scope(organizationId)))
        .write(values);
  }
}

class UploadQueueItem {
  const UploadQueueItem(
      {required this.entry,
      required this.penLabel,
      required this.businessDate,
      required this.captureKind,
      required this.totalAssets,
      required this.uploadedAssets,
      required this.thumbnail});
  final OutboxEntry entry;
  final String penLabel;
  final DateTime businessDate;
  final String captureKind;
  final int totalAssets;
  final int uploadedAssets;
  final String? thumbnail;
}
