CREATE TABLE master_data_command (
    organization_id BINARY(16) NOT NULL,
    idempotency_key BINARY(16) NOT NULL,
    actor_id VARCHAR(128) NOT NULL,
    request_json JSON NOT NULL,
    response_json JSON NOT NULL,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (organization_id, idempotency_key),
    CONSTRAINT fk_master_command_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id)
);
