import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/database_provider.dart';
import '../domain/master_data_changes.dart';

final masterDataRepositoryProvider = Provider<DriftMasterDataRepository>(
  (ref) => DriftMasterDataRepository(ref.watch(appDatabaseProvider)),
);

class DriftMasterDataRepository {
  DriftMasterDataRepository(this._database);
  final AppDatabase _database;

  Future<String?> cursor(String organizationId) async {
    final SyncCursor? value = await (_database.select(_database.syncCursors)
          ..where((SyncCursors table) =>
              table.organizationId.equals(organizationId)))
        .getSingleOrNull();
    return value?.cursor;
  }

  Future<void> apply(String organizationId, MasterDataChanges changes) =>
      _database.transaction(() async {
        if (changes.fullResyncRequired) {
          await _database.customStatement(
            'DELETE FROM cached_pens WHERE building_id IN (SELECT id FROM cached_buildings WHERE organization_id = ?)',
            <Object>[organizationId],
          );
          await (_database.delete(_database.cachedBuildings)
                ..where((CachedBuildings table) =>
                    table.organizationId.equals(organizationId)))
              .go();
          await (_database.delete(_database.cachedOrganizations)
                ..where((CachedOrganizations table) =>
                    table.id.equals(organizationId)))
              .go();
        }
        for (final MasterDataEntity organization in changes.organizations) {
          await _database
              .into(_database.cachedOrganizations)
              .insertOnConflictUpdate(CachedOrganizationsCompanion.insert(
                id: organization.id,
                code: organization.code,
                name: organization.name,
                enabled: Value<bool>(organization.enabled),
                syncVersion: Value<int>(organization.syncVersion),
                syncedAt: DateTime.now().toUtc(),
              ));
        }
        for (final MasterDataEntity building in changes.buildings) {
          await _database
              .into(_database.cachedBuildings)
              .insertOnConflictUpdate(CachedBuildingsCompanion.insert(
                id: building.id,
                organizationId: building.parentId ?? organizationId,
                code: building.code,
                name: building.name,
                enabled: Value<bool>(building.enabled),
                syncVersion: Value<int>(building.syncVersion),
              ));
        }
        for (final MasterDataEntity pen in changes.pens) {
          if (pen.parentId == null) continue;
          await _database
              .into(_database.cachedPens)
              .insertOnConflictUpdate(CachedPensCompanion.insert(
                id: pen.id,
                buildingId: pen.parentId!,
                code: pen.code,
                name: pen.name,
                enabled: Value<bool>(pen.enabled),
                syncVersion: Value<int>(pen.syncVersion),
              ));
        }
        for (final DeletedMasterDataEntity deleted in changes.deletedEntities) {
          switch (deleted.entityType) {
            case 'pen':
              await (_database.delete(_database.cachedPens)
                    ..where((CachedPens table) => table.id.equals(deleted.id)))
                  .go();
            case 'building':
              await (_database.delete(_database.cachedPens)
                    ..where((CachedPens table) =>
                        table.buildingId.equals(deleted.id)))
                  .go();
              await (_database.delete(_database.cachedBuildings)
                    ..where(
                        (CachedBuildings table) => table.id.equals(deleted.id)))
                  .go();
            case 'organization':
              await _database.customStatement(
                'DELETE FROM cached_pens WHERE building_id IN (SELECT id FROM cached_buildings WHERE organization_id = ?)',
                <Object>[deleted.id],
              );
              await (_database.delete(_database.cachedBuildings)
                    ..where((CachedBuildings table) =>
                        table.organizationId.equals(deleted.id)))
                  .go();
              await (_database.delete(_database.cachedOrganizations)
                    ..where((CachedOrganizations table) =>
                        table.id.equals(deleted.id)))
                  .go();
          }
        }
        await _database
            .into(_database.syncCursors)
            .insertOnConflictUpdate(SyncCursorsCompanion.insert(
              organizationId: organizationId,
              cursor: changes.cursor,
              syncedAt: DateTime.now().toUtc(),
            ));
      });

  Stream<List<PenChoice>> watchPens(String organizationId,
      {String query = ''}) {
    final String pattern = '%${query.trim()}%';
    final queryBuilder = _database
        .select(_database.cachedPens)
        .join(<Join<HasResultSet, dynamic>>[
      innerJoin(
          _database.cachedBuildings,
          _database.cachedBuildings.id
              .equalsExp(_database.cachedPens.buildingId)),
    ])
      ..where(_database.cachedBuildings.organizationId.equals(organizationId))
      ..where(
        _database.cachedPens.code.like(pattern) |
            _database.cachedPens.name.like(pattern) |
            _database.cachedBuildings.code.like(pattern) |
            _database.cachedBuildings.name.like(pattern),
      )
      ..orderBy(<OrderingTerm>[
        OrderingTerm.asc(_database.cachedBuildings.code),
        OrderingTerm.asc(_database.cachedPens.code),
      ]);
    return queryBuilder
        .watch()
        .map((List<TypedResult> rows) => rows.map((TypedResult row) {
              final CachedPen pen = row.readTable(_database.cachedPens);
              final CachedBuilding building =
                  row.readTable(_database.cachedBuildings);
              return PenChoice(
                organizationId: organizationId,
                buildingId: building.id,
                buildingCode: building.code,
                buildingName: building.name,
                penId: pen.id,
                penCode: pen.code,
                penName: pen.name,
                enabled: building.enabled && pen.enabled,
              );
            }).toList(growable: false));
  }

  Future<DateTime?> lastSyncedAt(String organizationId) async {
    final SyncCursor? cursor = await (_database.select(_database.syncCursors)
          ..where((SyncCursors table) =>
              table.organizationId.equals(organizationId)))
        .getSingleOrNull();
    return cursor?.syncedAt;
  }
}
