-- Apply "Reprice to current rates" to a job's hardware. Door/frame/lining/VP/over panel
-- snapshots are re-priced by the pricing engine and saved per door. $1 job id, $2 user uid
UPDATE job_door_items i
SET unit_cost = p.cost, mat_code = p.mat_code, description = p.description, updated_by = $2::text
FROM job_doors d, products p
WHERE d.id = i.job_door_id AND p.id = i.product_id
  AND d.job_id = $1::uuid
  AND (i.unit_cost IS DISTINCT FROM p.cost OR i.mat_code IS DISTINCT FROM p.mat_code
       OR i.description IS DISTINCT FROM p.description)
RETURNING i.id, i.unit_cost;
