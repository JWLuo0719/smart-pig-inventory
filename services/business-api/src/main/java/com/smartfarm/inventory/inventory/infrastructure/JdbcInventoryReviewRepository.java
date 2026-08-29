package com.smartfarm.inventory.inventory.infrastructure;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcInventoryReviewRepository {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcInventoryReviewRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    public Optional<SessionRow> findSession(UUID sessionId) {
        return querySession("WHERE s.id = ?", bytes(sessionId));
    }

    public List<NearDuplicateRow> listOpenNearDuplicates(UUID organizationId) {
        return jdbc.query("""
                SELECT id, organization_id, session_id, source_media_id, candidate_media_id, hamming_distance, state,
                       created_at, resolved_at, resolution_idempotency_key
                FROM near_duplicate_review
                WHERE organization_id = ? AND state = 'open'
                ORDER BY created_at
                """, this::mapNearDuplicate, bytes(organizationId));
    }

    public Optional<NearDuplicateRow> lockNearDuplicate(UUID reviewId) {
        return jdbc.query("""
                SELECT id, organization_id, session_id, source_media_id, candidate_media_id, hamming_distance, state,
                       created_at, resolved_at, resolution_idempotency_key
                FROM near_duplicate_review WHERE id = ? FOR UPDATE
                """, this::mapNearDuplicate, bytes(reviewId)).stream().findFirst();
    }

    public void resolveNearDuplicate(UUID reviewId, UUID idempotencyKey) {
        jdbc.update("""
                UPDATE near_duplicate_review
                SET state = 'resolved', resolved_at = CURRENT_TIMESTAMP(6), resolution_idempotency_key = ?
                WHERE id = ? AND state = 'open'
                """, idempotencyKey.toString(), bytes(reviewId));
    }

    public List<TaskRow> listTasks(UUID organizationId, LocalDate businessDate) {
        return jdbc.query("""
                SELECT p.id AS pen_id, b.code AS building_code, b.name AS building_name, p.code AS pen_code, p.name AS pen_name,
                       s.id AS session_id, s.status, s.confirmed_count
                FROM pen p
                JOIN building b ON b.id = p.building_id
                LEFT JOIN inventory_session s ON s.id = (
                    SELECT candidate.id FROM inventory_session candidate
                    WHERE candidate.pen_id = p.id AND candidate.business_date = ?
                    ORDER BY candidate.updated_at DESC, candidate.created_at DESC LIMIT 1
                )
                WHERE b.organization_id = ? AND b.enabled = TRUE AND p.enabled = TRUE
                ORDER BY b.code, p.code
                """, (resultSet, rowNumber) -> new TaskRow(
                readUuid(resultSet, "pen_id"), resultSet.getString("building_code"), resultSet.getString("building_name"),
                resultSet.getString("pen_code"), resultSet.getString("pen_name"), readUuid(resultSet, "session_id"),
                resultSet.getString("status"), nullableInt(resultSet, "confirmed_count")), businessDate, bytes(organizationId));
    }

    public List<DailyRecordRow> listConfirmedForDate(UUID organizationId, LocalDate businessDate) {
        return jdbc.query("""
                SELECT s.id AS session_id, p.id AS pen_id, b.code AS building_code, b.name AS building_name,
                       p.code AS pen_code, p.name AS pen_name, s.business_date, s.confirmed_count
                FROM inventory_session s
                JOIN pen p ON p.id = s.pen_id
                JOIN building b ON b.id = p.building_id
                WHERE b.organization_id = ? AND s.business_date = ? AND s.status = 'confirmed'
                ORDER BY b.code, p.code, s.confirmed_at
                """, (resultSet, rowNumber) -> new DailyRecordRow(
                readUuid(resultSet, "session_id"), readUuid(resultSet, "pen_id"), resultSet.getString("building_code"),
                resultSet.getString("building_name"), resultSet.getString("pen_code"), resultSet.getString("pen_name"),
                resultSet.getObject("business_date", LocalDate.class), resultSet.getInt("confirmed_count")),
                bytes(organizationId), businessDate);
    }

    public Optional<UUID> organizationForPen(UUID penId) {
        List<UUID> organizations = jdbc.query("""
                SELECT b.organization_id FROM pen p
                JOIN building b ON b.id = p.building_id
                WHERE p.id = ?
                """, (resultSet, rowNumber) -> readUuid(resultSet, "organization_id"), bytes(penId));
        return organizations.stream().findFirst();
    }

    public List<ConfirmedCountRow> confirmedCounts(UUID penId, LocalDate from, LocalDate to) {
        return jdbc.query("""
                SELECT business_date, confirmed_count
                FROM inventory_session
                WHERE pen_id = ? AND status = 'confirmed' AND business_date BETWEEN ? AND ?
                ORDER BY business_date, confirmed_at
                """, (resultSet, rowNumber) -> new ConfirmedCountRow(
                resultSet.getObject("business_date", LocalDate.class), resultSet.getInt("confirmed_count")),
                bytes(penId), from, to);
    }

    public Optional<SessionRow> lockSession(UUID sessionId) {
        return querySession("WHERE s.id = ? FOR UPDATE", bytes(sessionId));
    }

    public List<MediaEvidenceRow> listSessionMedia(UUID sessionId) {
        return jdbc.query("""
                SELECT m.asset_id, m.view_position, m.content_type, m.byte_size, m.state, m.locked_at, m.deleted_at,
                       m.storage_key, b.organization_id
                FROM media_asset m
                JOIN capture_set c ON c.id = m.capture_set_id
                JOIN inventory_session s ON s.id = c.session_id
                JOIN pen p ON p.id = s.pen_id
                JOIN building b ON b.id = p.building_id
                WHERE c.session_id = ?
                ORDER BY FIELD(m.view_position, 'single', 'left', 'center', 'right'), m.created_at
                """, this::mapMediaEvidence, bytes(sessionId));
    }

    public Optional<MediaEvidenceRow> findMediaEvidence(UUID assetId) {
        return jdbc.query("""
                SELECT m.asset_id, m.view_position, m.content_type, m.byte_size, m.state, m.locked_at, m.deleted_at,
                       m.storage_key, b.organization_id
                FROM media_asset m
                JOIN capture_set c ON c.id = m.capture_set_id
                JOIN inventory_session s ON s.id = c.session_id
                JOIN pen p ON p.id = s.pen_id
                JOIN building b ON b.id = p.building_id
                WHERE m.asset_id = ?
                """, this::mapMediaEvidence, bytes(assetId)).stream().findFirst();
    }

    public Optional<MediaRow> lockMediaByAssetId(UUID assetId) {
        List<MediaRow> rows = jdbc.query("""
                SELECT m.id, m.asset_id, m.locked_at, m.deleted_at, b.organization_id
                FROM media_asset m
                JOIN capture_set c ON c.id = m.capture_set_id
                JOIN inventory_session s ON s.id = c.session_id
                JOIN pen p ON p.id = s.pen_id
                JOIN building b ON b.id = p.building_id
                WHERE m.asset_id = ? FOR UPDATE
                """, (resultSet, rowNumber) -> new MediaRow(
                readUuid(resultSet, "id"), readUuid(resultSet, "asset_id"), readUuid(resultSet, "organization_id"),
                resultSet.getTimestamp("locked_at") != null, resultSet.getTimestamp("deleted_at") != null), bytes(assetId));
        return rows.stream().findFirst();
    }

    public void lockPen(UUID penId) {
        jdbc.queryForObject("SELECT id FROM pen WHERE id = ? FOR UPDATE", byte[].class, bytes(penId));
    }

    public boolean hasOtherConfirmedSession(UUID penId, LocalDate businessDate, UUID sessionId) {
        Integer matches = jdbc.queryForObject("""
                SELECT COUNT(*) FROM inventory_session
                WHERE pen_id = ? AND business_date = ? AND status = 'confirmed' AND id <> ?
                """, Integer.class, bytes(penId), businessDate, bytes(sessionId));
        return matches != null && matches > 0;
    }

    public void confirm(SessionRow session, int confirmedCount, UUID idempotencyKey, String subjectId) {
        jdbc.update("""
                UPDATE inventory_session
                SET status = 'confirmed', confirmed_count = ?, confirmed_by = ?, confirmed_at = CURRENT_TIMESTAMP(6),
                    confirmation_idempotency_key = ?
                WHERE id = ? AND status = 'review_required'
                """, confirmedCount, subjectId, idempotencyKey.toString(), bytes(session.id()));
    }

    public void lockEvidence(UUID sessionId) {
        jdbc.update("""
                UPDATE media_asset m
                JOIN capture_set c ON c.id = m.capture_set_id
                SET m.state = 'locked', m.locked_at = COALESCE(m.locked_at, CURRENT_TIMESTAMP(6))
                WHERE c.session_id = ? AND m.deleted_at IS NULL
                """, bytes(sessionId));
    }

    public void softDelete(MediaRow media, UUID idempotencyKey) {
        jdbc.update("""
                UPDATE media_asset
                SET state = 'deleted', deleted_at = CURRENT_TIMESTAMP(6), delete_idempotency_key = ?
                WHERE id = ? AND deleted_at IS NULL
                """, idempotencyKey.toString(), bytes(media.id()));
    }

    public Optional<String> findDeleteIdempotencyKey(UUID mediaId) {
        List<String> keys = jdbc.query("SELECT delete_idempotency_key FROM media_asset WHERE id = ?",
                (resultSet, rowNumber) -> resultSet.getString("delete_idempotency_key"), bytes(mediaId));
        return keys.stream().findFirst();
    }

    public List<AuditEventRow> listAuditEvents(UUID organizationId, Instant before, int limit) {
        return jdbc.query("""
                SELECT id, actor_id, action, target_type, target_id, reason, before_json, after_json, correlation_id, created_at
                FROM audit_event
                WHERE organization_id = ? AND created_at < ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """, (resultSet, rowNumber) -> new AuditEventRow(
                readUuid(resultSet, "id"), resultSet.getString("actor_id"), resultSet.getString("action"),
                resultSet.getString("target_type"), resultSet.getString("target_id"), resultSet.getString("reason"),
                jsonValue(resultSet.getString("before_json")), jsonValue(resultSet.getString("after_json")),
                resultSet.getString("correlation_id"), resultSet.getTimestamp("created_at").toInstant()),
                bytes(organizationId), java.sql.Timestamp.from(before), limit);
    }

    public void insertAudit(UUID organizationId, String actorId, String action, String targetType, UUID targetId,
            String reason, Object before, Object after, String correlationId) {
        jdbc.update("""
                INSERT INTO audit_event
                  (id, organization_id, actor_id, action, target_type, target_id, reason, before_json, after_json, correlation_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON), CAST(? AS JSON), ?)
                """, bytes(UUID.randomUUID()), bytes(organizationId), actorId, action, targetType, targetId.toString(), reason,
                json(before), json(after), correlationId);
    }

    private Optional<SessionRow> querySession(String predicate, Object... args) {
        List<SessionRow> rows = jdbc.query("""
                SELECT s.id, s.pen_id, b.organization_id, s.business_date, s.status, s.candidate_count, s.confirmed_count,
                       s.confirmation_idempotency_key, r.model_key, r.model_version, r.model_checksum, r.adapter_version,
                       r.inference_source, r.warnings_json
                FROM inventory_session s
                JOIN pen p ON p.id = s.pen_id
                JOIN building b ON b.id = p.building_id
                LEFT JOIN inference_job j ON j.session_id = s.id
                LEFT JOIN count_result r ON r.inference_job_id = j.id
                %s
                """.formatted(predicate), (resultSet, rowNumber) -> new SessionRow(
                readUuid(resultSet, "id"), readUuid(resultSet, "pen_id"), readUuid(resultSet, "organization_id"),
                resultSet.getObject("business_date", LocalDate.class), resultSet.getString("status"),
                nullableInt(resultSet, "candidate_count"), nullableInt(resultSet, "confirmed_count"),
                resultSet.getString("confirmation_idempotency_key"), resultSet.getString("model_key"),
                resultSet.getString("model_version"), resultSet.getString("model_checksum"), resultSet.getString("adapter_version"),
                resultSet.getString("inference_source"), stringList(resultSet.getString("warnings_json"))), args);
        return rows.stream().findFirst();
    }

    private NearDuplicateRow mapNearDuplicate(ResultSet resultSet, int rowNumber) throws SQLException {
        java.sql.Timestamp resolvedAt = resultSet.getTimestamp("resolved_at");
        return new NearDuplicateRow(readUuid(resultSet, "id"), readUuid(resultSet, "organization_id"),
                readUuid(resultSet, "session_id"), readUuid(resultSet, "source_media_id"),
                readUuid(resultSet, "candidate_media_id"), resultSet.getInt("hamming_distance"), resultSet.getString("state"),
                resultSet.getTimestamp("created_at").toInstant(), resolvedAt == null ? null : resolvedAt.toInstant(),
                resultSet.getString("resolution_idempotency_key"));
    }

    private MediaEvidenceRow mapMediaEvidence(ResultSet resultSet, int rowNumber) throws SQLException {
        return new MediaEvidenceRow(readUuid(resultSet, "asset_id"), resultSet.getString("view_position"),
                resultSet.getString("content_type"), resultSet.getLong("byte_size"), resultSet.getString("state"),
                resultSet.getTimestamp("locked_at") != null, resultSet.getTimestamp("deleted_at") != null,
                resultSet.getString("storage_key"), readUuid(resultSet, "organization_id"));
    }

    private Object jsonValue(String value) {
        if (value == null) return null;
        try {
            return objectMapper.readValue(value, Object.class);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot read persisted audit JSON", exception);
        }
    }

    private List<String> stringList(String value) {
        if (value == null) return List.of();
        try {
            return objectMapper.readValue(value, new TypeReference<>() { });
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot read persisted inference warnings", exception);
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot serialize audit event", exception);
        }
    }

    private static Integer nullableInt(ResultSet resultSet, String column) throws SQLException {
        int value = resultSet.getInt(column);
        return resultSet.wasNull() ? null : value;
    }

    private static UUID readUuid(ResultSet resultSet, String column) throws SQLException {
        byte[] value = resultSet.getBytes(column);
        return value == null ? null : new UUID(ByteBuffer.wrap(value).getLong(), ByteBuffer.wrap(value).getLong(8));
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    public record NearDuplicateRow(UUID id, UUID organizationId, UUID sessionId, UUID sourceMediaId,
            UUID candidateMediaId, int hammingDistance, String state, Instant createdAt, Instant resolvedAt,
            String resolutionIdempotencyKey) {
    }

    public record MediaEvidenceRow(UUID assetId, String viewPosition, String contentType, long byteSize, String state,
            boolean locked, boolean deleted, String storageKey, UUID organizationId) {
    }

    public record AuditEventRow(UUID id, String actorId, String action, String targetType, String targetId,
            String reason, Object before, Object after, String correlationId, Instant createdAt) {
    }

    public record TaskRow(UUID penId, String buildingCode, String buildingName, String penCode, String penName,
            UUID sessionId, String status, Integer confirmedCount) {
    }

    public record DailyRecordRow(UUID sessionId, UUID penId, String buildingCode, String buildingName, String penCode,
            String penName, LocalDate businessDate, int confirmedCount) {
    }

    public record ConfirmedCountRow(LocalDate businessDate, int confirmedCount) {
    }

    public record SessionRow(UUID id, UUID penId, UUID organizationId, LocalDate businessDate, String status,
            Integer candidateCount, Integer confirmedCount, String confirmationIdempotencyKey, String modelKey,
            String modelVersion, String modelChecksum, String adapterVersion, String inferenceSource, List<String> warnings) {
    }

    public record MediaRow(UUID id, UUID assetId, UUID organizationId, boolean locked, boolean deleted) {
    }
}
