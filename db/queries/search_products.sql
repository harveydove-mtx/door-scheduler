-- Catalogue search (spec CAT-05). Every word typed must appear somewhere in the product's
-- MAT code / supplier code / description / finish; partial words match ("9205" finds
-- "TS.9205 EN2-5 SNP"). An exact MAT or supplier code match ranks first.
-- $1 search text, $2 category id (NULL = all), $3 include inactive, $4 max rows
SELECT p.id, p.version, p.mat_code, p.supplier_code, p.description, p.finish, p.unit, p.cost,
       p.active, p.verified, c.key AS category_key, c.label AS category_label
FROM products p
JOIN product_categories c ON c.id = p.category_id
WHERE ($2::uuid IS NULL OR p.category_id = $2::uuid)
  AND ($3::boolean OR p.active)
  AND NOT EXISTS (
        SELECT 1
        FROM regexp_split_to_table(lower(btrim($1::text)), '\s+') AS w(word)
        WHERE w.word <> ''
          AND strpos(p.search_text, w.word) = 0
      )
ORDER BY coalesce(p.mat_code = upper(btrim($1::text)) OR upper(p.supplier_code) = upper(btrim($1::text)), false) DESC,
         similarity(p.search_text, lower(btrim($1::text))) DESC,
         p.description
LIMIT $4::integer;
