import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/storage/app_database.dart';
import 'package:smart_pig_inventory/features/master_data/data/drift_master_data_repository.dart';
import 'package:smart_pig_inventory/features/master_data/domain/master_data_changes.dart';

void main() {
  late AppDatabase database;
  late DriftMasterDataRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftMasterDataRepository(database);
  });
  tearDown(() => database.close());

  test(
      'full sync replaces only the active organization cache and persists its cursor',
      () async {
    await repository.apply(
        'org-b',
        _changes(
            cursor: '1',
            organization: _entity('org-b', 'B'),
            building: _entity('building-b', 'B1', parentId: 'org-b'),
            pen: _entity('pen-b', 'P1', parentId: 'building-b')));
    await repository.apply(
        'org-a',
        _changes(
            cursor: '8',
            organization: _entity('org-a', 'A'),
            building: _entity('building-a', 'A1', parentId: 'org-a'),
            pen: _entity('pen-a', 'P1', parentId: 'building-a')));

    final List<PenChoice> orgAPens = await repository.watchPens('org-a').first;
    final List<PenChoice> orgBPens = await repository.watchPens('org-b').first;
    expect(orgAPens.single.penId, 'pen-a');
    expect(orgBPens.single.penId, 'pen-b');
    expect(await repository.cursor('org-a'), '8');
  });

  test(
      'incremental tombstone removes a deleted pen without replacing existing cache',
      () async {
    await repository.apply(
        'org-a',
        _changes(
            cursor: '8',
            organization: _entity('org-a', 'A'),
            building: _entity('building-a', 'A1', parentId: 'org-a'),
            pen: _entity('pen-a', 'P1', parentId: 'building-a')));
    await repository.apply(
      'org-a',
      const MasterDataChanges(
        cursor: '9',
        fullResyncRequired: false,
        organizations: <MasterDataEntity>[],
        buildings: <MasterDataEntity>[],
        pens: <MasterDataEntity>[],
        deletedEntities: <DeletedMasterDataEntity>[
          DeletedMasterDataEntity(entityType: 'pen', id: 'pen-a')
        ],
      ),
    );

    expect(await repository.watchPens('org-a').first, isEmpty);
    expect(await repository.cursor('org-a'), '9');
  });
}

MasterDataChanges _changes(
        {required String cursor,
        required MasterDataEntity organization,
        required MasterDataEntity building,
        required MasterDataEntity pen}) =>
    MasterDataChanges(
      cursor: cursor,
      fullResyncRequired: true,
      organizations: <MasterDataEntity>[organization],
      buildings: <MasterDataEntity>[building],
      pens: <MasterDataEntity>[pen],
      deletedEntities: const <DeletedMasterDataEntity>[],
    );

MasterDataEntity _entity(String id, String code, {String? parentId}) =>
    MasterDataEntity(
      id: id,
      parentId: parentId,
      code: code,
      name: code,
      enabled: true,
      syncVersion: 1,
    );
