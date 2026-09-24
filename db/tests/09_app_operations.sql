-- The queries behind the V2 app's Data Connect operations (dataconnect/connector).
BEGIN;
-- EnsureMe: first sign-in creates the user, later sign-ins return the same row
EXECUTE ensure_me('uid-harvey', 'Harvey.Dove@MatrixHardware.co.uk') \gset me_
SELECT pg_temp.ok(:'me_email' = 'harvey.dove@matrixhardware.co.uk' AND :'me_display_name' = 'Harvey Dove'
                  AND :'me_role' = 'estimator', 'EnsureMe creates the user: lower-case email, name from the email');
EXECUTE ensure_me('uid-harvey', 'harvey.dove@matrixhardware.co.uk') \gset me2_
SELECT pg_temp.ok(:'me2_uid' = 'uid-harvey', 'EnsureMe again returns the existing user');
SELECT pg_temp.ok(count(*) = 1, 'no duplicate user row') FROM app_users WHERE uid = 'uid-harvey';
SELECT pg_temp.throws($$EXECUTE ensure_me('uid-x', 'x@gmail.com')$$, 'EnsureMe refuses a non-Matrix email');

-- Settings and categories
CREATE TEMP TABLE st ON COMMIT DROP AS EXECUTE get_settings;
SELECT pg_temp.ok((SELECT value FROM st WHERE key = 'lining_depth_threshold_mm') = '150', 'GetSettings returns the lining threshold');
CREATE TEMP TABLE cat ON COMMIT DROP AS EXECUTE list_categories;
SELECT pg_temp.ok(count(*) = 16 AND (SELECT key FROM cat LIMIT 1) = 'hinges', 'ListCategories: 16 categories, hinges first') FROM cat;

-- SetMatCode: only the named table is touched; stale saves change nothing
SELECT id AS rid, version AS ver FROM frame_rates WHERE finish_code = 'SPRAY'
  AND door_type_id = (SELECT id FROM door_types WHERE form_code = 'SASL') \gset
EXECUTE set_mat_code__products('frame_rates', :'rid', :ver, 'MAT-FR-1', 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 0, 'the products statement ignores a frame_rates save');
EXECUTE set_mat_code__frame_rates('frame_rates', :'rid', :ver, ' mat-fr-1 ', 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 1, 'the frame_rates statement saves it');
SELECT pg_temp.ok(mat_code = 'MAT-FR-1' AND updated_by = 'uid-harvey', 'MAT code saved upper-case, by the signed-in user')
FROM frame_rates WHERE id = :'rid';
EXECUTE set_mat_code__frame_rates('frame_rates', :'rid', :ver, 'MAT-FR-2', 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 0, 'CON-02: stale MAT code save rejected');
EXECUTE set_mat_code__frame_rates('frame_rates', :'rid', :ver + 1, '', 'uid-harvey');
SELECT pg_temp.ok(mat_code IS NULL, 'blank MAT code clears it') FROM frame_rates WHERE id = :'rid';

-- MatCodeOwner
UPDATE vp_rates SET mat_code = 'MAT-VP-30' WHERE fire_rating_code = 'FD30';
CREATE TEMP TABLE o ON COMMIT DROP AS EXECUTE mat_code_owner(' mat-vp-30');
SELECT pg_temp.ok(table_name = 'vp_rates' AND item LIKE 'Vision panel FD30%', 'MatCodeOwner says where a code is used') FROM o;
DROP TABLE o; CREATE TEMP TABLE o ON COMMIT DROP AS EXECUTE mat_code_owner('MAT-UNUSED');
SELECT pg_temp.ok(count(*) = 0, 'MatCodeOwner: unused code -> nothing') FROM o;

-- SetPrice
SELECT id AS pid, version AS pver FROM products WHERE supplier_code = 'TS.9205' \gset
EXECUTE set_price__products('products', :'pid', :pver, '33.10', 'uid-harvey');
SELECT pg_temp.ok(cost = 33.10, 'SetPrice saves a product cost exactly (text -> numeric)') FROM products WHERE id = :'pid';
SELECT pg_temp.ok(new_cost = 33.10 AND changed_by = 'uid-harvey', 'price history records the change')
FROM product_cost_history WHERE product_id = :'pid';
EXECUTE set_price__products('products', :'pid', :pver, '1.00', 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 0, 'CON-02: stale price save rejected');
SELECT pg_temp.throws(format($$EXECUTE set_price__products('products', %L, %s, '-1', 'uid-harvey')$$, :'pid', :pver + 1),
  'negative prices rejected');

-- AddProduct / UpdateProduct
SELECT id AS closers FROM product_categories WHERE key = 'closers' \gset
EXECUTE add_product(:'closers', ' mat-cl-9 ', ' DC200 ', ' DC200 closer ', '', NULL, '42.5', 'uid-harvey') \gset np
SELECT pg_temp.ok(mat_code = 'MAT-CL-9' AND supplier_code = 'DC200' AND description = 'DC200 closer' AND finish IS NULL
                  AND unit = 'each' AND cost = 42.50 AND NOT verified AND created_by = 'uid-harvey',
                  'AddProduct: trimmed, blank -> null, unit defaults to each, unverified')
FROM products WHERE id = :'npid';
EXECUTE update_product(:'npid', 1, 'DC200 closer SSS', 'DC200', 'SSS', 'each', false, 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 1, 'UpdateProduct saves with the current version');
SELECT pg_temp.ok(finish = 'SSS' AND NOT active AND version = 2, 'product updated and deactivated') FROM products WHERE id = :'npid';
EXECUTE update_product(:'npid', 1, 'overwrite', NULL, NULL, NULL, true, 'uid-harvey');
SELECT pg_temp.ok(:ROW_COUNT = 0, 'CON-02: stale product edit rejected');
ROLLBACK;
