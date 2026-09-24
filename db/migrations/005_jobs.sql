-- 005_jobs.sql
-- Clients, folders, jobs (quotes), door lines and door hardware.

-- ---------------------------------------------------------------------------
-- Clients: shared address book (spec CLI-01; V1 kept this in one browser only)
-- ---------------------------------------------------------------------------
CREATE TABLE clients (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company      text NOT NULL,
  site         text,
  contact_name text,
  phone        text,
  email        text,
  notes        text,
  active       boolean NOT NULL DEFAULT true,
  search_text  text GENERATED ALWAYS AS (
                 lower(company || ' ' || coalesce(site, '') || ' ' || coalesce(contact_name, '') || ' ' ||
                       coalesce(email, ''))
               ) STORED,
  version      integer NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text REFERENCES app_users (uid),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   text REFERENCES app_users (uid)
);
CREATE TRIGGER clients_touch BEFORE UPDATE ON clients FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX clients_search_trgm ON clients USING gin (search_text gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Folders: nested (spec JOB-03)
-- ---------------------------------------------------------------------------
CREATE TABLE folders (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL CHECK (btrim(name) <> ''),
  parent_id  uuid REFERENCES folders (id) ON DELETE RESTRICT,
  version    integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text REFERENCES app_users (uid),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text REFERENCES app_users (uid),
  CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE TRIGGER folders_touch BEFORE UPDATE ON folders FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX folders_parent_idx ON folders (parent_id);

-- Stop a folder being moved inside its own sub-tree.
CREATE FUNCTION folders_no_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_id IS NOT NULL AND EXISTS (
    WITH RECURSIVE up AS (
      SELECT id, parent_id FROM folders WHERE id = NEW.parent_id
      UNION ALL
      SELECT f.id, f.parent_id FROM folders f JOIN up ON f.id = up.parent_id
    )
    SELECT 1 FROM up WHERE id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Folder cannot be moved inside itself' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER folders_no_cycle BEFORE UPDATE OF parent_id ON folders
  FOR EACH ROW EXECUTE FUNCTION folders_no_cycle();

-- ---------------------------------------------------------------------------
-- Quote reference numbers: MH-2026-0001, sequential per year, never reused (spec JOB-01)
-- ---------------------------------------------------------------------------
CREATE TABLE quote_counters (
  year        integer PRIMARY KEY,
  last_number integer NOT NULL
);

-- ---------------------------------------------------------------------------
-- Jobs (spec §5). Rates are NOT embedded: each line keeps its own price snapshot.
-- Totals are calculated by the v_job_totals view, so the dashboard and the job always
-- agree (DSH-04) and door edits don't bump the job header's version.
-- ---------------------------------------------------------------------------
CREATE TABLE jobs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_ref         text NOT NULL UNIQUE,   -- set by trigger on insert
  project_name      text NOT NULL DEFAULT 'New Project',
  client_id         uuid REFERENCES clients (id),
  -- Contact details as quoted. Copied from the client, editable per job (CLI-02).
  client_company    text,
  site              text,
  contact_name      text,
  contact_phone     text,
  contact_email     text,
  po_number         text,
  notes             text,
  markup_pct        numeric(6,4) NOT NULL DEFAULT 0.22 CHECK (markup_pct >= 0),
  status            text NOT NULL DEFAULT 'outstanding'
                    CHECK (status IN ('outstanding', 'won', 'lost', 'redundant')),
  status_changed_at timestamptz NOT NULL DEFAULT now(),
  folder_id         uuid REFERENCES folders (id) ON DELETE SET NULL,
  prepared_by       text REFERENCES app_users (uid),   -- USR-05: shown on the PDF
  priced_at         timestamptz,                      -- last "reprice to current rates"
  deleted_at        timestamptz,                      -- JOB-08 soft delete
  deleted_by        text REFERENCES app_users (uid),
  search_text       text GENERATED ALWAYS AS (
                      lower(quote_ref || ' ' || project_name || ' ' || coalesce(client_company, '') || ' ' ||
                            coalesce(site, '') || ' ' || coalesce(contact_name, '') || ' ' ||
                            coalesce(po_number, ''))
                    ) STORED,
  version           integer NOT NULL DEFAULT 1,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text REFERENCES app_users (uid),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        text REFERENCES app_users (uid)
);
CREATE TRIGGER jobs_touch BEFORE UPDATE ON jobs FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX jobs_status_idx ON jobs (status, status_changed_at) WHERE deleted_at IS NULL;
CREATE INDEX jobs_folder_idx ON jobs (folder_id) WHERE deleted_at IS NULL;
CREATE INDEX jobs_client_idx ON jobs (client_id);
CREATE INDEX jobs_search_trgm ON jobs USING gin (search_text gin_trgm_ops);

CREATE FUNCTION jobs_assign_quote_ref() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  yr     integer := extract(year FROM now() AT TIME ZONE 'Europe/London');
  n      integer;
  prefix text;
BEGIN
  IF NEW.quote_ref IS NULL THEN
    SELECT coalesce(value #>> '{}', 'MH') INTO prefix FROM settings WHERE key = 'quote_ref_prefix';
    INSERT INTO quote_counters AS qc (year, last_number) VALUES (yr, 1)
      ON CONFLICT (year) DO UPDATE SET last_number = qc.last_number + 1
      RETURNING last_number INTO n;
    NEW.quote_ref := coalesce(prefix, 'MH') || '-' || yr || '-' || lpad(n::text, 4, '0');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER jobs_quote_ref BEFORE INSERT ON jobs FOR EACH ROW EXECUTE FUNCTION jobs_assign_quote_ref();

CREATE FUNCTION jobs_status_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.status_changed_at := now();
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER jobs_status_changed BEFORE UPDATE OF status ON jobs
  FOR EACH ROW EXECUTE FUNCTION jobs_status_changed();

-- Who has a job open right now (spec JOB-07). Rows older than ~60s are treated as gone.
CREATE TABLE job_viewers (
  job_id    uuid NOT NULL REFERENCES jobs (id) ON DELETE CASCADE,
  uid       text NOT NULL REFERENCES app_users (uid) ON DELETE CASCADE,
  last_seen timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (job_id, uid)
);

-- ---------------------------------------------------------------------------
-- Door lines (spec §6.1). One row per schedule line; each saved on its own (CON-01).
-- cost_* columns are the price SNAPSHOT set by the pricing engine (JOB-06).
-- ---------------------------------------------------------------------------
CREATE TABLE job_doors (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id               uuid NOT NULL REFERENCES jobs (id) ON DELETE CASCADE,
  sort_order           double precision NOT NULL,   -- fractional, so drag-reorder touches one row
  qty                  integer NOT NULL DEFAULT 1 CHECK (qty >= 1),
  door_mark            text,
  location             text,
  -- Door type: a rated type, or manual with free description + cost.
  door_type_id         uuid REFERENCES door_types (id),
  is_manual            boolean NOT NULL DEFAULT false,
  manual_desc          text,
  width_mm             integer CHECK (width_mm > 0),
  height_mm            integer CHECK (height_mm > 0),
  thickness_mm         integer CHECK (thickness_mm > 0),
  handing_code         text REFERENCES handings (code),
  fire_rating_code     text REFERENCES fire_ratings (code),
  vp_count             integer NOT NULL DEFAULT 0 CHECK (vp_count BETWEEN 0 AND 8),
  door_finish_code     text REFERENCES door_finishes (code),
  -- Surround: frame or lining (spec §6.1 / RAT-05)
  surround             text NOT NULL DEFAULT 'FRAME' CHECK (surround IN ('NONE', 'FRAME', 'LINING')),
  frame_finish_code    text REFERENCES frame_finishes (code),
  lining_finish_code   text REFERENCES lining_finishes (code),
  lining_depth_mm      integer CHECK (lining_depth_mm > 0),
  lining_uplift        numeric(12,2) CHECK (lining_uplift >= 0),  -- asked for when depth > threshold (RAT-05a)
  architrave_type_id   uuid REFERENCES architrave_types (id),
  over_panel_type_code text REFERENCES over_panel_types (code),   -- NULL = none
  added_uplift         numeric(12,2) NOT NULL DEFAULT 0,
  sell_override        numeric(12,2) CHECK (sell_override >= 0),   -- per unit; NULL = use markup
  complete             boolean NOT NULL DEFAULT false,
  comments             text,
  -- Price snapshot (per unit). Hardware snapshot lives on job_door_items.
  cost_door            numeric(12,2) NOT NULL DEFAULT 0,   -- leaf, or manual cost
  cost_vp              numeric(12,2) NOT NULL DEFAULT 0,
  cost_surround        numeric(12,2) NOT NULL DEFAULT 0,   -- frame or lining base
  cost_architrave      numeric(12,2) NOT NULL DEFAULT 0,
  cost_over_panel      numeric(12,2) NOT NULL DEFAULT 0,
  priced_at            timestamptz,
  version              integer NOT NULL DEFAULT 1,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           text REFERENCES app_users (uid),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  updated_by           text REFERENCES app_users (uid),
  CHECK (NOT is_manual OR door_type_id IS NULL)
);
CREATE TRIGGER job_doors_touch BEFORE UPDATE ON job_doors FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX job_doors_job_idx ON job_doors (job_id, sort_order);
CREATE INDEX job_doors_mark_trgm ON job_doors USING gin (lower(coalesce(door_mark, '') || ' ' || coalesce(location, '')) gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Door hardware (spec §6.1 "Ironmongery" column set).
-- Phase 1: one product per category per door (the V1-style grid columns), enforced by
-- job_door_items_one_per_category. Phase 2 (ironmongery schedule, §7) drops that
-- constraint to allow any number of lines, and adds sets. No rebuild needed.
-- ---------------------------------------------------------------------------
CREATE TABLE job_door_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_door_id     uuid NOT NULL REFERENCES job_doors (id) ON DELETE CASCADE,
  category_id     uuid NOT NULL REFERENCES product_categories (id),
  product_id      uuid NOT NULL,
  qty             numeric(10,2) NOT NULL DEFAULT 1 CHECK (qty > 0),
  -- Snapshot of the product when added / last repriced (JOB-06, CAT-06)
  unit_cost       numeric(12,2) CHECK (unit_cost >= 0),
  mat_code        text,
  description     text,
  note            text,
  version         integer NOT NULL DEFAULT 1,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text REFERENCES app_users (uid),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      text REFERENCES app_users (uid),
  FOREIGN KEY (product_id, category_id) REFERENCES products (id, category_id),
  CONSTRAINT job_door_items_one_per_category UNIQUE (job_door_id, category_id)
);
CREATE TRIGGER job_door_items_touch BEFORE UPDATE ON job_door_items FOR EACH ROW EXECUTE FUNCTION touch_row();
CREATE INDEX job_door_items_product_idx ON job_door_items (product_id);

-- Fill the snapshot from the catalogue when a product is added or swapped, unless the
-- caller supplied its own cost.
CREATE FUNCTION job_door_items_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p products%ROWTYPE;
BEGIN
  IF TG_OP = 'INSERT' OR NEW.product_id IS DISTINCT FROM OLD.product_id THEN
    SELECT * INTO p FROM products WHERE id = NEW.product_id;
    NEW.mat_code    := p.mat_code;
    NEW.description := p.description;
    IF NEW.unit_cost IS NULL OR (TG_OP = 'UPDATE' AND NEW.unit_cost IS NOT DISTINCT FROM OLD.unit_cost) THEN
      NEW.unit_cost := p.cost;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER job_door_items_snapshot BEFORE INSERT OR UPDATE OF product_id ON job_door_items
  FOR EACH ROW EXECUTE FUNCTION job_door_items_snapshot();
