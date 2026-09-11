-- IHP applies this file and its schema_migrations entry in one transaction.
CREATE TABLE users (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    username TEXT NOT NULL UNIQUE CHECK (username = btrim(username) AND username <> ''),
    password_hash TEXT NOT NULL CHECK (password_hash LIKE '$argon2id$%'),
    created_at TIMESTAMPTZ NOT NULL CHECK (isfinite(created_at)),
    disabled_at TIMESTAMPTZ CHECK (isfinite(disabled_at) AND disabled_at >= created_at)
);

CREATE TABLE sessions (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    user_id UUID REFERENCES users(id),
    token_digest BYTEA NOT NULL UNIQUE CHECK (octet_length(token_digest) = 32),
    transport TEXT NOT NULL CHECK (transport IN ('browser', 'native')),
    csrf_digest BYTEA CHECK (octet_length(csrf_digest) = 32),
    device_name TEXT,
    created_at TIMESTAMPTZ NOT NULL CHECK (isfinite(created_at)),
    last_seen_at TIMESTAMPTZ NOT NULL CHECK (isfinite(last_seen_at)),
    idle_expires_at TIMESTAMPTZ NOT NULL CHECK (isfinite(idle_expires_at)),
    absolute_expires_at TIMESTAMPTZ NOT NULL CHECK (isfinite(absolute_expires_at)),
    revoked_at TIMESTAMPTZ CHECK (isfinite(revoked_at) AND revoked_at >= created_at),
    CHECK (created_at <= last_seen_at AND last_seen_at < idle_expires_at
           AND idle_expires_at <= absolute_expires_at),
    -- Anonymous browser sessions support the existing CSRF bootstrap contract.
    CHECK ((transport = 'browser' AND csrf_digest IS NOT NULL)
        OR (transport = 'native' AND csrf_digest IS NULL AND user_id IS NOT NULL))
);
CREATE INDEX sessions_user_id ON sessions (user_id, created_at DESC, id DESC);

CREATE TABLE workouts (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    user_id UUID NOT NULL REFERENCES users(id),
    -- Unbounded decimal integers match WorkoutRevision; no int64 truncation.
    revision NUMERIC NOT NULL CHECK (revision::text ~ '^[1-9][0-9]*$'),
    storage_version SMALLINT NOT NULL CHECK (storage_version = 1),
    observation JSONB NOT NULL CHECK (jsonb_typeof(observation) = 'object'),
    user_data JSONB NOT NULL CHECK (jsonb_typeof(user_data) = 'object'),
    CHECK (observation ? 'observationRange' AND observation ? 'observationSport'),
    CHECK (jsonb_typeof(observation->'observationRange') = 'object'
       AND jsonb_typeof(observation->'observationSport') = 'object'),
    CHECK ((observation->'observationSport'->>'type') IS NOT NULL
       AND observation->'observationSport'->>'type' IN ('cycling', 'running'))
);
CREATE INDEX workouts_user_id ON workouts (user_id, id);
