-- Loaded before every test file (same psql session).
-- pg_temp.ok(cond, msg): fail the file unless cond is true.
-- pg_temp.throws(sql, msg): fail the file unless running sql raises an error.
\o /dev/null
SET client_min_messages = notice;
CREATE FUNCTION pg_temp.ok(cond boolean, msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cond IS NOT TRUE THEN RAISE EXCEPTION 'not ok - %', msg; END IF;
  RAISE NOTICE 'ok - %', msg;
END $$;

CREATE FUNCTION pg_temp.throws(stmt text, msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'ok - % (%)', msg, SQLERRM;
    RETURN;
  END;
  RAISE EXCEPTION 'not ok - % (no error raised)', msg;
END $$;
-- Every file in db/queries and db/queries/generated is PREPAREd under its file name by
-- db/test.sh, so tests run exactly the SQL the app runs (via the Data Connect connector).
