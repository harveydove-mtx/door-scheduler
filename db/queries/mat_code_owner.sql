-- Which item already uses a MAT code, if any, so the app can say "already used on ..."
-- before saving. $1 MAT code (any case / spacing)
SELECT r.table_name, r.row_id, t.item
FROM mat_code_registry r
LEFT JOIN v_mat_code_table t ON t.table_name = r.table_name AND t.row_id = r.row_id
WHERE r.mat_code = nullif(upper(btrim($1::text)), '')
