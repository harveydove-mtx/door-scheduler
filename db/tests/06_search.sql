-- Catalogue and job search (spec CAT-05, JOB-09).
BEGIN;

DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('9205', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 1 AND min(supplier_code) = 'TS.9205', 'partial code "9205" finds TS.9205 closer') FROM s;

DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('fdks', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 1 AND min(category_key) = 'signage', 'lower-case "fdks" finds the FDKS sign') FROM s;

DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('zhss hinge', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 1, 'every word must match: "zhss hinge" finds one hinge') FROM s;

SELECT id AS closers_id FROM product_categories WHERE key = 'closers' \gset
DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('closer', :'closers_id', false, 20);
SELECT pg_temp.ok(count(*) = 2, 'category filter: 2 closers') FROM s;

DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('intumescent', NULL, false, 3);
SELECT pg_temp.ok(count(*) = 3, 'result limit respected') FROM s;

-- Exact MAT code ranks first
UPDATE products SET mat_code = 'MAT104' WHERE supplier_code = '104SFW';
UPDATE products SET description = description || ' (see MAT104)' WHERE supplier_code = '104FOW';
DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('mat104', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 2, 'MAT code search finds both mentions') FROM s;
SELECT pg_temp.ok(supplier_code = '104SFW', 'exact MAT code match is ranked first')
FROM (SELECT * FROM s LIMIT 1) x;

-- Inactive products hidden unless asked for
UPDATE products SET active = false WHERE supplier_code = 'NOR810';
DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('nor810', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 1, 'inactive products hidden by default') FROM s;
DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('nor810', NULL, true, 20);
SELECT pg_temp.ok(count(*) = 2, 'inactive products shown when requested') FROM s;

DROP TABLE IF EXISTS s; CREATE TEMP TABLE s AS EXECUTE search_products('100%', NULL, false, 20);
SELECT pg_temp.ok(count(*) = 0, 'special characters are searched literally') FROM s;

-- Jobs
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('riverside', NULL, 20);
SELECT pg_temp.ok(count(*) = 1, 'job found by project/site name') FROM js;
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('example builders', NULL, 20);
SELECT pg_temp.ok(count(*) = 2, 'jobs found by client company') FROM js;
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('example builders', 'won', 20);
SELECT pg_temp.ok(count(*) = 1, 'job search filtered by status') FROM js;
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('plant room', NULL, 20);
SELECT pg_temp.ok(count(*) = 1, 'job found by a door location') FROM js;
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('zas03rs', NULL, 20);
SELECT pg_temp.ok(count(*) = 1, 'job found by a product code used on its doors') FROM js;
SELECT quote_ref AS lost_ref FROM jobs WHERE project_name = 'Lost sample job' \gset
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs(:'lost_ref', NULL, 20);
SELECT pg_temp.ok(count(*) = 1 AND min(project_name) = 'Lost sample job', 'job found by quote ref') FROM js;
UPDATE jobs SET deleted_at = now() WHERE project_name = 'Won sample job';
DROP TABLE IF EXISTS js; CREATE TEMP TABLE js AS EXECUTE search_jobs('example builders', NULL, 20);
SELECT pg_temp.ok(count(*) = 1, 'deleted jobs excluded from search') FROM js;
ROLLBACK;
