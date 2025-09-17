BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "alert_history" (
    "id" bigserial PRIMARY KEY,
    "host" text NOT NULL,
    "service" text,
    "canonicalKey" text NOT NULL,
    "state" bigint NOT NULL,
    "message" text,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "alert_history_canonical_idx" ON "alert_history" USING btree ("canonicalKey");
CREATE INDEX "alert_history_created_at_idx" ON "alert_history" USING btree ("createdAt");

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
    VALUES ('vaktmesteren', '20250917061121096', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20250917061121096', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20240516151843329', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20240516151843329', "timestamp" = now();


COMMIT;
