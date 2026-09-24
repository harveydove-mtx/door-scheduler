-- Job search (spec JOB-09): quote ref, project, client, site, contact, PO number,
-- any door mark / location in the job, or any MAT / supplier code used on its doors.
-- $1 search text, $2 status (NULL = all), $3 max rows
WITH words AS (
  SELECT w.word FROM regexp_split_to_table(lower(btrim($1::text)), '\s+') AS w(word) WHERE w.word <> ''
), job_text AS (
  SELECT j.id,
         j.search_text || ' ' ||
         coalesce((SELECT string_agg(lower(coalesce(d.door_mark, '') || ' ' || coalesce(d.location, '')), ' ')
                   FROM job_doors d WHERE d.job_id = j.id), '') || ' ' ||
         coalesce((SELECT string_agg(DISTINCT lower(coalesce(i.mat_code, '') || ' ' || coalesce(p.supplier_code, '')), ' ')
                   FROM job_doors d
                   JOIN job_door_items i ON i.job_door_id = d.id
                   JOIN products p ON p.id = i.product_id
                   WHERE d.job_id = j.id), '') AS txt
  FROM jobs j
  WHERE j.deleted_at IS NULL
    AND ($2::text IS NULL OR j.status = $2::text)
)
SELECT v.id, v.quote_ref, v.project_name, v.client_company, v.site, v.status,
       v.door_count, v.total_sell, v.updated_at
FROM job_text t
JOIN v_jobs v ON v.id = t.id
WHERE NOT EXISTS (SELECT 1 FROM words WHERE strpos(t.txt, words.word) = 0)
ORDER BY coalesce(upper(v.quote_ref) = upper(btrim($1::text)), false) DESC, v.updated_at DESC
LIMIT $3::integer;
