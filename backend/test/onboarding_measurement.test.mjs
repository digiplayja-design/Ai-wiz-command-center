import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {clientRows, createOnboardingMeasurement} from '../onboarding/measurement.mjs';

const uid = '00000000-0000-4000-8000-000000000001';
const req = (events = [{id: randomUUID(), name: 'app_open', new_setup: true}]) => ({
  get: key => ({'X-Korlix-Device-Id': 'korlix_123456789_12345', 'X-Korlix-Platform': 'android'})[key],
  body: {events}, query: {}, socket: {remoteAddress: '127.0.0.1'},
});
const response = () => ({statusCode: 200,
  status(code) {this.statusCode = code; return this;}, set() {return this;},
  json(body) {this.body = body; return this;},
});
function fakeDatabase(fail = false) {
  const writes = [], reports = [];
  const pending = value => ({abortSignal: () => Promise.resolve(value)});
  return {writes, reports, from: () => ({upsert: (rows, options) => {
    writes.push({rows, options}); return pending({error: fail ? new Error('secret-provider-message') : null});
  }}), rpc: (name, args) => {reports.push({name, args}); return pending({data: {opened_setups: 4}});}};
}

test('only allowlisted observations can be ingested; identity and content cannot be injected', () => {
  const rows = clientRows(req());
  assert.equal(rows.length, 1);
  assert.equal(rows[0].installation_hash.length, 64);
  assert.equal(rows[0].user_id, undefined);
  for (const extra of [{user_id: uid}, {prompt: 'private text'}, {email: 'someone@example.test'}, {recorded_at: '2020-01-01'}]) {
    assert.equal(clientRows(req([{id: randomUUID(), name: 'app_open', ...extra}])), null);
  }
  assert.equal(clientRows(req([{id: randomUUID(), name: 'sign_in_succeeded'}])), null);
  assert.equal(clientRows(req([{id: randomUUID(), name: 'registration_submit', error_code: 'secret string'}])), null);
  assert.equal(clientRows({...req(), get: () => 'user@example.test'}), null);
  assert.equal(clientRows(req(Array.from({length: 13}, () => ({id: randomUUID(), name: 'app_open'})))), null);
});

test('retries use idempotent insert and persistence failure is reported without secret details', async () => {
  const database = fakeDatabase();
  const measurement = createOnboardingMeasurement({database});
  const request = req(), result = response();
  await measurement.ingest(request, result);
  await measurement.ingest(request, response());
  assert.equal(result.statusCode, 202);
  assert.deepEqual(database.writes[0], database.writes[1]);
  assert.equal(database.writes[0].options.ignoreDuplicates, true);
  const failed = response(), warnings = [];
  await createOnboardingMeasurement({database: fakeDatabase(true), warn: s => warnings.push(s)}).ingest(req(), failed);
  assert.equal(failed.statusCode, 503);
  assert(!JSON.stringify({failed, warnings}).includes('secret-provider-message'));
});

test('accepted signup without session is never treated as a verified account or successful login', () => {
  const database = fakeDatabase(), measurement = createOnboardingMeasurement({database});
  const request = req(); request.body = {email: 'secret@example.test', password: 'secret-password'};
  const result = response();
  measurement.observeAuth('signup')(request, result, () => {});
  result.json({success: true, user: {id: uid, email: 'secret@example.test'}, session: null});
  assert.deepEqual(database.writes.flatMap(w => w.rows.map(r => r.event_name)), ['signup_attempt', 'signup_accepted']);
  assert(!JSON.stringify(database.writes).includes('secret'));
  assert(database.writes.every(w => w.rows.every(r => r.user_id === null)));
});

test('successful login is associated with the verified user; analytics outage cannot change the auth response', async () => {
  const database = fakeDatabase(true), measurement = createOnboardingMeasurement({database, warn: () => {}});
  const result = response();
  measurement.observeAuth('signin')(req(), result, () => {});
  const payload = {success: true, user: {id: uid, email: 'private@example.test'}, session: {access_token: 'secret-token'}};
  assert.equal(result.json(payload), result);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(result.body, payload);
  assert.equal(database.writes[1].rows[0].event_name, 'sign_in_succeeded');
  assert.equal(database.writes[1].rows[0].user_id, uid);
  assert(!JSON.stringify(database.writes).includes('secret-token'));
});

test('admin report checks server-owned grant and rejects unauthorized or invalid windows', async () => {
  const database = fakeDatabase();
  for (const [user, status] of [[{id: uid}, 403], [{id: uid, developer_unlimited: true, is_disabled: true}, 403], [{id: uid, developer_unlimited: true}, 200]]) {
    const result = response();
    await createOnboardingMeasurement({database, requireUser: async () => user}).summary(req(), result);
    assert.equal(result.statusCode, status);
  }
  assert.equal(database.reports.filter(r => r.name === 'korlix_onboarding_summary').length, 1);
  const result = response();
  await createOnboardingMeasurement({database, requireUser: async () => {throw Object.assign(new Error('secret'), {statusCode: 401});}}).summary(req(), result);
  assert.equal(result.statusCode, 401);
});

test('migration enforces access controls and counts a consistent new-setup cohort', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key, created_at timestamptz,
        email_confirmed_at timestamptz, last_sign_in_at timestamptz, deleted_at timestamptz, is_anonymous boolean);
      create table public.generation_history(user_id uuid, created_at timestamptz);
      grant usage on schema public, auth to service_role; grant select on auth.users, public.generation_history to service_role;`);
    await db.exec(await readFile(new URL('../../supabase/migrations/20261017123110_onboarding_measurement.sql', import.meta.url), 'utf8'));
    await db.query('insert into auth.users values ($1,$2,$2,$2,null,false)', [uid, '2026-10-17T13:00:00Z']);
    await db.query('insert into public.generation_history values ($1,$2)', [uid, '2026-10-17T15:00:00Z']);
    async function event(hash, name, {source = 'client', newSetup = null, userId = null, date = '2026-10-17T14:00:00Z'} = {}) {
      await db.query(`insert into public.korlix_onboarding_events
        (id,installation_hash,platform,source,event_name,new_setup,user_id,recorded_at) values ($1,$2,'android',$3,$4,$5,$6,$7)`,
      [randomUUID(), hash.repeat(64), source, name, newSetup, userId, date]);
    }
    await event('a', 'app_open', {newSetup: true});
    await event('a', 'app_open', {newSetup: false});
    await event('a', 'registration_screen_viewed');
    await event('a', 'registration_submit');
    await event('a', 'registration_submit');
    await event('a', 'sign_in_succeeded', {source: 'server', userId: uid});
    await event('b', 'app_open', {newSetup: false}); // existing user's app update
    await event('c', 'app_open', {newSetup: true, date: '2026-10-15T14:00:00Z'});
    await event('c', 'registration_submit'); // old cohort is excluded
    await event('d', 'app_open', {newSetup: true, date: '2000-01-01T00:00:00Z'});
    await db.exec('set role service_role');
    await db.query('select public.korlix_prune_onboarding_events()');
    assert.equal((await db.query("select count(*)::int n from public.korlix_onboarding_events where installation_hash=repeat('d',64)")).rows[0].n, 0);
    const {rows} = await db.query(`select public.korlix_onboarding_summary($1,$2,'android') as result`,
      ['2026-10-17T00:00:00Z','2026-10-18T00:00:00Z']);
    assert.equal(rows[0].result.opened_setups, 2);
    assert.deepEqual(rows[0].result.new_setup_cohort, {opened: 1, registration_screen: 1,
      registration_submitted: 1, confirmation_screen: 0, signed_in: 1, completed_ai_generation: 1});
    assert.deepEqual(rows[0].result.new_accounts_all_platforms, {created: 1, email_confirmed: 1, signed_in: 1, completed_ai_generation: 1});
    await db.exec('reset role');
    for (const role of ['anon', 'authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query('select * from public.korlix_onboarding_events'), /permission denied/);
      await assert.rejects(db.query("insert into public.korlix_onboarding_events (id,installation_hash,platform,source,event_name) values (gen_random_uuid(),repeat('f',64),'android','client','app_open')"), /permission denied/);
      await assert.rejects(db.query(`select public.korlix_onboarding_summary(now()-interval '1 day',now(),'android')`), /permission denied/);
      await db.exec('reset role');
    }
    await db.query('delete from auth.users where id=$1', [uid]);
    assert.equal((await db.query('select count(*)::int n from public.korlix_onboarding_events where user_id is not null')).rows[0].n, 0);
  } finally {await db.close();}
});
