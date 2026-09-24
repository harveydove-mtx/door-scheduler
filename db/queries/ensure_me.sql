-- Called by the app straight after every sign-in: makes sure the signed-in user has an
-- app_users row (every created_by / updated_by points at it) and returns it.
-- Display name defaults from the email: harvey.dove@... -> "Harvey Dove".
-- $1 uid (auth.uid, set by the server), $2 email (auth.token.email, set by the server)
INSERT INTO app_users (uid, email, display_name)
VALUES ($1::text, lower($2::text), initcap(replace(split_part(lower($2::text), '@', 1), '.', ' ')))
ON CONFLICT (uid) DO UPDATE SET email = EXCLUDED.email
RETURNING uid, email, display_name, role
