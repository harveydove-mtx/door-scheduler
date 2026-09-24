-- Dashboard headline figures (spec DSH-01/03). Redundant jobs are excluded throughout.
-- $1 year (e.g. 2026), $2 prepared_by uid (NULL = everyone)
SELECT
  coalesce(sum(total_sell) FILTER (WHERE status = 'outstanding'), 0)                       AS pipeline_value,
  count(*) FILTER (WHERE status = 'outstanding')                                           AS outstanding_count,
  coalesce(sum(total_sell) FILTER (WHERE status = 'won'
            AND extract(year FROM status_changed_at AT TIME ZONE 'Europe/London') = $1::integer), 0) AS won_this_year,
  round(count(*) FILTER (WHERE status = 'won')::numeric
        / nullif(count(*) FILTER (WHERE status IN ('won', 'lost')), 0), 4)                 AS win_rate,
  round(avg(total_sell), 2)                                                                AS average_quote,
  count(*) FILTER (WHERE status = 'outstanding' AND age_days >= 30)                       AS follow_ups_due
FROM v_jobs
WHERE status <> 'redundant'
  AND ($2::text IS NULL OR prepared_by = $2::text);
