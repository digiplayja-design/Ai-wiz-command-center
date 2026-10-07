import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

test('Bookkeeping dependency rehearsal records why a generic Auth deletion cannot fulfill account erasure', async () => {
  const db = new PGlite(), owner = randomUUID(), other = randomUUID();
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      grant usage on schema public to service_role;
    `);
    await db.exec(await readFile(new URL('../../supabase/migrations/20260925015926_bookkeeping_foundation.sql', import.meta.url), 'utf8'));
    await db.query('insert into auth.users values($1),($2)', [owner, other]);
    await db.exec('set role service_role');
    const input = { name: 'Synthetic deletion rehearsal', legal_structure: 'llc', tax_treatment: 'unsure', contractor_income: false, request_key: randomUUID() };
    const business = (await db.query("select korlix_bookkeeping_v1($1,'create_business',null,$2) result", [owner, input])).rows[0].result.business;
    const before = {
      business: (await db.query('select * from korlix_bookkeeping_businesses where id=$1', [business.id])).rows,
      accounts: (await db.query('select * from korlix_bookkeeping_accounts where business_id=$1 order by code', [business.id])).rows,
      audit: (await db.query('select * from korlix_bookkeeping_audit where business_id=$1', [business.id])).rows,
    };
    await db.exec('reset role');
    await assert.rejects(db.query('delete from auth.users where id=$1', [owner]), error => error.code === '23503');
    await assert.rejects(db.query('delete from korlix_bookkeeping_businesses where id=$1', [business.id]), error => error.code === '23503');
    await assert.rejects(db.query('delete from korlix_bookkeeping_audit where business_id=$1', [business.id]), /cannot|immutable/i);
    assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n, 2);
    assert.deepEqual((await db.query('select * from korlix_bookkeeping_businesses where id=$1', [business.id])).rows, before.business);
    assert.deepEqual((await db.query('select * from korlix_bookkeeping_accounts where business_id=$1 order by code', [business.id])).rows, before.accounts);
    assert.deepEqual((await db.query('select * from korlix_bookkeeping_audit where business_id=$1', [business.id])).rows, before.audit);
    // Expected safety constraint, not successful fulfillment. Never disable
    // triggers or add broad cascades to make an erasure rehearsal appear green.
  } finally { await db.close(); }
});
