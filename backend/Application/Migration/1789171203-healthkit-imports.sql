-- Source identities and successful mappings survive deletion of canonical data.
CREATE TABLE healthkit_imports (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    user_id UUID NOT NULL REFERENCES users(id),
    object_id UUID NOT NULL CHECK (object_id <> '00000000-0000-0000-0000-000000000000'),
    storage_version SMALLINT NOT NULL CHECK (storage_version = 1),
    record JSONB NOT NULL CHECK (jsonb_typeof(record) = 'object'),
    workout_id UUID,
    FOREIGN KEY (user_id, workout_id) REFERENCES workouts(user_id, id),
    UNIQUE (user_id, object_id),
    UNIQUE (workout_id)
);
