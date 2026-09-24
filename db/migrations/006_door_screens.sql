-- 006_door_screens.sql
-- Door screens: STRUCTURE ONLY for now (spec §7a, SCR-01..03).
-- Glazed side screens / fan-lights quoted alongside doorsets. Cost is entered by hand
-- until screen rates and pricing rules are defined.

CREATE TABLE job_screens (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id            uuid NOT NULL REFERENCES jobs (id) ON DELETE CASCADE,
  job_door_id       uuid REFERENCES job_doors (id) ON DELETE SET NULL,  -- optional: the door it sits beside
  sort_order        double precision NOT NULL,
  qty               integer NOT NULL DEFAULT 1 CHECK (qty >= 1),
  screen_mark       text,
  location          text,
  width_mm          integer CHECK (width_mm > 0),
  height_mm         integer CHECK (height_mm > 0),
  fire_rating_code  text REFERENCES fire_ratings (code),
  glazing_desc      text,
  frame_finish_code text REFERENCES frame_finishes (code),
  description       text,
  unit_cost         numeric(12,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),   -- manual for now (SCR-03)
  sell_override     numeric(12,2) CHECK (sell_override >= 0),
  comments          text,
  version           integer NOT NULL DEFAULT 1,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text REFERENCES app_users (uid),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        text REFERENCES app_users (uid)
);
CREATE TRIGGER job_screens_touch BEFORE UPDATE ON job_screens FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX job_screens_job_idx ON job_screens (job_id, sort_order);
