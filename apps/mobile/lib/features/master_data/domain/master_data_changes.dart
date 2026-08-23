class MasterDataChanges {
  const MasterDataChanges({
    required this.cursor,
    required this.fullResyncRequired,
    required this.organizations,
    required this.buildings,
    required this.pens,
    required this.deletedEntities,
  });

  final String cursor;
  final bool fullResyncRequired;
  final List<MasterDataEntity> organizations;
  final List<MasterDataEntity> buildings;
  final List<MasterDataEntity> pens;
  final List<DeletedMasterDataEntity> deletedEntities;
}

class MasterDataEntity {
  const MasterDataEntity({
    required this.id,
    required this.parentId,
    required this.code,
    required this.name,
    required this.enabled,
    required this.syncVersion,
  });

  final String id;
  final String? parentId;
  final String code;
  final String name;
  final bool enabled;
  final int syncVersion;
}

class DeletedMasterDataEntity {
  const DeletedMasterDataEntity({required this.entityType, required this.id});
  final String entityType;
  final String id;
}

class PenChoice {
  const PenChoice({
    required this.organizationId,
    required this.buildingId,
    required this.buildingCode,
    required this.buildingName,
    required this.penId,
    required this.penCode,
    required this.penName,
    required this.enabled,
  });

  final String organizationId;
  final String buildingId;
  final String buildingCode;
  final String buildingName;
  final String penId;
  final String penCode;
  final String penName;
  final bool enabled;
}
