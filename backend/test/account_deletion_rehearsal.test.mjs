import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import vm from 'node:vm';
import express from 'express';
import sharp from 'sharp';
import { PGlite } from '@electric-sql/pglite';
import { registerReceiptWiz } from '../receipt_wiz/routes.mjs';

// A local rehearsal of existing operations, not an account-purger implementation.
// Real route/SQL code runs against synthetic users. Storage and Auth are local
// adapters; nothing reads production credentials or contacts a provider.
const source = await readFile(new URL('../server.js', import.meta.url), 'utf8');
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert(a >= 0 && b > a);
  return source.slice(a, b);
}
const auth = section('function makeHttpError(', 'async function getOrCreateProfile(');
const intake = section('app.post("/api/account/delete-request"', 'async function createKorlixImprovedImage(');
let db, server, base, actor, other, objects, storageFails, databaseFails;
const tokens = new Map();
const tableCount = async (table, user) =>
  (await db.query(`select count(*)::int n from ${table} where owner_id=$1`, [user])).rows[0].n;
async function rpc(name, p) {
  try {
    if (databaseFails) throw Object.assign(Error('Synthetic private storage failure'), { code: '08006' });
    assert(['korlix_request_account_deletion', 'korlix_receipt_wiz_v1'].includes(name));
    const args = name === 'korlix_request_account_deletion'
      ? [p.p_user_id, p.p_email, p.p_reason] : [p.p_actor, p.p_action, p.p_id, p.p_data];
    return { data: (await db.query(`select public.${name}(${args.map((_, i) => '$' + (i + 1)).join(',')}) result`, args)).rows[0].result };
  } catch (error) { return { error }; }
}
async function request(path, { user = actor, method = 'GET', body, status = 200 } = {}) {
  const response = await fetch(base + path, {
    method, headers: { ...(user ? { Authorization: 'Bearer ' + user.token } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await response.json();
  assert.equal(response.status, status, JSON.stringify(data));
  return data;
}
async function upload(user = actor) {
  const bytes = await sharp({ create: { width: 16, height: 24, channels: 3, background: '#ddd' } }).png().toBuffer();
  const body = new FormData(); body.append('receipt', new Blob([bytes]), 'synthetic-receipt.png');
  const response = await fetch(base + '/api/receipt-wiz', {
    method: 'POST', headers: { Authorization: 'Bearer ' + user.token, 'X-Receipt-Request-Key': randomUUID() }, body,
  });
  const data = await response.json(); assert.equal(response.status, 201, JSON.stringify(data)); return data.receipt;
}
async function admin(fn) {
  await db.exec('reset role');
  try { return await fn(); } finally { await db.exec('set role service_role'); }
}
const receiptCommand = async (user, action, id) => {
  const result = await rpc('korlix_receipt_wiz_v1', { p_actor: user.id, p_action: action, p_id: id, p_data: { confirmed: true } });
  if (result.error) throw result.error;
  return result.data;
};

test.before(async () => {
  db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key,email text);
    create table public.user_profiles(id uuid primary key references auth.users(id) on delete cascade,is_disabled boolean default false);
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id text primary key,bucket_id text); alter table storage.objects enable row level security;
    grant usage on schema auth,public,storage to service_role;
    grant select on auth.users,public.user_profiles to service_role;
    create table public.korlix_bookkeeping_businesses(id uuid primary key,owner_id uuid,name text);
    create table public.korlix_tax_workspaces(id uuid primary key,owner_id uuid,tax_year int);
    grant select on korlix_bookkeeping_businesses,korlix_tax_workspaces to service_role;
    create table public.account_deletion_requests(
      id uuid primary key default gen_random_uuid(),user_id uuid,email text,reason text,
      status text not null default 'requested',created_at timestamptz not null default now(),completed_at timestamptz
    );
    create table public.reports(id uuid primary key default gen_random_uuid(),user_id uuid,reason text,status text default 'new');
  `);
  for (const name of ['20261006171056_receipt_wiz_shared_inbox.sql', '20261006174957_receipt_wiz_explicit_private_policies.sql', '20261007113219_support_intake_and_default_privileges.sql']) {
    await db.exec(await readFile(new URL('../../supabase/migrations/' + name, import.meta.url), 'utf8'));
  }
  const database = {
    rpc,
    auth: { getUser: async token => ({ data: { user: (await db.query('select id,email from auth.users where id=$1', [tokens.get(token) ?? null])).rows[0] ?? null } }) },
    from(table) {
      assert.equal(table, 'user_profiles'); let id;
      const chain = { select() { return chain; }, eq(column, value) { assert.equal(column, 'id'); id = value; return chain; },
        async maybeSingle() { return { data: (await db.query('select is_disabled from public.user_profiles where id=$1', [id])).rows[0] ?? null }; } };
      return chain;
    },
  };
  const app = express(); app.use(express.json());
  const context = vm.createContext({ app, supabaseAdmin: database,
    getRequestDeviceInfo: () => ({ explicitDeviceId: false }),
    getKorlixUserFacingError: error => error.statusCode ? error.message : 'The request could not be completed. Please retry.',
  });
  vm.runInContext(auth + intake, context);
  registerReceiptWiz(app, { database, requireUser: context.requireUser,
    storage: {
      upload: async (path, bytes) => { objects.set(path, Buffer.from(bytes)); },
      download: async path => { if (!objects.has(path)) throw Error('Missing synthetic object'); return objects.get(path); },
      remove: async paths => { if (storageFails) throw Error('Synthetic object removal unavailable'); paths.forEach(path => objects.delete(path)); },
    },
    scanReceipt: async () => { throw Error('This rehearsal must not invoke AI'); },
  });
  server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
});
test.beforeEach(async () => {
  objects = new Map(); storageFails = databaseFails = false;
  actor = { id: randomUUID(), token: randomUUID(), email: 'owner@example.invalid' };
  other = { id: randomUUID(), token: randomUUID(), email: 'other@example.invalid' };
  await admin(async () => { for (const user of [actor, other]) {
    tokens.set(user.token, user.id);
    await db.query('insert into auth.users values($1,$2)', [user.id, user.email]);
    await db.query('insert into public.user_profiles(id) values($1)', [user.id]);
  } });
});
test.after(async () => { server?.closeAllConnections(); if (server) await new Promise(resolve => server.close(resolve)); await db?.close(); });

test('HTTP deletion intake persists once using verified identity and does not erase files or account', async () => {
  await upload();
  const body = { user_id: other.id, email: other.email, reason: 'Please remove my synthetic account.' };
  const first = await request('/api/account/delete-request', { method: 'POST', body });
  const retry = await request('/api/account/delete-request', { method: 'POST', body });
  assert.equal(first.success, true); assert.equal(first.request.user_id, actor.id);
  assert.equal(first.request.email, actor.email); assert.equal(first.request.status, 'requested');
  assert.equal(retry.request.id, first.request.id); assert.equal(first.request.completed_at, null);
  assert.equal((await db.query('select count(*)::int n from account_deletion_requests where user_id=$1', [actor.id])).rows[0].n, 1);
  assert.equal(await tableCount('korlix_receipt_wiz', actor.id), 1); assert.equal(objects.size, 2);
  assert.equal((await db.query('select id from auth.users where id=$1', [actor.id])).rows.length, 1);
});

test('anonymous requests and persistence failures cannot falsely acknowledge deletion', async () => {
  await request('/api/account/delete-request', { user: null, method: 'POST', body: {}, status: 401 });
  databaseFails = true;
  const failed = await request('/api/account/delete-request', { method: 'POST', body: {}, status: 500 });
  assert.equal(failed.success, undefined); assert(!JSON.stringify(failed).includes('private storage'));
  assert.equal((await db.query('select count(*)::int n from account_deletion_requests where user_id=$1', [actor.id])).rows[0].n, 0);
});

test('receipt removal must finish before auth deletion; failures remain retryable and another owner survives', async () => {
  const receipt = await upload(), foreignReceipt = await upload(other);
  const requestRow = (await request('/api/account/delete-request', { method: 'POST', body: {} })).request;
  storageFails = true;
  await request('/api/receipt-wiz/' + receipt.id, { method: 'DELETE', body: { confirmed: true }, status: 503 });
  assert.equal(objects.size, 4);
  storageFails = false;
  // Operator freezes new requests. The existing service-only receipt commands
  // remain available to authorized fulfillment after browser access is blocked.
  await admin(() => db.query('update user_profiles set is_disabled=true where id=$1', [actor.id]));
  // Receipt Wiz intentionally maps authentication failures to its 401 response.
  await request('/api/receipt-wiz', { status: 401 });
  await assert.rejects(receiptCommand(other, 'delete_begin', receipt.id));
  let pending = await receiptCommand(actor, 'delete_begin', receipt.id);
  const paths = [pending.object_path, pending.preview_path].filter(Boolean);
  assert.equal(paths.length, 2); assert(paths.every(path => objects.has(path)));
  // An object-store failure cannot justify deleting the metadata or closing the case.
  assert.equal((await db.query('select state from korlix_receipt_wiz where id=$1', [receipt.id])).rows[0].state, 'deleting');
  assert.equal((await db.query('select status from account_deletion_requests where id=$1', [requestRow.id])).rows[0].status, 'requested');
  pending = await receiptCommand(actor, 'delete_begin', receipt.id);
  assert.deepEqual([pending.object_path, pending.preview_path].filter(Boolean), paths);
  // Successful synthetic object deletion, then the real feature SQL finish.
  for (const path of paths) objects.delete(path);
  await receiptCommand(actor, 'delete_finish', receipt.id);
  await admin(() => db.query('delete from auth.users where id=$1', [actor.id]));
  await request('/api/receipt-wiz', { status: 401 });
  assert.equal(await tableCount('korlix_receipt_wiz', actor.id), 0);
  assert.equal(await tableCount('korlix_receipt_wiz_scans', actor.id), 0);
  assert.equal(objects.size, 2); assert(paths.every(path => !objects.has(path)));
  const remaining = await request('/api/receipt-wiz/' + foreignReceipt.id, { user: other });
  assert.equal(remaining.receipt.id, foreignReceipt.id);
  // This is selected-feature evidence only, so the actual support case remains open.
  assert.equal((await db.query('select status from account_deletion_requests where id=$1', [requestRow.id])).rows[0].status, 'requested');
});

test('auth-row cascade alone is not storage fulfillment and must not be called complete', async () => {
  await upload(); assert.equal(objects.size, 2);
  await admin(() => db.query('delete from auth.users where id=$1', [actor.id]));
  assert.equal(await tableCount('korlix_receipt_wiz', actor.id), 0);
  assert.equal(objects.size, 2, 'Cloud object bytes are independent of PostgreSQL cascades');
  await request('/api/receipt-wiz', { status: 401 });
});
