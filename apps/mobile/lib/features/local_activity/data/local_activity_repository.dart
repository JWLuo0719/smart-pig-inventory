import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/database_provider.dart';

final localActivityRepositoryProvider = Provider<LocalActivityRepository>(
  (ref) => LocalActivityRepository(ref.watch(appDatabaseProvider)),
);

class LocalCaptureActivity {
  const LocalCaptureActivity({
    required this.draftId,
    required this.penId,
    required this.buildingLabel,
    required this.penLabel,
    required this.captureKind,
    required this.draftState,
    required this.outboxState,
    required this.sessionId,
    required this.mediaCount,
    required this.totalBytes,
    required this.businessDate,
    required this.updatedAt,
  });

  final String draftId;
  final String penId;
  final String buildingLabel;
  final String penLabel;
  final String captureKind;
  final String draftState;
  final String? outboxState;
  final String? sessionId;
  final int mediaCount;
  final int totalBytes;
  final DateTime businessDate;
  final DateTime updatedAt;

  bool get isPending =>
      outboxState != null &&
      outboxState != 'synced' &&
      outboxState != 'abandoned';
}

class LocalActivityStats {
  const LocalActivityStats({
    required this.draftCount,
    required this.pendingUploadCount,
    required this.blockedUploadCount,
    required this.mediaCount,
    required this.mediaBytes,
  });

  final int draftCount;
  final int pendingUploadCount;
  final int blockedUploadCount;
  final int mediaCount;
  final int mediaBytes;
}

class LocalActivityRepository {
  LocalActivityRepository(this._database);

  final AppDatabase _database;

  Future<List<LocalMediaAsset>> mediaForDraft(
      String organizationId, String draftId) async {
    final draft = await (_database.select(_database.captureDrafts)
          ..where((row) =>
              row.id.equals(draftId) &
              row.organizationId.equals(organizationId)))
        .getSingleOrNull();
    if (draft == null) throw StateError('当前组织不可读取这份草稿。');
    return (_database.select(_database.localMediaAssets)
          ..where((row) => row.draftId.equals(draftId)))
        .get();
  }

  Stream<List<LocalCaptureActivity>> watchRecent(String organizationId,
      {int limit = 50}) {
    return _changeTrigger(organizationId)
        .asyncMap((_) => _loadRecent(organizationId, limit));
  }

  Stream<LocalActivityStats> watchStats(String organizationId) {
    return _changeTrigger(organizationId)
        .asyncMap((_) => _loadStats(organizationId));
  }

  Stream<List<QueryRow>> _changeTrigger(String organizationId) =>
      _database.customSelect(
        'SELECT d.id FROM capture_drafts d '
        'LEFT JOIN outbox_entries o ON o.draft_id = d.id '
        'LEFT JOIN local_media_assets m ON m.draft_id = d.id '
        'WHERE d.organization_id = ? GROUP BY d.id, o.updated_at, m.id',
        variables: <Variable<Object>>[Variable<String>(organizationId)],
        readsFrom: <ResultSetImplementation>{
          _database.captureDrafts,
          _database.outboxEntries,
          _database.localMediaAssets,
          _database.cachedPens,
          _database.cachedBuildings,
        },
      ).watch();

  Future<List<LocalCaptureActivity>> _loadRecent(
      String organizationId, int limit) async {
    final List<CaptureDraft> drafts = await (_database.select(
      _database.captureDrafts,
    )
          ..where(
              (CaptureDrafts row) => row.organizationId.equals(organizationId))
          ..orderBy(<OrderingTerm Function(CaptureDrafts)>[
            (CaptureDrafts row) => OrderingTerm.desc(row.updatedAt),
          ])
          ..limit(limit))
        .get();

    return Future.wait(drafts.map(_activity));
  }

  Future<LocalCaptureActivity> _activity(CaptureDraft draft) async {
    final OutboxEntry? outbox = await (_database.select(_database.outboxEntries)
          ..where((OutboxEntries row) => row.draftId.equals(draft.id)))
        .getSingleOrNull();
    final List<LocalMediaAsset> media = await (_database.select(
      _database.localMediaAssets,
    )..where((LocalMediaAssets row) => row.draftId.equals(draft.id)))
        .get();
    final CachedPen? pen = await (_database.select(_database.cachedPens)
          ..where((CachedPens row) => row.id.equals(draft.penId)))
        .getSingleOrNull();
    final CachedBuilding? building = pen == null
        ? null
        : await (_database.select(_database.cachedBuildings)
              ..where((CachedBuildings row) => row.id.equals(pen.buildingId)))
            .getSingleOrNull();

    return LocalCaptureActivity(
      draftId: draft.id,
      penId: draft.penId,
      buildingLabel:
          building == null ? '未同步栋舍' : '${building.code} ${building.name}',
      penLabel: pen == null ? draft.penId : '${pen.code}栏 · ${pen.name}',
      captureKind: draft.captureKind,
      draftState: draft.state,
      outboxState: outbox?.state,
      sessionId: outbox?.sessionId,
      mediaCount: media.length,
      totalBytes: media.fold<int>(
          0, (int total, LocalMediaAsset asset) => total + asset.byteSize),
      businessDate: draft.businessDate,
      updatedAt: draft.updatedAt,
    );
  }

  Future<LocalActivityStats> _loadStats(String organizationId) async {
    final List<CaptureDraft> drafts = await (_database.select(
      _database.captureDrafts,
    )..where((CaptureDrafts row) => row.organizationId.equals(organizationId)))
        .get();
    if (drafts.isEmpty) {
      return const LocalActivityStats(
          draftCount: 0,
          pendingUploadCount: 0,
          blockedUploadCount: 0,
          mediaCount: 0,
          mediaBytes: 0);
    }
    final Set<String> draftIds =
        drafts.map((CaptureDraft row) => row.id).toSet();
    final List<OutboxEntry> outbox =
        await _database.select(_database.outboxEntries).get();
    final List<LocalMediaAsset> media =
        await _database.select(_database.localMediaAssets).get();
    return LocalActivityStats(
      draftCount: drafts.length,
      pendingUploadCount: outbox
          .where((OutboxEntry row) =>
              draftIds.contains(row.draftId) &&
              row.state != 'synced' &&
              row.state != 'abandoned')
          .length,
      blockedUploadCount: outbox
          .where((OutboxEntry row) =>
              draftIds.contains(row.draftId) && row.state == 'blocked')
          .length,
      mediaCount: media
          .where((LocalMediaAsset row) => draftIds.contains(row.draftId))
          .length,
      mediaBytes: media
          .where((LocalMediaAsset row) => draftIds.contains(row.draftId))
          .fold<int>(
              0, (int total, LocalMediaAsset row) => total + row.byteSize),
    );
  }
}
