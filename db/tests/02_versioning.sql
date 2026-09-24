-- Conflict handling (spec CON-01/02) and audit log (USR-06).
BEGIN;

SELECT pg_temp.ok(version = 1, 'new rows start at version 1') FROM job_doors WHERE door_mark = 'D01';

-- Estimator 1 and estimator 2 both load D01 at version 1 and D02 at version 1.
-- Estimator 1 saves D01 -> succeeds, version 2.
EXECUTE update_door_field('00000000-0000-4000-8000-0000000000d1', 1, 'D01', 3, 'est1 comment', 'u-est1');
SELECT pg_temp.ok(:ROW_COUNT = 1 AND version = 2, 'first save of D01 succeeds and bumps version to 2') FROM job_doors WHERE door_mark = 'D01';

-- Estimator 2 saves D02 (a different door) with the version they loaded -> no conflict.
EXECUTE update_door_field('00000000-0000-4000-8000-0000000000d2', 1, 'D02', 1, 'est2 comment', 'u-est2');
SELECT pg_temp.ok(:ROW_COUNT = 1, 'CON-01: a different door saves without conflict');

-- Estimator 2 now saves D01 with the stale version 1 -> nothing updated (conflict).
EXECUTE update_door_field('00000000-0000-4000-8000-0000000000d1', 1, 'D01', 5, 'est2 overwrite', 'u-est2');
SELECT pg_temp.ok(:ROW_COUNT = 0, 'CON-02: stale save of the same door is rejected');
SELECT pg_temp.ok(comments = 'est1 comment' AND qty = 3, 'CON-02: estimator 1''s save is not overwritten')
FROM job_doors WHERE door_mark = 'D01';

-- After "take theirs / keep mine", saving with the current version works.
EXECUTE update_door_field('00000000-0000-4000-8000-0000000000d1', 2, 'D01', 5, 'est2 after merge', 'u-est2');
SELECT pg_temp.ok(:ROW_COUNT = 1 AND version = 3, 'save with the current version succeeds') FROM job_doors WHERE door_mark = 'D01';

-- Editing a door does not bump the job header version (no false conflicts on the job)
SELECT pg_temp.ok(version = 1, 'door edits leave the job header version alone')
FROM jobs WHERE id = '00000000-0000-4000-8000-0000000000a1';

-- Rate rows are separate: two admins changing different door rates never touch the same row
UPDATE door_rates SET price = 470, updated_by = 'u-admin'
WHERE finish_code = 'LAMINATE' AND fire_rating_code = 'FD30'
  AND door_type_id = (SELECT id FROM door_types WHERE form_code = 'SASL');
SELECT pg_temp.ok(count(*) = 1, 'RAT-08: only the edited rate row changed version')
FROM door_rates WHERE version > 1;

-- Audit trail
SELECT pg_temp.ok(count(*) = 2, 'USR-06: both successful D01 saves are in the audit log (the rejected one is not)')
FROM audit_log WHERE table_name = 'job_doors' AND action = 'UPDATE'
  AND row_id = '00000000-0000-4000-8000-0000000000d1';
SELECT pg_temp.ok(changed_by = 'u-est2' AND old_row ->> 'comments' = 'est1 comment'
                  AND new_row ->> 'comments' = 'est2 after merge',
                  'USR-06: audit keeps who changed it and the before/after values')
FROM audit_log WHERE table_name = 'job_doors' AND row_id = '00000000-0000-4000-8000-0000000000d1'
ORDER BY id DESC LIMIT 1;
SELECT pg_temp.ok(changed_by = 'u-admin', 'USR-06: rate change audited with the admin''s uid')
FROM audit_log WHERE table_name = 'door_rates' AND action = 'UPDATE';
ROLLBACK;
