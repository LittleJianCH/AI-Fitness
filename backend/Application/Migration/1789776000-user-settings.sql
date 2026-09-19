CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    storage_version SMALLINT NOT NULL CHECK (storage_version = 1),
    payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object')
);
