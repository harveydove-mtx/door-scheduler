-- "Reprice to current rates" preview (spec JOB-06): hardware lines whose saved price or
-- MAT code differs from the catalogue today. $1 job id
SELECT d.door_mark, c.label AS category, i.description, i.qty,
       i.unit_cost AS quoted_unit_cost, p.cost AS current_unit_cost,
       (p.cost - i.unit_cost) * i.qty * d.qty AS line_cost_change,
       i.mat_code AS quoted_mat_code, p.mat_code AS current_mat_code, p.active AS product_active
FROM job_door_items i
JOIN job_doors d ON d.id = i.job_door_id
JOIN product_categories c ON c.id = i.category_id
JOIN products p ON p.id = i.product_id
WHERE d.job_id = $1::uuid
  AND (i.unit_cost IS DISTINCT FROM p.cost OR i.mat_code IS DISTINCT FROM p.mat_code
       OR i.description IS DISTINCT FROM p.description)
ORDER BY d.sort_order, c.sort;
