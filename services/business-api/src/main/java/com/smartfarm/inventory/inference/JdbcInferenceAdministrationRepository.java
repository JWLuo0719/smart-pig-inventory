package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcInferenceAdministrationRepository {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcInferenceAdministrationRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    public List<FailedJobRow> listFailed(UUID organizationId, Instant before, int limit) {
        return jdbc.query("""
                SELECT j.id, j.root_job_id, j.retry_of_job_id, child.id AS retried_by_job_id,
                       j.session_id, j.capture_set_id, j.status, j.retry_sequence, j.failure_code, j.failure_message,
                       j.requested_model_key, j.requested_model_version, j.requested_model_checksum,
                       j.requested_adapter_version, j.provider_key, s.status AS session_status,
                       (SELECT COUNT(*) FROM media_asset m WHERE m.capture_set_id = j.capture_set_id) AS media_count,
                       (SELECT COUNT(*) FROM media_asset m WHERE m.capture_set_id = j.capture_set_id
                          AND (m.deleted_at IS NOT NULL OR m.storage_key IS NULL)) AS unavailable_media_count,
                       j.started_at, j.finished_at, j.created_at
                FROM inference_job j
                JOIN inventory_session s ON s.id = j.session_id
                JOIN capture_set c ON c.id = j.capture_set_id
                JOIN upload_package u ON u.id = c.upload_package_id
                LEFT JOIN inference_job child ON child.retry_of_job_id = j.id
                WHERE u.organization_id = ? AND j.status = 'failed' AND j.created_at < ?
                ORDER BY j.created_at DESC, j.id DESC
                LIMIT ?
                """, this::mapFailedJob, bytes(organizationId), java.sql.Timestamp.from(before), limit);
    }

    public Optional<LockedJobRow> lockJob(UUID jobId) {
        return jdbc.query("""
                SELECT j.id, j.root_job_id, j.retry_of_job_id, j.session_id, j.capture_set_id, j.status,
                       j.retry_sequence, j.failure_code, j.failure_message, j.requested_model_key,
                       j.requested_model_version, j.requested_model_checksum, j.requested_adapter_version,
                       j.provider_key, j.correlation_id, s.status AS session_status, u.organization_id
                FROM inference_job j
                JOIN inventory_session s ON s.id = j.session_id
                JOIN capture_set c ON c.id = j.capture_set_id
                JOIN upload_package u ON u.id = c.upload_package_id
                WHERE j.id = ?
                FOR UPDATE
                """, this::mapLockedJob, bytes(jobId)).stream().findFirst();
    }

    public Optional<RetryChildRow> findRetryChild(UUID sourceJobId) {
        return jdbc.query("""
                SELECT id, root_job_id, retry_sequence, retry_idempotency_key, retry_reason, status
                FROM inference_job
                WHERE retry_of_job_id = ?
                """, (resultSet, rowNumber) -> new RetryChildRow(
                readUuid(resultSet, "id"), readUuid(resultSet, "root_job_id"),
                resultSet.getInt("retry_sequence"), resultSet.getString("retry_idempotency_key"),
                resultSet.getString("retry_reason"), resultSet.getString("status")), bytes(sourceJobId)).stream().findFirst();
    }

    public List<MediaAvailabilityRow> lockMedia(UUID captureSetId) {
        return jdbc.query("""
                SELECT id, deleted_at, storage_key
                FROM media_asset
                WHERE capture_set_id = ?
                ORDER BY id
                FOR UPDATE
                """, (resultSet, rowNumber) -> new MediaAvailabilityRow(
                readUuid(resultSet, "id"), resultSet.getTimestamp("deleted_at") != null,
                resultSet.getString("storage_key")), bytes(captureSetId));
    }

    public void insertRetryJob(UUID retryJobId, LockedJobRow source, UUID idempotencyKey, String reason,
            String actorId, String correlationId) {
        jdbc.update("""
                INSERT INTO inference_job
                  (id, root_job_id, retry_of_job_id, retry_sequence, retry_idempotency_key, retry_reason,
                   retry_requested_by, retry_requested_at, session_id, capture_set_id, status, provider_key,
                   correlation_id, requested_model_key, requested_model_version, requested_model_checksum,
                   requested_adapter_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP(6), ?, ?, 'submitted', 'unavailable', ?, ?, ?, ?, ?)
                """, bytes(retryJobId), bytes(source.rootJobId()), bytes(source.id()), source.retrySequence() + 1,
                idempotencyKey.toString(), reason, actorId, bytes(source.sessionId()), bytes(source.captureSetId()),
                correlationId, source.requestedModelKey(), source.requestedModelVersion(),
                source.requestedModelChecksum(), source.requestedAdapterVersion());
    }

    public void insertRetryOutbox(UUID eventId, UUID retryJobId, UUID sourceJobId, String correlationId, Instant occurredAt) {
        jdbc.update("""
                INSERT INTO domain_event_outbox
                  (id, aggregate_type, aggregate_id, event_type, payload_json, correlation_id)
                VALUES (?, 'inference_job', ?, 'inference_job.retry_requested.v1', CAST(? AS JSON), ?)
                """, bytes(eventId), retryJobId.toString(), json(java.util.Map.of(
                "eventVersion", 1,
                "occurredAt", occurredAt.toString(),
                "sourceInferenceJobId", sourceJobId,
                "inferenceJobId", retryJobId)), correlationId);
    }

    public void insertAudit(UUID organizationId, String actorId, UUID sourceJobId, String reason,
            Object before, Object after, String correlationId) {
        jdbc.update("""
                INSERT INTO audit_event
                  (id, organization_id, actor_id, action, target_type, target_id, reason,
                   before_json, after_json, correlation_id)
                VALUES (?, ?, ?, 'inference.retry_requested', 'inference_job', ?, ?,
                        CAST(? AS JSON), CAST(? AS JSON), ?)
                """, bytes(UUID.randomUUID()), bytes(organizationId), actorId, sourceJobId.toString(), reason,
                json(before), json(after), correlationId);
    }

    private FailedJobRow mapFailedJob(ResultSet resultSet, int rowNumber) throws SQLException {
        return new FailedJobRow(
                readUuid(resultSet, "id"), readUuid(resultSet, "root_job_id"),
                readUuid(resultSet, "retry_of_job_id"), readUuid(resultSet, "retried_by_job_id"),
                readUuid(resultSet, "session_id"), readUuid(resultSet, "capture_set_id"),
                resultSet.getString("status"), resultSet.getInt("retry_sequence"),
                resultSet.getString("failure_code"), resultSet.getString("failure_message"),
                resultSet.getString("requested_model_key"), resultSet.getString("requested_model_version"),
                resultSet.getString("requested_model_checksum"), resultSet.getString("requested_adapter_version"),
                resultSet.getString("provider_key"), resultSet.getString("session_status"),
                resultSet.getInt("media_count"), resultSet.getInt("unavailable_media_count"),
                instant(resultSet, "started_at"), instant(resultSet, "finished_at"),
                resultSet.getTimestamp("created_at").toInstant());
    }

    private LockedJobRow mapLockedJob(ResultSet resultSet, int rowNumber) throws SQLException {
        return new LockedJobRow(
                readUuid(resultSet, "id"), readUuid(resultSet, "root_job_id"),
                readUuid(resultSet, "retry_of_job_id"), readUuid(resultSet, "session_id"),
                readUuid(resultSet, "capture_set_id"), readUuid(resultSet, "organization_id"),
                resultSet.getString("status"), resultSet.getString("session_status"),
                resultSet.getInt("retry_sequence"), resultSet.getString("failure_code"),
                resultSet.getString("failure_message"), resultSet.getString("requested_model_key"),
                resultSet.getString("requested_model_version"), resultSet.getString("requested_model_checksum"),
                resultSet.getString("requested_adapter_version"), resultSet.getString("provider_key"),
                resultSet.getString("correlation_id"));
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot serialize inference retry evidence", exception);
        }
    }

    private static Instant instant(ResultSet resultSet, String column) throws SQLException {
        java.sql.Timestamp timestamp = resultSet.getTimestamp(column);
        return timestamp == null ? null : timestamp.toInstant();
    }

    private static UUID readUuid(ResultSet resultSet, String column) throws SQLException {
        byte[] value = resultSet.getBytes(column);
        return value == null ? null : new UUID(ByteBuffer.wrap(value).getLong(), ByteBuffer.wrap(value).getLong(8));
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    public record FailedJobRow(
            UUID id, UUID rootJobId, UUID retryOfJobId, UUID retriedByJobId, UUID sessionId, UUID captureSetId,
            String status, int retrySequence, String failureCode, String failureMessage, String requestedModelKey,
            String requestedModelVersion, String requestedModelChecksum, String requestedAdapterVersion,
            String providerKey, String sessionStatus, int mediaCount, int unavailableMediaCount,
            Instant startedAt, Instant finishedAt, Instant createdAt) {
    }

    public record LockedJobRow(
            UUID id, UUID rootJobId, UUID retryOfJobId, UUID sessionId, UUID captureSetId, UUID organizationId,
            String status, String sessionStatus, int retrySequence, String failureCode, String failureMessage,
            String requestedModelKey, String requestedModelVersion, String requestedModelChecksum,
            String requestedAdapterVersion, String providerKey, String correlationId) {
    }

    public record RetryChildRow(UUID id, UUID rootJobId, int retrySequence, String idempotencyKey,
            String reason, String status) {
    }

    public record MediaAvailabilityRow(UUID id, boolean deleted, String storageKey) {
    }
}
