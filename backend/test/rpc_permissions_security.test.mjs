import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Isolated signature/privilege fixture only: no production credentials, rows,
// RPC execution, external providers, or assumptions about customer balances.
const alice = '10000000-0000-4000-8000-000000000001';
const bob = '10000000-0000-4000-8000-000000000002';
const signup = '10000000-0000-4000-8000-000000000003';
const signatures = [
  'public.handle_new_user()',
  'public.korlix_claim_monthly_video_generation(uuid,text,text)',
  'public.korlix_get_monthly_video_generation_usage(uuid,text)',
  'public.korlix_get_custom_access(uuid,text)',
  'public.korlix_create_custom_access_code_for_email(text,integer,text[],timestamptz)',
  'public.korlix_redeem_custom_access_code(uuid,text,text)',
];
const helpers = [
  'public.set_updated_at()',
  'public.korlix_normalize_video_tier(text)',
  'public.korlix_video_month_key(timestamptz)',
  'public.korlix_custom_access_email_norm(text)',
  'public.korlix_custom_access_code_norm(text)',
];
const calls = [
  ['select public.korlix_claim_monthly_video_generation($1,$2,$3) as result', [bob, 'enterprise', '2026-10']],
  ['select public.korlix_get_monthly_video_generation_usage($1,$2) as result', [bob, '2026-10']],
  ['select public.korlix_get_custom_access($1,$2) as result', [bob, '2026-10']],
  ['select public.korlix_create_custom_access_code_for_email($1,$2,$3,$4) as result', ['b@example.invalid', 30, ['enterprise'], '2026-12-01T00:00:00Z']],
  ['select public.korlix_redeem_custom_access_code($1,$2,$3) as result', [bob, 'b@example.invalid', 'SYNTHETIC-CODE']],
];

test('RPC hardening removes browser privilege escalation while preserving trusted service and owner access', async t => {
  const db = new PGlite();
  const asRole = async (role, uid, fn) => {
    assert(['anon', 'authenticated', 'service_role', 'supabase_auth_admin'].includes(role));
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [uid || '']);
    await db.exec('set role ' + role);
    try { return await fn(); }
    finally { await db.exec('reset role'); }
  };
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create role service_role bypassrls; create role supabase_auth_admin;
      create schema auth; create schema attack_fixture;
      grant usage on schema public, auth to anon, authenticated, service_role, supabase_auth_admin;
      grant usage, create on schema attack_fixture to anon, authenticated;
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
      $$;
      create table public.user_profiles(id uuid primary key, label text, updated_at timestamptz);
      alter table public.user_profiles enable row level security;
      create policy owner_read on public.user_profiles for select to authenticated using(id=(select auth.uid()));
      create policy owner_insert on public.user_profiles for insert to authenticated with check(id=(select auth.uid()));
      grant select,insert on public.user_profiles to authenticated;
      grant all on public.user_profiles to service_role;
      grant truncate,references,trigger on public.user_profiles to public,anon,authenticated;
      create table public.private_rpc_fixture(id uuid primary key, secret text, calls integer not null default 0);
      alter table public.private_rpc_fixture enable row level security;
      grant all on public.private_rpc_fixture to service_role;
      create table auth.users(id uuid primary key, email text);
      grant insert on auth.users to supabase_auth_admin;
      create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
        begin insert into public.user_profiles(id,label) values(new.id,new.email); return new; end
      $$;
      create trigger on_signup after insert on auth.users for each row execute function public.handle_new_user();
      create function public.korlix_claim_monthly_video_generation(uuid,text,text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
        declare r jsonb; begin update public.private_rpc_fixture set calls=calls+1 where id=$1 returning to_jsonb(private_rpc_fixture) into r; return r; end
      $$;
      create function public.korlix_get_monthly_video_generation_usage(uuid,text) returns jsonb language sql security definer set search_path=pg_catalog,public as $$
        select to_jsonb(x) from public.private_rpc_fixture x where id=$1
      $$;
      create function public.korlix_get_custom_access(uuid,text) returns jsonb language sql security definer set search_path=pg_catalog,public as $$
        select to_jsonb(x) from public.private_rpc_fixture x where id=$1
      $$;
      create function public.korlix_create_custom_access_code_for_email(text,integer,text[],timestamptz) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
        begin update public.private_rpc_fixture set calls=calls+1; return jsonb_build_object('created',true); end
      $$;
      create function public.korlix_redeem_custom_access_code(uuid,text,text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
        begin update public.private_rpc_fixture set calls=calls+1 where id=$1; return jsonb_build_object('redeemed',true); end
      $$;
      create function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
      create function public.korlix_normalize_video_tier(text) returns text language sql immutable as $$ select lower(trim($1)) $$;
      create function public.korlix_video_month_key(timestamptz) returns text language sql stable as $$ select to_char($1 at time zone 'UTC','YYYY-MM') $$;
      create function public.korlix_custom_access_email_norm(text) returns text language sql immutable as $$ select lower(trim($1)) $$;
      create function public.korlix_custom_access_code_norm(text) returns text language sql immutable as $$ select upper(trim($1)) $$;
      grant execute on all functions in schema public to anon,authenticated;
    `);
    await db.query('insert into public.user_profiles(id,label) values($1,$2),($3,$4)', [alice, 'Alice fixture', bob, 'Bob fixture']);
    await db.query('insert into public.private_rpc_fixture(id,secret) values($1,$2),($3,$4)', [alice, 'Synthetic A', bob, 'Synthetic B']);
    const policiesBefore = (await db.query("select policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname")).rows;
    const tableBefore = (await db.query("select oid::text,relrowsecurity from pg_class where oid in ('public.user_profiles'::regclass,'public.private_rpc_fixture'::regclass) order by oid")).rows;

    await t.test('reproduces anonymous and authenticated definer calls against another synthetic owner before hardening', async () => {
      for (const role of ['anon', 'authenticated']) await asRole(role, alice, async () => {
        await assert.rejects(db.query('select * from public.private_rpc_fixture'), e => e.code === '42501');
        for (const [sql, params] of calls) assert((await db.query(sql, params)).rows[0].result);
        assert.equal((await db.query(calls[2][0], calls[2][1])).rows[0].result.secret, 'Synthetic B');
        for (const signature of signatures) assert.equal((await db.query('select has_function_privilege(current_user,$1,\'execute\') as allowed', [signature])).rows[0].allowed, true);
        assert.equal((await db.query("select has_table_privilege(current_user,'public.user_profiles','TRUNCATE') as allowed")).rows[0].allowed, true);
      });
    });

    const folder = new URL('../../supabase/migrations/', import.meta.url);
    const file = process.env.KORLIX_RPC_HARDENING_MIGRATION || (await readdir(folder)).find(name => name.endsWith('_rpc_security_hardening.sql'));
    assert(file, 'RPC security hardening migration must exist');
    const migration = await readFile(process.env.KORLIX_RPC_HARDENING_MIGRATION || new URL(file, folder), 'utf8');
    await db.exec(migration);

    await t.test('all dangerous functions deny both browser roles after revocation', async () => {
      const before = (await db.query('select * from public.private_rpc_fixture order by id')).rows;
      for (const role of ['anon', 'authenticated']) await asRole(role, alice, async () => {
        for (const [sql, params] of calls) await assert.rejects(db.query(sql, params), e => e.code === '42501');
        for (const signature of signatures) assert.equal((await db.query('select has_function_privilege(current_user,$1,\'execute\') as allowed', [signature])).rows[0].allowed, false);
      });
      assert.deepEqual((await db.query('select * from public.private_rpc_fixture order by id')).rows, before);
    });

    await t.test('trusted service role retains all function execution and authorized operations', async () => {
      await asRole('service_role', null, async () => {
        for (const signature of signatures) assert.equal((await db.query('select has_function_privilege(current_user,$1,\'execute\') as allowed', [signature])).rows[0].allowed, true);
        for (const [sql, params] of calls) assert((await db.query(sql, params)).rows[0].result);
        assert.equal((await db.query('select * from public.user_profiles')).rows.length, 2);
      });
    });

    await t.test('preinstalled signup trigger still creates the profile without direct execute permission', async () => {
      await asRole('supabase_auth_admin', null, async () => {
        assert.equal((await db.query("select has_function_privilege(current_user,'public.handle_new_user()','execute') as allowed")).rows[0].allowed, false);
        await db.query('insert into auth.users values($1,$2)', [signup, 'signup@example.invalid']);
      });
      assert.deepEqual((await db.query('select id,label from public.user_profiles where id=$1', [signup])).rows, [{ id: signup, label: 'signup@example.invalid' }]);
    });

    await t.test('helper search paths are pinned and callable helper behavior remains intact', async () => {
      for (const signature of helpers) {
        const row = (await db.query('select proconfig from pg_proc where oid=$1::regprocedure', [signature])).rows[0];
        assert(row.proconfig.includes('search_path=pg_catalog'));
      }
      await asRole('authenticated', alice, async () => {
        await db.exec('set search_path=attack_fixture,public');
        assert.deepEqual((await db.query("select public.korlix_normalize_video_tier(' ENTERPRISE ') as tier, public.korlix_video_month_key('2026-10-07T00:00:00Z') as month, public.korlix_custom_access_email_norm(' A@EXAMPLE.INVALID ') as email, public.korlix_custom_access_code_norm(' sample ') as code")).rows[0], { tier: 'enterprise', month: '2026-10', email: 'a@example.invalid', code: 'SAMPLE' });
      });
      await db.exec('reset search_path');
    });

    await t.test('RLS policies and legitimate grants are preserved, with foreign-owner data still invisible', async () => {
      assert.deepEqual((await db.query("select policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname")).rows, policiesBefore);
      assert.deepEqual((await db.query("select oid::text,relrowsecurity from pg_class where oid in ('public.user_profiles'::regclass,'public.private_rpc_fixture'::regclass) order by oid")).rows, tableBefore);
      for (const uid of [alice, bob]) await asRole('authenticated', uid, async () => {
        assert.deepEqual((await db.query('select id from public.user_profiles')).rows, [{ id: uid }]);
        assert.equal((await db.query("select has_table_privilege(current_user,'public.user_profiles','INSERT') as allowed")).rows[0].allowed, true);
        await assert.rejects(db.query('insert into public.user_profiles(id,label) values(gen_random_uuid(),\'foreign\')'), e => e.code === '42501');
      });
      await asRole('anon', null, async () => { await assert.rejects(db.query('select * from public.user_profiles'), e => e.code === '42501'); });
    });

    await t.test('TRUNCATE, REFERENCES, and TRIGGER are denied without changing service privileges', async () => {
      for (const role of ['anon', 'authenticated']) await asRole(role, alice, async () => {
        for (const privilege of ['TRUNCATE', 'REFERENCES', 'TRIGGER']) assert.equal((await db.query('select has_table_privilege(current_user,\'public.user_profiles\',$1) as allowed', [privilege])).rows[0].allowed, false);
        await assert.rejects(db.exec('truncate public.user_profiles'), e => e.code === '42501');
        await assert.rejects(db.exec('create table attack_fixture.link(id uuid references public.user_profiles(id))'), e => e.code === '42501');
        await assert.rejects(db.exec('create trigger injected before update on public.user_profiles for each row execute function public.set_updated_at()'), e => e.code === '42501');
      });
      await asRole('service_role', null, async () => {
        for (const privilege of ['TRUNCATE', 'REFERENCES', 'TRIGGER']) assert.equal((await db.query('select has_table_privilege(current_user,\'public.user_profiles\',$1) as allowed', [privilege])).rows[0].allowed, true);
      });
      assert.equal((await db.query('select count(*)::int as n from public.user_profiles')).rows[0].n, 3);
    });

    await t.test('hardening can be reapplied without widening privileges or disrupting existing policies', async () => {
      await db.exec(migration);
      for (const signature of signatures) {
        assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') as allowed", [signature])).rows[0].allowed, false);
        assert.equal((await db.query("select has_function_privilege('service_role',$1,'execute') as allowed", [signature])).rows[0].allowed, true);
      }
      assert.deepEqual((await db.query("select policyname,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname")).rows, policiesBefore);
    });
  } finally { await db.close(); }
});
