ALTER TABLE inventory_session
    ADD COLUMN confirmation_idempotency_key CHAR(36) NULL AFTER confirmed_at,
    ADD CONSTRAINT uk_session_confirmation_idempotency UNIQUE (id, confirmation_idempotency_key);

ALTER TABLE media_asset
    ADD COLUMN delete_idempotency_key CHAR(36) NULL AFTER deleted_at,
    ADD CONSTRAINT uk_media_delete_idempotency UNIQUE (id, delete_idempotency_key);

CREATE INDEX idx_session_review_queue ON inventory_session (status, business_date, updated_at);
CREATE INDEX idx_media_asset_external_id ON media_asset (asset_id);
