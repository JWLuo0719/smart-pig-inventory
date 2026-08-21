package com.smartfarm.inventory.capture.infrastructure;

import com.smartfarm.inventory.capture.domain.CaptureKind;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfarm.inventory.capture.domain.ManifestAsset;
import com.smartfarm.inventory.capture.domain.UploadPackageState;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcUploadRepository {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcUploadRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    public boolean isEnabledPenInOrganization(UUID penId, UUID organizationId) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM pen p
                JOIN building b ON b.id = p.building_id
                WHERE p.id = ? AND p.enabled = TRUE AND b.enabled = TRUE
                  AND b.organization_id = ?
                """, Integer.class, bytes(penId), bytes(organizationId));
        return count != null && count == 1;
    }

    public Optional<StoredPackage> findById(UUID packageId) {
        return one("SELECT * FROM upload_package WHERE id = ?", bytes(packageId));
    }

    public Optional<StoredPackage> lockById(UUID packageId) {
        return one("SELECT * FROM upload_package WHERE id = ? FOR UPDATE", bytes(packageId));
    }

    public Optional<StoredPackage> findByClientPackageId(UUID organizationId, UUID clientPackageId) {
        return one("SELECT * FROM upload_package WHERE organization_id = ? AND client_package_id = ?",
                bytes(organizationId), bytes(clientPackageId));
    }

    public Optional<StoredPackage> findByCreateIdempotencyKey(UUID organizationId, UUID idempotencyKey) {
        return one("SELECT * FROM upload_package WHERE organization_id = ? AND idempotency_key = ?",
                bytes(organizationId), idempotencyKey.toString());
    }

    public void insertPackage(StoredPackage uploadPackage, UUID idempotencyKey) {
        jdbc.update("""
                INSERT INTO upload_package
                  (id, organization_id, pen_id, client_package_id, business_date, capture_kind, idempotency_key, state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, bytes(uploadPackage.id()), bytes(uploadPackage.organizationId()), bytes(uploadPackage.penId()),
                bytes(uploadPackage.clientPackageId()), uploadPackage.businessDate(), uploadPackage.captureKind().wireValue(),
                idempotencyKey.toString(), uploadPackage.state().databaseValue());
    }

    public List<UUID> existingAssetIds(UUID packageId) {
        return jdbc.query("SELECT asset_id FROM upload_blob WHERE package_id = ? AND uploaded_at IS NOT NULL",
                (resultSet, rowNumber) -> readUuid(resultSet, "asset_id"), bytes(packageId));
    }

    public Optional<StoredBlob> findBlob(UUID packageId, UUID assetId) {
        List<StoredBlob> results = jdbc.query("SELECT * FROM upload_blob WHERE package_id = ? AND asset_id = ?",
                blobRowMapper, bytes(packageId), bytes(assetId));
        return results.stream().findFirst();
    }

    public void insertBlob(UUID packageId, UUID assetId, String sha256, long byteSize, String storageKey) {
        jdbc.update("""
                INSERT INTO upload_blob (asset_id, package_id, sha256, byte_size, content_type, storage_key, uploaded_at)
                VALUES (?, ?, ?, ?, 'application/octet-stream', ?, CURRENT_TIMESTAMP(6))
                """, bytes(assetId), bytes(packageId), sha256, byteSize, storageKey);
    }

    public boolean hasExactDuplicate(UUID organizationId, String sha256) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM media_asset WHERE organization_id = ? AND sha256 = ? AND deleted_at IS NULL",
                Integer.class, bytes(organizationId), sha256);
        return count != null && count > 0;
    }

    public void storeManifest(UUID packageId, UUID idempotencyKey, String manifestJson, String manifestSha256) {
        jdbc.update("""
                UPDATE upload_package
                SET manifest_json = ?, manifest_idempotency_key = ?, manifest_sha256 = ?, state = ?
                WHERE id = ?
                """, manifestJson, idempotencyKey.toString(), manifestSha256,
                UploadPackageState.READY_TO_COMMIT.databaseValue(), bytes(packageId));
    }

    public void insertInventorySession(UUID sessionId, UUID penId, LocalDate businessDate, String actorId) {
        jdbc.update("""
                INSERT INTO inventory_session (id, pen_id, business_date, status, created_by)
                VALUES (?, ?, ?, 'submitted', ?)
                """, bytes(sessionId), bytes(penId), businessDate, actorId);
    }

    public void insertCaptureSet(UUID captureSetId, UUID sessionId, UUID packageId, CaptureKind kind) {
        jdbc.update("""
                INSERT INTO capture_set (id, session_id, upload_package_id, client_capture_id, kind)
                VALUES (?, ?, ?, ?, ?)
                """, bytes(captureSetId), bytes(sessionId), bytes(packageId), bytes(captureSetId), kind.wireValue());
    }

    public void insertMediaAsset(UUID mediaId, UUID organizationId, UUID captureSetId, ManifestAsset asset, String storageKey) {
        jdbc.update("""
                INSERT INTO media_asset
                  (id, organization_id, capture_set_id, asset_id, view_position, original_name, content_type,
                   byte_size, sha256, perceptual_hash, storage_key, roi_json, exif_json, state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON), CAST(? AS JSON), 'submitted')
                """, bytes(mediaId), bytes(organizationId), bytes(captureSetId), bytes(asset.assetId()),
                asset.viewPosition().wireValue(), asset.originalName(), asset.mediaType(), asset.byteSize(), asset.sha256(),
                asset.perceptualHash(), storageKey, json(asset.roi()), json(asset.exif()));
    }

    public void insertInferenceJob(UUID jobId, UUID sessionId, UUID captureSetId, String correlationId) {
        jdbc.update("""
                INSERT INTO inference_job (id, session_id, capture_set_id, status, provider_key, correlation_id)
                VALUES (?, ?, ?, 'submitted', 'unavailable', ?)
                """, bytes(jobId), bytes(sessionId), bytes(captureSetId), correlationId);
    }

    public void insertOutbox(UUID eventId, UUID packageId, String correlationId, String payloadJson) {
        jdbc.update("""
                INSERT INTO domain_event_outbox (id, aggregate_type, aggregate_id, event_type, payload_json, correlation_id)
                VALUES (?, 'upload_package', ?, 'capture_package.committed.v1', CAST(? AS JSON), ?)
                """, bytes(eventId), packageId.toString(), payloadJson, correlationId);
    }

    public void markCommitted(UUID packageId, UUID sessionId, UUID idempotencyKey) {
        jdbc.update("""
                UPDATE upload_package
                SET session_id = ?, state = ?, commit_idempotency_key = ?, committed_at = CURRENT_TIMESTAMP(6)
                WHERE id = ?
                """, bytes(sessionId), UploadPackageState.COMMITTED.databaseValue(), idempotencyKey.toString(), bytes(packageId));
    }

    public Optional<CommittedReferences> findCommittedReferences(UUID packageId) {
        List<CommittedReferences> results = jdbc.query("""
                SELECT p.session_id, j.id AS job_id
                FROM upload_package p
                JOIN capture_set c ON c.session_id = p.session_id AND c.upload_package_id = p.id
                JOIN inference_job j ON j.capture_set_id = c.id
                WHERE p.id = ?
                """, (resultSet, rowNumber) -> new CommittedReferences(
                readUuid(resultSet, "session_id"), readUuid(resultSet, "job_id")), bytes(packageId));
        return results.stream().findFirst();
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("Could not serialize upload metadata", exception);
        }
    }

    private Optional<StoredPackage> one(String sql, Object... args) {
        return jdbc.query(sql, packageRowMapper, args).stream().findFirst();
    }

    private final RowMapper<StoredPackage> packageRowMapper = (resultSet, rowNumber) -> new StoredPackage(
            readUuid(resultSet, "id"),
            readUuid(resultSet, "organization_id"),
            readUuid(resultSet, "pen_id"),
            readUuid(resultSet, "client_package_id"),
            resultSet.getObject("business_date", LocalDate.class),
            CaptureKind.fromWire(resultSet.getString("capture_kind")),
            UploadPackageState.fromDatabase(resultSet.getString("state")),
            resultSet.getString("manifest_json"),
            readNullableUuid(resultSet, "session_id"));

    private final RowMapper<StoredBlob> blobRowMapper = (resultSet, rowNumber) -> new StoredBlob(
            readUuid(resultSet, "asset_id"), resultSet.getString("sha256"), resultSet.getLong("byte_size"),
            resultSet.getString("storage_key"), resultSet.getTimestamp("uploaded_at") != null);

    public record StoredPackage(
            UUID id, UUID organizationId, UUID penId, UUID clientPackageId, LocalDate businessDate,
            CaptureKind captureKind, UploadPackageState state, String manifestJson, UUID sessionId) {
    }

    public record StoredBlob(UUID assetId, String sha256, long byteSize, String storageKey, boolean uploaded) {
    }

    public record CommittedReferences(UUID sessionId, UUID inferenceJobId) {
    }

    private static byte[] bytes(UUID uuid) {
        return java.nio.ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    private static UUID readUuid(ResultSet resultSet, String field) throws SQLException {
        return fromBytes(resultSet.getBytes(field));
    }

    private static UUID readNullableUuid(ResultSet resultSet, String field) throws SQLException {
        byte[] value = resultSet.getBytes(field);
        return value == null ? null : fromBytes(value);
    }

    private static UUID fromBytes(byte[] value) {
        java.nio.ByteBuffer buffer = java.nio.ByteBuffer.wrap(value);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
}
