CREATE TABLE export_receipts (
    id UUID PRIMARY KEY CHECK (id <> '00000000-0000-0000-0000-000000000000'),
    user_id UUID NOT NULL REFERENCES users(id),
    workout_id UUID NOT NULL CHECK (workout_id <> '00000000-0000-0000-0000-000000000000'),
    live_workout_id UUID,
    workout_revision NUMERIC NOT NULL CHECK (workout_revision::text ~ '^[1-9][0-9]*$'),
    platform TEXT NOT NULL CHECK (platform = 'appleHealth'),
    external_id UUID NOT NULL CHECK (external_id <> '00000000-0000-0000-0000-000000000000'),
    exported_at TIMESTAMPTZ NOT NULL CHECK (isfinite(exported_at)),
    CHECK (live_workout_id IS NULL OR live_workout_id = workout_id),
    FOREIGN KEY (user_id, live_workout_id) REFERENCES workouts(user_id, id) ON DELETE SET NULL (live_workout_id),
    UNIQUE (user_id, platform, external_id)
);
CREATE INDEX export_receipts_workout ON export_receipts (user_id, workout_id, exported_at DESC, id DESC);
-- Historical workout/source identities survive canonical deletion, so a later
-- HealthKit import cannot resurrect an object that this app exported.
