-- Sequential quote references (spec JOB-01).
BEGIN;
SELECT pg_temp.ok(count(*) = 4 AND count(DISTINCT quote_ref) = 4, 'every sample job has its own quote ref') FROM jobs;
SELECT pg_temp.ok(
  quote_ref = 'MH-' || extract(year FROM now() AT TIME ZONE 'Europe/London') || '-0001',
  'first job of the year is MH-YYYY-0001')
FROM jobs WHERE id = '00000000-0000-4000-8000-0000000000a1';

INSERT INTO jobs (project_name) VALUES ('Next job');
SELECT pg_temp.ok(quote_ref LIKE 'MH-%-0005', 'next job continues the sequence (0005)')
FROM jobs WHERE project_name = 'Next job';

UPDATE settings SET value = '"MXH"' WHERE key = 'quote_ref_prefix';
INSERT INTO jobs (project_name) VALUES ('Prefixed job');
SELECT pg_temp.ok(quote_ref LIKE 'MXH-%-0006', 'quote ref prefix comes from settings')
FROM jobs WHERE project_name = 'Prefixed job';

INSERT INTO jobs (project_name, quote_ref) VALUES ('Migrated V1 job', 'MH-V1-ABC123');
SELECT pg_temp.ok(quote_ref = 'MH-V1-ABC123', 'an explicit ref (V1 migration) is kept')
FROM jobs WHERE project_name = 'Migrated V1 job';

SELECT pg_temp.throws($$INSERT INTO jobs (project_name, quote_ref) VALUES ('dup', 'MH-V1-ABC123')$$,
  'quote refs are unique');

-- Status change date is recorded
UPDATE jobs SET status_changed_at = now() - interval '10 days' WHERE project_name = 'Next job';
UPDATE jobs SET status = 'won' WHERE project_name = 'Next job';
SELECT pg_temp.ok(status_changed_at > now() - interval '1 minute', 'JOB-02: status change date recorded')
FROM jobs WHERE project_name = 'Next job';
ROLLBACK;
