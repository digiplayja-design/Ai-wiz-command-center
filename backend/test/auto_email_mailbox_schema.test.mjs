import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
const sql=readFileSync(new URL('../../supabase/migrations/20261028022242_auto_email_mailbox_connections.sql',import.meta.url),'utf8');
const owner=randomUUID(),other=randomUUID(),device='a'.repeat(64);
let db;
test.before(async()=>{db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);grant usage on schema public to anon,authenticated,service_role;');await db.query('insert into auth.users values($1),($2)',[owner,other]);await db.exec(sql);});
test.after(async()=>db.close());
test.beforeEach(async()=>db.exec('reset role;truncate korlix_auto_email_mailboxes cascade;'));
async function start(){const flow={id:randomUUID(),user_id:owner,agent_id:'nova',provider:'google',device_hash:device,state_hash:randomUUID().replaceAll('-','')+'b'.repeat(32),browser_hash:'c'.repeat(64),secrets:{v:1,data:'encrypted-verifier'}};await db.query('select korlix_auto_email_mailbox_begin($1::jsonb)',[JSON.stringify(flow)]);return flow;}
async function ready(f){await db.query("update korlix_auto_email_mailbox_flows set status='review',identity=$2,scopes='[\"gmail.send\"]' where id=$1",[f.id,{accountId:'google-account',email:'owner@example.test'}]);}
async function confirm(f,user=owner,dev=device){return(await db.query('select korlix_auto_email_mailbox_confirm($1,$2,$3,$4,$5) result',[user,'nova',dev,f.id,{v:1,data:'encrypted-tokens'}])).rows[0].result;}
test('anonymous and authenticated roles cannot read credentials or execute service operations',async()=>{
 for(const role of ['anon','authenticated']){await db.exec(`set role ${role}`);for(const query of ['select * from korlix_auto_email_mailboxes','select * from korlix_auto_email_mailbox_flows',"select korlix_auto_email_mailbox_cleanup()"]){await assert.rejects(db.query(query),/permission denied/);}await db.exec('reset role');}
 const flags=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_auto_email_mailboxes','korlix_auto_email_mailbox_flows')")).rows;assert(flags.every(x=>x.relrowsecurity));
});
test('confirmation is transactional, isolated by owner/device, and consumes pending credentials once',async()=>{
 await db.exec('set role service_role');const f=await start();await ready(f);assert.equal((await confirm(f,other)).confirmed,false);assert.equal((await confirm(f,owner,'wrong-device')).confirmed,false);assert.equal((await confirm(f)).confirmed,true);assert.equal((await confirm(f)).confirmed,false);
 const connection=(await db.query('select * from korlix_auto_email_mailboxes')).rows[0],flow=(await db.query('select * from korlix_auto_email_mailbox_flows')).rows[0];assert.equal(connection.status,'connected');assert.equal(connection.identity.email,'owner@example.test');assert.equal(flow.secrets,null);assert.equal(flow.identity,null);
});
test('a new attempt or disconnect invalidates every previous callback and review',async()=>{
 const old=await start();await ready(old);const newer=await start();assert.equal((await confirm(old)).confirmed,false);await ready(newer);await db.query('select korlix_auto_email_mailbox_disconnect($1,$2,$3)',[owner,'nova','google']);assert.equal((await confirm(newer)).confirmed,false);const row=(await db.query('select * from korlix_auto_email_mailboxes')).rows[0];assert.equal(row.status,'disconnected');assert.equal(row.secrets,null);assert.equal(row.identity,null);
});
test('expired reviews cannot activate and cleanup removes their encrypted material',async()=>{
 const f=await start();await ready(f);await db.query("update korlix_auto_email_mailbox_flows set expires_at=now()-interval '1 second' where id=$1",[f.id]);assert.equal((await confirm(f)).confirmed,false);await db.query('select korlix_auto_email_mailbox_cleanup()');const row=(await db.query('select * from korlix_auto_email_mailbox_flows')).rows[0];assert.equal(row.status,'expired');assert.equal(row.secrets,null);
});
