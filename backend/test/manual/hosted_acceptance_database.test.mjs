import test from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import {
  beginHostedAcceptanceTransaction,
  validateHostedAcceptanceDatabase,
  bootstrapHostedAcceptanceDatabase,
} from "./hosted_acceptance_database.mjs";

// These tests execute the real bootstrap, migrations, and catalog queries in
// PostgreSQL. Only the dedicated database name is adapted for the embedded
// engine; no catalog, privilege, advisory-lock, or migration results are faked.
const EXPECTED_DATABASE = "korlix_2meetu_acceptance";
const NOW = Date.parse("2026-10-05T18:00:00.000Z");
const CONFIG = Object.freeze({
  database: Object.freeze({ database: EXPECTED_DATABASE }),
  bindingHash: "39a168de".repeat(8),
  paymentRuntime: false,
});
const RUNTIME_CONFIG = Object.freeze({ ...CONFIG, paymentRuntime: true });
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;

async function databaseFixture() {
  const db = new PGlite();
  await db.waitReady;
  const queries = [];
  const client = {
    async query(sql, values) {
      assert.equal(typeof sql, "string");
      queries.push(sql);
      const executable = sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
      assert.doesNotMatch(executable, /\bCREATE\s+(?:ROLE|USER)\b/i,
        "The hosted bootstrap must not create PostgreSQL roles.");
      const embeddedSql = sql.replace(/^(\s*SELECT\s+)current_database\(\)(\s+AS\s+database\b)/i,
        `$1'${EXPECTED_DATABASE}'::text$2`);
      const result = values?.length
        ? await db.query(embeddedSql, values)
        : (await db.exec(embeddedSql)).at(-1) ?? { rows: [] };
      return { ...result, rowCount: result.affectedRows ?? result.rows?.length ?? 0 };
    },
    release() {},
  };
  return { db, client, queries, pool: { async connect() { return client; } } };
}

async function roles(client) {
  return (await client.query("SELECT rolname FROM pg_roles ORDER BY rolname")).rows.map(row => row.rolname);
}

async function validateInTransaction(client, config = RUNTIME_CONFIG) {
  await beginHostedAcceptanceTransaction(client);
  try { return await validateHostedAcceptanceDatabase(client, config); }
  finally { await client.query("ROLLBACK"); }
}

test("hosted acceptance bootstrap uses real PostgreSQL and refuses restart drift", async (t) => {
  const { db, client, pool, queries } = await databaseFixture();
  t.after(() => db.close());
  const originalRoles = await roles(client);
  let initialState, runtimeState;

  await t.test("stage one initializes only the guard and can resume", async () => {
    initialState = await bootstrapHostedAcceptanceDatabase(CONFIG, pool, { now: () => NOW });
    assert.equal(initialState.createdAt, new Date(NOW).toISOString());
    assert.equal(initialState.lastVerifiedAt, null);
    assert.equal(initialState.runId, undefined);
    assert.equal(initialState.hostId, undefined);
    assert.deepEqual((await client.query(`SELECT tablename FROM pg_tables
      WHERE schemaname='public' ORDER BY tablename`)).rows,
    [{ tablename: "korlix_hosted_acceptance_state" }]);
    assert.deepEqual(await bootstrapHostedAcceptanceDatabase(CONFIG, pool, { now: () => NOW + 1000 }), initialState);
    const sentinel = await validateInTransaction(client, CONFIG);
    assert.equal(sentinel.config_hash, CONFIG.bindingHash);
  });

  await t.test("binding mismatch cannot take over the stage-one database", async () => {
    await assert.rejects(bootstrapHostedAcceptanceDatabase({ ...CONFIG, bindingHash: "a1".repeat(32) }, pool),
      /configuration|binding|config.*mismatch/i);
    assert.deepEqual(await bootstrapHostedAcceptanceDatabase(CONFIG, pool, { now: () => NOW + 2000 }), initialState);
  });

  await t.test("explicit runtime opt-in upgrades the guard and preserves run and host IDs", async () => {
    runtimeState = await bootstrapHostedAcceptanceDatabase(RUNTIME_CONFIG, pool, { now: () => NOW + 3000 });
    assert.equal(runtimeState.createdAt, initialState.createdAt);
    assert.equal(runtimeState.lastVerifiedAt, null);
    assert.match(runtimeState.runId, UUID);
    assert.match(runtimeState.hostId, UUID);
    assert.deepEqual(await bootstrapHostedAcceptanceDatabase(RUNTIME_CONFIG, pool, { now: () => NOW + 4000 }), runtimeState);
    assert.equal((await client.query("SELECT count(*)::int AS count FROM public.korlix_hosted_acceptance_run")).rows[0].count, 1);
    assert.equal((await client.query("SELECT count(*)::int AS count FROM auth.users WHERE id=$1", [runtimeState.hostId])).rows[0].count, 1);
    assert.equal((await client.query("SELECT count(*)::int AS count FROM public.user_profiles WHERE id=$1", [runtimeState.hostId])).rows[0].count, 1);
    assert.equal((await client.query("SELECT public.korlix_schedule_active_v1($1) AS active", [runtimeState.hostId])).rows[0].active, true);
    const schedulingTables = (await client.query(`SELECT c.relname,c.relrowsecurity FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'korlix_schedule_%'
      ORDER BY c.relname`)).rows;
    assert.equal(schedulingTables.length, 17);
    assert(schedulingTables.every(row => row.relrowsecurity), "Every scheduling table must retain RLS.");
    const exposure = (await client.query(`SELECT
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname LIKE 'korlix_schedule_%' AND p.prosecdef) AS definers,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
        LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
        WHERE n.nspname='public' AND p.proname LIKE 'korlix_schedule_%' AND a.grantee=0) AS public_functions,
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace,
        LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
        WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'korlix_schedule_%' AND a.grantee=0) AS public_tables`)).rows[0];
    assert(Object.values(exposure).every(count => Number(count) === 0),
      "The isolated runtime must retain invoker functions and revoke PUBLIC access.");
    assert.deepEqual(await roles(client), originalRoles);
    const sentinel = await validateInTransaction(client);
    assert.equal(sentinel.config_hash, CONFIG.bindingHash);
  });

  await t.test("binding mismatch cannot resume an initialized payment runtime", async () => {
    await assert.rejects(bootstrapHostedAcceptanceDatabase({ ...RUNTIME_CONFIG, bindingHash: "a2".repeat(32) }, pool),
      /configuration|binding|config.*mismatch/i);
    assert.deepEqual(await bootstrapHostedAcceptanceDatabase(RUNTIME_CONFIG, pool), runtimeState);
  });

  const mutations = [
    ["an unrelated table", "CREATE TABLE public.acceptance_unrelated_table(id integer)"],
    ["an unrelated function", "CREATE FUNCTION public.acceptance_unrelated_function() RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$"],
    ["an extra index on a permitted table", "CREATE INDEX acceptance_unrelated_index ON public.korlix_schedule_events(title)"],
    ["an unrelated schema", "CREATE SCHEMA acceptance_unrelated_schema"],
    ["a changed scheduling function", `CREATE OR REPLACE FUNCTION public.korlix_schedule_active_v1(p_actor uuid)
      RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$ SELECT true $$`],
    ["a scheduling table granted to PUBLIC", "GRANT SELECT ON public.korlix_schedule_events TO PUBLIC"],
    ["a scheduling function granted to PUBLIC", "GRANT EXECUTE ON FUNCTION public.korlix_schedule_active_v1(uuid) TO PUBLIC"],
    ["a changed scheduling constraint", `ALTER TABLE public.korlix_schedule_events
      DROP CONSTRAINT korlix_schedule_events_duration_minutes_check;
      ALTER TABLE public.korlix_schedule_events ADD CONSTRAINT korlix_schedule_events_duration_minutes_check
      CHECK(duration_minutes BETWEEN 5 AND 485 AND duration_minutes%5=0)`],
    ["disabled scheduling RLS", "ALTER TABLE public.korlix_schedule_events DISABLE ROW LEVEL SECURITY"],
  ];
  for (const [description, mutation] of mutations) {
    await t.test(`restart validation refuses ${description}`, async () => {
      await beginHostedAcceptanceTransaction(client);
      try {
        await client.query(mutation);
        await assert.rejects(validateHostedAcceptanceDatabase(client, RUNTIME_CONFIG),
          { code: "ERR_ASSERTION" });
      } finally { await client.query("ROLLBACK"); }
      // A refused restart must not force destructive cleanup or damage the
      // known-good state; each mutation above is independently rolled back.
      const sentinel = await validateInTransaction(client);
      assert.equal(sentinel.config_hash, CONFIG.bindingHash);
    });
  }

  await t.test("all successful and refused restarts retain the same roles and run", async () => {
    assert.deepEqual(await roles(client), originalRoles);
    assert.deepEqual(await bootstrapHostedAcceptanceDatabase(RUNTIME_CONFIG, pool), runtimeState);
    assert(queries.some(sql => /create table public\.korlix_schedule_profiles/i.test(sql)),
      "The runtime must execute the scheduling migrations.");
  });
});
