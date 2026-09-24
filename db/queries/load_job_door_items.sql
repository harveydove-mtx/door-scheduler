-- Hardware on every door in a job, keyed by the grid column (door_field_key). $1 job id
SELECT i.*, c.key AS category_key, c.door_field_key, p.active AS product_active
FROM job_door_items i
JOIN job_doors d ON d.id = i.job_door_id
JOIN product_categories c ON c.id = i.category_id
JOIN products p ON p.id = i.product_id
WHERE d.job_id = $1::uuid
ORDER BY d.sort_order, c.sort;
