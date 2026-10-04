import test from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
const uid='10000000-0000-4000-8000-000000000001',other='10000000-0000-4000-8000-000000000002';
test('CRM durable follow-ups: ownership, review, edits, send claims, duplicate prevention and unsubscribe',async()=>{
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const f of ['20260921162128_enterprise_contacts_crm.sql','20261004115009_crm_autonomous_email.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 await db.query('insert into auth.users values($1),($2)',[uid,other]);await db.query("insert into user_profiles values($1,'enterprise'),($2,'enterprise')",[uid,other]);
 const cmd=async(a,p={},u=uid)=>(await db.query('select korlix_crm_email_v1($1,$2,$3) result',[u,a,JSON.stringify(p)])).rows[0].result;
 for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(cmd('state'),/permission denied/);await assert.rejects(db.query('select * from korlix_crm_email_rules'),/permission denied/);await db.exec('reset role');}
 const c=(await db.query("insert into korlix_contacts(user_id,name,email,email_permission,follow_up_on) values($1,'Sam','sam@example.com','transactional',current_date) returning *",[uid])).rows[0];
 const hour=Number((await db.query("select extract(hour from now() at time zone 'UTC') h")).rows[0].h);
 const input={contact_id:c.id,subject:'Checking in',body:'Any update?',timezone:'UTC',send_hour:Math.min(20,hour),delivery_mode:'review'};
 await assert.rejects(cmd('save',input,other),/Contact not found/);
 let r=(await cmd('save',input)).rule;assert.equal(r.enabled,false);await cmd('tick',{},null);assert.equal((await cmd('state')).jobs.length,0);
 r=(await cmd('toggle',{id:r.id,version:r.version,enabled:true,confirmed:true})).rule;
 await cmd('tick',{},null);await cmd('tick',{},null);let jobs=(await cmd('state')).jobs;assert.equal(jobs.length,1);assert.equal(jobs[0].status,'draft');assert.equal(await cmd('claim',{},null),null);
 // Changing content invalidates the old draft and saving pauses the rule.
 const old=jobs[0];r=(await cmd('save',{...input,version:r.version,body:'Fresh instructions'})).rule;assert.equal(r.enabled,false);await assert.rejects(cmd('approve',{id:old.id,version:old.version,confirmed:true}),/draft changed/);
 r=(await cmd('toggle',{id:r.id,version:r.version,enabled:true,confirmed:true})).rule;await cmd('tick',{},null);let j=(await cmd('state')).jobs[0];assert.equal(j.body,'Fresh instructions');assert.equal(j.status,'draft');
 await cmd('approve',{id:j.id,version:j.version,confirmed:true});j=await cmd('claim',{},null);assert(j.lease_token);assert.equal(await cmd('claim',{},null),null);
 const pin={id:j.id,lease_token:j.lease_token,reply_to:'owner@example.com',sender_fingerprint:'sender'};
 assert.deepEqual(await cmd('prepare',{...pin,token_hash:'a'.repeat(64),unsubscribe_url:'https://example.com/stop'}),{prepared:true});
 const claim=await cmd('authorize',pin);assert.equal(claim.email_payload.to,c.email);assert.match(claim.email_payload.text,/Fresh instructions/);
 await assert.rejects(cmd('authorize',pin),/claim expired/);
 await cmd('finish',{...pin,status:'sent',provider_id:'20000000-0000-4000-8000-000000000001',code:'accepted'});
 // A rule edit/re-enable can never repeat a dispatched contact/date.
 r=(await cmd('save',{...input,version:r.version,body:'Would duplicate'})).rule;r=(await cmd('toggle',{id:r.id,version:r.version,enabled:true,confirmed:true})).rule;await cmd('tick',{},null);assert.equal((await cmd('state')).jobs[0].status,'sent');assert.equal(await cmd('claim',{},null),null);
 await cmd('unsubscribe',{token_hash:'a'.repeat(64)},null);r=(await cmd('state')).rules[0];assert.equal(r.enabled,false);assert.equal(r.suppressed,true);await assert.rejects(cmd('toggle',{id:r.id,version:r.version,enabled:true,confirmed:true}),/stopped CRM emails/);
 // A different contact is blocked if permissions change after it is queued.
 const c2=(await db.query("insert into korlix_contacts(user_id,name,email,email_permission,follow_up_on) values($1,'Lee','lee@example.com','transactional',current_date) returning *",[uid])).rows[0];
 let r2=(await cmd('save',{...input,contact_id:c2.id,delivery_mode:'automatic'})).rule;r2=(await cmd('toggle',{id:r2.id,version:r2.version,enabled:true,confirmed:true})).rule;await cmd('tick',{},null);j=await cmd('claim',{},null);await db.query("update korlix_contacts set email_permission='none',version=version+1 where id=$1",[c2.id]);assert.deepEqual(await cmd('prepare',{...pin,id:j.id,lease_token:j.lease_token,token_hash:'b'.repeat(64),unsubscribe_url:'https://example.com/stop'}),{blocked:true});
 await db.query("update user_profiles set tier='basic' where id=$1",[uid]);await assert.rejects(cmd('state'),/Enterprise required/);
 }finally{await db.close();}
});
