CREATE TYPE account_token_kind AS ENUM (
    'EMAIL_VERIFICATION',
    'PASSWORD_RESET',
    'DEVICE_ENROLLMENT'
);

ALTER TABLE users
    ADD COLUMN email_normalized VARCHAR(320),
    ADD COLUMN password_hash VARCHAR(100),
    ADD COLUMN email_verified_at TIMESTAMPTZ;

CREATE UNIQUE INDEX uq_users_email_normalized
    ON users (email_normalized)
    WHERE email_normalized IS NOT NULL;

ALTER TABLE sessions
    ADD COLUMN device_id UUID,
    ADD COLUMN access_token_hash BYTEA,
    ADD COLUMN access_expires_at TIMESTAMPTZ,
    ADD COLUMN refresh_token_hash BYTEA,
    ADD COLUMN refresh_expires_at TIMESTAMPTZ;

ALTER TABLE sessions
    ADD CONSTRAINT fk_sessions_device
    FOREIGN KEY (user_id, device_id)
    REFERENCES devices (user_id, device_id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX uq_sessions_access_token_hash
    ON sessions (access_token_hash)
    WHERE access_token_hash IS NOT NULL;

CREATE UNIQUE INDEX uq_sessions_refresh_token_hash
    ON sessions (refresh_token_hash)
    WHERE refresh_token_hash IS NOT NULL;

CREATE TABLE account_action_tokens (
    action_token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    kind account_token_kind NOT NULL,
    token_hash BYTEA NOT NULL UNIQUE,
    challenge BYTEA,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (octet_length(token_hash) = 32),
    CHECK (challenge IS NULL OR octet_length(challenge) = 32),
    CHECK (expires_at > created_at)
);

CREATE INDEX ix_account_action_tokens_active
    ON account_action_tokens (user_id, kind, expires_at)
    WHERE consumed_at IS NULL;

COMMENT ON TABLE account_action_tokens IS
    'One-use account action tokens stored only as SHA-256 hashes.';
COMMENT ON COLUMN sessions.access_token_hash IS
    'SHA-256 of a 256-bit opaque bearer access token; never store raw tokens.';
COMMENT ON COLUMN sessions.refresh_token_hash IS
    'SHA-256 of a 256-bit opaque refresh token; changed on every refresh.';
