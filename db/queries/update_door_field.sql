-- Optimistic-concurrency save of a door line (spec CON-01/02). The pattern every save uses:
-- the client sends the version it loaded; if someone else saved first the version has moved
-- on, NO row is updated and nothing is returned, so the app shows "keep mine / take theirs".
-- This example saves the mark, qty and comments. $1 door id, $2 expected version,
-- $3 door mark, $4 qty, $5 comments, $6 user uid
UPDATE job_doors
SET door_mark = $3::text, qty = $4::integer, comments = $5::text, updated_by = $6::text
WHERE id = $1::uuid AND version = $2::integer
RETURNING id, version, updated_at, updated_by;
