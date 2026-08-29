ALTER TABLE near_duplicate_review
    ADD COLUMN resolution_idempotency_key CHAR(36) NULL AFTER resolved_at,
    ADD CONSTRAINT uk_near_duplicate_resolution_idempotency UNIQUE (id, resolution_idempotency_key);
