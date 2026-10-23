package com.smartfarm.inventory.inventory.thumbnail;

import java.nio.ByteBuffer;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** Small autocommit reads/CAS only: image decoding and object I/O never hold a database transaction. */
@Repository
public class JdbcThumbnailRepository {
    private final JdbcTemplate jdbc;

    public JdbcThumbnailRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public Optional<Source> find(UUID organizationId, UUID assetId) {
        return jdbc.query("""
                SELECT content_type, byte_size, sha256, storage_key, thumbnail_key
                FROM media_asset WHERE organization_id=? AND asset_id=? AND deleted_at IS NULL
                """, (rs, n) -> new Source(organizationId, assetId, rs.getString("content_type"),
                        rs.getLong("byte_size"), rs.getString("sha256"), rs.getString("storage_key"),
                        rs.getString("thumbnail_key")), bytes(organizationId), bytes(assetId)).stream().findFirst();
    }

    public boolean attach(Source source, String thumbnailKey) {
        return jdbc.update("""
                UPDATE media_asset SET thumbnail_key=?
                WHERE organization_id=? AND asset_id=? AND deleted_at IS NULL AND sha256=? AND storage_key=?
                """, thumbnailKey, bytes(source.organizationId()), bytes(source.assetId()), source.sha256(),
                source.storageKey()) == 1;
    }

    public record Source(UUID organizationId, UUID assetId, String contentType, long byteSize, String sha256,
                         String storageKey, String thumbnailKey) {}

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
