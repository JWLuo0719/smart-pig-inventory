package com.smartfarm.inventory.masterdata.domain;

import java.util.List;
import java.util.UUID;

public record MasterDataChanges(
        String cursor,
        boolean fullResyncRequired,
        List<NamedEntity> organizations,
        List<NamedEntity> buildings,
        List<NamedEntity> pens,
        List<DeletedEntity> deletedEntities) {
    public record NamedEntity(
            UUID id,
            UUID parentId,
            String code,
            String name,
            boolean enabled,
            String erpExternalId,
            long syncVersion) {
    }

    public record DeletedEntity(String entityType, UUID id, long syncVersion) {
    }
}
