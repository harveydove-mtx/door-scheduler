-- MAT codes on every priced item (spec CAT-01, Q10).
BEGIN;
CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table(NULL, false, NULL, false);
SELECT pg_temp.ok(count(*) FILTER (WHERE kind = 'product') = 29 AND count(*) FILTER (WHERE kind = 'door') = 36
                  AND count(*) FILTER (WHERE kind = 'vision_panel') = 3 AND count(*) FILTER (WHERE kind = 'frame') = 12
                  AND count(*) FILTER (WHERE kind = 'architrave') = 4 AND count(*) FILTER (WHERE kind = 'over_panel') = 4,
                  'MAT code table lists every product and rate row (29 + 36 + 3 + 12 + 4 + 4)') FROM t;
SELECT pg_temp.ok(bool_and(mat_code IS NULL), 'no MAT codes seeded: Matrix fills them in') FROM t;
SELECT pg_temp.ok(item = 'Door SASL SINGLE ACTION SINGLE LEAF / FD30 / Spray (uplift on PRIMED)',
                  'door rate rows are described in words, spray shown as an uplift')
FROM t WHERE kind = 'door' AND item LIKE '%SASL%FD30%Spray%';

-- Fill one door rate in via the versioned save
SELECT row_id AS rid, version AS ver FROM t WHERE kind = 'door' AND item LIKE '%SASL%FD30 / Laminate' \gset
EXECUTE set_mat_code('door_rates', :'rid', :ver, '  mat-d-sasl-30-lam ', 'u-admin');
SELECT pg_temp.ok(mat_code = 'MAT-D-SASL-30-LAM' AND version = :ver + 1 AND updated_by = 'u-admin',
                  'MAT code saved trimmed + upper-case, version bumped, user recorded')
FROM door_rates WHERE id = :'rid';

-- Stale save refused
CREATE TEMP TABLE r ON COMMIT DROP AS EXECUTE set_mat_code('door_rates', :'rid', :ver, 'MAT-OTHER', 'u-est1');
SELECT pg_temp.ok(new_version IS NULL, 'CON-02: stale MAT code save returns NULL (conflict)') FROM r;
SELECT pg_temp.ok(mat_code = 'MAT-D-SASL-30-LAM', 'the first save is kept') FROM door_rates WHERE id = :'rid';

-- Unique across ALL tables
SELECT pg_temp.throws($$UPDATE products SET mat_code = 'MAT-D-SASL-30-LAM' WHERE supplier_code = 'TS.9205'$$,
  'a MAT code on a door rate cannot be reused on a product');
SELECT pg_temp.throws($$UPDATE frame_rates SET mat_code = 'MAT-D-SASL-30-LAM' WHERE finish_code = 'SPRAY'
                        AND door_type_id = (SELECT id FROM door_types WHERE form_code = 'SASL')$$,
  'a MAT code on a door rate cannot be reused on a frame rate');
SELECT pg_temp.throws($$UPDATE vp_rates SET mat_code = '' WHERE fire_rating_code = 'NFR'$$,
  'blank MAT code rejected (use NULL)');
SELECT pg_temp.throws($$SELECT set_mat_code('jobs', gen_random_uuid(), 1, 'X', 'u-admin')$$,
  'MAT codes can only be set on priced tables');

-- Moving a code: clear it, then it's free to use elsewhere
EXECUTE set_mat_code('door_rates', :'rid', :ver + 1, NULL, 'u-admin');
UPDATE products SET mat_code = 'MAT-D-SASL-30-LAM' WHERE supplier_code = 'TS.9205';
SELECT pg_temp.ok(table_name = 'products', 'a cleared code can be used on another item') FROM mat_code_registry WHERE mat_code = 'MAT-D-SASL-30-LAM';
UPDATE products SET mat_code = 'MAT-TS9205' WHERE supplier_code = 'TS.9205';
SELECT pg_temp.ok(count(*) = 0, 'changing a code releases the old one') FROM mat_code_registry WHERE mat_code = 'MAT-D-SASL-30-LAM';

-- Missing codes come first; "only missing" filter
DROP TABLE t; CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table('product', false, NULL, false);
SELECT pg_temp.ok((SELECT mat_code FROM t OFFSET 28 LIMIT 1) = 'MAT-TS9205' AND (SELECT mat_code FROM t LIMIT 1) IS NULL,
                  'items with no MAT code are listed first') ;
DROP TABLE t; CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table(NULL, true, NULL, false);
SELECT pg_temp.ok(count(*) = 29 + 36 + 3 + 12 + 4 + 4 - 1, '"only missing" hides the one item with a code') FROM t;
DROP TABLE t; CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table(NULL, false, 'mat-ts9205', false);
SELECT pg_temp.ok(count(*) = 1, 'MAT code table can be searched by code') FROM t;
DROP TABLE t; CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table(NULL, false, 'sasl  FD30 veneer', false);
SELECT pg_temp.ok(count(*) = 1 AND min(item) LIKE 'Door SASL%FD30 / Veneer', 'search matches every word, in any order and case') FROM t;
DROP TABLE t; CREATE TEMP TABLE t ON COMMIT DROP AS EXECUTE mat_code_table(NULL, false, '', false);
SELECT pg_temp.ok(count(*) = 88, 'empty search = everything (all 88 items)') FROM t;

-- Deleting a rate row frees its code
UPDATE vp_rates SET mat_code = 'MAT-VP-NFR' WHERE fire_rating_code = 'NFR';
DELETE FROM vp_rates WHERE fire_rating_code = 'NFR';
SELECT pg_temp.ok(count(*) = 0, 'deleting a row frees its MAT code') FROM mat_code_registry WHERE mat_code = 'MAT-VP-NFR';
ROLLBACK;
