import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const migration = new URL('../../supabase/migrations/20261007224627_legacy_report_review_ledger.sql', import.meta.url);
const id = n => `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const batch = '20000000-0000-4000-8000-000000000001';

async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    grant usage on schema public to anon, authenticated, service_role;
    create table public.reports (
      id uuid primary key, user_id uuid, generation_id uuid, reason text not null,
      details text, status text not null default 'new', created_at timestamptz not null default now()
    );
    alter table public.reports enable row level security;
    grant select, insert, update, delete on public.reports to service_role;
    alter default privileges grant all on tables to anon, authenticated, service_role;
  `);
  await db.exec(await readFile(migration, 'utf8'));
  const role = async (name, fn) => {
    assert(['anon', 'authenticated', 'service_role'].includes(name));
    await db.exec(`set role ${name}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };
  const report = async n => db.query('insert into public.reports(id,reason) values($1,$2)', [id(n), 'Synthetic report']);
  const review = async (n, fields = {}) => {
    const values = {outcome:'needs_followup', note:'Synthetic review only.', duplicate_of:null, method:'codex_assisted_owner_requested', batch_id:batch, ...fields};
    return db.query(`insert into public.korlix_legacy_report_reviews
      (report_id, outcome, note, duplicate_of, method, batch_id) values($1,$2,$3,$4,$5,$6)`,
    [id(n), values.outcome, values.note, values.duplicate_of, values.method, values.batch_id]);
  };
  return {db, role, report, review};
}

test('legacy review ledger is private despite permissive inherited defaults', async () => {
  const {db, role, report, review} = await fixture();
  try {
    await report(1);
    await role('service_role', () => review(1));
    assert.equal((await db.query("select relrowsecurity from pg_class where oid='public.korlix_legacy_report_reviews'::regclass")).rows[0].relrowsecurity, true);
    for (const name of ['anon', 'authenticated']) await role(name, async () => {
      for (const privilege of ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) {
        assert.equal((await db.query("select has_table_privilege(current_user,'public.korlix_legacy_report_reviews',$1) allowed", [privilege])).rows[0].allowed, false);
      }
      for (const sql of [
        'select * from public.korlix_legacy_report_reviews',
        `insert into public.korlix_legacy_report_reviews(report_id,outcome,note,batch_id) values('${id(1)}','no_action','Forged.','${batch}')`,
        "update public.korlix_legacy_report_reviews set outcome='no_action'",
        'delete from public.korlix_legacy_report_reviews',
      ]) await assert.rejects(db.exec(sql), error => error.code === '42501');
    });
    await role('service_role', async () => {
      assert.equal((await db.query('select count(*)::int count from public.korlix_legacy_report_reviews')).rows[0].count, 1);
      await db.exec("update public.korlix_legacy_report_reviews set note='Follow-up remains open.'");
      await assert.rejects(db.exec('delete from public.korlix_legacy_report_reviews'), error => error.code === '42501');
    });
    // RLS remains closed even if a future migration accidentally regrants CRUD.
    await db.exec('grant select,insert,update,delete on public.korlix_legacy_report_reviews to anon,authenticated');
    for (const name of ['anon','authenticated']) await role(name, async () => {
      assert.equal((await db.query('select * from public.korlix_legacy_report_reviews')).rows.length, 0);
      await assert.rejects(review(1), error => error.code === '42501');
      assert.equal((await db.query("update public.korlix_legacy_report_reviews set note='Forged' returning report_id")).rows.length, 0);
      assert.equal((await db.query('delete from public.korlix_legacy_report_reviews returning report_id')).rows.length, 0);
    });
  } finally { await db.close(); }
});

test('legacy reviews reject malformed fields and invalid report relationships', async () => {
  const {db, report, review} = await fixture();
  try {
    await report(1); await report(2);
    for (const fields of [
      {outcome:'resolved'}, {outcome:null}, {note:''}, {note:'  '}, {note:'x'.repeat(1001)}, {note:'x'+' '.repeat(1000)}, {note:null},
      {method:'human_confirmed'}, {method:null}, {batch_id:null},
      {duplicate_of:id(1), outcome:'duplicate'},
      {duplicate_of:id(2), outcome:'no_action'}, {duplicate_of:id(2), outcome:'needs_followup'},
    ]) await assert.rejects(review(1, fields), error => ['23514','23502'].includes(error.code));
    await assert.rejects(review(3), error => error.code === '23503');
    await assert.rejects(review(1, {outcome:'duplicate',duplicate_of:id(3)}), error => error.code === '23503');
    await assert.rejects(review(1, {batch_id:'invalid'}), error => error.code === '22P02');
    await review(1, {outcome:'duplicate', duplicate_of:id(2)});
    await assert.rejects(review(1), error => error.code === '23505');
    for (const value of [null, 'infinity', '-infinity']) await assert.rejects(
      db.query('update public.korlix_legacy_report_reviews set reviewed_at=$1 where report_id=$2', [value,id(1)]),
      error => ['23514','23502'].includes(error.code),
    );
    await db.query('delete from public.reports where id=$1', [id(2)]);
    const surviving = (await db.query('select * from public.korlix_legacy_report_reviews')).rows[0];
    assert.equal(surviving.duplicate_of, null);
    assert.equal(surviving.outcome, 'duplicate');
    await db.query('delete from public.reports where id=$1', [id(1)]);
    assert.equal((await db.query('select * from public.korlix_legacy_report_reviews')).rows.length, 0);
  } finally { await db.close(); }
});

test('guarded synthetic review commits status and ledger atomically without losing six open follow-ups', async () => {
  const {db, role} = await fixture();
  try {
    for (let n=1;n<=39;n++) {
      const group = n<=7 ? n : 1 + ((n-8)%7);
      await db.query(`insert into public.reports(id,user_id,generation_id,reason,details,created_at)
        values($1,$2,$3,'Synthetic concern','Synthetic details','2026-01-01')`, [id(n),id(100),id(200+group)]);
    }
    const originals = (await db.query('select id,user_id,generation_id,reason,details,created_at from public.reports order by id')).rows;
    const reviewed = [];
    for (let n=1;n<=39;n++) reviewed.push({report_id:id(n), outcome:n<=6?'needs_followup':n===7?'no_action':'duplicate', duplicate_of:n>7?id(1+((n-8)%7)):null, note:n<=6?'Further verification needed.':n===7?'Synthetic refusal reviewed; no action needed.':'Exact duplicate of the linked synthetic case.'});
    await role('service_role', () => db.transaction(async tx => {
      const pending = (await tx.query("select id from public.reports where status='new' order by id for update")).rows;
      assert.equal(pending.length,39);
      for (const row of reviewed) {
        if (row.duplicate_of) {
          const equal = (await tx.query(`select a.user_id is not distinct from b.user_id
            and a.generation_id is not distinct from b.generation_id and a.reason=b.reason
            and a.details is not distinct from b.details as equal
            from public.reports a join public.reports b on b.id=$2 where a.id=$1`, [row.report_id,row.duplicate_of])).rows[0];
          assert.equal(equal.equal,true);
        }
        await tx.query(`insert into public.korlix_legacy_report_reviews(report_id,outcome,note,duplicate_of,batch_id)
          values($1,$2,$3,$4,$5)`, [row.report_id,row.outcome,row.note,row.duplicate_of,batch]);
        const result = await tx.query(`update public.reports set status=$2 where id=$1 and status='new' returning id`,
          [row.report_id,row.outcome==='needs_followup'?'new':'resolved']);
        assert.equal(result.rows.length,1);
      }
    }));
    assert.deepEqual((await db.query('select id,user_id,generation_id,reason,details,created_at from public.reports order by id')).rows, originals);
    assert.deepEqual((await db.query('select status,count(*)::int count from public.reports group by status order by status')).rows,
      [{status:'new',count:6},{status:'resolved',count:33}]);
    assert.equal((await db.query('select count(*)::int count from public.korlix_legacy_report_reviews')).rows[0].count,39);
    const before = (await db.query('select * from public.korlix_legacy_report_reviews order by report_id')).rows;
    await assert.rejects(role('service_role', () => db.transaction(async tx => {
      await tx.query("update public.reports set status='resolved' where id=$1", [id(1)]);
      await tx.query("update public.korlix_legacy_report_reviews set outcome='bad_outcome' where report_id=$1", [id(1)]);
    })), error => error.code === '23514');
    assert.equal((await db.query('select status from public.reports where id=$1',[id(1)])).rows[0].status,'new');
    assert.deepEqual((await db.query('select * from public.korlix_legacy_report_reviews order by report_id')).rows,before);
  } finally { await db.close(); }
});
