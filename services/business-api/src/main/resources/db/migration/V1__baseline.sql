CREATE TABLE farm_organization (
    id BINARY(16) PRIMARY KEY,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    erp_external_id VARCHAR(128),
    sync_version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT uk_organization_code UNIQUE (code)
);

CREATE TABLE building (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    erp_external_id VARCHAR(128),
    sync_version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_building_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT uk_building_organization_code UNIQUE (organization_id, code)
);

CREATE TABLE pen (
    id BINARY(16) PRIMARY KEY,
    building_id BINARY(16) NOT NULL,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    erp_external_id VARCHAR(128),
    sync_version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_pen_building FOREIGN KEY (building_id) REFERENCES building(id),
    CONSTRAINT uk_pen_building_code UNIQUE (building_id, code)
);

CREATE TABLE inventory_campaign (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    name VARCHAR(128) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    aggregation_method VARCHAR(32) NOT NULL DEFAULT 'ARITHMETIC_MEAN',
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_campaign_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT ck_campaign_dates CHECK (start_date <= end_date)
);

CREATE TABLE organization_membership (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    subject_id VARCHAR(128) NOT NULL,
    role_key VARCHAR(32) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_membership_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT uk_membership_subject UNIQUE (organization_id, subject_id),
    CONSTRAINT ck_membership_role CHECK (role_key IN ('OPERATOR', 'REVIEWER', 'FARM_ADMIN', 'SYSTEM_ADMIN'))
);

CREATE TABLE inventory_session (
    id BINARY(16) PRIMARY KEY,
    campaign_id BINARY(16),
    pen_id BINARY(16) NOT NULL,
    business_date DATE NOT NULL,
    status VARCHAR(32) NOT NULL,
    candidate_count INT,
    confirmed_count INT,
    raw_mean DECIMAL(12,4),
    version INT NOT NULL DEFAULT 1,
    created_by VARCHAR(128) NOT NULL,
    confirmed_by VARCHAR(128),
    confirmed_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_session_campaign FOREIGN KEY (campaign_id) REFERENCES inventory_campaign(id),
    CONSTRAINT fk_session_pen FOREIGN KEY (pen_id) REFERENCES pen(id),
    CONSTRAINT ck_session_candidate_count CHECK (candidate_count IS NULL OR candidate_count >= 0),
    CONSTRAINT ck_session_confirmed_count CHECK (confirmed_count IS NULL OR confirmed_count >= 0),
    INDEX idx_session_pen_date (pen_id, business_date, status)
);

CREATE TABLE upload_package (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    pen_id BINARY(16) NOT NULL,
    session_id BINARY(16),
    client_package_id BINARY(16) NOT NULL,
    business_date DATE NOT NULL,
    capture_kind VARCHAR(32) NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    state VARCHAR(32) NOT NULL,
    manifest_json JSON,
    committed_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_package_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT fk_package_pen FOREIGN KEY (pen_id) REFERENCES pen(id),
    CONSTRAINT fk_package_session FOREIGN KEY (session_id) REFERENCES inventory_session(id),
    CONSTRAINT uk_package_client_id UNIQUE (organization_id, client_package_id),
    CONSTRAINT uk_package_organization_idempotency UNIQUE (organization_id, idempotency_key),
    CONSTRAINT ck_package_capture_kind CHECK (capture_kind IN ('single', 'left_center_right'))
);

CREATE TABLE upload_blob (
    asset_id BINARY(16) PRIMARY KEY,
    package_id BINARY(16) NOT NULL,
    sha256 CHAR(64) NOT NULL,
    byte_size BIGINT NOT NULL,
    content_type VARCHAR(128) NOT NULL,
    storage_key VARCHAR(512),
    uploaded_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_blob_package FOREIGN KEY (package_id) REFERENCES upload_package(id),
    CONSTRAINT uk_blob_package_sha UNIQUE (package_id, sha256),
    CONSTRAINT ck_blob_size CHECK (byte_size > 0)
);

CREATE TABLE capture_set (
    id BINARY(16) PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    upload_package_id BINARY(16) NOT NULL,
    client_capture_id BINARY(16) NOT NULL,
    kind VARCHAR(32) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_capture_session FOREIGN KEY (session_id) REFERENCES inventory_session(id),
    CONSTRAINT fk_capture_package FOREIGN KEY (upload_package_id) REFERENCES upload_package(id),
    CONSTRAINT uk_capture_client_id UNIQUE (client_capture_id)
);

CREATE TABLE media_asset (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    capture_set_id BINARY(16) NOT NULL,
    asset_id BINARY(16) NOT NULL,
    view_position VARCHAR(16) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(128) NOT NULL,
    byte_size BIGINT NOT NULL,
    sha256 CHAR(64) NOT NULL,
    perceptual_hash VARCHAR(128),
    storage_key VARCHAR(512) NOT NULL,
    thumbnail_key VARCHAR(512),
    roi_json JSON,
    exif_json JSON,
    state VARCHAR(32) NOT NULL,
    duplicate_of_id BINARY(16),
    locked_at TIMESTAMP(6),
    deleted_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_media_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT fk_media_capture FOREIGN KEY (capture_set_id) REFERENCES capture_set(id),
    CONSTRAINT fk_media_blob FOREIGN KEY (asset_id) REFERENCES upload_blob(asset_id),
    CONSTRAINT fk_media_duplicate FOREIGN KEY (duplicate_of_id) REFERENCES media_asset(id),
    CONSTRAINT uk_media_organization_sha UNIQUE (organization_id, sha256),
    CONSTRAINT uk_media_capture_position UNIQUE (capture_set_id, view_position),
    INDEX idx_media_review (organization_id, state, created_at)
);

CREATE TABLE model_registry (
    id BINARY(16) PRIMARY KEY,
    model_key VARCHAR(128) NOT NULL,
    version VARCHAR(128) NOT NULL,
    checksum CHAR(64) NOT NULL,
    adapter_version VARCHAR(64) NOT NULL,
    runtime VARCHAR(64) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    metadata_json JSON,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT uk_model_identity UNIQUE (model_key, version, checksum, adapter_version)
);

CREATE TABLE inference_job (
    id BINARY(16) PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    capture_set_id BINARY(16) NOT NULL,
    model_registry_id BINARY(16),
    status VARCHAR(32) NOT NULL,
    provider_key VARCHAR(128) NOT NULL,
    attempt_count INT NOT NULL DEFAULT 0,
    correlation_id VARCHAR(128) NOT NULL,
    failure_code VARCHAR(128),
    failure_message VARCHAR(1000),
    started_at TIMESTAMP(6),
    finished_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_job_session FOREIGN KEY (session_id) REFERENCES inventory_session(id),
    CONSTRAINT fk_job_capture FOREIGN KEY (capture_set_id) REFERENCES capture_set(id),
    CONSTRAINT fk_job_model FOREIGN KEY (model_registry_id) REFERENCES model_registry(id),
    CONSTRAINT uk_job_capture UNIQUE (capture_set_id)
);

CREATE TABLE count_result (
    id BINARY(16) PRIMARY KEY,
    inference_job_id BINARY(16) NOT NULL,
    count_value INT,
    detections_json JSON,
    warnings_json JSON,
    latency_ms BIGINT,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_result_job FOREIGN KEY (inference_job_id) REFERENCES inference_job(id),
    CONSTRAINT uk_result_job UNIQUE (inference_job_id),
    CONSTRAINT ck_result_count CHECK (count_value IS NULL OR count_value >= 0)
);

CREATE TABLE audit_event (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    actor_id VARCHAR(128) NOT NULL,
    action VARCHAR(128) NOT NULL,
    target_type VARCHAR(128) NOT NULL,
    target_id VARCHAR(128) NOT NULL,
    reason VARCHAR(500),
    before_json JSON,
    after_json JSON,
    correlation_id VARCHAR(128) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_audit_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    INDEX idx_audit_target (organization_id, target_type, target_id, created_at)
);

CREATE TABLE erp_sync_log (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16),
    provider_key VARCHAR(128) NOT NULL,
    direction VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    external_reference VARCHAR(255),
    summary_json JSON,
    error_message VARCHAR(1000),
    started_at TIMESTAMP(6) NOT NULL,
    finished_at TIMESTAMP(6),
    CONSTRAINT fk_erp_log_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    INDEX idx_erp_log_status (status, started_at)
);

CREATE TABLE domain_event_outbox (
    id BINARY(16) PRIMARY KEY,
    aggregate_type VARCHAR(128) NOT NULL,
    aggregate_id VARCHAR(128) NOT NULL,
    event_type VARCHAR(128) NOT NULL,
    payload_json JSON NOT NULL,
    correlation_id VARCHAR(128) NOT NULL,
    state VARCHAR(32) NOT NULL DEFAULT 'PENDING',
    attempt_count INT NOT NULL DEFAULT 0,
    available_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    published_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    INDEX idx_outbox_dispatch (state, available_at, created_at)
);
