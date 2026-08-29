CREATE TABLE near_duplicate_review (
    id BINARY(16) PRIMARY KEY,
    organization_id BINARY(16) NOT NULL,
    session_id BINARY(16) NOT NULL,
    source_media_id BINARY(16) NOT NULL,
    candidate_media_id BINARY(16) NOT NULL,
    hamming_distance INT NOT NULL,
    state VARCHAR(32) NOT NULL DEFAULT 'open',
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    resolved_at TIMESTAMP(6),
    CONSTRAINT fk_near_duplicate_organization FOREIGN KEY (organization_id) REFERENCES farm_organization(id),
    CONSTRAINT fk_near_duplicate_session FOREIGN KEY (session_id) REFERENCES inventory_session(id),
    CONSTRAINT fk_near_duplicate_source FOREIGN KEY (source_media_id) REFERENCES media_asset(id),
    CONSTRAINT fk_near_duplicate_candidate FOREIGN KEY (candidate_media_id) REFERENCES media_asset(id),
    CONSTRAINT uk_near_duplicate_pair UNIQUE (source_media_id, candidate_media_id),
    CONSTRAINT ck_near_duplicate_distance CHECK (hamming_distance BETWEEN 0 AND 64),
    CONSTRAINT ck_near_duplicate_state CHECK (state IN ('open', 'resolved')),
    INDEX idx_near_duplicate_queue (organization_id, state, created_at)
);
