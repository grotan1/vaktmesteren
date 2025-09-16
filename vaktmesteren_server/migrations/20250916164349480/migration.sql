BEGIN;


--
-- MIGRATION VERSION FOR vaktmesteren
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('vaktmesteren', '20250916164349480', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20250916164349480', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20240516151843329', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20240516151843329', "timestamp" = now();


COMMIT;
