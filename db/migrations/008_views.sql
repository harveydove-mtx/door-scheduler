-- 008_views.sql
-- Totals are CALCULATED from the stored price snapshots, never stored twice.
-- The arithmetic matches V1 exactly (index.html calcUnitCost / calcTotalCost / calcSellPrice):
--   unit cost  = door + VP + frame/lining + architrave + over panel + hardware + uplifts
--   line cost  = unit cost x qty
--   line sell  = sell_override x qty                         when overridden (per-unit override)
--              = round(line cost x (1 + markup), 2)          otherwise (rounded on the LINE, as V1)

-- Lining depth threshold (mm) from settings; NULL = not configured (no uplift required).
CREATE FUNCTION lining_depth_threshold_mm() RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT (value #>> '{}')::integer FROM settings
  WHERE key = 'lining_depth_threshold_mm' AND jsonb_typeof(value) = 'number'
$$;

CREATE VIEW v_job_door_lines AS
WITH hw AS (
  SELECT job_door_id, sum(qty * unit_cost) AS cost_hardware, count(*) AS hardware_items
  FROM job_door_items
  GROUP BY job_door_id
), costed AS (
  SELECT d.*,
         j.markup_pct,
         coalesce(hw.cost_hardware, 0)::numeric(12,2) AS cost_hardware,
         coalesce(hw.hardware_items, 0)               AS hardware_items,
         CASE WHEN d.surround = 'LINING' THEN coalesce(d.lining_uplift, 0) ELSE 0 END AS lining_uplift_applied,
         coalesce(d.surround = 'LINING'
                  AND d.lining_depth_mm > lining_depth_threshold_mm()
                  AND d.lining_uplift IS NULL, false) AS needs_lining_uplift
  FROM job_doors d
  JOIN jobs j ON j.id = d.job_id
  LEFT JOIN hw ON hw.job_door_id = d.id
), unit AS (
  SELECT c.*,
         (c.cost_door + c.cost_vp + c.cost_surround + c.cost_architrave + c.cost_over_panel
          + c.cost_hardware + c.added_uplift + c.lining_uplift_applied) AS unit_cost
  FROM costed c
)
SELECT u.*,
       u.unit_cost * u.qty AS line_cost,
       CASE WHEN u.sell_override IS NOT NULL THEN u.sell_override * u.qty
            ELSE round(u.unit_cost * u.qty * (1 + u.markup_pct), 2)
       END AS line_sell
FROM unit u;

CREATE VIEW v_job_screen_lines AS
SELECT s.*,
       j.markup_pct,
       s.unit_cost * s.qty AS line_cost,
       CASE WHEN s.sell_override IS NOT NULL THEN s.sell_override * s.qty
            ELSE round(s.unit_cost * s.qty * (1 + j.markup_pct), 2)
       END AS line_sell
FROM job_screens s
JOIN jobs j ON j.id = s.job_id;

-- One row per job with its totals. Dashboard, job list and PDF all read from here.
CREATE VIEW v_job_totals AS
WITH d AS (
  SELECT job_id,
         count(*)                          AS door_rows,
         sum(qty)                          AS door_count,
         sum(line_cost)                    AS cost,
         sum(line_sell)                    AS sell,
         count(*) FILTER (WHERE needs_lining_uplift) AS lining_uplift_missing
  FROM v_job_door_lines GROUP BY job_id
), s AS (
  SELECT job_id, count(*) AS screen_rows, sum(qty) AS screen_count,
         sum(line_cost) AS cost, sum(line_sell) AS sell
  FROM v_job_screen_lines GROUP BY job_id
)
SELECT j.id AS job_id,
       coalesce(d.door_rows, 0)                          AS door_rows,
       coalesce(d.door_count, 0)                         AS door_count,
       coalesce(s.screen_rows, 0)                        AS screen_rows,
       coalesce(s.screen_count, 0)                       AS screen_count,
       (coalesce(d.cost, 0) + coalesce(s.cost, 0))::numeric(14,2) AS total_cost,
       (coalesce(d.sell, 0) + coalesce(s.sell, 0))::numeric(14,2) AS total_sell,
       CASE WHEN coalesce(d.sell, 0) + coalesce(s.sell, 0) > 0
            THEN round(1 - (coalesce(d.cost, 0) + coalesce(s.cost, 0))
                           / (coalesce(d.sell, 0) + coalesce(s.sell, 0)), 4)
       END                                               AS margin_pct,
       coalesce(d.lining_uplift_missing, 0)              AS lining_uplift_missing
FROM jobs j
LEFT JOIN d ON d.job_id = j.id
LEFT JOIN s ON s.job_id = j.id;

-- Live (not deleted) jobs with totals: the Saved Jobs list and dashboard source.
CREATE VIEW v_jobs AS
SELECT j.*, t.door_rows, t.door_count, t.screen_rows, t.screen_count,
       t.total_cost, t.total_sell, t.margin_pct, t.lining_uplift_missing,
       (now()::date - j.created_at::date) AS age_days
FROM jobs j
JOIN v_job_totals t ON t.job_id = j.id
WHERE j.deleted_at IS NULL;
