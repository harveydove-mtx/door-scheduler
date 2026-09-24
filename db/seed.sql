-- seed.sql
-- Starting reference data for a fresh V2 database. Everything here was hard-coded in V1
-- (index.html DEFAULT_RATES lines 368-453, constants 455-471, PDF terms 3321-3337).
-- Live V1 rates held in Firestore are imported later by the V1 -> V2 migration, not here.
--
-- Safe to run once on an empty database. Contains NO users and NO jobs
-- (dev sample data lives in db/sample_data.sql).

BEGIN;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
INSERT INTO settings (key, value, description) VALUES
  ('default_markup_pct',        '0.22',  'Markup on cost for new jobs (0.22 = 22%)'),
  ('quote_ref_prefix',          '"MH"',  'Prefix for quote references, e.g. MH-2026-0001'),
  ('lining_depth_threshold_mm', '150',   'Linings up to this depth (mm) are standard; deeper ones need an uplift cost'),
  ('quote_terms', jsonb_build_array(
     'Prices are valid for 30 days from the date of this quotation unless otherwise stated.',
     'All prices are exclusive of VAT unless stated otherwise.',
     'Payment terms: 30 days from date of invoice unless otherwise agreed.',
     'Delivery lead times are subject to stock availability at time of order.',
     'All goods remain the property of Matrix Hardware until paid for in full.',
     'This quotation is based on the information provided. Any variations may result in price adjustments.',
     'Installation is not included unless specifically stated.'),
   'Terms & Conditions printed on the PDF quote'),
  ('quote_footer', jsonb_build_array(
     'Matrix Hardware  |  Architectural Ironmongery Specialists',
     'www.matrixhardware.co.uk  |  sales@matrixhardware.co.uk'),
   'Footer lines printed on the PDF quote');

-- ---------------------------------------------------------------------------
-- Lookup lists
-- ---------------------------------------------------------------------------
INSERT INTO fire_ratings (code, label, base_code, is_fire_door, sort) VALUES
  ('NFR',  'NFR (non fire rated)', NULL, false, 10),
  ('FD30', 'FD30',                 NULL, true,  20),
  ('FD60', 'FD60',                 NULL, true,  40);
INSERT INTO fire_ratings (code, label, base_code, is_fire_door, sort) VALUES
  ('FD30S', 'FD30S (smoke sealed)', 'FD30', true, 30),
  ('FD60S', 'FD60S (smoke sealed)', 'FD60', true, 50);

INSERT INTO handings (code, label, sort) VALUES
  ('LH', 'Left hand', 10), ('RH', 'Right hand', 20), ('N/A', 'N/A', 30);

INSERT INTO door_finishes (code, label, base_finish_code, sort) VALUES
  ('PRIMED',   'Primed',   NULL, 10),
  ('LAMINATE', 'Laminate', NULL, 20),
  ('VENEER',   'Veneer',   NULL, 30);
INSERT INTO door_finishes (code, label, base_finish_code, sort) VALUES
  ('SPRAY',    'Spray',    'PRIMED', 40);   -- priced as PRIMED + spray uplift (V1 sprayAdd)

INSERT INTO frame_finishes (code, label, sort) VALUES
  ('PRIMED', 'Primed', 10), ('HARDWOOD/OAK', 'Hardwood / Oak', 20),
  ('HARDWOOD SPRAY', 'Hardwood spray', 30), ('SPRAY', 'Spray', 40);

-- Lining finishes: starting list, TO CONFIRM. No lining prices yet (spec Q1).
INSERT INTO lining_finishes (code, label, sort) VALUES
  ('PRIMED', 'Primed', 10), ('HARDWOOD/OAK', 'Hardwood / Oak', 20), ('SPRAY', 'Spray', 30);

INSERT INTO over_panel_types (code, label, sort) VALUES
  ('SOLID', 'Solid', 10), ('GLAZED', 'Glazed', 20);

INSERT INTO door_types (form_code, description, leaf_count, needs_flush_bolts, sort) VALUES
  ('SASL', 'SINGLE ACTION SINGLE LEAF',   1,   false, 10),
  ('SALH', 'SINGLE ACTION LEAF AND HALF', 1.5, true,  20),
  ('SADL', 'SINGLE ACTION DOUBLE LEAF',   2,   true,  30);

-- V1 'NONE' is represented by NULL on the door, so it is not seeded.
INSERT INTO architrave_types (code, label, price, sort) VALUES
  ('PRIMED', 'Primed', 0, 10), ('SPRAY', 'Spray', 0, 20),
  ('BESPOKE', 'Bespoke', 40, 30), ('TBC', 'TBC', 0, 40);

-- ---------------------------------------------------------------------------
-- Door rates (V1 rates.doors). SPRAY row = uplift on PRIMED.
-- ---------------------------------------------------------------------------
INSERT INTO door_rates (door_type_id, fire_rating_code, finish_code, price)
SELECT dt.id, v.fire, f.finish, f.price
FROM (VALUES
  ('SADL', 'FD30', 621.72, 770.56, 823.17, 187.59),
  ('SADL', 'NFR',  621.72, 770.56, 823.17, 187.59),
  ('SADL', 'FD60', 794.60, 943.43, 996.04, 187.59),
  ('SALH', 'FD30', 578.91, 733.81, 758.45, 187.59),
  ('SALH', 'NFR',  578.91, 733.81, 758.45, 187.59),
  ('SALH', 'FD60', 729.36, 884.26, 908.90, 187.59),
  ('SASL', 'FD30', 387.43, 461.84, 488.15, 187.59),
  ('SASL', 'NFR',  387.43, 461.84, 488.15, 187.59),
  ('SASL', 'FD60', 518.43, 592.85, 619.15, 187.59)
) AS v(form_code, fire, primed, laminate, veneer, spray_add)
JOIN door_types dt ON dt.form_code = v.form_code
CROSS JOIN LATERAL (VALUES
  ('PRIMED', v.primed), ('LAMINATE', v.laminate), ('VENEER', v.veneer), ('SPRAY', v.spray_add)
) AS f(finish, price);

INSERT INTO vp_rates (fire_rating_code, price, glass_desc) VALUES
  ('NFR',  100.42, '6.4mm Laminated Glass'),
  ('FD30', 127.01, '7mm Pyrobelite 1/2hr'),
  ('FD60', 194.77, '12mm Pyrobelite 1hr');

-- Frame rates (V1 rates.frames)
INSERT INTO frame_rates (door_type_id, finish_code, price)
SELECT dt.id, f.finish, f.price
FROM (VALUES
  ('SASL', 0, 226.20, 0, 85),
  ('SALH', 0, 260.80, 0, 95),
  ('SADL', 0, 260.80, 0, 95)
) AS v(form_code, primed, hardwood, hardwood_spray, spray)
JOIN door_types dt ON dt.form_code = v.form_code
CROSS JOIN LATERAL (VALUES
  ('PRIMED', v.primed), ('HARDWOOD/OAK', v.hardwood),
  ('HARDWOOD SPRAY', v.hardwood_spray), ('SPRAY', v.spray)
) AS f(finish, price);

-- Over panel rates (V1 rates.overPanels). V1 only priced LAMINATE (other columns were 0,
-- which V1 treated as "fall back to laminate"); the pricing engine keeps that fallback.
INSERT INTO over_panel_rates (door_type_id, fire_rating_code, panel_type_code, finish_code, price)
SELECT dt.id, v.fire, v.panel, 'LAMINATE', v.price
FROM (VALUES
  ('SASL', 'NFR',  'SOLID',  189.01),
  ('SASL', 'NFR',  'GLAZED', 177.22),
  ('SASL', 'FD30', 'SOLID',  199.85),
  ('SASL', 'FD30', 'GLAZED', 211.65)
) AS v(form_code, fire, panel, price)
JOIN door_types dt ON dt.form_code = v.form_code;

-- ---------------------------------------------------------------------------
-- Product categories (V1 HW_CATEGORIES) and products (V1 rates.hardware)
-- ---------------------------------------------------------------------------
INSERT INTO product_categories (key, label, door_field_key, sort) VALUES
  ('hinges',       'Hinges',            'hinge',       10),
  ('closers',      'Closers',           'closer',      20),
  ('intumescents', 'Intumescents',      'intumescent', 30),
  ('lockcases',    'Lockcases',         'lockcase',    40),
  ('levers',       'Lever Handles',     'lever',       50),
  ('pushPull',     'Push/Pull',         'pushPull',    60),
  ('combiLocks',   'Combination Locks', 'combiLock',   70),
  ('escutcheons',  'Escutcheons',       'escutcheon',  80),
  ('flushBolts',   'Flush Bolts',       'flushBolt',   90),
  ('kickPlates',   'Kick Plates',       'kickPlate',  100),
  ('fingerGuards', 'Finger Guards',     'fingerGuard',110),
  ('signage',      'Signage',           'signage',    120),
  ('thresholds',   'Thresholds',        'threshold',  130),
  ('dropseals',    'Dropseals',         'dropseal',   140),
  ('cylinders',    'Cylinders',         'cylinder',   150),
  ('doorStops',    'Door Stops',        'doorStop',   160);

-- Quantity is no longer part of the product name: V1 "ZHSS243RS3 X 2" is product
-- ZHSS243RS3 at qty 2 on the door; "2 x FDKL SS" is FDKL SS at qty 2; "ZCS2001SS X 2"
-- at £1.40 is ZCS2001SS at £0.70 each. MAT codes are not known yet, so products are
-- seeded with supplier codes, unverified, awaiting MAT codes (spec Q10).
-- V1's only door stop was "None" at £1 (V1 bug 1), so no door stop products are seeded.
INSERT INTO products (category_id, supplier_code, description, cost)
SELECT c.id, v.code, v.descr, v.cost
FROM (VALUES
  ('hinges',       'VHC243RS',            'VHC243RS hinge',                         5.95),
  ('hinges',       'ZHSS243RS3',          'ZHSS243RS3 hinge',                       3.48),
  ('closers',      'TS.9205',             'TS.9205 EN2-5 SNP closer',              31.42),
  ('closers',      'TS.4204',             'TS.4204 EN2-4 SNP closer',              20.97),
  ('intumescents', 'LAS1212',             'LAS1212 intumescent',                    0),
  ('intumescents', '104FOW',              '104FOW intumescent',                     0),
  ('intumescents', '154FOW',              '154FOW intumescent',                     0),
  ('intumescents', '204FOW',              '204FOW intumescent',                     0),
  ('intumescents', '104SFW',              '104SFW intumescent',                     0),
  ('intumescents', '154SFW',              '154SFW intumescent',                     0),
  ('lockcases',    'ZDL7260RSS',          'ZDL7260RSS lockcase',                    5.50),
  ('lockcases',    'ZDL70060RSS',         'ZDL70060RSS lockcase',                   5.50),
  ('levers',       'ZCS2030SS',           'ZCS2030SS lever handle',                 3.50),
  ('pushPull',     'ZAS32RCS/ZCS2D425',   'ZAS32RCS / ZCS2D425 push/pull set',      7.00),
  ('combiLocks',   'BL2501 FT',           'BL2501 FT combination lock',            47.00),
  ('escutcheons',  'ZCS2001SS',           'ZCS2001SS escutcheon',                   0.70),
  ('escutcheons',  'ZAS16SS',             'ZAS16SS escutcheon',                     2.23),
  ('flushBolts',   'ZAS03RS',             'ZAS03RS flush bolt',                     7.32),
  ('kickPlates',   'KP-200',              'Kick plate 200mm high',                  5.50),
  ('fingerGuards', 'ROLLER FINGER GUARD', 'Roller finger guard',                   75.00),
  ('signage',      'FDKL SS',             'FDKL SS sign (Fire door keep locked)',   0.60),
  ('signage',      'FDKS SS',             'FDKS SS sign (Fire door keep shut)',     0.60),
  ('signage',      'AFDKC SS',            'AFDKC SS sign (Auto fire door keep clear)', 0.80),
  ('thresholds',   'NOR620-1000',         'NOR620 threshold 1000mm',                6.15),
  ('thresholds',   'NOR625-1000',         'NOR625 threshold 1000mm',               13.10),
  ('dropseals',    'NOR810S',             'NOR810S dropseal',                       0),
  ('dropseals',    'NOR810',              'NOR810 dropseal',                        0),
  ('cylinders',    'V5EP70CTSC',          'V5EP70CTSC cylinder',                    3.60),
  ('cylinders',    'V5EP80CTSC',          'V5EP80CTSC cylinder',                    3.82)
) AS v(cat, code, descr, cost)
JOIN product_categories c ON c.key = v.cat;

COMMIT;
