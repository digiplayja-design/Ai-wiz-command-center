// Dedicated hosted sandbox storage. Never import from production entrypoints.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";

const EXPECTED_DATABASE = "korlix_2meetu_acceptance";
const FORMAT = "korlix-hosted-acceptance-staging-v1";
const TABLE = "korlix_hosted_acceptance_state";
const SCHEMA_TABLE = "korlix_hosted_acceptance_schema";
const RUN_TABLE = "korlix_hosted_acceptance_run";
const SCHEMA_VERSION = "scheduling-ledger-v1";
const sha = value => createHash("sha256").update(value).digest("hex");
const fail = (status, code) => { throw Object.assign(new Error(code), { status, code }); };

export async function beginHostedAcceptanceTransaction(client) {
  await client.query("BEGIN");
  await client.query("SET LOCAL search_path = pg_catalog, public");
  await client.query("SET LOCAL lock_timeout = '3s'");
  await client.query("SET LOCAL statement_timeout = '10s'");
  await client.query("SET LOCAL idle_in_transaction_session_timeout = '45s'");
  const lock = await client.query("SELECT pg_try_advisory_xact_lock(135792468, 246813579) AS locked");
  if (lock.rows[0]?.locked !== true) fail(409, "readiness_check_in_progress");
}

async function inspectDatabase(client) {
  const identity = await client.query("SELECT current_database() AS database, current_user AS owner");
  assert.equal(identity.rows[0]?.database, EXPECTED_DATABASE, "Dedicated database identity mismatch.");
  const unsafe = await client.query(`SELECT
    (SELECT count(*) FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname NOT IN ('public','information_schema')) AS schemas,
    (SELECT count(*) FROM pg_extension WHERE extname <> 'plpgsql') AS extensions,
    (SELECT count(*) FROM pg_event_trigger) AS event_triggers,
    (SELECT count(*) FROM pg_largeobject_metadata) AS large_objects,
    (SELECT count(*) FROM pg_foreign_server) AS foreign_servers,
    (SELECT count(*) FROM pg_publication) AS publications,
    (SELECT count(oid) FROM pg_subscription WHERE subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())) AS subscriptions`);
  assert(unsafe.rows[0] && Object.values(unsafe.rows[0]).every(v => Number(v) === 0), "Dedicated database contains unrelated objects.");
  const objects = await client.query(`SELECT d.classid::regclass::text AS catalog, d.objid::text AS id, d.objsubid AS subid
    FROM pg_depend d WHERE d.refclassid='pg_namespace'::regclass
    AND d.refobjid='public'::regnamespace ORDER BY d.classid,d.objid,d.objsubid`);
  return { owner: identity.rows[0].owner, objects: objects.rows };
}

const COLUMNS = [
  ["singleton", "boolean", true], ["format", "text", true], ["config_hash", "text", true],
  ["created_at", "timestamp with time zone", true], ["verified_at", "timestamp with time zone", false],
  ["evidence", "jsonb", false],
];

async function validateState(client, config, inspection, sentinelOnly = true) {
  const table = await client.query(`SELECT c.oid::text AS id,c.reltype::text AS type_id,t.typarray::text AS array_id,
    i.indexrelid::text AS index_id,c.relkind,c.relrowsecurity,pg_get_userbyid(c.relowner) AS owner
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_type t ON t.oid=c.reltype
    LEFT JOIN pg_index i ON i.indrelid=c.oid AND i.indisprimary
    WHERE n.nspname='public' AND c.relname='${TABLE}'`);
  const row = table.rows[0];
  assert(table.rows.length === 1 && row.relkind === "r" && row.relrowsecurity === false && row.owner === inspection.owner && row.index_id,
    "Dedicated database guard is invalid.");
  const allowed = new Set(["pg_class:" + row.id, "pg_class:" + row.index_id, "pg_type:" + row.type_id, "pg_type:" + row.array_id]);
  assert(!sentinelOnly || inspection.objects.length > 0 && inspection.objects.every(o => o.subid === 0 && allowed.has(o.catalog + ":" + o.id)),
    "Dedicated database contains unrelated objects.");
  const shape = await client.query(`SELECT attname,format_type(atttypid,atttypmod) AS type,attnotnull
    FROM pg_attribute WHERE attrelid=$1::oid AND attnum>0 AND NOT attisdropped ORDER BY attnum`, [row.id]);
  assert.deepEqual(shape.rows.map(c => [c.attname, c.type, c.attnotnull]), COLUMNS, "Dedicated database guard shape mismatch.");
  const hooks = await client.query(`SELECT
    (SELECT count(*) FROM pg_trigger WHERE tgrelid=$1::oid AND NOT tgisinternal) AS triggers,
    (SELECT count(*) FROM pg_rewrite WHERE ev_class=$1::oid) AS rules,
    (SELECT count(*) FROM pg_attrdef WHERE adrelid=$1::oid) AS defaults,
    (SELECT count(*) FROM pg_class c, LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE c.oid=$1::oid AND a.grantee<>c.relowner) AS foreign_grants`, [row.id]);
  assert(hooks.rows[0] && Object.values(hooks.rows[0]).every(v => Number(v) === 0), "Dedicated database guard has unexpected behavior.");
  const constraints = await client.query(`SELECT pg_get_constraintdef(oid) AS definition,convalidated,condeferrable,condeferred
    FROM pg_constraint WHERE conrelid=$1::oid AND contype<>'n'`, [row.id]);
  assert(constraints.rows.every(c => c.convalidated && !c.condeferrable && !c.condeferred), "Dedicated database guard constraints were changed.");
  assert.deepEqual(constraints.rows.map(c => c.definition).sort(), ["CHECK (singleton)",
    `CHECK ((format = '${FORMAT}'::text))`, "CHECK ((config_hash ~ '^[a-f0-9]{64}$'::text))", "PRIMARY KEY (singleton)"].sort(),
  "Dedicated database guard constraints were changed.");
  const state = await client.query(`SELECT singleton,format,config_hash,created_at,verified_at,evidence FROM public.${TABLE}`);
  assert(state.rows.length === 1 && state.rows[0].singleton === true && state.rows[0].format === FORMAT &&
    state.rows[0].config_hash === config.bindingHash, "Dedicated database belongs to another acceptance configuration.");
  return state.rows[0];
}

async function bootstrapStageOne(config, pool, { now = Date.now } = {}) {
  assert(config.database, "The dedicated database credential is required.");
  const client = await pool.connect();
  try {
    await beginHostedAcceptanceTransaction(client);
    let inspection = await inspectDatabase(client);
    if (inspection.objects.length === 0) {
      await client.query(`CREATE TABLE public.${TABLE} (
        singleton boolean PRIMARY KEY CHECK(singleton),
        format text NOT NULL CHECK(format='${FORMAT}'),
        config_hash text NOT NULL CHECK(config_hash ~ '^[a-f0-9]{64}$'),
        created_at timestamptz NOT NULL, verified_at timestamptz, evidence jsonb
      )`);
      await client.query(`REVOKE ALL ON public.${TABLE} FROM PUBLIC`);
      await client.query(`INSERT INTO public.${TABLE}(singleton,format,config_hash,created_at) VALUES(true,$1,$2,$3)`,
        [FORMAT, config.bindingHash, new Date(now()).toISOString()]);
      inspection = await inspectDatabase(client);
    }
    const state = await validateState(client, config, inspection);
    await client.query("COMMIT");
    return { createdAt: new Date(state.created_at).toISOString(), lastVerifiedAt: state.verified_at ? new Date(state.verified_at).toISOString() : null };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally { client.release(); }
}

// Source checksums make an upstream migration change an explicit review point.
// Only the two final permission blocks are replaced; business SQL is unchanged.
const MIGRATIONS = [
  ["20260930152919_scheduling_engine.sql", "2cb059e9feb7db106232fb56099d541c1223ef616eae5654592dd969a0a7f238"],
  ["20260930163605_scheduling_connected.sql", "585be93c69ccc7d74eb9adcaafb410221be3853034bef25a9c37cb2be016f497"],
];
const SOURCE_HASH = sha(JSON.stringify({ version: SCHEMA_VERSION, migrations: MIGRATIONS,
  scaffold: "auth-users-user-profiles-v1", permissions: "owner-only-public-revoked-rls-v1", run: "singleton-run-v1" }));
const SCHEDULE_TABLES = ["profiles", "events", "blocks", "bookings", "contexts", "audit", "notifications",
  "teams", "members", "booking_hosts", "connections", "oauth", "calendar_windows", "calendar_links",
  "payments", "payment_receipts", "ai_plans"].map(name => "korlix_schedule_" + name);
const EXPECTED_TABLES = [TABLE, SCHEMA_TABLE, RUN_TABLE, "user_profiles", ...SCHEDULE_TABLES].sort();
const SCHEMA_COLUMNS = [["singleton", "boolean", true], ["version", "text", true],
  ["source_hash", "text", true], ["catalog_hash", "text", true]];
const RUN_COLUMNS = [["singleton", "boolean", true], ["run_id", "uuid", true], ["host_id", "uuid", true],
  ["event_id", "uuid", false], ["booking_id", "uuid", false], ["enabled", "boolean", true],
  ["created_at", "timestamp with time zone", true]];

async function runtimeSql() {
  const parts = [];
  for (const [name, checksum] of MIGRATIONS) {
    const original = await readFile(new URL("../../../supabase/migrations/" + name, import.meta.url), "utf8");
    assert.equal(sha(original), checksum, "Scheduling migration changed; review and version the sandbox schema explicitly.");
    const marker = "\ndo $$ declare t text; f record; begin\n";
    const at = original.indexOf(marker);
    assert(at > 0 && at === original.lastIndexOf(marker) && /\nend \$\$;\s*$/.test(original.slice(at)),
      "Scheduling migration privilege block is not the reviewed terminal block.");
    const sql = original.slice(0, at);
    assert(!/\b(?:anon|authenticated|service_role)\b/.test(sql.replace(/^\s*--.*$/gm, "")),
      "Unexpected role dependency outside scheduling privilege block.");
    parts.push(sql);
  }
  return parts;
}

async function inspectRuntimeDatabase(client) {
  const identity = await client.query("SELECT current_database() AS database, current_user AS owner");
  assert.equal(identity.rows[0]?.database, EXPECTED_DATABASE, "Dedicated database identity mismatch.");
  const unsafe = await client.query(`SELECT
    (SELECT count(*) FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname NOT IN ('public','auth','information_schema')) AS schemas,
    (SELECT count(*) FROM pg_extension WHERE extname <> 'plpgsql') AS extensions,
    (SELECT count(*) FROM pg_event_trigger) AS event_triggers,
    (SELECT count(*) FROM pg_largeobject_metadata) AS large_objects,
    (SELECT count(*) FROM pg_foreign_server) AS foreign_servers,
    (SELECT count(*) FROM pg_publication) AS publications,
    (SELECT count(*) FROM pg_subscription WHERE subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())) AS subscriptions`);
  assert(unsafe.rows[0] && Object.values(unsafe.rows[0]).every(v => Number(v) === 0),
    "Dedicated database contains unrelated objects.");
  return { owner: identity.rows[0].owner };
}

// Fingerprint every namespace-dependent object, plus schema, ACL and executable
// details. Capture only after checked sources run atomically on the exact v1
// sentinel-only database. Persist it separately from mutable identity evidence.
async function catalog(client) {
  const queries = {
    schemas: `SELECT nspname,pg_get_userbyid(nspowner) AS owner,coalesce(nspacl::text,'') AS acl
      FROM pg_namespace WHERE nspname IN ('public','auth') ORDER BY nspname`,
    objects: `SELECT d.classid::regclass::text AS catalog,pg_describe_object(d.classid,d.objid,d.objsubid) AS object
      FROM pg_depend d WHERE d.refclassid='pg_namespace'::regclass
      AND d.refobjid IN ('public'::regnamespace,'auth'::regnamespace)
      ORDER BY 1,2`,
    relations: `SELECT n.nspname,c.relname,c.relkind,c.relpersistence,c.relrowsecurity,c.relforcerowsecurity,
      pg_get_userbyid(c.relowner) AS owner,coalesce(c.relacl::text,'') AS acl,coalesce(c.reloptions::text,'') AS options
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','auth')
      ORDER BY n.nspname,c.relname`,
    columns: `SELECT n.nspname,c.relname,a.attnum,a.attname,format_type(a.atttypid,a.atttypmod) AS type,
      a.attcollation::regcollation::text AS collation,
      a.attnotnull,a.attidentity,a.attgenerated,a.attisdropped,coalesce(a.attacl::text,'') AS acl,
      coalesce(pg_get_expr(d.adbin,d.adrelid),'') AS expression
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE n.nspname IN ('public','auth') AND a.attnum>0 ORDER BY n.nspname,c.relname,a.attnum`,
    constraints: `SELECT n.nspname,c.relname,k.conname,k.contype,k.convalidated,k.condeferrable,k.condeferred,
      pg_get_constraintdef(k.oid) AS definition FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname,k.conname`,
    indexes: `SELECT n.nspname,c.relname,pg_get_indexdef(c.oid) AS definition,i.indisvalid,i.indisready,i.indisunique,i.indisprimary
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_index i ON i.indexrelid=c.oid
      WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname`,
    functions: `SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,
      pg_get_functiondef(p.oid) AS definition,pg_get_userbyid(p.proowner) AS owner,coalesce(p.proacl::text,'') AS acl,
      p.prosecdef,p.proleakproof,p.provolatile,p.proparallel,coalesce(p.proconfig::text,'') AS configuration
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','auth')
      ORDER BY n.nspname,p.proname,arguments`,
    triggers: `SELECT n.nspname,c.relname,t.tgname,t.tgenabled,t.tgisinternal,pg_get_triggerdef(t.oid) AS definition
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname,t.tgname`,
    rules: `SELECT n.nspname,c.relname,r.rulename,pg_get_ruledef(r.oid) AS definition
      FROM pg_rewrite r JOIN pg_class c ON c.oid=r.ev_class JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname,r.rulename`,
    policies: `SELECT n.nspname,c.relname,p.polname,p.polcmd,p.polpermissive,p.polroles::text,
      pg_get_expr(p.polqual,p.polrelid) AS qualifier,pg_get_expr(p.polwithcheck,p.polrelid) AS check_expression
      FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname,p.polname`,
    sequences: `SELECT n.nspname,c.relname,s.seqtypid::regtype::text AS type,s.seqstart::text,s.seqincrement::text,
      s.seqmax::text,s.seqmin::text,s.seqcache::text,s.seqcycle
      FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','auth') ORDER BY n.nspname,c.relname`,
    defaults: `SELECT pg_get_userbyid(d.defaclrole) AS owner,coalesce(n.nspname,'') AS schema,d.defaclobjtype,d.defaclacl::text AS acl
      FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
      WHERE d.defaclnamespace=0 OR n.nspname IN ('public','auth') ORDER BY owner,schema,d.defaclobjtype`,
    foreignGrants: `SELECT
      (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace,
        LATERAL aclexplode(coalesce(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,c.relowner))) a
        WHERE n.nspname IN ('public','auth') AND c.relkind IN ('r','S') AND a.grantee<>c.relowner) AS relations,
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
        LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
        WHERE n.nspname IN ('public','auth') AND a.grantee<>p.proowner) AS functions,
      (SELECT count(*) FROM pg_attribute at JOIN pg_class c ON c.oid=at.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace,
        LATERAL aclexplode(at.attacl) a WHERE n.nspname IN ('public','auth') AND a.grantee<>c.relowner) AS columns`,
  };
  const result = {};
  for (const [key, sql] of Object.entries(queries)) result[key] = (await client.query(sql)).rows;
  return result;
}

function assertRuntimeCatalog(snapshot, owner) {
  assert(snapshot.defaults.length === 0 && snapshot.foreignGrants.length === 1 &&
    Object.values(snapshot.foreignGrants[0]).every(value => Number(value) === 0),
    "Sandbox schema has unexpected default privileges or foreign grants.");
  const tables = snapshot.relations.filter(r => r.relkind === "r");
  assert.deepEqual(tables.filter(r => r.nspname === "public").map(r => r.relname).sort(), EXPECTED_TABLES,
    "Dedicated sandbox tables differ from the approved schema.");
  assert.deepEqual(tables.filter(r => r.nspname === "auth").map(r => r.relname), ["users"],
    "Dedicated synthetic auth schema differs from the approved schema.");
  assert(snapshot.relations.every(r => r.owner === owner && ["r", "i", "S"].includes(r.relkind)),
    "Dedicated sandbox objects must be owned by the isolated runtime.");
  assert(snapshot.functions.every(f => f.owner === owner && f.prosecdef === false && f.nspname === "public" &&
    /^korlix_schedule_[a-z_]+_v[12]$/.test(f.proname)), "Unexpected sandbox executable object.");
  assert(snapshot.triggers.every(t => t.tgisinternal) && snapshot.rules.length === 0 && snapshot.policies.length === 0,
    "Unexpected sandbox trigger, rule or policy.");
  for (const table of SCHEDULE_TABLES) {
    const row = tables.find(t => t.relname === table);
    assert(row.relrowsecurity && !row.relforcerowsecurity, "Sandbox scheduling RLS must remain enabled and owner accessible.");
  }
  for (const [table, expected] of [[SCHEMA_TABLE, SCHEMA_COLUMNS], [RUN_TABLE, RUN_COLUMNS]]) {
    assert.deepEqual(snapshot.columns.filter(c => c.nspname === "public" && c.relname === table)
      .map(c => [c.attname, c.type, c.attnotnull]), expected, "Sandbox control-table shape mismatch.");
  }
}

async function validateRuntime(client, config) {
  const inspection = await inspectRuntimeDatabase(client);
  // Still validate the original sentinel's exact shape, ACLs and binding.
  const state = await validateState(client, config, inspection, false);
  const rows = (await client.query(`SELECT singleton,version,source_hash,catalog_hash FROM public.${SCHEMA_TABLE}`)).rows;
  assert(rows.length === 1 && rows[0].singleton === true && rows[0].version === SCHEMA_VERSION &&
    rows[0].source_hash === SOURCE_HASH && /^[a-f0-9]{64}$/.test(rows[0].catalog_hash), "Sandbox schema manifest is invalid.");
  const snapshot = await catalog(client);
  assertRuntimeCatalog(snapshot, inspection.owner);
  assert.equal(sha(JSON.stringify(snapshot)), rows[0].catalog_hash, "Sandbox schema drift detected.");
  const runs = (await client.query(`SELECT singleton,run_id,host_id,event_id,booking_id,enabled,created_at FROM public.${RUN_TABLE}`)).rows;
  assert(runs.length === 1 && runs[0].singleton === true, "Sandbox acceptance run is invalid.");
  return { state, run: runs[0] };
}

async function installRuntime(client, config, { now }) {
  const parts = await runtimeSql();
  await client.query(`CREATE SCHEMA auth;
    REVOKE ALL ON SCHEMA auth FROM PUBLIC;
    CREATE TABLE auth.users(id uuid PRIMARY KEY,email_confirmed_at timestamptz,is_anonymous boolean);
    CREATE TABLE public.user_profiles(id uuid PRIMARY KEY,tier text,is_disabled boolean);
    REVOKE ALL ON auth.users,public.user_profiles FROM PUBLIC`);
  for (const sql of parts) await client.query(sql);
  for (const table of SCHEDULE_TABLES) {
    await client.query(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY`);
    await client.query(`REVOKE ALL ON public.${table} FROM PUBLIC`);
  }
  await client.query("REVOKE ALL ON SEQUENCE public.korlix_schedule_audit_id_seq FROM PUBLIC");
  const functions = (await client.query(`SELECT oid::regprocedure::text AS signature FROM pg_proc
    WHERE pronamespace='public'::regnamespace ORDER BY oid::regprocedure::text`)).rows;
  for (const f of functions) {
    // The schema was empty except the reviewed sentinel before checked SQL ran.
    assert(/^(?:public\.)?korlix_schedule_[a-z_]+_v[12]\(/.test(f.signature), "Unexpected scheduling function.");
    await client.query(`REVOKE ALL ON FUNCTION ${f.signature} FROM PUBLIC`);
  }
  await client.query(`CREATE TABLE public.${RUN_TABLE}(
    singleton boolean PRIMARY KEY CHECK(singleton),run_id uuid NOT NULL,host_id uuid NOT NULL,
    event_id uuid,booking_id uuid,enabled boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL
  );
  CREATE TABLE public.${SCHEMA_TABLE}(
    singleton boolean PRIMARY KEY CHECK(singleton),version text NOT NULL CHECK(version='${SCHEMA_VERSION}'),
    source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'),
    catalog_hash text NOT NULL CHECK(catalog_hash ~ '^[a-f0-9]{64}$')
  );
  REVOKE ALL ON public.${RUN_TABLE},public.${SCHEMA_TABLE} FROM PUBLIC`);
  const runId = randomUUID(), hostId = randomUUID();
  await client.query(`INSERT INTO public.${RUN_TABLE}(singleton,run_id,host_id,enabled,created_at)
    VALUES(true,$1,$2,false,$3)`, [runId, hostId, new Date(now()).toISOString()]);
  await client.query("INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES($1,$2,false)",
    [hostId, new Date(now()).toISOString()]);
  await client.query("INSERT INTO public.user_profiles(id,tier,is_disabled) VALUES($1,'basic',false)", [hostId]);
  const inspection = await inspectRuntimeDatabase(client), snapshot = await catalog(client);
  assertRuntimeCatalog(snapshot, inspection.owner);
  await client.query(`INSERT INTO public.${SCHEMA_TABLE}(singleton,version,source_hash,catalog_hash) VALUES(true,$1,$2,$3)`,
    [SCHEMA_VERSION, SOURCE_HASH, sha(JSON.stringify(snapshot))]);
}

/** Call inside a transaction protected by beginHostedAcceptanceTransaction. */
export async function validateHostedAcceptanceDatabase(client, config) {
  if (!config.paymentRuntime) return validateState(client, config, await inspectDatabase(client));
  return (await validateRuntime(client, config)).state;
}

export async function bootstrapHostedAcceptanceDatabase(config, pool, { now = Date.now } = {}) {
  if (!config.paymentRuntime) return bootstrapStageOne(config, pool, { now });
  assert(config.database, "The dedicated database credential is required.");
  const client = await pool.connect();
  try {
    await beginHostedAcceptanceTransaction(client);
    const installed = (await client.query("SELECT to_regclass('public.korlix_hosted_acceptance_schema') IS NOT NULL AS installed")).rows[0]?.installed;
    if (!installed) {
      const inspection = await inspectDatabase(client);
      // Stage two upgrades an existing validated stage-one sentinel only.
      // It never adopts unknown or partially provisioned application objects.
      await validateState(client, config, inspection);
      await installRuntime(client, config, { now });
    }
    const { state, run } = await validateRuntime(client, config);
    await client.query("COMMIT");
    return { createdAt: new Date(state.created_at).toISOString(),
      lastVerifiedAt: state.verified_at ? new Date(state.verified_at).toISOString() : null,
      schemaVersion: SCHEMA_VERSION, runId: run.run_id, hostId: run.host_id,
      eventId: run.event_id, bookingId: run.booking_id, enabled: run.enabled };
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally { client.release(); }
}
