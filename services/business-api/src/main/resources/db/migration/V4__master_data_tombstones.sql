CREATE TABLE master_data_tombstone (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    entity_type VARCHAR(32) NOT NULL,
    entity_id BINARY(16) NOT NULL,
    sync_version BIGINT NOT NULL,
    deleted_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_tombstone_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT uk_tombstone_entity_version UNIQUE (organization_id, entity_type, entity_id, sync_version),
    CONSTRAINT ck_tombstone_entity_type CHECK (entity_type IN ('building', 'pen')),
    CONSTRAINT ck_tombstone_sync_version CHECK (sync_version >= 0),
    INDEX idx_tombstone_organization_version (organization_id, sync_version)
);
