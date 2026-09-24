-- Local stand-in for the Cloud SQL permission setup, copied from what
-- `firebase dataconnect:sql:setup` runs (firebase-tools lib/gcp/cloudsql/permissions.js),
-- so the emulator test runs with the SAME privileges as production:
--   * tables are created by db/migrate.sh as the owner role (MIGRATE_ROLE)
--   * Data Connect connects as a login that only has the writer role
-- Run as a superuser on an empty database named doorscheduler.
CREATE ROLE cloudsqlsuperuser NOLOGIN;
GRANT CREATE ON DATABASE doorscheduler TO cloudsqlsuperuser;       -- can create trusted extensions
CREATE ROLE firebaseowner_doorscheduler_public NOLOGIN;
CREATE ROLE firebasewriter_doorscheduler_public NOLOGIN;
CREATE ROLE firebasereader_doorscheduler_public NOLOGIN;
GRANT firebaseowner_doorscheduler_public, firebasewriter_doorscheduler_public,
      firebasereader_doorscheduler_public TO cloudsqlsuperuser;
ALTER SCHEMA public OWNER TO firebaseowner_doorscheduler_public;
GRANT USAGE ON SCHEMA public TO firebasewriter_doorscheduler_public, firebasereader_doorscheduler_public;
ALTER DEFAULT PRIVILEGES FOR ROLE firebaseowner_doorscheduler_public IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO firebasewriter_doorscheduler_public;
ALTER DEFAULT PRIVILEGES FOR ROLE firebaseowner_doorscheduler_public IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO firebasewriter_doorscheduler_public;
ALTER DEFAULT PRIVILEGES FOR ROLE firebaseowner_doorscheduler_public IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO firebasewriter_doorscheduler_public;
ALTER DEFAULT PRIVILEGES FOR ROLE firebaseowner_doorscheduler_public IN SCHEMA public
  GRANT SELECT ON TABLES TO firebasereader_doorscheduler_public;
-- The temporary built-in user the deploy workflow creates (a Cloud SQL superuser member)
CREATE ROLE migrator LOGIN IN ROLE cloudsqlsuperuser;
-- The Data Connect service account: writer only
CREATE ROLE fdc_service LOGIN IN ROLE firebasewriter_doorscheduler_public;
