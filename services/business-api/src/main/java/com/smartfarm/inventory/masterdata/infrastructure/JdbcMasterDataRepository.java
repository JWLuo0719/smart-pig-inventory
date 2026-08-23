package com.smartfarm.inventory.masterdata.infrastructure;

import com.smartfarm.inventory.masterdata.domain.MasterDataChanges.DeletedEntity;
import com.smartfarm.inventory.masterdata.domain.MasterDataChanges.NamedEntity;
import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcMasterDataRepository {
    private final JdbcTemplate jdbc;

    public JdbcMasterDataRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public long highWatermark(UUID organizationId) {
        Long result = jdbc.queryForObject("""
                SELECT COALESCE(MAX(sync_version), 0) FROM (
                    SELECT sync_version FROM farm_organization WHERE id = ?
                    UNION ALL
                    SELECT b.sync_version FROM building b WHERE b.organization_id = ?
                    UNION ALL
                    SELECT p.sync_version FROM pen p JOIN building b ON b.id = p.building_id WHERE b.organization_id = ?
                    UNION ALL
                    SELECT sync_version FROM master_data_tombstone WHERE organization_id = ?
                ) AS versions
                """, Long.class, bytes(organizationId), bytes(organizationId), bytes(organizationId), bytes(organizationId));
        return result == null ? 0 : result;
    }

    public List<NamedEntity> organizations(UUID organizationId, Long afterVersion) {
        return jdbc.query("SELECT id, NULL AS parent_id, code, name, enabled, erp_external_id, sync_version FROM farm_organization "
                        + "WHERE id = ?" + after(afterVersion), this::mapEntity, arguments(organizationId, afterVersion));
    }

    public List<NamedEntity> buildings(UUID organizationId, Long afterVersion) {
        return jdbc.query("SELECT id, organization_id AS parent_id, code, name, enabled, erp_external_id, sync_version FROM building "
                        + "WHERE organization_id = ?" + after(afterVersion), this::mapEntity, arguments(organizationId, afterVersion));
    }

    public List<NamedEntity> pens(UUID organizationId, Long afterVersion) {
        return jdbc.query("""
                SELECT p.id, p.building_id AS parent_id, p.code, p.name, p.enabled, p.erp_external_id, p.sync_version
                FROM pen p JOIN building b ON b.id = p.building_id
                WHERE b.organization_id = ?
                """ + (afterVersion == null ? "" : " AND p.sync_version > ?"), this::mapEntity,
                arguments(organizationId, afterVersion));
    }

    public List<DeletedEntity> tombstones(UUID organizationId, Long afterVersion) {
        return jdbc.query("SELECT entity_type, entity_id, sync_version FROM master_data_tombstone WHERE organization_id = ?"
                        + after(afterVersion) + " ORDER BY sync_version, entity_type, entity_id",
                (resultSet, rowNumber) -> new DeletedEntity(resultSet.getString("entity_type"),
                        readUuid(resultSet, "entity_id"), resultSet.getLong("sync_version")),
                arguments(organizationId, afterVersion));
    }

    private String after(Long afterVersion) {
        return afterVersion == null ? "" : " AND sync_version > ?";
    }

    private Object[] arguments(UUID organizationId, Long afterVersion) {
        return afterVersion == null ? new Object[] {bytes(organizationId)} : new Object[] {bytes(organizationId), afterVersion};
    }

    private NamedEntity mapEntity(ResultSet resultSet, int rowNumber) throws SQLException {
        return new NamedEntity(readUuid(resultSet, "id"), readNullableUuid(resultSet, "parent_id"),
                resultSet.getString("code"), resultSet.getString("name"), resultSet.getBoolean("enabled"),
                resultSet.getString("erp_external_id"), resultSet.getLong("sync_version"));
    }

    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }

    private static UUID readUuid(ResultSet resultSet, String field) throws SQLException {
        return fromBytes(resultSet.getBytes(field));
    }

    private static UUID readNullableUuid(ResultSet resultSet, String field) throws SQLException {
        byte[] value = resultSet.getBytes(field);
        return value == null ? null : fromBytes(value);
    }

    private static UUID fromBytes(byte[] value) {
        ByteBuffer buffer = ByteBuffer.wrap(value);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
}
