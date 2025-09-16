BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "persisted_alert_state" (
    "id" bigserial PRIMARY KEY,
    "host" text NOT NULL,
    "service" text,
    "canonicalKey" text NOT NULL,
    "lastState" bigint NOT NULL,
    "lastUpdated" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "persisted_alert_state_canonical_key_idx" ON "persisted_alert_state" USING btree ("canonicalKey");


--
-- MIGRATION VERSION FOR vaktmesteren
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('vaktmesteren', '20250917000000000', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20250917000000000', "timestamp" = now();


COMMIT;

