-- 003_rates.sql
-- Price tables. One row per price, so two people editing different prices never
-- conflict (spec RAT-08). V1 kept all of this in a single Firestore document.

-- Door leaf price: door type x fire rating x finish (spec RAT-01).
-- For a finish with base_finish_code (SPRAY), `price` is the uplift on the base finish.
CREATE TABLE door_rates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door_type_id     uuid NOT NULL REFERENCES door_types (id),
  fire_rating_code text NOT NULL REFERENCES fire_ratings (code),
  finish_code      text NOT NULL REFERENCES door_finishes (code),
  price            numeric(12,2) NOT NULL CHECK (price >= 0),
  version          integer NOT NULL DEFAULT 1,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text REFERENCES app_users (uid),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       text REFERENCES app_users (uid),
  UNIQUE (door_type_id, fire_rating_code, finish_code)
);
CREATE TRIGGER door_rates_touch BEFORE UPDATE ON door_rates FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Vision panel price per panel, by fire rating (spec RAT-03).
CREATE TABLE vp_rates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fire_rating_code text NOT NULL UNIQUE REFERENCES fire_ratings (code),
  price            numeric(12,2) NOT NULL CHECK (price >= 0),
  glass_desc       text NOT NULL DEFAULT '',
  version          integer NOT NULL DEFAULT 1,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text REFERENCES app_users (uid),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       text REFERENCES app_users (uid)
);
CREATE TRIGGER vp_rates_touch BEFORE UPDATE ON vp_rates FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Frame price: door type x frame finish (spec RAT-04).
CREATE TABLE frame_rates (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door_type_id uuid NOT NULL REFERENCES door_types (id),
  finish_code  text NOT NULL REFERENCES frame_finishes (code),
  price        numeric(12,2) NOT NULL CHECK (price >= 0),
  version      integer NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text REFERENCES app_users (uid),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   text REFERENCES app_users (uid),
  UNIQUE (door_type_id, finish_code)
);
CREATE TRIGGER frame_rates_touch BEFORE UPDATE ON frame_rates FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Lining base price: door type x lining finish (spec RAT-05). Depth-over-threshold
-- uplift is entered per door line (job_doors.lining_uplift), not held here (RAT-05a).
CREATE TABLE lining_rates (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door_type_id uuid NOT NULL REFERENCES door_types (id),
  finish_code  text NOT NULL REFERENCES lining_finishes (code),
  price        numeric(12,2) NOT NULL CHECK (price >= 0),
  version      integer NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text REFERENCES app_users (uid),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   text REFERENCES app_users (uid),
  UNIQUE (door_type_id, finish_code)
);
CREATE TRIGGER lining_rates_touch BEFORE UPDATE ON lining_rates FOR EACH ROW EXECUTE FUNCTION touch_row();

-- Over panel price: door type x fire rating x panel type x door finish (spec RAT-07).
CREATE TABLE over_panel_rates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door_type_id     uuid NOT NULL REFERENCES door_types (id),
  fire_rating_code text NOT NULL REFERENCES fire_ratings (code),
  panel_type_code  text NOT NULL REFERENCES over_panel_types (code),
  finish_code      text NOT NULL REFERENCES door_finishes (code),
  price            numeric(12,2) NOT NULL CHECK (price >= 0),
  version          integer NOT NULL DEFAULT 1,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text REFERENCES app_users (uid),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       text REFERENCES app_users (uid),
  UNIQUE (door_type_id, fire_rating_code, panel_type_code, finish_code)
);
CREATE TRIGGER over_panel_rates_touch BEFORE UPDATE ON over_panel_rates FOR EACH ROW EXECUTE FUNCTION touch_row();
