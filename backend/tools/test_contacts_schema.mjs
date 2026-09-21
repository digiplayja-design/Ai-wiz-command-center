import {createRequire} from 'node:module';
const require = createRequire(process.env.KORLIX_CRM_TEST_DEPS ? process.env.KORLIX_CRM_TEST_DEPS + '/package.json' : import.meta.url);
const {PGlite} = require('@electric-sql/pglite');
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key); create table public.user_profiles(id uuid primary key,tier text); create table public.korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz); grant usage on schema public to anon,authenticated,service_role; grant select on public.user_profiles to service_role; grant all on public.korlix_agent_email_recipients to service_role;`);
await db.exec(await readFile(new URL('../../supabase/migrations/20260921162128_enterprise_contacts_crm.sql', import.meta.url),'utf8'));
const uid='00000000-0000-4000-8000-000000000001',basic='00000000-0000-4000-8000-000000000002';
await db.query('insert into auth.users values ($1),($2)',[uid,basic]);await db.query('insert into public.user_profiles values ($1,$2),($3,$4)',[uid,'enterprise',basic,'basic']);
for(const role of ['anon','authenticated']){
 await db.exec(`set role ${role}`);
 await assert.rejects(db.query('select * from public.korlix_contacts'),/permission denied/);
 await assert.rejects(db.query('select public.korlix_contacts_import_v1($1,$2)',[uid,JSON.stringify([{name:'a'}])]),/permission denied/);
 await db.exec('reset role');
}
await db.exec('set role service_role');
const contacts=JSON.stringify([{name:'Sam',email:'sam@example.com',category:'customer',source:'email',email_permission:'marketing',call_permission:'allowed'},{name:'Duplicate',email:'sam@example.com',source:'email'},{name:'Other'}]);
let r=await db.query('select public.korlix_contacts_import_v1($1,$2) as result',[uid,contacts]);assert.deepEqual(r.rows[0].result,{imported:2,duplicates:1});
r=await db.query('select * from public.korlix_contacts where email=$1',['sam@example.com']);let c=r.rows[0];assert.equal(c.email_permission,'none');assert.equal(c.call_permission,'none');
await assert.rejects(db.query('select public.korlix_contacts_import_v1($1,$2)',[basic,contacts]),/Enterprise required/);
await assert.rejects(db.query('select public.korlix_contacts_import_v1($1,$2)',[uid,JSON.stringify([{name:'Will roll back'},{name:'bad',category:'notvalid'}])]),/check constraint/);
assert.equal((await db.query("select count(*)::int as n from public.korlix_contacts where name='Will roll back'")).rows[0].n,0);
// Importing an existing Email Center contact does not revoke its independent permission.
await db.query('insert into public.korlix_agent_email_recipients(user_id,email,source_reference) values($1,$2,$3)',[uid,c.email,'manual']);
await db.query("update public.korlix_contacts set notes='New note' where id=$1",[c.id]);assert.equal((await db.query('select active from public.korlix_agent_email_recipients')).rows[0].active,true);
await assert.rejects(db.query('insert into public.korlix_agent_email_recipients(user_id,email,source_reference) values($1,$2,$3)',[uid,c.email,'crm:'+c.id]),/does not permit/);
await db.query("update public.korlix_contacts set email_permission='transactional' where id=$1",[c.id]);
await db.query('update public.korlix_agent_email_recipients set source_reference=$1',['crm:'+c.id]);
await db.query('update public.korlix_contacts set do_not_contact=true where id=$1',[c.id]);
r=await db.query('select * from public.korlix_agent_email_recipients');assert.equal(r.rows[0].active,false);assert.equal(r.rows[0].consent_status,'suppressed');
await assert.rejects(db.query("update public.korlix_agent_email_recipients set active=true,consent_status='transactional_only'"),/does not permit/);
await db.query('insert into public.korlix_agent_email_recipients(user_id,email) values($1,$2)',[uid,'existing@example.com']);
await db.query("insert into public.korlix_contacts(user_id,name,email,do_not_contact) values($1,'Blocked','existing@example.com',true)",[uid]);
assert.equal((await db.query("select active from public.korlix_agent_email_recipients where email='existing@example.com'")).rows[0].active,false);
await db.exec('reset role');
assert.equal((await db.query("select relrowsecurity from pg_class where relname='korlix_contacts'")).rows[0].relrowsecurity,true);
console.log('PASS: PostgreSQL migration, client role denial, service role import, duplicate skipping, forced permissions, all-or-nothing rollback, tier enforcement and email suppression/reactivation guard.');
await db.close();
