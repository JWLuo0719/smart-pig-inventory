ALTER TABLE inventory_session
    ADD COLUMN supersedes_session_id BINARY(16) NULL AFTER version,
    ADD COLUMN evidence_session_id BINARY(16) NULL AFTER supersedes_session_id,
    ADD COLUMN correction_idempotency_key VARCHAR(128) NULL AFTER confirmation_idempotency_key,
    ADD COLUMN correction_reason VARCHAR(500) NULL AFTER correction_idempotency_key,
    ADD COLUMN current_confirmation_marker TINYINT
        GENERATED ALWAYS AS (CASE WHEN status = 'confirmed' THEN 1 ELSE NULL END) STORED,
    ADD CONSTRAINT fk_session_supersedes FOREIGN KEY (supersedes_session_id) REFERENCES inventory_session(id),
    ADD CONSTRAINT fk_session_evidence FOREIGN KEY (evidence_session_id) REFERENCES inventory_session(id),
    ADD CONSTRAINT uk_session_supersedes UNIQUE (supersedes_session_id),
    ADD CONSTRAINT uk_session_current_confirmation
        UNIQUE (pen_id, business_date, current_confirmation_marker),
    ADD CONSTRAINT ck_session_correction_lineage CHECK (
        (supersedes_session_id IS NULL AND evidence_session_id IS NULL
            AND correction_idempotency_key IS NULL AND correction_reason IS NULL)
        OR
        (supersedes_session_id IS NOT NULL AND evidence_session_id IS NOT NULL
            AND correction_idempotency_key IS NOT NULL AND correction_reason IS NOT NULL)
    );
