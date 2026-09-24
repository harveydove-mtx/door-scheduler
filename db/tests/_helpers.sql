-- Loaded before every test file (same psql session).
-- pg_temp.ok(cond, msg): fail the file unless cond is true.
-- pg_temp.throws(sql, msg): fail the file unless running sql raises an error.
-- Every canonical query in db/queries is PREPAREd under its file name, so tests exercise
-- exactly the SQL the app will run.
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

\set q `cat queries/search_products.sql`
PREPARE search_products AS :q
\set q `cat queries/search_jobs.sql`
PREPARE search_jobs AS :q
\set q `cat queries/load_job.sql`
PREPARE load_job AS :q
\set q `cat queries/load_job_doors.sql`
PREPARE load_job_doors AS :q
\set q `cat queries/load_job_door_items.sql`
PREPARE load_job_door_items AS :q
\set q `cat queries/update_door_field.sql`
PREPARE update_door_field AS :q
\set q `cat queries/reprice_job_hardware_preview.sql`
PREPARE reprice_job_hardware_preview AS :q
\set q `cat queries/reprice_job_hardware.sql`
PREPARE reprice_job_hardware AS :q
\set q `cat queries/dashboard_summary.sql`
PREPARE dashboard_summary AS :q
