-- Canonical JSON is always UTC. Packing calendar components as NUMERIC keeps
-- sub-microsecond ordering without casting through PostgreSQL timestamptz.
ALTER TABLE workouts ADD COLUMN start_key NUMERIC GENERATED ALWAYS AS
    (translate(observation #>> '{observationRange,rangeStart}', '-:TZ', '')::numeric) STORED NOT NULL;
ALTER TABLE workouts ADD CONSTRAINT workouts_start_utc CHECK
    ((observation #>> '{observationRange,rangeStart}') ~ '^[0-9]{4,}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$');
CREATE INDEX workouts_owner_start ON workouts (user_id, start_key DESC, id DESC);
ALTER TABLE workouts ADD CONSTRAINT workouts_owner_identity UNIQUE (user_id, id);
DROP INDEX workouts_user_id;

CREATE TABLE workout_submissions (
    user_id UUID NOT NULL REFERENCES users(id),
    submission_id UUID NOT NULL CHECK (submission_id <> '00000000-0000-0000-0000-000000000000'),
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest) = 32),
    workout_id UUID,
    PRIMARY KEY (user_id, submission_id),
    FOREIGN KEY (user_id, workout_id) REFERENCES workouts(user_id, id) ON DELETE SET NULL (workout_id)
);
-- A committed NULL workout_id is a tombstone, retained after deletion. A pending
-- claim is never committed: claim, workout and publication share one transaction.
CREATE INDEX workout_submissions_workout ON workout_submissions (user_id, workout_id);
