import pg from 'pg';
import {spawn} from 'node:child_process';
import {mkdtemp, chmod, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {check, backupError, hash, MAX_PART, SOURCE_PROJECT} from './archive.mjs';
import {readBoundedStream} from '../receipt_backup/backblaze.mjs';

export const APPLICATION_SCHEMAS = ['public', 'auth', 'storage', 'k135z_b5b_private',
  'k135z_workspace_private', 'korlix_live_private', 'supabase_migrations'];
const MANAGED_SCHEMAS = ['extensions', 'graphql', 'graphql_public', 'realtime', 'vault'];
export const SHORT_RETENTION_EXCLUSIONS = ['public.korlix_live_studio_*'];
export const RECOVERY_CONTROL_TABLES = ['account_deletion_requests', 'korlix_social_dump_requests',
  'korlix_social_message_dumps', 'korlix_social_shared_message_dumps', 'korlix_crm_email_suppressions',
  'korlix_funnel_removed_requests', 'korlix_funnel_cleanup_receipts'];
export const BUCKETS = ['korlix-app-portals', 'korlix-babyblend', 'korlix-bookkeeping-receipts', 'korlix-directory',
  'korlix-fieldproof', 'korlix-fieldproof-mail', 'korlix-inventory', 'korlix-live-studio', 'korlix-meeting-recordings',
  'korlix-receipt-wiz', 'korlix-social-albums', 'korlix-social-attachments', 'korlix-social-avatars',
  'korlix-social-videos', 'korlix-virtual-closet', 'korlix-workforce-evidence'];

export function connectionConfig(env) {
  let u;
  try { u = new URL(env.KORLIX_BACKUP_DATABASE_URL || ''); }
  catch { throw backupError('BACKUP_APP_DATABASE_CREDENTIAL_REQUIRED'); }
  const username = decodeURIComponent(u.username), password = decodeURIComponent(u.password);
  const direct = u.hostname === `db.${SOURCE_PROJECT}.supabase.co` && username === 'postgres';
  const pooler = /^aws-[0-9]+-us-east-2\.pooler\.supabase\.com$/.test(u.hostname) && username === `postgres.${SOURCE_PROJECT}`;
  check(['postgres:', 'postgresql:'].includes(u.protocol) && (direct || pooler) && (!u.port || u.port === '5432')
    && u.pathname === '/postgres' && !u.hash && password.length > 0 && password.length <= 500,
  'BACKUP_APP_DATABASE_SOURCE_INVALID');
  for (const [k, v] of u.searchParams) check(k === 'sslmode' && ['require', 'verify-full'].includes(v), 'BACKUP_APP_DATABASE_SOURCE_INVALID');
  const ca = env.KORLIX_BACKUP_DATABASE_CA_PEM || '';
  check(!ca || (ca.length <= 20000 && ca.includes('-----BEGIN CERTIFICATE-----')), 'BACKUP_APP_DATABASE_CA_INVALID');
  return {host: u.hostname, port: 5432, user: username, password, database: 'postgres',
    ssl: {rejectUnauthorized: true, ...(ca ? {ca} : {})}, application_name: 'korlix-readonly-backup',
    connectionTimeoutMillis: 15000, query_timeout: 45000, statement_timeout: 40000};
}

export function inventoryDigest(inventory) { return hash(Buffer.from(JSON.stringify(inventory))); }

export async function readInventory(client) {
  const buckets = (await client.query('select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id')).rows;
  check(buckets.every(b => BUCKETS.includes(b.id) && b.public === false), 'BACKUP_APP_BUCKET_REVIEW_REQUIRED');
  const objects = (await client.query(`select id,bucket_id,name,owner_id,created_at,updated_at,version,metadata,user_metadata,
    archived_at,is_delete_marker,is_versioned from storage.objects order by bucket_id,name,id limit 10001`)).rows;
  check(objects.length <= 10000, 'BACKUP_APP_OBJECT_COUNT_LIMIT');
  let total = 0;
  for (const o of objects) {
    check(BUCKETS.includes(o.bucket_id) && typeof o.name === 'string' && o.name.length > 0 && o.name.length <= 2048
      && !o.name.split('/').some(p => !p || p === '.' || p === '..') && !/[\x00-\x1f]/.test(o.name), 'BACKUP_APP_OBJECT_INVALID');
    check(!o.archived_at && !o.is_delete_marker && !o.is_versioned, 'BACKUP_APP_STORAGE_VERSIONING_REVIEW_REQUIRED');
    const size = Number(o.metadata?.size);
    check(Number.isSafeInteger(size) && size >= 0 && size <= 64 * 1024 * 1024, 'BACKUP_APP_SOURCE_SIZE_LIMIT');
    total += size;
  }
  check(total <= 1024 * 1024 * 1024, 'BACKUP_APP_RUN_SIZE_LIMIT');
  return {buckets, objects, sourceBytes: total};
}

// Only fixed executables/arguments selected by this module; never a shell or customer-provided command.
export async function runProcess(command, args, {env, signal, maximum = MAX_PART - 65536, input, spawnImpl = spawn} = {}) {
  const child = spawnImpl(command, args, {env, signal, stdio: ['pipe', 'pipe', 'pipe'], shell: false});
  child.stderr.resume(); // Provider errors may contain hostnames/rows/secrets. Never log them.
  const complete = new Promise((resolve, reject) => {
    child.once('error', () => reject(backupError('BACKUP_APP_DATABASE_TOOL_FAILED')));
    child.once('close', code => code === 0 ? resolve() : reject(backupError('BACKUP_APP_DATABASE_TOOL_FAILED')));
  });
  child.stdin.on('error', () => {}); child.stdin.end(input);
  try {
    const [bytes] = await Promise.all([readBoundedStream(child.stdout, maximum), complete]);
    return bytes;
  } catch { child.kill('SIGKILL'); throw backupError('BACKUP_APP_DATABASE_TOOL_FAILED'); }
}

export function createPostgresBackupSource({env = process.env, Client = pg.Client, fetchImpl = fetch, processRunner = runProcess} = {}) {
  const connection = connectionConfig(env);
  check(env.SUPABASE_URL === `https://${SOURCE_PROJECT}.supabase.co` && Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
    'BACKUP_APP_STORAGE_SOURCE_INVALID');
  const client = new Client(connection);
  let workdir, snapshot, closed = false, abortHandler, parentSignal;
  async function end() {
    if (closed) return;
    closed = true;
    parentSignal?.removeEventListener('abort', abortHandler);
    await client.end().catch(() => {});
    if (workdir) await rm(workdir, {recursive: true, force: true});
  }
  return {
    async begin(signal) {
      parentSignal = signal;
      signal?.throwIfAborted();
      await client.connect();
      // A broken connection is handled by the running query rather than an unhandled EventEmitter error.
      client.on('error', () => {});
      abortHandler = () => { void client.end().catch(() => {}); };
      signal?.addEventListener('abort', abortHandler, {once: true});
      await client.query('begin isolation level repeatable read read only');
      await client.query("set local idle_in_transaction_session_timeout='20min'");
      const meta = (await client.query(`select current_setting('server_version_num')::int as version,
        pg_export_snapshot() as snapshot, clock_timestamp() as captured_at,
        (select count(*)::int from vault.secrets) as vault_secrets`)).rows[0];
      check(meta.version >= 170000 && meta.version < 180000, 'BACKUP_APP_POSTGRES_VERSION_REVIEW_REQUIRED');
      check(meta.vault_secrets === 0, 'BACKUP_APP_VAULT_KEY_ESCROW_REQUIRED');
      check(/^[0-9A-Fa-f-]+$/.test(meta.snapshot), 'BACKUP_APP_SNAPSHOT_INVALID'); snapshot = meta.snapshot;
      const schemas = (await client.query("select nspname from pg_namespace where nspname not like 'pg_%' and nspname <> 'information_schema' order by nspname")).rows.map(r => r.nspname);
      check(schemas.every(n => APPLICATION_SCHEMAS.includes(n) || MANAGED_SCHEMAS.includes(n)), 'BACKUP_APP_SCHEMA_REVIEW_REQUIRED');
      const roles = (await client.query(`select rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconfig
        from pg_roles order by rolname`)).rows;
      const memberships = (await client.query(`select r.rolname as role,m.rolname as member,a.admin_option from pg_auth_members a
        join pg_roles r on r.oid=a.roleid join pg_roles m on m.oid=a.member order by r.rolname,m.rolname`)).rows;
      const extensions = (await client.query('select extname,extversion from pg_extension order by extname')).rows;
      const inventory = await readInventory(client);
      const recoveryControls = {};
      for (const table of RECOVERY_CONTROL_TABLES) {
        // table names come only from the fixed allowlist above, never from a request or archive.
        const rows = (await client.query(`select * from public.${table} limit 10001`)).rows;
        check(rows.length <= 10000, 'BACKUP_APP_RECOVERY_CONTROL_LIMIT'); recoveryControls[table] = rows;
      }
      recoveryControls.activeProfileInventory = (await client.query('select id,is_disabled from public.user_profiles order by id limit 10001')).rows;
      check(recoveryControls.activeProfileInventory.length <= 10000
        && Buffer.byteLength(JSON.stringify(recoveryControls)) <= 16 * 1024 * 1024, 'BACKUP_APP_RECOVERY_CONTROL_LIMIT');
      return {inventory, recoveryControls, capturedAt: new Date(meta.captured_at).toISOString(), databaseMetadata: {
        serverVersion: meta.version, schemas, roles, memberships, extensions, includedSchemas: APPLICATION_SCHEMAS,
        excludedTableData: SHORT_RETENTION_EXCLUSIONS, vaultSecrets: 0}};
    },
    async dump(signal) {
      check(snapshot, 'BACKUP_APP_SNAPSHOT_REQUIRED');
      workdir = await mkdtemp(join(tmpdir(), 'korlix-backup-')); await chmod(workdir, 0o700);
      const childEnv = {PATH: process.env.PATH, LANG: 'C.UTF-8', PGHOST: connection.host, PGPORT: '5432',
        PGUSER: connection.user, PGPASSWORD: connection.password, PGDATABASE: 'postgres', PGSSLMODE: 'verify-full',
        PGCONNECT_TIMEOUT: '15', PGAPPNAME: 'korlix-readonly-backup',
        PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=900000'};
      if (connection.ssl.ca) {
        const caPath = join(workdir, 'root.crt'); await writeFile(caPath, connection.ssl.ca, {mode: 0o600}); childEnv.PGSSLROOTCERT = caPath;
      } else { childEnv.PGSSLROOTCERT = 'system'; }
      const version = (await processRunner('pg_dump', ['--version'], {env: childEnv, signal, maximum: 1000})).toString();
      check(/PostgreSQL\) 17\./.test(version), 'BACKUP_APP_POSTGRES_CLIENT_INVALID');
      const bytes = await processRunner('pg_dump', ['--format=custom', '--compress=6', '--no-password', '--no-owner',
        '--lock-wait-timeout=10000', '--no-publications', '--no-subscriptions', '--snapshot=' + snapshot,
        ...APPLICATION_SCHEMAS.map(s => '--schema=' + s), ...SHORT_RETENTION_EXCLUSIONS.map(s => '--exclude-table-data=' + s)],
      {env: childEnv, signal});
      check(bytes.subarray(0, 5).toString() === 'PGDMP', 'BACKUP_APP_DATABASE_ARCHIVE_INVALID');
      await processRunner('pg_restore', ['--list'], {env: {PATH: process.env.PATH, LANG: 'C.UTF-8'}, signal,
        input: bytes, maximum: 8 * 1024 * 1024});
      // Force decompression of every archive entry too; --list alone only checks the table of contents.
      await processRunner('pg_restore', ['--file=/dev/null'], {env: {PATH: process.env.PATH, LANG: 'C.UTF-8'}, signal,
        input: bytes, maximum: 1024});
      return bytes;
    },
    async download(object, signal) {
      const path = object.name.split('/').map(encodeURIComponent).join('/');
      const response = await fetchImpl(`${env.SUPABASE_URL}/storage/v1/object/authenticated/${object.bucket_id}/${path}`,
        {redirect: 'error', cache: 'no-store', signal,
          headers: {apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`}});
      try {
        check(response.ok, 'BACKUP_APP_SOURCE_DOWNLOAD_FAILED');
        const bytes = await readBoundedStream(response.body, 64 * 1024 * 1024);
        check(bytes.length === Number(object.metadata.size), 'BACKUP_APP_SOURCE_SIZE_MISMATCH');
        return bytes;
      } finally { await response.body?.cancel().catch(() => {}); }
    },
    async unchanged(inventory, signal) {
      signal?.throwIfAborted();
      // Finish the original snapshot, then compare with a fresh view, including deletes and ownership changes.
      await client.query('commit');
      await client.query('begin isolation level repeatable read read only');
      return inventoryDigest(inventory) === inventoryDigest(await readInventory(client));
    },
    close: end,
  };
}
