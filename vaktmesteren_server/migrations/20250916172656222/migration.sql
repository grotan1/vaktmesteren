BEGIN;


--
-- MIGRATION VERSION FOR vaktmesteren
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('vaktmesteren', '20250916172656222', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20250916172656222', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20240516151843329', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20240516151843329', "timestamp" = now();


COMMIT;
