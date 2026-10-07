import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const alice = '10000000-0000-4000-8000-000000000001';
const bob = '10000000-0000-4000-8000-000000000002';
const migration = new URL('../../supabase/migrations/20261007113219_support_intake_and_default_privileges.sql', import.meta.url);

test('support intake rejects direct clients and safely deduplicates authenticated backend requests', async t => {
  const db = new PGlite();
  const asRole = async (role, fn) => {
    assert(['anon', 'authenticated', 'service_role'].includes(role));
    await db.exec('set role ' + role);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };
  const request = async (id = alice, email = 'alice@example.invalid', reason = 'Please remove my account.') =>
    (await db.query('select public.korlix_request_account_deletion($1,$2,$3) result', [id, email, reason])).rows[0].result;
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth;
      grant usage on schema public, auth to anon, authenticated, service_role;
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
      $$;
      create table public.account_deletion_requests (
        id uuid primary key default gen_random_uuid(), user_id uuid, email text, reason text,
        status text not null default 'requested', created_at timestamptz not null default now(), completed_at timestamptz
      );
      create table public.reports (
        id uuid primary key default gen_random_uuid(), user_id uuid, reason text not null,
        details text, status text not null default 'new', created_at timestamptz not null default now()
      );
      alter table public.account_deletion_requests enable row level security;
      alter table public.reports enable row level security;
      create policy "Users can request account deletion" on public.account_deletion_requests for insert
        with check ((select auth.uid()) = user_id or user_id is null);
      create policy "Users can create reports" on public.reports for insert
        with check ((select auth.uid()) = user_id or user_id is null);
      grant all on public.account_deletion_requests, public.reports to anon, authenticated, service_role;
      create table public.existing_catalog_fixture (label text);
      grant select, maintain on public.existing_catalog_fixture to anon, authenticated;
      alter default privileges for role postgres in schema public
        grant truncate, references, trigger, maintain on tables to anon, authenticated;
      alter default privileges for role postgres in schema public grant all on tables to service_role;
      alter default privileges for role postgres in schema public grant execute on functions to service_role;
    `);
    await t.test('reproduces anonymous forged support states before the migration', async () => {
      await asRole('anon', async () => {
        await db.exec("insert into public.account_deletion_requests(email,status) values('other@example.invalid','completed')");
        await db.exec("insert into public.reports(reason,status) values('Synthetic report','resolved')");
      });
      assert.equal((await db.query('select count(*)::int n from public.account_deletion_requests')).rows[0].n, 1);
    });
    await db.exec(await readFile(migration, 'utf8'));
    await t.test('both browser roles cannot read, insert, change, delete or invoke support intake', async () => {
      for (const role of ['anon', 'authenticated']) await asRole(role, async () => {
        for (const table of ['account_deletion_requests', 'reports']) {
          for (const sql of [`select * from public.${table}`, `insert into public.${table}(reason) values('forged')`,
            `update public.${table} set status='completed'`, `delete from public.${table}`]) {
            await assert.rejects(db.query(sql), error => error.code === '42501');
          }
        }
        await assert.rejects(request(), error => error.code === '42501');
      });
    });
    await t.test('verified backend retries reuse one pending request and separate users', async () => {
      await asRole('service_role', async () => {
        const first = await request();
        const again = await request(alice, 'alice@example.invalid', 'Retry reason');
        assert.deepEqual(again, first);
        assert.equal(first.status, 'requested');
        assert.equal(first.completed_at, null);
        const other = await request(bob, 'bob@example.invalid');
        assert.notEqual(other.id, first.id);
        assert.equal(other.user_id, bob);
        assert.equal((await db.query('select count(*)::int n from public.account_deletion_requests where user_id=$1', [alice])).rows[0].n, 1);
        await db.query("update public.account_deletion_requests set status='completed',completed_at=now() where id=$1", [first.id]);
        assert.notEqual((await request()).id, first.id);
        await db.query("insert into public.reports(user_id,reason) values($1,'Verified backend report')", [alice]);
      });
    });
    await t.test('existing duplicates are preserved and return the earliest pending request', async () => {
      await db.query("insert into public.account_deletion_requests(user_id,email,reason,created_at) values($1,'alice@example.invalid','Older request','2026-01-01')", [alice]);
      const before = (await db.query('select * from public.account_deletion_requests order by id')).rows;
      await asRole('service_role', async () => assert.equal((await request()).reason, 'Older request'));
      assert.deepEqual((await db.query('select * from public.account_deletion_requests order by id')).rows, before);
    });
    await t.test('invalid internal inputs cannot create malformed requests', async () => {
      await asRole('service_role', async () => {
        await assert.rejects(request(null), error => error.code === '42501');
        for (const email of [null, '', 'x', 'not-an-email', 'x'.repeat(255) + '@example.invalid']) {
          await assert.rejects(request(alice, email), error => error.code === '22023');
        }
        await assert.rejects(request(alice, 'alice@example.invalid', 'x'.repeat(2001)), error => error.code === '22023');
      });
    });
    await t.test('future app tables and privileged RPCs deny browser roles without per-object revokes', async () => {
      await db.exec(`
        create table public.future_private_fixture (id int primary key, secret text);
        insert into public.future_private_fixture values(1,'synthetic-only');
        create function public.future_privileged_fixture() returns text language sql security definer
          set search_path=pg_catalog,public as $$ select secret from public.future_private_fixture where id=1 $$;
      `);
      for (const role of ['anon', 'authenticated']) await asRole(role, async () => {
        assert.equal((await db.query("select has_table_privilege(current_user,'public.existing_catalog_fixture','MAINTAIN') allowed")).rows[0].allowed, false);
        assert.equal((await db.query("select has_table_privilege(current_user,'public.existing_catalog_fixture','SELECT') allowed")).rows[0].allowed, true);
        await assert.rejects(db.query('select * from public.future_private_fixture'), error => error.code === '42501');
        await assert.rejects(db.query('truncate public.future_private_fixture'), error => error.code === '42501');
        await assert.rejects(db.query('select public.future_privileged_fixture()'), error => error.code === '42501');
        for (const privilege of ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) {
          assert.equal((await db.query("select has_table_privilege(current_user,'public.future_private_fixture',$1) allowed", [privilege])).rows[0].allowed, false);
        }
      });
      await asRole('service_role', async () => {
        assert.equal((await db.query('select public.future_privileged_fixture() value')).rows[0].value, 'synthetic-only');
        assert.equal((await db.query('select * from public.future_private_fixture')).rows.length, 1);
      });
    });
  } finally { await db.close(); }
});
