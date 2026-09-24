-- sample_data.sql
-- DEVELOPMENT / TEST ONLY. Never load into the live database.
-- Test users, a client, and jobs whose price snapshots were worked out by hand from the
-- seed (= V1 default) rates, so the tests can check V2 totals against V1 arithmetic.

BEGIN;

INSERT INTO app_users (uid, email, display_name, role) VALUES
  ('u-admin', 'test.admin@matrixhardware.co.uk',      'Test Admin',         'admin'),
  ('u-est1',  'test.estimator1@matrixhardware.co.uk', 'Test Estimator One', 'estimator'),
  ('u-est2',  'test.estimator2@matrixhardware.co.uk', 'Test Estimator Two', 'estimator');

INSERT INTO clients (id, company, site, contact_name, email, created_by, updated_by) VALUES
  ('00000000-0000-4000-8000-00000000c001', 'Example Builders Ltd', 'Riverside Apartments',
   'Sam Example', 'sam@example.com', 'u-est1', 'u-est1');

INSERT INTO folders (id, name, created_by, updated_by) VALUES
  ('00000000-0000-4000-8000-00000000f001', 'Sample folder', 'u-est1', 'u-est1');

-- ---------------------------------------------------------------------------
-- Job 1: outstanding, three door lines + one door screen
-- ---------------------------------------------------------------------------
INSERT INTO jobs (id, project_name, client_id, client_company, site, contact_name, contact_email,
                  markup_pct, folder_id, prepared_by, created_by, updated_by)
VALUES ('00000000-0000-4000-8000-0000000000a1', 'Riverside Apartments - Block A',
        '00000000-0000-4000-8000-00000000c001', 'Example Builders Ltd', 'Riverside Apartments',
        'Sam Example', 'sam@example.com', 0.22, '00000000-0000-4000-8000-00000000f001',
        'u-est1', 'u-est1', 'u-est1');

-- D01: SASL, FD30S (prices as FD30), laminate, 1 VP, hardwood/oak frame, bespoke architrave,
-- qty 3, £10 uplift.
--   door 461.84 + VP 127.01 + frame 226.20 + architrave 40.00
--   + hardware (ZHSS243RS3 2 x 3.48 + TS.9205 31.42 + FDKS 2 x 0.60 + ZCS2030SS 3.50
--               + ZDL7260RSS 5.50 + LAS1212 0) = 48.58
--   + uplift 10.00                             = unit 913.63
--   line cost 913.63 x 3 = 2740.89; sell round(2740.89 x 1.22, 2) = 3343.89
INSERT INTO job_doors (id, job_id, sort_order, qty, door_mark, location, door_type_id,
                       width_mm, height_mm, handing_code, fire_rating_code, vp_count, door_finish_code,
                       surround, frame_finish_code, architrave_type_id, added_uplift,
                       cost_door, cost_vp, cost_surround, cost_architrave, cost_over_panel, priced_at,
                       created_by, updated_by)
SELECT '00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000a1', 1, 3,
       'D01', 'Flat 1 entrance', dt.id, 926, 2040, 'LH', 'FD30S', 1, 'LAMINATE',
       'FRAME', 'HARDWOOD/OAK', a.id, 10,
       461.84, 127.01, 226.20, 40.00, 0, now(), 'u-est1', 'u-est1'
FROM door_types dt, architrave_types a WHERE dt.form_code = 'SASL' AND a.code = 'BESPOKE';

-- D02: SADL, NFR, spray (primed 621.72 + spray 187.59 = 809.31), LINING 180mm deep with
-- no uplift entered yet (over the 150mm threshold, so flagged), 2 flush bolts (2 x 7.32 = 14.64).
--   unit 823.95; sell round(823.95 x 1.22, 2) = 1005.22
INSERT INTO job_doors (id, job_id, sort_order, qty, door_mark, location, door_type_id,
                       width_mm, height_mm, handing_code, fire_rating_code, door_finish_code,
                       surround, lining_finish_code, lining_depth_mm,
                       cost_door, priced_at, created_by, updated_by)
SELECT '00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000a1', 2, 1,
       'D02', 'Plant room', dt.id, 1626, 2040, 'N/A', 'NFR', 'SPRAY',
       'LINING', 'PRIMED', 180, 809.31, now(), 'u-est1', 'u-est1'
FROM door_types dt WHERE dt.form_code = 'SADL';

-- D03: manual door, cost 250, sell overridden at 400 per unit, qty 2 -> sell 800
INSERT INTO job_doors (id, job_id, sort_order, qty, door_mark, is_manual, manual_desc,
                       sell_override, cost_door, priced_at, created_by, updated_by)
VALUES ('00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000a1', 3, 2,
        'D03', true, 'Bespoke riser door', 400, 250, now(), 'u-est1', 'u-est1');

INSERT INTO job_door_items (job_door_id, category_id, product_id, qty, created_by, updated_by)
SELECT v.door::uuid, p.category_id, p.id, v.qty, 'u-est1', 'u-est1'
FROM (VALUES
  ('00000000-0000-4000-8000-0000000000d1', 'ZHSS243RS3', 2),
  ('00000000-0000-4000-8000-0000000000d1', 'TS.9205',    1),
  ('00000000-0000-4000-8000-0000000000d1', 'FDKS SS',    2),
  ('00000000-0000-4000-8000-0000000000d1', 'ZCS2030SS',  1),
  ('00000000-0000-4000-8000-0000000000d1', 'ZDL7260RSS', 1),
  ('00000000-0000-4000-8000-0000000000d1', 'LAS1212',    1),
  ('00000000-0000-4000-8000-0000000000d2', 'ZAS03RS',    2)
) AS v(door, code, qty)
JOIN products p ON p.supplier_code = v.code;

-- Door screen beside D01, manual cost 350 -> sell 427.00
INSERT INTO job_screens (job_id, job_door_id, sort_order, qty, screen_mark, location,
                         width_mm, height_mm, fire_rating_code, glazing_desc, unit_cost,
                         created_by, updated_by)
VALUES ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000d1', 1, 1,
        'S01', 'Beside D01', 400, 2040, 'FD30', '7mm Pyrobelite', 350, 'u-est1', 'u-est1');

-- ---------------------------------------------------------------------------
-- Jobs 2-4: won / lost / redundant, one manual door each (for dashboard figures)
-- ---------------------------------------------------------------------------
INSERT INTO jobs (id, project_name, client_company, status, prepared_by, created_by, updated_by) VALUES
  ('00000000-0000-4000-8000-0000000000a2', 'Won sample job',       'Example Builders Ltd', 'won',       'u-est2', 'u-est2', 'u-est2'),
  ('00000000-0000-4000-8000-0000000000a3', 'Lost sample job',      'Other Contractor Ltd', 'lost',      'u-est2', 'u-est2', 'u-est2'),
  ('00000000-0000-4000-8000-0000000000a4', 'Redundant sample job', 'Other Contractor Ltd', 'redundant', 'u-est2', 'u-est2', 'u-est2');

INSERT INTO job_doors (job_id, sort_order, qty, door_mark, is_manual, manual_desc, cost_door, created_by, updated_by) VALUES
  ('00000000-0000-4000-8000-0000000000a2', 1, 1, 'W1', true, 'Manual door',  100, 'u-est2', 'u-est2'),  -- sell 122.00
  ('00000000-0000-4000-8000-0000000000a3', 1, 1, 'L1', true, 'Manual door',  200, 'u-est2', 'u-est2'),  -- sell 244.00
  ('00000000-0000-4000-8000-0000000000a4', 1, 1, 'R1', true, 'Manual door', 1000, 'u-est2', 'u-est2');  -- sell 1220.00

COMMIT;
