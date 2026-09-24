-- Save one MAT code from the MAT code table. Returns the row's new version, or NULL when
-- someone else changed that row first (show "keep mine / take theirs", spec CON-02).
-- Fails with unique_violation if the code is already used anywhere else.
-- $1 table_name, $2 row_id, $3 expected version, $4 MAT code (NULL or '' clears), $5 user uid
SELECT set_mat_code($1::text, $2::uuid, $3::integer, $4::text, $5::text) AS new_version;
