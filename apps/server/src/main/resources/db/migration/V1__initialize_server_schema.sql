CREATE TABLE mirrorline_schema_marker (
    version INTEGER PRIMARY KEY,
    installed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO mirrorline_schema_marker (version) VALUES (1);
