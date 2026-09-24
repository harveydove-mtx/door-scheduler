-- 001_foundation.sql
-- Users, settings, and the shared helpers every other table uses.
--
-- Conventions (see docs/v2-data-model.md):
--   * Every editable table has: version, created_at, created_by, updated_at, updated_by.
--   * `version` starts at 1 and is bumped by trigger on every UPDATE. Clients save with
--     `... WHERE id = $id AND version = $expected_version`; 0 rows updated = someone else
--     changed it first (spec CON-02).
--   * Money is numeric(12,2) in GBP, ex VAT. Sizes are integer millimetres.

CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- partial-word search on MAT codes, descriptions, jobs

-- ---------------------------------------------------------------------------
-- Shared trigger: bump version + updated_at on every update
-- ---------------------------------------------------------------------------
CREATE FUNCTION touch_row() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.version    := OLD.version + 1;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------------
-- Users (spec USR-01..06). uid = Firebase Auth uid.
-- The domain check here is a second line of defence behind the Auth blocking function.
-- ---------------------------------------------------------------------------
CREATE TABLE app_users (
  uid          text PRIMARY KEY,
  email        text NOT NULL UNIQUE
               CHECK (email = lower(email) AND email LIKE '%@matrixhardware.co.uk'),
  display_name text NOT NULL,
  role         text NOT NULL DEFAULT 'estimator' CHECK (role IN ('admin', 'estimator', 'viewer')),
  active       boolean NOT NULL DEFAULT true,
  version      integer NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER app_users_touch BEFORE UPDATE ON app_users FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Per-user preferences, e.g. schedule column order / hidden columns / density (spec SCH-02).
CREATE TABLE user_preferences (
  uid        text NOT NULL REFERENCES app_users (uid) ON DELETE CASCADE,
  pref_key   text NOT NULL,
  value      jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (uid, pref_key)
);

-- ---------------------------------------------------------------------------
-- App settings (admin-editable). Values are jsonb so each key can hold a number,
-- text or structure. Known keys are seeded in seed.sql.
-- ---------------------------------------------------------------------------
CREATE TABLE settings (
  key         text PRIMARY KEY,
  value       jsonb,
  description text NOT NULL DEFAULT '',
  version     integer NOT NULL DEFAULT 1,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text REFERENCES app_users (uid),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  text REFERENCES app_users (uid)
);
CREATE TRIGGER settings_touch BEFORE UPDATE ON settings FOR EACH ROW EXECUTE FUNCTION touch_row();
