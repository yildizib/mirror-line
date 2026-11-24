CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_status AS ENUM ('ACTIVE', 'DISABLED', 'DELETED');
CREATE TYPE session_status AS ENUM ('ACTIVE', 'REVOKED', 'EXPIRED');
CREATE TYPE device_role AS ENUM ('MAIN', 'SOURCE');
CREATE TYPE device_status AS ENUM ('PENDING', 'ACTIVE', 'RETIRED', 'REVOKED');
CREATE TYPE key_version_status AS ENUM (
    'PENDING',
    'ACTIVE',
    'RETIRING',
    'RETIRED',
    'REVOKED'
);
CREATE TYPE pairing_session_state AS ENUM (
    'CREATED',
    'REDEEMED',
    'PROOFS_VERIFIED',
    'COMPARISON_CONFIRMED',
    'COMPLETED',
    'EXPIRED',
    'CANCELLED',
    'REJECTED',
    'FAILED'
);
CREATE TYPE pairing_status AS ENUM ('ACTIVE', 'REVOKED');
CREATE TYPE key_rotation_state AS ENUM (
    'PENDING',
    'ACTIVE',
    'COMPLETED',
    'FAILED',
    'REVOKED'
);
CREATE TYPE key_rotation_reason AS ENUM (
    'SCHEDULED',
    'DEVICE_ADDED',
    'DEVICE_RETIRED',
    'SUSPECTED_COMPROMISE',
    'EMERGENCY',
    'MANUAL'
);
CREATE TYPE relay_status AS ENUM ('PENDING', 'DELIVERED', 'ACKNOWLEDGED', 'EXPIRED');
CREATE TYPE audit_result AS ENUM ('SUCCESS', 'FAILURE', 'DENIED');

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status user_status NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_successful_login_at TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    CHECK ((status <> 'DISABLED') OR disabled_at IS NOT NULL)
);

CREATE TABLE sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    session_fingerprint VARCHAR(128) NOT NULL,
    status session_status NOT NULL DEFAULT 'ACTIVE',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    UNIQUE (user_id, session_fingerprint),
    CHECK (expires_at > issued_at),
    CHECK ((status <> 'REVOKED') OR revoked_at IS NOT NULL)
);

CREATE TABLE devices (
    device_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    role device_role NOT NULL,
    status device_status NOT NULL DEFAULT 'PENDING',
    platform VARCHAR(32) NOT NULL,
    app_version VARCHAR(64) NOT NULL,
    display_name VARCHAR(128) NOT NULL,
    fcm_token VARCHAR(4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_authenticated_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,
    active_key_version INTEGER,
    retired_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    UNIQUE (user_id, device_id),
    CHECK (length(display_name) > 0),
    CHECK (active_key_version IS NULL OR active_key_version > 0),
    CHECK ((status <> 'RETIRED') OR retired_at IS NOT NULL),
    CHECK ((status <> 'REVOKED') OR revoked_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_devices_one_active_main_per_user
    ON devices (user_id)
    WHERE role = 'MAIN' AND status = 'ACTIVE';

CREATE TABLE device_key_versions (
    key_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_id UUID NOT NULL,
    key_version INTEGER NOT NULL,
    previous_key_version INTEGER,
    status key_version_status NOT NULL DEFAULT 'PENDING',
    signing_public_key BYTEA NOT NULL,
    encryption_public_key BYTEA NOT NULL,
    certificate_binding_material BYTEA NOT NULL,
    key_fingerprint VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMPTZ,
    retiring_at TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    FOREIGN KEY (user_id, device_id)
        REFERENCES devices (user_id, device_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, device_id, previous_key_version)
        REFERENCES device_key_versions (user_id, device_id, key_version)
        ON DELETE RESTRICT,
    UNIQUE (user_id, device_id, key_version),
    CHECK (key_version > 0),
    CHECK (previous_key_version IS NULL OR previous_key_version < key_version),
    CHECK (octet_length(signing_public_key) = 32),
    CHECK (octet_length(encryption_public_key) = 32),
    CHECK (octet_length(certificate_binding_material) BETWEEN 16 AND 8192),
    CHECK (length(key_fingerprint) > 0),
    CHECK ((status <> 'ACTIVE') OR activated_at IS NOT NULL),
    CHECK ((status <> 'RETIRING') OR retiring_at IS NOT NULL),
    CHECK ((status <> 'RETIRED') OR retired_at IS NOT NULL),
    CHECK ((status <> 'REVOKED') OR revoked_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_device_key_versions_one_active_per_device
    ON device_key_versions (user_id, device_id)
    WHERE status = 'ACTIVE';

ALTER TABLE devices
    ADD CONSTRAINT fk_devices_active_key_version
    FOREIGN KEY (user_id, device_id, active_key_version)
    REFERENCES device_key_versions (user_id, device_id, key_version)
    ON DELETE RESTRICT;

CREATE TABLE pairing_sessions (
    pairing_session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    initiator_user_id UUID NOT NULL,
    initiator_device_id UUID NOT NULL,
    state pairing_session_state NOT NULL DEFAULT 'CREATED',
    initiator_public_key BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    terminal_at TIMESTAMPTZ,
    FOREIGN KEY (initiator_user_id, initiator_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE CASCADE,
    CHECK (octet_length(initiator_public_key) > 0),
    CHECK (expires_at > created_at),
    CHECK ((state <> 'COMPLETED') OR completed_at IS NOT NULL),
    CHECK (
        state NOT IN ('EXPIRED', 'CANCELLED', 'REJECTED', 'FAILED')
        OR terminal_at IS NOT NULL
    )
);

CREATE TABLE pairings (
    pairing_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pairing_session_id UUID NOT NULL REFERENCES pairing_sessions (pairing_session_id)
        ON DELETE RESTRICT,
    main_user_id UUID NOT NULL,
    main_device_id UUID NOT NULL,
    source_user_id UUID NOT NULL,
    source_device_id UUID NOT NULL,
    status pairing_status NOT NULL DEFAULT 'ACTIVE',
    source_public_key BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,
    FOREIGN KEY (main_user_id, main_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    FOREIGN KEY (source_user_id, source_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    UNIQUE (main_user_id, main_device_id, source_user_id, source_device_id),
    CHECK (main_user_id = source_user_id),
    CHECK (main_device_id <> source_device_id),
    CHECK (octet_length(source_public_key) > 0),
    CHECK ((status <> 'REVOKED') OR revoked_at IS NOT NULL)
);

CREATE TABLE key_rotations (
    rotation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_id UUID NOT NULL,
    previous_key_version INTEGER NOT NULL,
    next_key_version INTEGER NOT NULL,
    state key_rotation_state NOT NULL DEFAULT 'PENDING',
    reason key_rotation_reason NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    FOREIGN KEY (user_id, device_id, previous_key_version)
        REFERENCES device_key_versions (user_id, device_id, key_version)
        ON DELETE RESTRICT,
    FOREIGN KEY (user_id, device_id, next_key_version)
        REFERENCES device_key_versions (user_id, device_id, key_version)
        ON DELETE RESTRICT,
    UNIQUE (user_id, device_id, next_key_version),
    CHECK (next_key_version > previous_key_version),
    CHECK ((state <> 'ACTIVE') OR activated_at IS NOT NULL),
    CHECK ((state <> 'COMPLETED') OR completed_at IS NOT NULL),
    CHECK ((state <> 'REVOKED') OR revoked_at IS NOT NULL)
);

CREATE TABLE key_rotation_acks (
    rotation_id UUID NOT NULL REFERENCES key_rotations (rotation_id) ON DELETE CASCADE,
    peer_user_id UUID NOT NULL,
    peer_device_id UUID NOT NULL,
    acknowledged_key_version INTEGER NOT NULL,
    acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (rotation_id, peer_user_id, peer_device_id),
    FOREIGN KEY (peer_user_id, peer_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    CHECK (acknowledged_key_version > 0)
);

CREATE TABLE relay_envelopes (
    envelope_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id UUID NOT NULL,
    sender_device_id UUID NOT NULL,
    recipient_user_id UUID NOT NULL,
    recipient_device_id UUID NOT NULL,
    message_id UUID NOT NULL,
    protocol_version SMALLINT NOT NULL,
    message_type VARCHAR(64) NOT NULL,
    client_created_at TIMESTAMPTZ NOT NULL,
    sender_key_version INTEGER NOT NULL,
    recipient_key_version INTEGER NOT NULL,
    nonce BYTEA,
    ciphertext BYTEA,
    associated_data BYTEA,
    signature BYTEA,
    envelope_digest BYTEA NOT NULL,
    status relay_status NOT NULL DEFAULT 'PENDING',
    server_accepted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    payload_purged_at TIMESTAMPTZ,
    FOREIGN KEY (sender_user_id, sender_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    FOREIGN KEY (recipient_user_id, recipient_device_id)
        REFERENCES devices (user_id, device_id) ON DELETE RESTRICT,
    FOREIGN KEY (sender_user_id, sender_device_id, sender_key_version)
        REFERENCES device_key_versions (user_id, device_id, key_version)
        ON DELETE RESTRICT,
    FOREIGN KEY (recipient_user_id, recipient_device_id, recipient_key_version)
        REFERENCES device_key_versions (user_id, device_id, key_version)
        ON DELETE RESTRICT,
    UNIQUE (sender_user_id, sender_device_id, message_id),
    CHECK (protocol_version > 0),
    CHECK (length(message_type) > 0),
    CHECK (sender_key_version > 0),
    CHECK (recipient_key_version > 0),
    CHECK (octet_length(envelope_digest) = 32),
    CHECK ((status <> 'DELIVERED') OR delivered_at IS NOT NULL),
    CHECK ((status <> 'ACKNOWLEDGED') OR acknowledged_at IS NOT NULL),
    CHECK (
        (
            payload_purged_at IS NULL
            AND ciphertext IS NOT NULL
            AND nonce IS NOT NULL
            AND signature IS NOT NULL
            AND octet_length(nonce) = 12
            AND octet_length(ciphertext) >= 16
            AND octet_length(signature) = 64
        )
        OR (payload_purged_at IS NOT NULL AND ciphertext IS NULL AND nonce IS NULL
            AND associated_data IS NULL AND signature IS NULL)
    )
);

CREATE INDEX ix_relay_envelopes_recipient_pending
    ON relay_envelopes (recipient_user_id, recipient_device_id, expires_at)
    WHERE status IN ('PENDING', 'DELIVERED');

CREATE FUNCTION enforce_relay_envelope_ttl()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.server_accepted_at := clock_timestamp();
        NEW.expires_at := NEW.server_accepted_at + INTERVAL '7 days';
    ELSIF NEW.server_accepted_at IS DISTINCT FROM OLD.server_accepted_at
        OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
        RAISE EXCEPTION 'relay acceptance and expiry times are server-controlled';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_relay_envelopes_enforce_ttl
BEFORE INSERT OR UPDATE ON relay_envelopes
FOR EACH ROW EXECUTE FUNCTION enforce_relay_envelope_ttl();

CREATE TABLE security_audit_events (
    audit_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_type VARCHAR(96) NOT NULL,
    result audit_result NOT NULL,
    -- Audit references intentionally restrict deletion to preserve immutable evidence.
    user_id UUID REFERENCES users (user_id) ON DELETE RESTRICT,
    device_id UUID REFERENCES devices (device_id) ON DELETE RESTRICT,
    session_id UUID REFERENCES sessions (session_id) ON DELETE RESTRICT,
    related_device_id UUID REFERENCES devices (device_id) ON DELETE RESTRICT,
    pairing_id UUID REFERENCES pairings (pairing_id) ON DELETE RESTRICT,
    rotation_id UUID REFERENCES key_rotations (rotation_id) ON DELETE RESTRICT,
    key_version INTEGER,
    key_fingerprint VARCHAR(128),
    ip_prefix CIDR,
    platform VARCHAR(32),
    app_version VARCHAR(64),
    correlation_id UUID,
    failure_code VARCHAR(64),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (length(event_type) > 0),
    CHECK (key_version IS NULL OR key_version > 0)
);

CREATE FUNCTION enforce_active_source_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.role = 'SOURCE' AND NEW.status = 'ACTIVE' THEN
        -- Locking the parent serializes source-device admission for this user.
        PERFORM 1 FROM users WHERE user_id = NEW.user_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'user % does not exist', NEW.user_id;
        END IF;

        IF (
            SELECT count(*)
            FROM devices
            WHERE user_id = NEW.user_id
              AND role = 'SOURCE'
              AND status = 'ACTIVE'
              AND device_id <> NEW.device_id
        ) >= 5 THEN
            RAISE EXCEPTION 'an account may have no more than five active source devices';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_devices_enforce_active_source_quota
BEFORE INSERT OR UPDATE OF user_id, role, status ON devices
FOR EACH ROW EXECUTE FUNCTION enforce_active_source_quota();

CREATE FUNCTION enforce_monotonic_device_key_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    latest_key_version INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.key_version <> OLD.key_version THEN
        RAISE EXCEPTION 'key version is immutable';
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- The device-row lock also serializes simultaneous rotation proposals.
        PERFORM 1 FROM devices
        WHERE user_id = NEW.user_id AND device_id = NEW.device_id
        FOR UPDATE;

        SELECT max(key_version)
        INTO latest_key_version
        FROM device_key_versions
        WHERE user_id = NEW.user_id AND device_id = NEW.device_id;

        IF latest_key_version IS NOT NULL AND NEW.key_version <= latest_key_version THEN
            RAISE EXCEPTION 'device key version must increase monotonically';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_device_key_versions_enforce_monotonic_version
BEFORE INSERT OR UPDATE OF key_version ON device_key_versions
FOR EACH ROW EXECUTE FUNCTION enforce_monotonic_device_key_version();

CREATE FUNCTION prevent_security_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'security_audit_events are append-only';
END;
$$;

CREATE TRIGGER trg_security_audit_events_append_only
BEFORE UPDATE OR DELETE ON security_audit_events
FOR EACH ROW EXECUTE FUNCTION prevent_security_audit_mutation();

COMMENT ON TABLE relay_envelopes IS
    'Opaque encrypted relay payloads only; plaintext is never persisted.';
COMMENT ON COLUMN relay_envelopes.ciphertext IS
    'Encrypted bytes, cleared after acknowledgement while the replay tombstone remains.';
COMMENT ON TABLE device_key_versions IS
    'Public certificate material only; private key material is never persisted.';
COMMENT ON TABLE security_audit_events IS
    'Append-only metadata; never store messages, credentials, pairing codes, ciphertext, or private keys.';
