-- 002_reference.sql
-- Lookup lists that were hard-coded constants in V1 (FIRE_RATINGS, HANDING, FINISHES,
-- FRAME_FINISHES, OVER_PANEL_TYPES, door types, architraves). All admin-editable data now.

-- Fire ratings. `base_code` lets an "S" (smoke-sealed) variant fall back to its base
-- rating's prices when it has no rate row of its own (spec RAT-02; fixes V1 bug 14).
CREATE TABLE fire_ratings (
  code      text PRIMARY KEY,
  label     text NOT NULL,
  base_code text REFERENCES fire_ratings (code),
  is_fire_door boolean NOT NULL DEFAULT true,   -- false for NFR; drives warnings
  sort      integer NOT NULL DEFAULT 0,
  active    boolean NOT NULL DEFAULT true,
  CHECK (base_code IS NULL OR base_code <> code)
);

CREATE TABLE handings (
  code   text PRIMARY KEY,
  label  text NOT NULL,
  sort   integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

-- Door leaf finishes. When `base_finish_code` is set, rates for this finish are an UPLIFT
-- added to the base finish's price (V1: SPRAY = PRIMED + sprayAdd).
CREATE TABLE door_finishes (
  code             text PRIMARY KEY,
  label            text NOT NULL,
  base_finish_code text REFERENCES door_finishes (code),
  sort             integer NOT NULL DEFAULT 0,
  active           boolean NOT NULL DEFAULT true,
  CHECK (base_finish_code IS NULL OR base_finish_code <> code)
);

CREATE TABLE frame_finishes (
  code   text PRIMARY KEY,
  label  text NOT NULL,
  sort   integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE lining_finishes (
  code   text PRIMARY KEY,
  label  text NOT NULL,
  sort   integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

-- Over panel types (V1: SOLID / GLAZED; "NONE" is represented by NULL on the door).
CREATE TABLE over_panel_types (
  code   text PRIMARY KEY,
  label  text NOT NULL,
  sort   integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

-- Door types / form codes (V1 rates.doors desc + formCode).
CREATE TABLE door_types (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  form_code         text NOT NULL UNIQUE,
  description       text NOT NULL,
  leaf_count        numeric(2,1) NOT NULL DEFAULT 1 CHECK (leaf_count IN (1, 1.5, 2)),
  needs_flush_bolts boolean NOT NULL DEFAULT false,  -- V1 warning: SADL/SALH without flush bolts
  sort              integer NOT NULL DEFAULT 0,
  active            boolean NOT NULL DEFAULT true,
  version           integer NOT NULL DEFAULT 1,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text REFERENCES app_users (uid),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        text REFERENCES app_users (uid)
);
CREATE TRIGGER door_types_touch BEFORE UPDATE ON door_types FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Architraves: flat price per type (V1 rates.architraves). NULL on a door = none.
CREATE TABLE architrave_types (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  label      text NOT NULL,
  price      numeric(12,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  sort       integer NOT NULL DEFAULT 0,
  active     boolean NOT NULL DEFAULT true,
  version    integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text REFERENCES app_users (uid),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text REFERENCES app_users (uid)
);
CREATE TRIGGER architrave_types_touch BEFORE UPDATE ON architrave_types FOR EACH ROW EXECUTE FUNCTION touch_row();
