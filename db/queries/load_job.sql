-- Job header with totals. $1 job id
SELECT * FROM v_jobs WHERE id = $1::uuid;
