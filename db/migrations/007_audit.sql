-- 007_audit.sql
-- Audit log: every insert / update / delete on shared data, with who and the before/after
-- row (spec USR-06). Generic: row id is taken from the row's `id`, `code` or `key` column.

CREATE TABLE audit_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name text NOT NULL,
  row_id     text NOT NULL,
  action     text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  changed_by text,
  changed_at timestamptz NOT NULL DEFAULT now(),
  old_row    jsonb,
  new_row    jsonb
);
CREATE INDEX audit_log_row_idx ON audit_log (table_name, row_id, changed_at DESC);
CREATE INDEX audit_log_user_idx ON audit_log (changed_by, changed_at DESC);

CREATE FUNCTION audit_row() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  o jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  n jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
  r jsonb := coalesce(n, o);
BEGIN
  -- Skip no-op updates (only version/updated_at moved)
  IF TG_OP = 'UPDATE' AND (o - 'version' - 'updated_at') = (n - 'version' - 'updated_at') THEN
    RETURN NULL;
  END IF;
  INSERT INTO audit_log (table_name, row_id, action, changed_by, old_row, new_row)
  VALUES (TG_TABLE_NAME,
          coalesce(r ->> 'id', r ->> 'code', r ->> 'key', r ->> 'uid'),
          TG_OP,
          coalesce(n ->> 'updated_by', n ->> 'created_by', o ->> 'updated_by'),
          o, n);
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'app_users', 'settings',
    'fire_ratings', 'handings', 'door_finishes', 'frame_finishes', 'lining_finishes', 'over_panel_types',
    'door_types', 'architrave_types',
    'door_rates', 'vp_rates', 'frame_rates', 'lining_rates', 'over_panel_rates',
    'suppliers', 'product_categories', 'products',
    'clients', 'folders', 'jobs', 'job_doors', 'job_door_items', 'job_screens'
  ] LOOP
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION audit_row()', t || '_audit', t);
  END LOOP;
END $$;
