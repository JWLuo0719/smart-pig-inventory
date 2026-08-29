ALTER TABLE domain_event_outbox
    ADD COLUMN lease_until TIMESTAMP(6) NULL,
    ADD COLUMN last_error VARCHAR(1000) NULL;

ALTER TABLE count_result
    ADD COLUMN model_key VARCHAR(128) NOT NULL DEFAULT 'unavailable',
    ADD COLUMN model_version VARCHAR(128) NOT NULL DEFAULT 'unverified',
    ADD COLUMN model_checksum VARCHAR(128) NOT NULL DEFAULT 'unverified',
    ADD COLUMN adapter_version VARCHAR(64) NOT NULL DEFAULT '1',
    ADD COLUMN inference_source VARCHAR(128) NOT NULL DEFAULT 'unavailable';

CREATE TABLE inference_result_receipt (
    inference_job_id BINARY(16) PRIMARY KEY,
    payload_sha256 CHAR(64) NOT NULL,
    received_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_inference_receipt_job FOREIGN KEY (inference_job_id) REFERENCES inference_job(id)
);

CREATE INDEX idx_outbox_lease ON domain_event_outbox (state, lease_until, available_at);
