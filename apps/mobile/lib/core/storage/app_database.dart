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
            await migrator.addColumn(
                localMediaAssets, localMediaAssets.capturedAt);
            await migrator.addColumn(localMediaAssets, localMediaAssets.width);
            await migrator.addColumn(localMediaAssets, localMediaAssets.height);
            await migrator.addColumn(
                outboxEntries, outboxEntries.serverPackageId);
            await migrator.addColumn(outboxEntries, outboxEntries.sessionId);
            await migrator.addColumn(
                outboxEntries, outboxEntries.inferenceJobId);
            await migrator.addColumn(outboxEntries, outboxEntries.attemptCount);
            await migrator.addColumn(
                outboxEntries, outboxEntries.nextAttemptAt);
            await migrator.addColumn(outboxEntries, outboxEntries.leaseOwner);
            await migrator.addColumn(
                outboxEntries, outboxEntries.leaseExpiresAt);
            await migrator.createTable(uploadAssetEntries);
          }
          if (from < 4) {
            await customStatement(
              'CREATE UNIQUE INDEX uk_local_media_draft_position '
              'ON local_media_assets (draft_id, view_position)',
            );
          }
          if (from < 5) {
            await customStatement(
              'CREATE UNIQUE INDEX uk_outbox_draft ON outbox_entries (draft_id)',
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
