-- Run once in the Supabase SQL Editor as the database owner.
-- Private schema: FastAPI is the data access boundary, not the Data API.
BEGIN;
CREATE SCHEMA IF NOT EXISTS pocketwise;
REVOKE ALL ON SCHEMA pocketwise FROM PUBLIC, anon, authenticated;
CREATE TABLE pocketwise.documents (
    collection text NOT NULL,
    id text NOT NULL,
    body jsonb NOT NULL,
    PRIMARY KEY (collection, id),
    CHECK (jsonb_typeof(body) = 'object'),
    CHECK (body ? 'id' AND jsonb_typeof(body->'id') = 'string' AND body->>'id' = id)
);
CREATE UNIQUE INDEX documents_unique_email
    ON pocketwise.documents ((body->>'email')) WHERE collection = 'users';
CREATE UNIQUE INDEX documents_unique_budget
    ON pocketwise.documents ((body->>'user_id'), (body->>'period'), (body->>'category_id'))
    NULLS NOT DISTINCT
    WHERE collection = 'budgets';
CREATE INDEX documents_body ON pocketwise.documents USING gin (body jsonb_path_ops);
ALTER TABLE pocketwise.documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pocketwise.documents FROM PUBLIC, anon, authenticated;
COMMIT;
