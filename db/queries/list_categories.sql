-- Product categories in display order (the door grid's hardware columns).
SELECT id, key, label, door_field_key, sort, active FROM product_categories ORDER BY sort, label
