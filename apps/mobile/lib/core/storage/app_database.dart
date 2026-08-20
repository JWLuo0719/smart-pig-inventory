import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

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
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

class OutboxEntries extends Table {
  TextColumn get packageId => text()();
  TextColumn get draftId => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get state => text().withDefault(const Constant('queued'))();
  TextColumn get manifestJson => text()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => <Column>{packageId};
}

@DriftDatabase(tables: <Type>[
  CachedOrganizations,
  CachedBuildings,
  CachedPens,
  CaptureDrafts,
  LocalMediaAssets,
  OutboxEntries,
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
  int get schemaVersion => 2;

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
