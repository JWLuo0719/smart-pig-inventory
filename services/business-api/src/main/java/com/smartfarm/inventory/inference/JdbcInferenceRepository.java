package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class JdbcInferenceRepository {
    private static final String COMMITTED_CAPTURE_EVENT = "capture_package.committed.v1";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final String bucket;
    private final CountingRequest.ModelIdentity requestedModel;

    public JdbcInferenceRepository(
            JdbcTemplate jdbc,
            ObjectMapper objectMapper,
            @Value("${app.object-storage.bucket}") String bucket,
            @Value("${app.inference.model-key:pending-license-review}") String modelKey,
            @Value("${app.inference.model-version:unverified}") String modelVersion,
            @Value("${app.inference.model-checksum:unverified}") String modelChecksum,
            @Value("${app.inference.adapter-version:http-v1}") String adapterVersion) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.bucket = bucket;
        this.requestedModel = new CountingRequest.ModelIdentity(modelKey, modelVersion, modelChecksum, adapterVersion);
    }

    @Transactional
    public Optional<DispatchableJob> claimNext(Duration leaseDuration) {
        jdbc.update("""
                UPDATE domain_event_outbox
                SET state = 'PENDING', lease_until = NULL
                WHERE state = 'DISPATCHING' AND lease_until < CURRENT_TIMESTAMP(6)
                """);
        List<UUID> eventIds = jdbc.query("""
                SELECT id FROM domain_event_outbox
                WHERE event_type = ? AND state = 'PENDING' AND available_at <= CURRENT_TIMESTAMP(6)
                ORDER BY created_at
                LIMIT 1 FOR UPDATE SKIP LOCKED
                """, (resultSet, rowNumber) -> readUuid(resultSet, "id"), COMMITTED_CAPTURE_EVENT);
        if (eventIds.isEmpty()) {
            return Optional.empty();
        }
        UUID eventId = eventIds.getFirst();
        jdbc.update("""
                UPDATE domain_event_outbox
                SET state = 'DISPATCHING', attempt_count = attempt_count + 1,
                    lease_until = DATE_ADD(CURRENT_TIMESTAMP(6), INTERVAL ? MICROSECOND), last_error = NULL
                WHERE id = ?
                """, leaseDuration.toMillis() * 1_000L, bytes(eventId));
        return Optional.of(loadDispatchableJob(eventId));
    }

    @Transactional
    public void markPublished(UUID eventId, UUID jobId) {
        jdbc.update("""
                UPDATE domain_event_outbox
                SET state = 'PUBLISHED', published_at = CURRENT_TIMESTAMP(6), lease_until = NULL, last_error = NULL
                WHERE id = ? AND state = 'DISPATCHING'
                """, bytes(eventId));
        jdbc.update("""
                UPDATE inference_job
                SET status = 'processing', provider_key = 'inference-api', started_at = COALESCE(started_at, CURRENT_TIMESTAMP(6))
                WHERE id = ? AND status = 'submitted'
                """, bytes(jobId));
    }

    public void markRetry(UUID eventId, int delaySeconds, String error) {
        jdbc.update("""
                UPDATE domain_event_outbox
                SET state = 'PENDING', lease_until = NULL, last_error = ?,
                    available_at = DATE_ADD(CURRENT_TIMESTAMP(6), INTERVAL ? SECOND)
                WHERE id = ? AND state = 'DISPATCHING'
                """, truncate(error, 1000), delaySeconds, bytes(eventId));
    }

    public Optional<LockedJob> lockJob(UUID jobId) {
        List<LockedJob> jobs = jdbc.query("""
                SELECT j.id AS job_id, j.status, j.session_id, c.kind AS capture_kind
                FROM inference_job j
                JOIN capture_set c ON c.id = j.capture_set_id
                WHERE j.id = ? FOR UPDATE
                """, (resultSet, rowNumber) -> new LockedJob(
                readUuid(resultSet, "job_id"), resultSet.getString("status"), readUuid(resultSet, "session_id"),
                resultSet.getString("capture_kind")), bytes(jobId));
        return jobs.stream().findFirst();
    }

    public Optional<String> findReceipt(UUID jobId) {
        List<String> receipts = jdbc.query("SELECT payload_sha256 FROM inference_result_receipt WHERE inference_job_id = ?",
                (resultSet, rowNumber) -> resultSet.getString("payload_sha256"), bytes(jobId));
        return receipts.stream().findFirst();
    }

    public void insertResult(UUID jobId, InferenceCallbackResult result) {
        jdbc.update("""
                INSERT INTO count_result (
                    id, inference_job_id, count_value, detections_json, warnings_json, latency_ms,
                    model_key, model_version, model_checksum, adapter_version, inference_source)
                VALUES (?, ?, ?, CAST(? AS JSON), CAST(? AS JSON), ?, ?, ?, ?, ?, ?)
                """, bytes(UUID.randomUUID()), bytes(jobId), result.count(), json(result.detections()), json(result.warnings()),
                result.latencyMs(), result.modelKey(), result.modelVersion(), result.modelChecksum(), result.adapterVersion(),
                result.inferenceSource());
    }

    public void insertReceipt(UUID jobId, String fingerprint) {
        jdbc.update("INSERT INTO inference_result_receipt (inference_job_id, payload_sha256) VALUES (?, ?)", bytes(jobId), fingerprint);
    }

    public void finishJob(UUID jobId, InferenceCallbackResult result) {
        jdbc.update("""
                UPDATE inference_job
                SET status = ?, provider_key = ?, failure_code = ?, failure_message = ?, finished_at = CURRENT_TIMESTAMP(6)
                WHERE id = ?
                """, result.status(), result.inferenceSource(), result.failureCode(), truncate(result.failureMessage(), 1000), bytes(jobId));
    }

    public void markSessionForReview(UUID sessionId, Integer candidateCount) {
        jdbc.update("""
                UPDATE inventory_session
                SET status = 'review_required', candidate_count = ?
                WHERE id = ?
                """, candidateCount, bytes(sessionId));
    }

    private DispatchableJob loadDispatchableJob(UUID eventId) {
        List<DispatchRow> rows = jdbc.query("""
                SELECT o.id AS event_id, j.id AS job_id, j.correlation_id, u.organization_id, c.id AS capture_set_id,
                       c.kind AS capture_kind, m.asset_id, m.view_position, m.storage_key, m.sha256, m.roi_json
                FROM domain_event_outbox o
                JOIN inference_job j ON BIN_TO_UUID(j.id) = JSON_UNQUOTE(JSON_EXTRACT(o.payload_json, '$.inferenceJobId'))
                JOIN capture_set c ON c.id = j.capture_set_id
                JOIN upload_package u ON u.id = c.upload_package_id
                JOIN media_asset m ON m.capture_set_id = c.id
                WHERE o.id = ?
                ORDER BY m.view_position
                """, (resultSet, rowNumber) -> new DispatchRow(
                readUuid(resultSet, "event_id"), readUuid(resultSet, "job_id"), resultSet.getString("correlation_id"),
                readUuid(resultSet, "organization_id"), readUuid(resultSet, "capture_set_id"), resultSet.getString("capture_kind"),
                readUuid(resultSet, "asset_id"), resultSet.getString("view_position"), resultSet.getString("storage_key"),
                resultSet.getString("sha256"), resultSet.getString("roi_json")), bytes(eventId));
        if (rows.isEmpty()) {
            throw new IllegalStateException("An inference outbox event has no committed media");
        }
        DispatchRow first = rows.getFirst();
        List<CountingRequest.MediaReference> media = new ArrayList<>();
        for (DispatchRow row : rows) {
            media.add(new CountingRequest.MediaReference(row.assetId(), row.viewPosition(), "s3://" + bucket + "/" + row.storageKey(),
                    row.sha256(), row.roiJson() == null ? null : map(row.roiJson())));
        }
        return new DispatchableJob(first.eventId(), new CountingRequest(first.jobId(), first.correlationId(), first.organizationId(),
                first.captureSetId(), first.captureKind(), List.copyOf(media), requestedModel));
    }

    private Map<String, Object> map(String value) {
        try {
            return objectMapper.readValue(value, new TypeReference<>() { });
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot read stored ROI", exception);
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Cannot serialize inference result", exception);
        }
    }

    private static UUID readUuid(ResultSet resultSet, String column) throws SQLException {
        byte[] bytes = resultSet.getBytes(column);
        return ByteBuffer.wrap(bytes).getLong() == 0 && ByteBuffer.wrap(bytes).getLong(8) == 0
                ? null
                : new UUID(ByteBuffer.wrap(bytes).getLong(), ByteBuffer.wrap(bytes).getLong(8));
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    private static String truncate(String value, int maxLength) {
        return value == null ? null : value.substring(0, Math.min(value.length(), maxLength));
    }

    public record DispatchableJob(UUID eventId, CountingRequest request) {
        public UUID jobId() { return request.jobId(); }
    }

    public record LockedJob(UUID jobId, String status, UUID sessionId, String captureKind) { }

    private record DispatchRow(
            UUID eventId, UUID jobId, String correlationId, UUID organizationId, UUID captureSetId, String captureKind,
            UUID assetId, String viewPosition, String storageKey, String sha256, String roiJson) { }
}
