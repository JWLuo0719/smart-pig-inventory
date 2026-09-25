import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';

void main() {
  late Directory sandbox;
  late File databaseFile;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('app-database-migration-test');
    databaseFile = File('${sandbox.path}/legacy.sqlite');
  });

  tearDown(() async {
    try {
      await sandbox.delete(recursive: true);
    } on FileSystemException {
      // 失败用例可能仍占着数据库连接,忽略清理失败避免二次噪音。
    }
  });

  test('upgrades schema 1 to 6 without a duplicate-column crash', () async {
    await _buildLegacyDatabase(databaseFile, 1, <String>[_outboxEntriesPreV3],
        seed: <String>[
          "INSERT INTO outbox_entries (package_id, draft_id, "
              "idempotency_key, state, manifest_json, created_at, updated_at) "
              "VALUES ('legacy-package', 'legacy-draft', 'legacy-key', "
              "'queued', '{}', 1000, 1000)",
        ]);

    // 首次访问触发 1 -> 6 升级:修复前 from<3 的 addColumn 会与 from<2
    // createTable 带出的 captured_at/width/height 撞车并抛 duplicate column。
    final AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
    final OutboxEntry entry =
        await database.select(database.outboxEntries).getSingle();

    expect(entry.packageId, 'legacy-package');
    expect(entry.serverPackageId, equals(null));
    expect(entry.attemptCount, 0);
    expect(
        (await _columnNames(database, 'local_media_assets'))
            .containsAll(<String>['captured_at', 'width', 'height']),
        isTrue);
    expect(
        await _indexNames(database),
        containsAll(
            <String>['uk_local_media_draft_position', 'uk_outbox_draft']));
    expect(await _userVersion(database), 6);

    // 三列在新写入路径上可正常读写。
    await database.into(database.localMediaAssets).insert(
        LocalMediaAssetsCompanion.insert(
            id: 'asset-id',
            draftId: 'draft-id',
            viewPosition: 'single',
            materializedPath: 'evidence.jpg',
            originalName: 'evidence.jpg',
            contentType: 'image/jpeg',
            byteSize: 3,
            sha256: 'a' * 64,
            capturedAt: Value<DateTime>(DateTime.utc(2026, 1, 1)),
            width: const Value<int>(640),
            height: const Value<int>(480),
            createdAt: DateTime.utc(2026, 1, 1)));
    final LocalMediaAsset asset =
        await database.select(database.localMediaAssets).getSingle();
    expect(asset.capturedAt?.toUtc(), DateTime.utc(2026, 1, 1));
    expect(asset.width, 640);
    expect(asset.height, 480);
    await database.close();
  });

  test('upgrades schema 2 to 6 by adding the three media columns once',
      () async {
    await _buildLegacyDatabase(databaseFile, 2, <String>[
      _outboxEntriesPreV3,
      ..._masterDataTables,
      _localMediaAssetsPreV3,
    ], seed: <String>[
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('legacy-asset', 'legacy-draft', "
          "'single', 'a.jpg', 'a.jpg', 'image/jpeg', 3, 'a', 1000)",
    ]);

    final AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
    // 触发 2 -> 6 升级:这一路径必须真正把三列补出来,而不是被存在性检查跳过。
    final LocalMediaAsset legacy =
        await database.select(database.localMediaAssets).getSingle();

    expect(legacy.id, 'legacy-asset');
    expect(legacy.capturedAt, equals(null));
    expect(legacy.width, equals(null));
    expect(legacy.height, equals(null));
    expect(
        (await _columnNames(database, 'local_media_assets'))
            .containsAll(<String>['captured_at', 'width', 'height']),
        isTrue);
    expect(await _userVersion(database), 6);
    await database.close();
  });

  test('upgrades schema 3 to 6 after deduplicating dirty rows', () async {
    await _buildLegacyDatabase(databaseFile, 3, <String>[
      _outboxEntriesV3,
      ..._masterDataTables,
      _localMediaAssetsV3,
      ..._v3ExtraTables,
    ], seed: <String>[
      // (draft_id, view_position) 重复:保留 created_at 较新的一条。
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('asset-old', 'draft-1', 'left', "
          "'a.jpg', 'a.jpg', 'image/jpeg', 3, 'a', 1000)",
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('asset-new', 'draft-1', 'left', "
          "'b.jpg', 'b.jpg', 'image/jpeg', 3, 'b', 2000)",
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('asset-right', 'draft-1', 'right', "
          "'c.jpg', 'c.jpg', 'image/jpeg', 3, 'c', 1000)",
      // created_at 并列时保留 rowid 较大(后插入)的一条。
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('tie-low', 'draft-2', 'single', "
          "'d.jpg', 'd.jpg', 'image/jpeg', 3, 'd', 1000)",
      "INSERT INTO local_media_assets (id, draft_id, view_position, "
          "materialized_path, original_name, content_type, byte_size, "
          "sha256, created_at) VALUES ('tie-high', 'draft-2', 'single', "
          "'e.jpg', 'e.jpg', 'image/jpeg', 3, 'e', 1000)",
      // draft_id 重复的出站记录:同样只保留最新一条。
      "INSERT INTO outbox_entries (package_id, draft_id, idempotency_key, "
          "state, manifest_json, created_at, updated_at) VALUES "
          "('pkg-old', 'draft-1', 'key-1', 'queued', '{}', 1000, 1000)",
      "INSERT INTO outbox_entries (package_id, draft_id, idempotency_key, "
          "state, manifest_json, created_at, updated_at) VALUES "
          "('pkg-new', 'draft-1', 'key-2', 'queued', '{}', 2000, 2000)",
      "INSERT INTO outbox_entries (package_id, draft_id, idempotency_key, "
          "state, manifest_json, created_at, updated_at) VALUES "
          "('pkg-2', 'draft-2', 'key-3', 'queued', '{}', 1000, 1000)",
    ]);

    // 修复前这里会在 CREATE UNIQUE INDEX 处抛异常并钉死升级。
    final AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
    final List<LocalMediaAsset> assets =
        await database.select(database.localMediaAssets).get();
    final List<OutboxEntry> entries =
        await database.select(database.outboxEntries).get();

    expect(assets.map((LocalMediaAsset row) => row.id).toSet(),
        <String>{'asset-new', 'asset-right', 'tie-high'});
    expect(entries.map((OutboxEntry row) => row.packageId).toSet(),
        <String>{'pkg-new', 'pkg-2'});
    expect(
        await _indexNames(database),
        containsAll(
            <String>['uk_local_media_draft_position', 'uk_outbox_draft']));
    expect(await _userVersion(database), 6);
    await database.close();
  });

  test('finishes a half-done upgrade when the unique index already exists',
      () async {
    await _buildLegacyDatabase(databaseFile, 3, <String>[
      _outboxEntriesV3,
      ..._masterDataTables,
      _localMediaAssetsV3,
      ..._v3ExtraTables,
      // 模拟上次升级建完 local_media_assets 索引后、写版本号前崩溃。
      'CREATE UNIQUE INDEX uk_local_media_draft_position '
          'ON local_media_assets (draft_id, view_position)',
    ], seed: <String>[
      "INSERT INTO outbox_entries (package_id, draft_id, idempotency_key, "
          "state, manifest_json, created_at, updated_at) VALUES "
          "('pkg-old', 'draft-1', 'key-1', 'queued', '{}', 1000, 1000)",
      "INSERT INTO outbox_entries (package_id, draft_id, idempotency_key, "
          "state, manifest_json, created_at, updated_at) VALUES "
          "('pkg-new', 'draft-1', 'key-2', 'queued', '{}', 2000, 2000)",
    ]);

    final AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
    final List<OutboxEntry> entries =
        await database.select(database.outboxEntries).get();

    expect(entries.map((OutboxEntry row) => row.packageId).toSet(),
        <String>{'pkg-new'});
    expect(await _userVersion(database), 6);
    await database.close();
  });
}

/// 按历史版本手工建库的辅助连接:onCreate 只执行给定 DDL,
/// drift 会把 user_version 写成 [schemaVersion],再用 AppDatabase 打开即可触发升级。
class _LegacySchemaDatabase extends GeneratedDatabase {
  _LegacySchemaDatabase(super.executor, this._version, this._ddl);

  final int _version;
  final List<String> _ddl;

  @override
  int get schemaVersion => _version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) async {
          for (final String statement in _ddl) {
            await customStatement(statement);
          }
        },
      );

  @override
  Iterable<TableInfo> get allTables => const <TableInfo>[];
}

/// 建出 [version] 版历史库并写入脏数据;DDL 与种子数据都在同一条连接上执行,
/// 关闭后 user_version 停留在 [version],等待 AppDatabase 触发升级。
Future<void> _buildLegacyDatabase(File file, int version, List<String> ddl,
    {List<String> seed = const <String>[]}) async {
  final _LegacySchemaDatabase legacy =
      _LegacySchemaDatabase(NativeDatabase(file), version, ddl);
  await legacy.customSelect('SELECT 1').getSingle();
  for (final String statement in seed) {
    await legacy.customStatement(statement);
  }
  expect(await _userVersion(legacy), version);
  await legacy.close();
}

Future<int> _userVersion(GeneratedDatabase database) async {
  final QueryRow row =
      await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Set<String>> _columnNames(
    GeneratedDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table)').get();
  return rows.map((QueryRow row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _indexNames(GeneratedDatabase database) async {
  final List<QueryRow> rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  return rows.map((QueryRow row) => row.read<String>('name')).toSet();
}

/// schema 1/2 的出站表:还没有 v3 补进来的 7 个同步列。
const String _outboxEntriesPreV3 = '''
CREATE TABLE outbox_entries (
  package_id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'queued',
  manifest_json TEXT NOT NULL,
  error TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (package_id)
)''';

/// schema 3 的出站表:列集与当前定义一致,但还没有 draft_id 唯一索引。
const String _outboxEntriesV3 = '''
CREATE TABLE outbox_entries (
  package_id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'queued',
  manifest_json TEXT NOT NULL,
  error TEXT,
  server_package_id TEXT,
  session_id TEXT,
  inference_job_id TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at DATETIME,
  lease_owner TEXT,
  lease_expires_at DATETIME,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (package_id)
)''';

/// schema 2 的媒体表:还没有 captured_at/width/height 三列。
const String _localMediaAssetsPreV3 = '''
CREATE TABLE local_media_assets (
  id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  view_position TEXT NOT NULL,
  materialized_path TEXT NOT NULL,
  original_name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  roi_json TEXT NOT NULL DEFAULT '{}',
  exif_json TEXT NOT NULL DEFAULT '{}',
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id)
)''';

/// schema 3 的媒体表:三列已补齐,但还没有 (draft_id, view_position) 唯一索引。
const String _localMediaAssetsV3 = '''
CREATE TABLE local_media_assets (
  id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  view_position TEXT NOT NULL,
  materialized_path TEXT NOT NULL,
  original_name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  roi_json TEXT NOT NULL DEFAULT '{}',
  exif_json TEXT NOT NULL DEFAULT '{}',
  captured_at DATETIME,
  width INTEGER,
  height INTEGER,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id)
)''';

/// schema 2 起就存在的主数据与采集草稿表。
const List<String> _masterDataTables = <String>[
  '''
CREATE TABLE cached_organizations (
  id TEXT NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  sync_version INTEGER NOT NULL DEFAULT 0,
  synced_at DATETIME NOT NULL,
  PRIMARY KEY (id)
)''',
  '''
CREATE TABLE cached_buildings (
  id TEXT NOT NULL,
  organization_id TEXT NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  sync_version INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
)''',
  '''
CREATE TABLE cached_pens (
  id TEXT NOT NULL,
  building_id TEXT NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  sync_version INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
)''',
  '''
CREATE TABLE capture_drafts (
  id TEXT NOT NULL,
  organization_id TEXT NOT NULL,
  pen_id TEXT NOT NULL,
  capture_kind TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'draft',
  business_date DATETIME NOT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (id)
)''',
];

/// schema 3 新增的同步游标、采集集与分片上传进度表。
const List<String> _v3ExtraTables = <String>[
  '''
CREATE TABLE sync_cursors (
  organization_id TEXT NOT NULL,
  cursor TEXT NOT NULL,
  synced_at DATETIME NOT NULL,
  PRIMARY KEY (organization_id)
)''',
  '''
CREATE TABLE capture_sets (
  id TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id)
)''',
  '''
CREATE TABLE upload_asset_entries (
  package_id TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  uploaded_at DATETIME,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (package_id, asset_id)
)''',
];
