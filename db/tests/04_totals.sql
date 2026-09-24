-- Line and job totals match V1 arithmetic (see hand calculations in sample_data.sql).
BEGIN;
CREATE TEMP TABLE lines ON COMMIT DROP AS
  SELECT * FROM v_job_door_lines WHERE job_id = '00000000-0000-4000-8000-0000000000a1';

SELECT pg_temp.ok(cost_hardware = 48.58, 'D01 hardware = 48.58 (qty x snapshot cost)') FROM lines WHERE door_mark = 'D01';
SELECT pg_temp.ok(unit_cost = 913.63, 'D01 unit cost = 913.63') FROM lines WHERE door_mark = 'D01';
SELECT pg_temp.ok(line_cost = 2740.89, 'D01 line cost = 2740.89 (x3)') FROM lines WHERE door_mark = 'D01';
SELECT pg_temp.ok(line_sell = 3343.89, 'D01 sell = round(2740.89 x 1.22, 2) = 3343.89 (V1 rounding)') FROM lines WHERE door_mark = 'D01';
SELECT pg_temp.ok(unit_cost = 823.95 AND line_sell = 1005.22, 'D02 spray + flush bolts = 823.95 / 1005.22') FROM lines WHERE door_mark = 'D02';
SELECT pg_temp.ok(line_cost = 500 AND line_sell = 800, 'D03 sell override is per unit x qty (800)') FROM lines WHERE door_mark = 'D03';

SELECT pg_temp.ok(total_cost = 4414.84 AND total_sell = 5576.11 AND door_rows = 3 AND door_count = 6
                  AND screen_count = 1,
                  'job totals include doors and the door screen (4414.84 / 5576.11, 6 doors)')
FROM v_job_totals WHERE job_id = '00000000-0000-4000-8000-0000000000a1';

-- Markup change flows straight through
UPDATE jobs SET markup_pct = 0.30 WHERE id = '00000000-0000-4000-8000-0000000000a1';
SELECT pg_temp.ok(line_sell = round(2740.89 * 1.30, 2), 'changing job markup reprices sell immediately')
FROM v_job_door_lines WHERE door_mark = 'D01' AND job_id = '00000000-0000-4000-8000-0000000000a1';
UPDATE jobs SET markup_pct = 0.22 WHERE id = '00000000-0000-4000-8000-0000000000a1';

-- Linings: depth over threshold needs an uplift (RAT-05a)
SELECT pg_temp.ok(NOT needs_lining_uplift, 'no threshold set -> no uplift needed') FROM v_job_door_lines WHERE door_mark = 'D02';
UPDATE settings SET value = '150' WHERE key = 'lining_depth_threshold_mm';
SELECT pg_temp.ok(needs_lining_uplift, 'RAT-05a: 180mm lining over 150mm threshold asks for uplift') FROM v_job_door_lines WHERE door_mark = 'D02';
SELECT pg_temp.ok(lining_uplift_missing = 1, 'RAT-05a: job shows 1 lining missing its uplift')
FROM v_job_totals WHERE job_id = '00000000-0000-4000-8000-0000000000a1';
UPDATE job_doors SET lining_uplift = 45 WHERE door_mark = 'D02';
SELECT pg_temp.ok(NOT needs_lining_uplift AND unit_cost = 868.95, 'RAT-05a: uplift entered -> added to unit cost (823.95 + 45)')
FROM v_job_door_lines WHERE door_mark = 'D02';
UPDATE job_doors SET lining_depth_mm = 120 WHERE door_mark = 'D02';
SELECT pg_temp.ok(NOT needs_lining_uplift, 'RAT-05a: lining under threshold needs no uplift') FROM v_job_door_lines WHERE door_mark = 'D02';
-- Uplift only counts while the door actually has a lining
UPDATE job_doors SET surround = 'FRAME' WHERE door_mark = 'D02';
SELECT pg_temp.ok(unit_cost = 823.95, 'lining uplift ignored once the door is switched to a frame') FROM v_job_door_lines WHERE door_mark = 'D02';

-- Deleted jobs drop out of v_jobs but keep their data (JOB-08)
UPDATE jobs SET deleted_at = now(), deleted_by = 'u-admin' WHERE id = '00000000-0000-4000-8000-0000000000a4';
SELECT pg_temp.ok(count(*) = 3, 'JOB-08: soft-deleted job hidden from the job list') FROM v_jobs;
SELECT pg_temp.ok(count(*) = 1, 'JOB-08: soft-deleted job still restorable') FROM jobs WHERE deleted_at IS NOT NULL;
ROLLBACK;
