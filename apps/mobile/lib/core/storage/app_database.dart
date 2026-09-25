import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class AuthContexts extends Table {
  TextColumn get subjectId => text()();
  TextColumn get displayName => text()();
  TextColumn get activeOrganizationId => text()();
  TextColumn get activeOrganizationCode => text()();
  TextColumn get activeOrganizationName => text()();
  TextColumn get rolesJson => text()();
  DateTimeColumn get lastVerifiedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{subjectId};
}

class CachedOrganizations extends Table {
  TextColumn get id => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class CachedBuildings extends Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class CachedPens extends Table {
  TextColumn get id => text()();
  TextColumn get buildingId => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class SyncCursors extends Table {
  TextColumn get organizationId => text()();
  TextColumn get cursor => text()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{organizationId};
}

class CaptureDrafts extends Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  TextColumn get penId => text()();
  TextColumn get captureKind => text()();
  TextColumn get state => text().withDefault(const Constant('draft'))();
  DateTimeColumn get businessDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class CaptureSets extends Table {
  TextColumn get id => text()();
  TextColumn get draftId => text().unique()();
  TextColumn get kind => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class LocalMediaAssets extends Table {
  TextColumn get id => text()();
  TextColumn get draftId => text()();
  TextColumn get viewPosition => text()();
  TextColumn get materializedPath => text()();
  TextColumn get originalName => text()();
  TextColumn get contentType => text()();
  IntColumn get byteSize => integer()();
  TextColumn get sha256 => text()();
  TextColumn get roiJson => text().withDefault(const Constant('{}'))();
  TextColumn get exifJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{id};

  @override
  List<Set<Column>> get uniqueKeys => <Set<Column>>[
        <Column>{draftId, viewPosition},
      ];
}

class OutboxEntries extends Table {
  TextColumn get packageId => text()();
  TextColumn get draftId => text().unique()();
  TextColumn get idempotencyKey => text()();
  TextColumn get state => text().withDefault(const Constant('queued'))();
  TextColumn get manifestJson => text()();
  TextColumn get error => text().nullable()();
  TextColumn get serverPackageId => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get inferenceJobId => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{packageId};
}

class UploadAssetEntries extends Table {
  TextColumn get packageId => text()();
  TextColumn get assetId => text()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get errorCode => text().nullable()();
  DateTimeColumn get uploadedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{packageId, assetId};
}

@DriftDatabase(tables: <Type>[
  AuthContexts,
  CachedOrganizations,
  CachedBuildings,
  CachedPens,
  SyncCursors,
  CaptureDrafts,
  CaptureSets,
  LocalMediaAssets,
  OutboxEntries,
  UploadAssetEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final File databaseFile =
        File(path.join(documents.path, 'pig_inventory.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(databaseFile));
  }

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) => migrator.createAll(),
        onUpgrade: (Migrator migrator, int from, int to) async {
          // drift 的 migrator 不查重:凡前面分支 createTable 已按当前表定义
          // 建出的列,后续 addColumn 必须先查存在性,否则 duplicate column
          // 异常会把升级钉死在启动循环里。
          Future<void> addColumnIfMissing(
              TableInfo table, GeneratedColumn column) async {
            final List<QueryRow> columns = await customSelect(
              'PRAGMA table_info(${table.actualTableName})',
            ).get();
            final bool exists = columns
                .any((QueryRow row) => row.read<String>('name') == column.name);
            if (exists) return;
            await migrator.addColumn(table, column);
          }

          if (from < 2) {
            await migrator.createTable(cachedOrganizations);
            await migrator.createTable(cachedBuildings);
            await migrator.createTable(cachedPens);
            await migrator.createTable(captureDrafts);
            await migrator.createTable(localMediaAssets);
          }
          if (from < 3) {
            await migrator.createTable(syncCursors);
            await migrator.createTable(captureSets);
            await addColumnIfMissing(
                localMediaAssets, localMediaAssets.capturedAt);
            await addColumnIfMissing(localMediaAssets, localMediaAssets.width);
            await addColumnIfMissing(localMediaAssets, localMediaAssets.height);
            await addColumnIfMissing(
                outboxEntries, outboxEntries.serverPackageId);
            await addColumnIfMissing(outboxEntries, outboxEntries.sessionId);
            await addColumnIfMissing(
                outboxEntries, outboxEntries.inferenceJobId);
            await addColumnIfMissing(outboxEntries, outboxEntries.attemptCount);
            await addColumnIfMissing(
                outboxEntries, outboxEntries.nextAttemptAt);
            await addColumnIfMissing(outboxEntries, outboxEntries.leaseOwner);
            await addColumnIfMissing(
                outboxEntries, outboxEntries.leaseExpiresAt);
            await migrator.createTable(uploadAssetEntries);
          }
          if (from < 4) {
            // 历史重复数据会让 CREATE UNIQUE INDEX 抛异常钉死升级:
            // 按 (draft_id, view_position) 只保留 created_at 最新的一条
            // (并列时保留 rowid 较大者),其余删除后再建唯一索引。
            await customStatement(
              'DELETE FROM local_media_assets WHERE EXISTS ('
              'SELECT 1 FROM local_media_assets AS newer '
              'WHERE newer.draft_id = local_media_assets.draft_id '
              'AND newer.view_position = local_media_assets.view_position '
              'AND (newer.created_at > local_media_assets.created_at '
              'OR (newer.created_at = local_media_assets.created_at '
              'AND newer.rowid > local_media_assets.rowid)))',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS uk_local_media_draft_position '
              'ON local_media_assets (draft_id, view_position)',
            );
          }
          if (from < 5) {
            // 同上:按 draft_id 只保留 created_at 最新的一条出站记录,
            // 其余删除后再建唯一索引,避免脏数据把升级钉死。
            await customStatement(
              'DELETE FROM outbox_entries WHERE EXISTS ('
              'SELECT 1 FROM outbox_entries AS newer '
              'WHERE newer.draft_id = outbox_entries.draft_id '
              'AND (newer.created_at > outbox_entries.created_at '
              'OR (newer.created_at = outbox_entries.created_at '
              'AND newer.rowid > outbox_entries.rowid)))',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS uk_outbox_draft '
              'ON outbox_entries (draft_id)',
            );
          }
          if (from < 6) {
            await migrator.createTable(authContexts);
          }
        },
      );

  Stream<List<OutboxEntry>> watchOutbox() => select(outboxEntries).watch();

  Future<void> queuePackage({
    required String packageId,
    required String draftId,
    required String idempotencyKey,
    required String manifestJson,
  }) async {
    final DateTime now = DateTime.now();
    await into(outboxEntries)
        .insertOnConflictUpdate(OutboxEntriesCompanion.insert(
      packageId: packageId,
      draftId: draftId,
      idempotencyKey: idempotencyKey,
      manifestJson: manifestJson,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> markState(String packageId, String state, {String? error}) {
    return (update(outboxEntries)
          ..where((entry) => entry.packageId.equals(packageId)))
        .write(
      OutboxEntriesCompanion(
          state: Value<String>(state),
          error: Value<String?>(error),
          updatedAt: Value<DateTime>(DateTime.now())),
    );
  }
}
