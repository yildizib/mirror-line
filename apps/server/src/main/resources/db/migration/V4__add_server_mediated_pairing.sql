ALTER TABLE pairing_sessions
    ADD COLUMN code_hash BYTEA,
    ADD COLUMN challenge BYTEA,
    ADD COLUMN initiator_key_version INTEGER,
    ADD COLUMN initiator_key_fingerprint VARCHAR(128),
    ADD COLUMN source_user_id UUID,
    ADD COLUMN source_device_id UUID,
    ADD COLUMN source_key_version INTEGER,
    ADD COLUMN source_public_key BYTEA,
    ADD COLUMN source_key_fingerprint VARCHAR(128),
    ADD COLUMN main_proof_verified_at TIMESTAMPTZ,
    ADD COLUMN source_proof_verified_at TIMESTAMPTZ,
    ADD COLUMN main_confirmation BOOLEAN,
    ADD COLUMN source_confirmation BOOLEAN;

ALTER TABLE pairing_sessions
    ADD CONSTRAINT fk_pairing_sessions_source_device
    FOREIGN KEY (source_user_id, source_device_id)
    REFERENCES devices (user_id, device_id) ON DELETE RESTRICT;

ALTER TABLE pairing_sessions
    ADD CONSTRAINT fk_pairing_sessions_initiator_key_version
    FOREIGN KEY (initiator_user_id, initiator_device_id, initiator_key_version)
    REFERENCES device_key_versions (user_id, device_id, key_version) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_pairing_sessions_source_key_version
    FOREIGN KEY (source_user_id, source_device_id, source_key_version)
    REFERENCES device_key_versions (user_id, device_id, key_version) ON DELETE RESTRICT;

ALTER TABLE pairing_sessions
    ADD CONSTRAINT ck_pairing_session_code_hash CHECK (code_hash IS NULL OR octet_length(code_hash) = 32),
    ADD CONSTRAINT ck_pairing_session_challenge CHECK (challenge IS NULL OR octet_length(challenge) = 32),
    ADD CONSTRAINT ck_pairing_session_initiator_key_version CHECK (initiator_key_version IS NULL OR initiator_key_version > 0),
    ADD CONSTRAINT ck_pairing_session_source_key_version CHECK (source_key_version IS NULL OR source_key_version > 0),
    ADD CONSTRAINT ck_pairing_session_source_key CHECK (source_public_key IS NULL OR octet_length(source_public_key) = 32),
    ADD CONSTRAINT ck_pairing_session_source_identity CHECK (
        (source_user_id IS NULL AND source_device_id IS NULL AND source_key_version IS NULL AND source_public_key IS NULL AND source_key_fingerprint IS NULL)
        OR (source_user_id IS NOT NULL AND source_device_id IS NOT NULL AND source_key_version IS NOT NULL AND source_public_key IS NOT NULL AND source_key_fingerprint IS NOT NULL)
    ),
    ADD CONSTRAINT ck_pairing_session_new_required_material CHECK (
        code_hash IS NULL OR (challenge IS NOT NULL AND initiator_key_version IS NOT NULL AND initiator_key_fingerprint IS NOT NULL AND octet_length(initiator_public_key) = 32)
    ),
    ADD CONSTRAINT ck_pairing_session_source_account CHECK (source_user_id IS NULL OR source_user_id = initiator_user_id),
    ADD CONSTRAINT ck_pairing_session_distinct_devices CHECK (source_device_id IS NULL OR source_device_id <> initiator_device_id),
    ADD CONSTRAINT ck_pairing_session_state_source CHECK (
        state NOT IN ('REDEEMED','PROOFS_VERIFIED','COMPARISON_CONFIRMED','COMPLETED','REJECTED','FAILED')
        OR code_hash IS NULL OR source_user_id IS NOT NULL
    ),
    ADD CONSTRAINT ck_pairing_session_state_proofs CHECK (
        state NOT IN ('PROOFS_VERIFIED','COMPARISON_CONFIRMED','COMPLETED','REJECTED','FAILED')
        OR code_hash IS NULL OR (main_proof_verified_at IS NOT NULL AND source_proof_verified_at IS NOT NULL)
    ),
    ADD CONSTRAINT ck_pairing_session_state_completion CHECK (
        state <> 'COMPLETED' OR code_hash IS NULL OR (main_confirmation = TRUE AND source_confirmation = TRUE)
    );

CREATE UNIQUE INDEX uq_pairing_sessions_code_hash
    ON pairing_sessions (code_hash) WHERE code_hash IS NOT NULL;

CREATE TABLE pairing_idempotency (
    pairing_session_id UUID NOT NULL REFERENCES pairing_sessions (pairing_session_id) ON DELETE CASCADE,
    actor_user_id UUID NOT NULL,
    actor_device_id UUID NOT NULL,
    operation VARCHAR(32) NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    resulting_state pairing_session_state NOT NULL,
    request_digest BYTEA NOT NULL,
    response_snapshot JSONB NOT NULL,
    failure_code VARCHAR(64),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (pairing_session_id, actor_user_id, actor_device_id, operation, idempotency_key),
    FOREIGN KEY (actor_user_id, actor_device_id) REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    CHECK (length(idempotency_key) > 0),
    CHECK (octet_length(request_digest) = 32),
    CHECK (operation IN ('REDEEM', 'PROOF', 'CONFIRM', 'CANCEL')),
    CHECK (jsonb_typeof(response_snapshot) = 'object'),
    CHECK (failure_code IS NULL OR failure_code IN ('DEVICE_LIMIT_REACHED', 'PAIRING_STATE_INVALID', 'PAIRING_CODE_EXPIRED')),
    CHECK (
        (resulting_state = 'FAILED' AND failure_code IN ('DEVICE_LIMIT_REACHED', 'PAIRING_STATE_INVALID')) OR
        (resulting_state = 'EXPIRED' AND failure_code = 'PAIRING_CODE_EXPIRED') OR
        (resulting_state NOT IN ('FAILED', 'EXPIRED') AND failure_code IS NULL)
    ),
    CHECK (expires_at > created_at)
);

CREATE INDEX ix_pairing_idempotency_expiry ON pairing_idempotency (expires_at);

CREATE TABLE device_revoke_idempotency (
    actor_user_id UUID NOT NULL,
    actor_device_id UUID NOT NULL,
    target_device_id UUID NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (actor_user_id, actor_device_id, idempotency_key),
    FOREIGN KEY (actor_user_id, actor_device_id) REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    FOREIGN KEY (actor_user_id, target_device_id) REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    CHECK (length(idempotency_key) > 0),
    CHECK (expires_at > created_at)
);

CREATE INDEX ix_device_revoke_idempotency_expiry ON device_revoke_idempotency (expires_at);

CREATE TABLE pairing_create_idempotency (
    actor_user_id UUID NOT NULL,
    actor_device_id UUID NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    request_digest BYTEA NOT NULL,
    pairing_session_id UUID NOT NULL REFERENCES pairing_sessions (pairing_session_id) ON DELETE CASCADE,
    capacity_current SMALLINT NOT NULL CHECK (capacity_current >= 0 AND capacity_current <= 5),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (actor_user_id, actor_device_id, idempotency_key),
    FOREIGN KEY (actor_user_id, actor_device_id) REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    CHECK (octet_length(request_digest) = 32),
    CHECK (length(idempotency_key) > 0),
    CHECK (expires_at > created_at)
);

ALTER TABLE security_audit_events
    ADD COLUMN pairing_session_id UUID REFERENCES pairing_sessions (pairing_session_id) ON DELETE RESTRICT;
