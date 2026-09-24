-- Add a catalogue product. New products are unverified until an admin approves them (CAT-09).
-- $1 category id, $2 MAT code (optional), $3 supplier code (optional), $4 description,
-- $5 finish (optional), $6 unit (optional, default 'each'), $7 cost (text, e.g. '12.50'), $8 user uid
INSERT INTO products (category_id, mat_code, supplier_code, description, finish, unit, cost, created_by, updated_by)
VALUES ($1::uuid, nullif(upper(btrim($2::text)), ''), nullif(btrim($3::text), ''), btrim($4::text),
        nullif(btrim($5::text), ''), coalesce(nullif(btrim($6::text), ''), 'each'), $7::numeric, $8::text, $8::text)
RETURNING id, version
