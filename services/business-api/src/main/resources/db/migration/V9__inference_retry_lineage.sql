ALTER TABLE inference_job
    ADD INDEX idx_job_capture (capture_set_id);

ALTER TABLE inference_job
    DROP INDEX uk_job_capture,
    ADD COLUMN root_job_id BINARY(16) NULL AFTER id,
    ADD COLUMN retry_of_job_id BINARY(16) NULL AFTER root_job_id,
    ADD COLUMN retry_sequence INT NOT NULL DEFAULT 0 AFTER retry_of_job_id,
    ADD COLUMN retry_idempotency_key CHAR(36) NULL AFTER retry_sequence,
    ADD COLUMN retry_reason VARCHAR(500) NULL AFTER retry_idempotency_key,
    ADD COLUMN retry_requested_by VARCHAR(128) NULL AFTER retry_reason,
    ADD COLUMN retry_requested_at TIMESTAMP(6) NULL AFTER retry_requested_by,
    ADD COLUMN requested_model_key VARCHAR(128) NOT NULL DEFAULT 'pending-license-review' AFTER model_registry_id,
    ADD COLUMN requested_model_version VARCHAR(128) NOT NULL DEFAULT 'unverified' AFTER requested_model_key,
    ADD COLUMN requested_model_checksum VARCHAR(128) NOT NULL DEFAULT 'unverified' AFTER requested_model_version,
    ADD COLUMN requested_adapter_version VARCHAR(64) NOT NULL DEFAULT 'http-v1' AFTER requested_model_checksum;

UPDATE inference_job
SET root_job_id = id
WHERE root_job_id IS NULL;

UPDATE inference_job j
JOIN count_result r ON r.inference_job_id = j.id
SET j.requested_model_key = r.model_key,
    j.requested_model_version = r.model_version,
    j.requested_model_checksum = r.model_checksum,
    j.requested_adapter_version = r.adapter_version;

ALTER TABLE inference_job
    MODIFY root_job_id BINARY(16) NOT NULL,
    ADD CONSTRAINT uk_job_retry_source UNIQUE (retry_of_job_id),
    ADD CONSTRAINT uk_job_capture_sequence UNIQUE (capture_set_id, retry_sequence),
    ADD INDEX idx_job_failed_created (status, created_at),
    ADD INDEX idx_job_root_sequence (root_job_id, retry_sequence);
