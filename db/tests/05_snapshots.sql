-- Price snapshots and "reprice to current rates" (spec JOB-06, CAT-06, CAT-07).
BEGIN;
-- Adding hardware copies the catalogue price, MAT code and description onto the door.
UPDATE products SET mat_code = 'MAT-TS9205' WHERE supplier_code = 'TS.9205';
INSERT INTO job_door_items (job_door_id, category_id, product_id, qty)
SELECT '00000000-0000-4000-8000-0000000000d2', category_id, id, 2 FROM products WHERE supplier_code = 'TS.9205';
SELECT pg_temp.ok(i.unit_cost = 31.42 AND i.mat_code = 'MAT-TS9205' AND i.description = p.description,
                  'adding a product snapshots its cost, MAT code and description')
FROM job_door_items i JOIN products p ON p.id = i.product_id
WHERE i.job_door_id = '00000000-0000-4000-8000-0000000000d2' AND p.supplier_code = 'TS.9205';

-- A catalogue price rise does NOT change saved jobs.
UPDATE products SET cost = 35.00, updated_by = 'u-admin' WHERE supplier_code = 'TS.9205';
SELECT pg_temp.ok(unit_cost = 913.63, 'JOB-06: price rise leaves the quoted door unchanged (913.63)')
FROM v_job_door_lines WHERE door_mark = 'D01';

-- ...but it is recorded in price history.
SELECT pg_temp.ok(old_cost = 31.42 AND new_cost = 35.00 AND changed_by = 'u-admin',
                  'CAT-07: cost change recorded in price history')
FROM product_cost_history h JOIN products p ON p.id = h.product_id WHERE p.supplier_code = 'TS.9205';

-- Preview shows what repricing would change.
CREATE TEMP TABLE pv ON COMMIT DROP AS
  EXECUTE reprice_job_hardware_preview('00000000-0000-4000-8000-0000000000a1');
SELECT pg_temp.ok(count(*) = 2, 'JOB-06: preview lists the two closer lines that changed') FROM pv;
SELECT pg_temp.ok(line_cost_change = (35.00 - 31.42) * 1 * 3, 'preview shows the D01 cost change (x door qty 3)')
FROM pv WHERE door_mark = 'D01';

-- Swapping a product re-snapshots from the catalogue.
UPDATE job_door_items SET product_id = (SELECT id FROM products WHERE supplier_code = 'TS.4204')
WHERE job_door_id = '00000000-0000-4000-8000-0000000000d2'
  AND product_id = (SELECT id FROM products WHERE supplier_code = 'TS.9205');
SELECT pg_temp.ok(i.unit_cost = 20.97 AND i.description LIKE 'TS.4204%', 'swapping a product takes the new product''s price')
FROM job_door_items i JOIN products p ON p.id = i.product_id
WHERE i.job_door_id = '00000000-0000-4000-8000-0000000000d2' AND p.supplier_code = 'TS.4204';

-- Apply the reprice.
EXECUTE reprice_job_hardware('00000000-0000-4000-8000-0000000000a1', 'u-est1');
SELECT pg_temp.ok(:ROW_COUNT = 1, 'reprice updates only the out-of-date line');
SELECT pg_temp.ok(unit_cost = 913.63 + 3.58, 'D01 now priced at current rates (+3.58)')
FROM v_job_door_lines WHERE door_mark = 'D01';

-- Deactivated products stay on old jobs (CAT-06), flagged as inactive.
UPDATE products SET active = false WHERE supplier_code = 'ZCS2030SS';
CREATE TEMP TABLE ji ON COMMIT DROP AS EXECUTE load_job_door_items('00000000-0000-4000-8000-0000000000a1');
SELECT pg_temp.ok(count(*) = 1 AND bool_and(NOT product_active), 'CAT-06: inactive product still on the job, flagged inactive')
FROM ji WHERE description LIKE 'ZCS2030SS%';
SELECT pg_temp.throws($$DELETE FROM products WHERE supplier_code = 'ZCS2030SS'$$,
  'a product used on a job cannot be hard-deleted');
ROLLBACK;
