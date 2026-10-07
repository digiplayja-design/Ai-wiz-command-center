import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const userA = '10000000-0000-4000-8000-000000000001';
const userB = '10000000-0000-4000-8000-000000000002';

// Exact production view definition inspected on 2026-10-07. The fixtures below
// contain synthetic data only and reproduce the existing owner-only policies.
const dashboardDefinition = `SELECT up.id AS user_id,
    up.email,
    up.display_name,
    up.tier,
    up.selected_character,
    up.crm_status,
    up.preferred_theme,
    up.last_location_lat,
    up.last_location_lng,
    up.last_location_accuracy,
    up.last_location_feature,
    up.last_location_at,
    up.created_at AS account_created_at,
    up.updated_at AS profile_updated_at,
    COALESCE(gh.total_generations, 0::bigint) AS total_generations,
    gh.last_generation_at,
    COALESCE(ds.active_devices, 0::bigint) AS active_devices,
    up.max_devices_override,
    up.crm_notes
   FROM user_profiles up
     LEFT JOIN ( SELECT generation_history.user_id,
            count(*) AS total_generations,
            max(generation_history.created_at) AS last_generation_at
           FROM generation_history
          GROUP BY generation_history.user_id) gh ON gh.user_id = up.id
     LEFT JOIN ( SELECT device_sessions.user_id,
            count(*) AS active_devices
           FROM device_sessions
          WHERE device_sessions.status = 'active'::text
          GROUP BY device_sessions.user_id) ds ON ds.user_id = up.id`;

test('CRM dashboard migration enforces owner RLS and preserves service access', async (t) => {
  const db = new PGlite();
  const asRole = async (role, uid, fn) => {
    assert(['anon', 'authenticated', 'service_role'].includes(role));
    await db.query("select set_config('request.jwt.claim.sub', $1, false)", [uid || '']);
    await db.exec('set role ' + role);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub', '', false)");
    }
  };
  const dashboard = () => db.query('select * from public.crm_user_dashboard order by user_id');
  const totals = rows => rows.map(row => ({
    user_id: row.user_id,
    total_generations: Number(row.total_generations),
    active_devices: Number(row.active_devices),
  }));
  const expected = [
    {user_id: userA, total_generations: 2, active_devices: 1},
    {user_id: userB, total_generations: 3, active_devices: 2},
  ];

  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role bypassrls;
      create schema auth;
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $$;
      grant usage on schema public, auth to anon, authenticated, service_role;
      create table public.user_profiles (
        id uuid primary key, email text, display_name text, tier text,
        selected_character text, crm_status text, preferred_theme text,
        last_location_lat numeric, last_location_lng numeric,
        last_location_accuracy numeric, last_location_feature text,
        last_location_at timestamptz, created_at timestamptz,
        updated_at timestamptz, max_devices_override integer, crm_notes text
      );
      create table public.generation_history (user_id uuid, created_at timestamptz);
      create table public.device_sessions (user_id uuid, status text);
      alter table public.user_profiles enable row level security;
      alter table public.generation_history enable row level security;
      alter table public.device_sessions enable row level security;
      create policy "Users can read own profile" on public.user_profiles
        for select using ((select auth.uid()) = id);
      create policy "Users can read own generation history" on public.generation_history
        for select using ((select auth.uid()) = user_id);
      create policy "Users can delete own generation history" on public.generation_history
        for delete using ((select auth.uid()) = user_id);
      create policy "Users can read own device sessions" on public.device_sessions
        for select using ((select auth.uid()) = user_id);
      grant select on public.user_profiles, public.generation_history,
        public.device_sessions to authenticated, service_role;
      create view public.crm_user_dashboard as ${dashboardDefinition};
      grant select on public.crm_user_dashboard to authenticated, service_role;
    `);
    await db.query(`insert into public.user_profiles
      (id, email, display_name, tier, crm_notes, last_location_lat)
      values ($1, 'a@example.invalid', 'Synthetic A', 'enterprise', 'A fixture note', 10),
             ($2, 'b@example.invalid', 'Synthetic B', 'basic', 'B fixture note', 20)`,
    [userA, userB]);
    await db.query(`insert into public.generation_history values
      ($1, '2026-10-01Z'), ($1, '2026-10-02Z'),
      ($2, '2026-10-01Z'), ($2, '2026-10-02Z'), ($2, '2026-10-03Z')`, [userA, userB]);
    await db.query(`insert into public.device_sessions values
      ($1, 'active'), ($1, 'inactive'), ($2, 'active'), ($2, 'active'), ($2, 'inactive')`,
    [userA, userB]);

    await t.test('reproduces the old definer-view leak despite base-table RLS', async () => {
      await asRole('authenticated', userA, async () => {
        const direct = await db.query('select id from public.user_profiles');
        assert.deepEqual(direct.rows, [{id: userA}]);
        assert.deepEqual(totals((await dashboard()).rows), expected);
      });
    });

    const migrations = new URL('../../supabase/migrations/', import.meta.url);
    const file = process.env.CRM_DASHBOARD_MIGRATION ||
      (await readdir(migrations)).find(name => name.endsWith('_crm_dashboard_security_invoker.sql'));
    assert(file, 'CRM dashboard security-invoker migration must exist');
    const migration = await readFile(process.env.CRM_DASHBOARD_MIGRATION || new URL(file, migrations), 'utf8');
    const before = (await db.query("select pg_get_viewdef('public.crm_user_dashboard'::regclass) as definition")).rows[0].definition;
    await db.exec(migration);

    await t.test('both signed-in users see only their profile and own counts', async () => {
      for (const [index, uid] of [userA, userB].entries()) {
        await asRole('authenticated', uid, async () => {
          const rows = (await dashboard()).rows;
          assert.deepEqual(totals(rows), [expected[index]]);
          assert.equal(rows[0].email, index === 0 ? 'a@example.invalid' : 'b@example.invalid');
          assert.equal(rows[0].crm_notes, index === 0 ? 'A fixture note' : 'B fixture note');
          const foreign = await db.query('select * from public.crm_user_dashboard where user_id = $1', [index === 0 ? userB : userA]);
          assert.deepEqual(foreign.rows, []);
        });
      }
    });

    await t.test('missing identity exposes no rows and anonymous access stays denied', async () => {
      assert.deepEqual((await asRole('authenticated', null, dashboard)).rows, []);
      await asRole('anon', null, async () => {
        await assert.rejects(dashboard, error => error.code === '42501');
      });
    });

    await t.test('service role retains the complete authorized aggregate', async () => {
      const result = await asRole('service_role', null, dashboard);
      assert.deepEqual(totals(result.rows), expected);
    });

    await t.test('migration is idempotent and preserves view shape and existing grants', async () => {
      await db.exec(migration);
      const metadata = (await db.query(`select
        pg_get_viewdef('public.crm_user_dashboard'::regclass) as definition,
        (select reloptions from pg_class where oid = 'public.crm_user_dashboard'::regclass) as options,
        has_table_privilege('authenticated', 'public.crm_user_dashboard', 'SELECT') as authenticated_select,
        has_table_privilege('service_role', 'public.crm_user_dashboard', 'SELECT') as service_select,
        has_table_privilege('anon', 'public.crm_user_dashboard', 'SELECT') as anon_select`)).rows[0];
      assert.equal(metadata.definition, before);
      assert(metadata.options.includes('security_invoker=true'));
      assert.equal(metadata.authenticated_select, true);
      assert.equal(metadata.service_select, true);
      assert.equal(metadata.anon_select, false);
      assert.deepEqual(totals((await asRole('authenticated', userA, dashboard)).rows), [expected[0]]);
    });
  } finally {
    await db.close();
  }
});
