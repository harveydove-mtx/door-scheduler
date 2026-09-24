-- Edit a product's details (not its cost or MAT code: those have their own saves).
-- Versioned like every save: returns nothing if someone else changed the product first.
-- $1 id, $2 expected version, $3 description, $4 supplier code, $5 finish, $6 unit, $7 active, $8 user uid
UPDATE products
SET description = btrim($3::text), supplier_code = nullif(btrim($4::text), ''), finish = nullif(btrim($5::text), ''),
    unit = coalesce(nullif(btrim($6::text), ''), 'each'), active = $7::boolean, updated_by = $8::text
WHERE id = $1::uuid AND version = $2::integer
RETURNING id, version
