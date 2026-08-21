ALTER TABLE farm_organization
    ADD COLUMN timezone_id VARCHAR(64) NOT NULL DEFAULT 'Asia/Shanghai' AFTER sync_version;

CREATE TABLE app_user (
    id BINARY(16) PRIMARY KEY,
    subject_id VARCHAR(128) NOT NULL,
    username VARCHAR(128) NOT NULL,
    display_name VARCHAR(128) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    token_version INT NOT NULL DEFAULT 0,
    last_authenticated_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT uk_app_user_subject UNIQUE (subject_id),
    CONSTRAINT uk_app_user_username UNIQUE (username),
    CONSTRAINT ck_app_user_token_version CHECK (token_version >= 0)
);

CREATE TABLE auth_refresh_session (
    id BINARY(16) PRIMARY KEY,
    user_id BINARY(16) NOT NULL,
    active_organization_id BINARY(16) NOT NULL,
    token_hash CHAR(64) NOT NULL,
    expires_at TIMESTAMP(6) NOT NULL,
    revoked_at TIMESTAMP(6),
    rotated_from_id BINARY(16),
    device_label VARCHAR(128),
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_used_at TIMESTAMP(6),
    CONSTRAINT fk_refresh_session_user FOREIGN KEY (user_id) REFERENCES app_user(id),
    CONSTRAINT fk_refresh_session_organization FOREIGN KEY (active_organization_id) REFERENCES farm_organization(id),
    CONSTRAINT fk_refresh_session_rotated_from FOREIGN KEY (rotated_from_id) REFERENCES auth_refresh_session(id),
    CONSTRAINT uk_refresh_session_token_hash UNIQUE (token_hash),
    CONSTRAINT ck_refresh_session_expiry CHECK (expires_at > created_at),
    INDEX idx_refresh_session_user_state (user_id, revoked_at, expires_at)
);
