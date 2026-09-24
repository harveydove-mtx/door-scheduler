-- 009_mat_codes.sql
-- MAT codes on EVERY priced item, not just catalogue products, filled in by Matrix from
-- one spreadsheet-style list (v_mat_code_table). Agreed 2026-09-24 (spec Q10).
--
--   * Each rate row (door, VP, frame, lining, architrave, over panel) gets an optional MAT code.
--   * A MAT code is unique across ALL of these tables and products, enforced via
--     mat_code_registry: a code used on a door rate can't also be used on a product.
--   * Door lines keep a snapshot of the MAT codes they were priced with, next to the
--     cost snapshot, so exports show MAT codes per door even after rates change.

-- ---------------------------------------------------------------------------
-- 1. MAT code column on every rate table (products already has one)
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['door_rates', 'vp_rates', 'frame_rates', 'lining_rates',
                           'architrave_types', 'over_panel_rates'] LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN mat_code text
                    CHECK (mat_code IS NULL OR (mat_code = upper(btrim(mat_code)) AND mat_code <> %L))',
                   t, '');
  END LOOP;
END $$;

-- products.mat_code: also forbid empty string, like the rate tables
ALTER TABLE products ADD CONSTRAINT products_mat_code_not_blank CHECK (mat_code <> '');

-- ---------------------------------------------------------------------------
-- 2. One registry of every MAT code in use -> unique across all tables
-- ---------------------------------------------------------------------------
CREATE TABLE mat_code_registry (
  mat_code   text PRIMARY KEY,
  table_name text NOT NULL,
  row_id     uuid NOT NULL,
  UNIQUE (table_name, row_id)
);

CREATE FUNCTION mat_code_register() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owner record;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.mat_code IS NOT NULL THEN
    DELETE FROM mat_code_registry WHERE table_name = TG_TABLE_NAME AND row_id = OLD.id;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.mat_code IS NOT NULL THEN
    SELECT * INTO owner FROM mat_code_registry WHERE mat_code = NEW.mat_code;
    IF FOUND THEN
      RAISE EXCEPTION 'MAT code % is already used (%)', NEW.mat_code, owner.table_name
        USING ERRCODE = 'unique_violation';
    END IF;
    INSERT INTO mat_code_registry (mat_code, table_name, row_id)
    VALUES (NEW.mat_code, TG_TABLE_NAME, NEW.id);
  END IF;
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['products', 'door_rates', 'vp_rates', 'frame_rates', 'lining_rates',
                           'architrave_types', 'over_panel_rates'] LOOP
    EXECUTE format('INSERT INTO mat_code_registry (mat_code, table_name, row_id)
                    SELECT mat_code, %L, id FROM %I WHERE mat_code IS NOT NULL', t, t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR DELETE OR UPDATE OF mat_code ON %I
                    FOR EACH ROW EXECUTE FUNCTION mat_code_register()', t || '_mat_code', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. MAT code snapshot on door lines (set by the pricing engine with the costs)
-- ---------------------------------------------------------------------------
ALTER TABLE job_doors
  ADD COLUMN mat_code_door       text,   -- the door rate row used (for SPRAY: the spray row)
  ADD COLUMN mat_code_vp         text,
  ADD COLUMN mat_code_surround   text,   -- frame or lining rate row
  ADD COLUMN mat_code_architrave text,
  ADD COLUMN mat_code_over_panel text;

-- ---------------------------------------------------------------------------
-- 4. The MAT code table: every priced item in one list
-- ---------------------------------------------------------------------------
CREATE VIEW v_mat_code_table AS
SELECT 'product'::text AS kind, 'products'::text AS table_name, p.id AS row_id, p.version,
       c.sort AS kind_sort, c.label || ': ' || p.description
         || coalesce(' [' || p.supplier_code || ']', '') AS item,
       p.mat_code, p.cost, p.active
FROM products p JOIN product_categories c ON c.id = p.category_id
UNION ALL
SELECT 'door', 'door_rates', r.id, r.version, 1000 + dt.sort,
       'Door ' || dt.form_code || ' ' || dt.description || ' / ' || r.fire_rating_code || ' / ' || f.label
         || CASE WHEN f.base_finish_code IS NOT NULL THEN ' (uplift on ' || f.base_finish_code || ')' ELSE '' END,
       r.mat_code, r.price, dt.active AND f.active
FROM door_rates r JOIN door_types dt ON dt.id = r.door_type_id JOIN door_finishes f ON f.code = r.finish_code
UNION ALL
SELECT 'vision_panel', 'vp_rates', r.id, r.version, 2000 + fr.sort,
       'Vision panel ' || r.fire_rating_code || coalesce(' / ' || nullif(r.glass_desc, ''), ''),
       r.mat_code, r.price, fr.active
FROM vp_rates r JOIN fire_ratings fr ON fr.code = r.fire_rating_code
UNION ALL
SELECT 'frame', 'frame_rates', r.id, r.version, 3000 + dt.sort,
       'Frame ' || dt.form_code || ' / ' || f.label, r.mat_code, r.price, dt.active AND f.active
FROM frame_rates r JOIN door_types dt ON dt.id = r.door_type_id JOIN frame_finishes f ON f.code = r.finish_code
UNION ALL
SELECT 'lining', 'lining_rates', r.id, r.version, 4000 + dt.sort,
       'Lining ' || dt.form_code || ' / ' || f.label, r.mat_code, r.price, dt.active AND f.active
FROM lining_rates r JOIN door_types dt ON dt.id = r.door_type_id JOIN lining_finishes f ON f.code = r.finish_code
UNION ALL
SELECT 'architrave', 'architrave_types', a.id, a.version, 5000 + a.sort,
       'Architrave ' || a.label, a.mat_code, a.price, a.active
FROM architrave_types a
UNION ALL
SELECT 'over_panel', 'over_panel_rates', r.id, r.version, 6000 + dt.sort,
       'Over panel ' || dt.form_code || ' / ' || r.fire_rating_code || ' / ' || pt.label || ' / ' || f.label,
       r.mat_code, r.price, dt.active AND pt.active AND f.active
FROM over_panel_rates r
JOIN door_types dt ON dt.id = r.door_type_id
JOIN over_panel_types pt ON pt.code = r.panel_type_code
JOIN door_finishes f ON f.code = r.finish_code;

-- ---------------------------------------------------------------------------
-- 5. Set one MAT code, with the same version check as every other save (CON-02).
--    Returns the row's new version, or NULL if someone else changed the row first.
--    Pass NULL / '' to clear a code. Codes are trimmed and upper-cased.
-- ---------------------------------------------------------------------------
CREATE FUNCTION set_mat_code(p_table text, p_row_id uuid, p_expected_version integer,
                             p_mat_code text, p_uid text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE new_version integer;
BEGIN
  IF p_table NOT IN ('products', 'door_rates', 'vp_rates', 'frame_rates', 'lining_rates',
                     'architrave_types', 'over_panel_rates') THEN
    RAISE EXCEPTION 'MAT codes cannot be set on %', p_table USING ERRCODE = 'invalid_parameter_value';
  END IF;
  EXECUTE format('UPDATE %I SET mat_code = nullif(upper(btrim($1)), %L), updated_by = $2
                  WHERE id = $3 AND version = $4 RETURNING version', p_table, '')
    INTO new_version
    USING p_mat_code, p_uid, p_row_id, p_expected_version;
  RETURN new_version;
END $$;
