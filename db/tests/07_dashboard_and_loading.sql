-- Dashboard figures (spec DSH-01..04) and the job-loading queries.
BEGIN;
CREATE TEMP TABLE d ON COMMIT DROP AS
  EXECUTE dashboard_summary(extract(year FROM now() AT TIME ZONE 'Europe/London')::integer, NULL);
SELECT pg_temp.ok(pipeline_value = 5576.11 AND outstanding_count = 1, 'DSH-01: pipeline = outstanding job sell (5576.11)') FROM d;
SELECT pg_temp.ok(won_this_year = 122.00, 'DSH-01: won this year = 122.00') FROM d;
SELECT pg_temp.ok(win_rate = 0.5, 'DSH-01: win rate = won / (won + lost) = 50%') FROM d;
SELECT pg_temp.ok(average_quote = 1980.70, 'DSH-01: average quote excludes redundant jobs (1980.70)') FROM d;
SELECT pg_temp.ok(follow_ups_due = 0, 'no follow-ups due on a new job') FROM d;
DROP TABLE d;

UPDATE jobs SET created_at = now() - interval '45 days' WHERE id = '00000000-0000-4000-8000-0000000000a1';
CREATE TEMP TABLE d ON COMMIT DROP AS
  EXECUTE dashboard_summary(extract(year FROM now() AT TIME ZONE 'Europe/London')::integer, NULL);
SELECT pg_temp.ok(follow_ups_due = 1, 'DSH-02: outstanding quote 30+ days old flagged for follow-up') FROM d;
DROP TABLE d;

CREATE TEMP TABLE d ON COMMIT DROP AS
  EXECUTE dashboard_summary(extract(year FROM now() AT TIME ZONE 'Europe/London')::integer, 'u-est2');
SELECT pg_temp.ok(pipeline_value = 0 AND won_this_year = 122.00, 'DSH-03: filtered to one estimator') FROM d;

-- Job loading
CREATE TEMP TABLE j ON COMMIT DROP AS EXECUTE load_job('00000000-0000-4000-8000-0000000000a1');
SELECT pg_temp.ok(total_sell = 5576.11 AND door_count = 6 AND prepared_by = 'u-est1',
                  'DSH-04: job header total matches the dashboard; prepared_by is the estimator') FROM j;
CREATE TEMP TABLE jd ON COMMIT DROP AS EXECUTE load_job_doors('00000000-0000-4000-8000-0000000000a1');
SELECT pg_temp.ok(string_agg(door_mark, ',' ORDER BY sort_order) = 'D01,D02,D03', 'door lines load in schedule order') FROM jd;
CREATE TEMP TABLE ji ON COMMIT DROP AS EXECUTE load_job_door_items('00000000-0000-4000-8000-0000000000a1');
SELECT pg_temp.ok(count(*) = 7 AND count(*) FILTER (WHERE door_field_key = 'hinge') = 1,
                  'hardware loads with its grid column key') FROM ji;
ROLLBACK;
