-- Owner-scoped file identity and publication are committed in one transaction.
-- The private archive is durable before a retained record can be committed.
CREATE TABLE fit_imports (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    user_id UUID NOT NULL REFERENCES users(id),
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    storage_version SMALLINT NOT NULL CHECK (storage_version = 1),
    record JSONB NOT NULL CHECK (jsonb_typeof(record) = 'object'),
    workout_id UUID,
    FOREIGN KEY (user_id, workout_id) REFERENCES workouts(user_id, id),
    UNIQUE (user_id, sha256),
    UNIQUE (workout_id)
);
