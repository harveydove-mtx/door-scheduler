-- Data rules the database itself enforces.
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;

SELECT pg_temp.throws($$INSERT INTO app_users (uid, email, display_name) VALUES ('x', 'someone@gmail.com', 'X')$$,
  'USR-01: non-Matrix email rejected');
SELECT pg_temp.throws($$INSERT INTO app_users (uid, email, display_name, role) VALUES ('x', 'x@matrixhardware.co.uk', 'X', 'owner')$$,
  'unknown role rejected');
SELECT pg_temp.throws($$UPDATE products SET verified = true WHERE supplier_code = 'VHC243RS'$$,
  'CAT-01: product cannot be verified without a MAT code');
SELECT pg_temp.throws($$UPDATE products SET mat_code = ' mat001' WHERE supplier_code = 'VHC243RS'$$,
  'MAT code must be stored upper-case and trimmed');
UPDATE products SET mat_code = 'MAT001', verified = true WHERE supplier_code = 'VHC243RS';
SELECT pg_temp.ok(verified, 'product verified once it has a MAT code') FROM products WHERE supplier_code = 'VHC243RS';
SELECT pg_temp.throws($$UPDATE products SET mat_code = 'MAT001' WHERE supplier_code = 'ZHSS243RS3'$$,
  'MAT codes are unique');
SELECT pg_temp.throws($$UPDATE job_doors SET vp_count = 9 WHERE door_mark = 'D01'$$,
  'vision panels limited to 0-8');
SELECT pg_temp.throws($$UPDATE job_doors SET qty = 0 WHERE door_mark = 'D01'$$,
  'qty must be at least 1');
SELECT pg_temp.throws($$UPDATE job_doors SET is_manual = true WHERE door_mark = 'D01'$$,
  'a manual door cannot also have a door type');
SELECT pg_temp.throws($$UPDATE job_doors SET surround = 'CASING' WHERE door_mark = 'D01'$$,
  'surround must be NONE, FRAME or LINING');
SELECT pg_temp.throws($$UPDATE jobs SET status = 'maybe' WHERE quote_ref IS NOT NULL$$,
  'job status limited to outstanding/won/lost/redundant');

-- Hardware must be in the right category column
SELECT pg_temp.throws($$
  INSERT INTO job_door_items (job_door_id, category_id, product_id)
  SELECT '00000000-0000-4000-8000-0000000000d3', c.id, p.id
  FROM product_categories c, products p WHERE c.key = 'hinges' AND p.supplier_code = 'TS.9205'$$,
  'a closer cannot be put in the hinge column');
-- Phase 1: one product per category per door
SELECT pg_temp.throws($$
  INSERT INTO job_door_items (job_door_id, category_id, product_id)
  SELECT '00000000-0000-4000-8000-0000000000d1', p.category_id, p.id FROM products p WHERE p.supplier_code = 'VHC243RS'$$,
  'phase 1: only one hinge product per door');
-- Category default must be from that category
SELECT pg_temp.throws($$
  UPDATE product_categories SET default_product_id = (SELECT id FROM products WHERE supplier_code = 'TS.9205')
  WHERE key = 'hinges'$$,
  'CAT-04: a category default must be one of its own products');
UPDATE product_categories SET default_product_id = (SELECT id FROM products WHERE supplier_code = 'ZHSS243RS3'), default_qty = 3
WHERE key = 'hinges';
SELECT pg_temp.ok(default_qty = 3, 'CAT-04: category default product + qty saved') FROM product_categories WHERE key = 'hinges';

-- Folders cannot be moved inside themselves
INSERT INTO folders (id, name, parent_id) VALUES
  ('00000000-0000-4000-8000-00000000f002', 'Child', '00000000-0000-4000-8000-00000000f001'),
  ('00000000-0000-4000-8000-00000000f003', 'Grandchild', '00000000-0000-4000-8000-00000000f002');
SELECT pg_temp.throws($$UPDATE folders SET parent_id = '00000000-0000-4000-8000-00000000f003'
                        WHERE id = '00000000-0000-4000-8000-00000000f001'$$,
  'JOB-03: folder cannot be moved into its own sub-folder');

-- Fire rating S variants point at their base rating
SELECT pg_temp.ok(base_code = 'FD30', 'RAT-02: FD30S falls back to FD30') FROM fire_ratings WHERE code = 'FD30S';
SELECT pg_temp.ok(base_finish_code = 'PRIMED', 'SPRAY priced as uplift on PRIMED') FROM door_finishes WHERE code = 'SPRAY';
ROLLBACK;
