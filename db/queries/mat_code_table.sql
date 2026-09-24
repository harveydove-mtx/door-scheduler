-- The MAT code table (agreed 2026-09-24): every priced item (products, door / VP / frame /
-- lining / architrave / over panel rates) in one list for Matrix to fill in, like a spreadsheet.
-- Items still missing a MAT code come first.
-- $1 kind filter (NULL = all: product, door, vision_panel, frame, lining, architrave, over_panel)
-- $2 only missing codes, $3 search text (NULL or '' = none; every word must match), $4 include inactive
SELECT kind, table_name, row_id, version, item, mat_code, cost, active
FROM v_mat_code_table
WHERE ($1::text IS NULL OR kind = $1::text)
  AND (NOT $2::boolean OR mat_code IS NULL)
  AND NOT EXISTS (             -- every word typed must appear (e.g. "sasl fd30 veneer")
        SELECT 1 FROM regexp_split_to_table(lower(btrim(coalesce($3::text, ''))), '\s+') AS w(word)
        WHERE w.word <> '' AND strpos(lower(item || ' ' || coalesce(mat_code, '')), w.word) = 0)
  AND ($4::boolean OR active)
ORDER BY (mat_code IS NULL) DESC, kind_sort, item;
