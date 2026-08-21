ALTER TABLE upload_package
    ADD COLUMN manifest_idempotency_key CHAR(36) NULL AFTER manifest_json,
    ADD COLUMN manifest_sha256 CHAR(64) NULL AFTER manifest_idempotency_key,
    ADD COLUMN commit_idempotency_key CHAR(36) NULL AFTER manifest_sha256;
