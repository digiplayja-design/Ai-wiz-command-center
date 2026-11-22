import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

const migration = name => readFile(new URL(`../../supabase/migrations/${name}`, import.meta.url), 'utf8');

test('complete released migration preserves companion sessions and isolates Magic Camera storage', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create schema storage;
    create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects(id text primary key, bucket_id text);
    alter table storage.objects enable row level security;
    grant usage on schema public, storage to anon, authenticated, service_role;
    grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
    create policy unrelated_broad_policy on storage.objects for all to anon, authenticated using (true) with check (true);
    create table public.user_profiles(id uuid primary key references auth.users, tier text not null default 'basic', is_disabled boolean not null default false, max_devices_override integer);
    create table public.korlix_developer_access(user_id uuid primary key, enabled boolean not null default false);
    grant select on public.user_profiles, public.korlix_developer_access to service_role;
    create function public.korlix_web_billing_profile(p_user_id uuid, p_provider_update boolean default false)
      returns jsonb language sql security invoker as 'select to_jsonb(p) from public.user_profiles p where p.id=p_user_id';
  `);
  for (const name of [
    '20261024165108_receipt_wiz_app_sessions.sql',
    '20261025014426_korlix_messenger_app_sessions.sql',
    '20261027224536_korlix_auto_email_app_sessions.sql',
  ]) await db.exec(await migration(name));

  const owner = randomUUID();
  await db.query('insert into auth.users values($1)', [owner]);
  await db.query('insert into public.user_profiles(id) values($1)', [owner]);
  const existing = [];
  for (const app of ['receipt_wiz', 'korlix_messenger', 'auto_email']) {
    existing.push((await db.query('select public.korlix_register_companion_app_session($1,$2,$3,$4) as session',
      [app, owner, randomUUID(), `${app}-device`])).rows[0].session);
  }

  // Execute the shipped file itself, including all schema and session changes.
  await db.exec(await migration('20261030031457_magic_camera_foundation.sql'));
  const after = (await db.query('select to_jsonb(s) as session from public.korlix_receipt_app_sessions s')).rows.map(r => r.session);
  assert.deepEqual(after.sort((a,b) => a.client_app.localeCompare(b.client_app)),
    existing.sort((a,b) => a.client_app.localeCompare(b.client_app)));
  assert.equal((await db.query("select public from storage.buckets where id='korlix-magic-camera'")).rows[0].public, false);

  await db.exec('set role service_role');
  const signedIn = (await db.query('select public.korlix_register_magic_camera_app_session($1,$2,$3) as session',
    [owner, randomUUID(), 'magic-device'])).rows[0].session;
  assert.equal(signedIn.client_app, 'magic_camera');
  const plan = (await db.query('select public.korlix_magic_plan($1,true) as plan', [owner])).rows[0].plan;
  assert.equal(plan.name, 'free');
  assert.equal(plan.remaining, 2);
  assert.equal((await db.query('select public.korlix_magic_plan($1,false) as plan', [owner])).rows[0].plan.can_generate, false);
  assert.equal((await db.query("select count(*)::integer as n from public.korlix_receipt_app_sessions where status='active'")).rows[0].n, 4);
  await db.exec(`insert into storage.objects values ('private-source','korlix-magic-camera'),('unrelated-photo','another-bucket'); reset role;`);

  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    // An unrelated permissive policy must never expose the Magic bucket.
    assert.deepEqual((await db.query('select id from storage.objects')).rows, [{id:'unrelated-photo'}]);
    await assert.rejects(db.query("insert into storage.objects values ('forbidden','korlix-magic-camera')"), /row-level security/);
    await assert.rejects(db.query("update storage.objects set bucket_id='korlix-magic-camera' where id='unrelated-photo'"), /row-level security/);
    assert.equal((await db.query("update storage.objects set bucket_id='another-bucket' where id='private-source' returning id")).rows.length, 0);
    assert.equal((await db.query("delete from storage.objects where id='private-source' returning id")).rows.length, 0);
    await assert.rejects(db.query('select * from public.korlix_magic_jobs'), /permission denied/);
    await assert.rejects(db.query('select public.korlix_magic_plan($1,true)', [owner]), /permission denied/);
    await assert.rejects(db.query("select public.korlix_magic_command(null,'claim')"), /permission denied/);
    await assert.rejects(db.query('select public.korlix_register_magic_camera_app_session($1,$2,$3)',
      [owner, randomUUID(), 'unauthorized-device']), /permission denied/);
    await db.exec('reset role');
  }
  assert.equal((await db.query("select count(*)::integer as n from storage.objects where id='private-source'")).rows[0].n, 1);
  assert.equal((await db.query('select tier from public.user_profiles where id=$1', [owner])).rows[0].tier, 'basic');
});
