import {test,before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db,profiles;
const users=Array.from({length:3},()=>randomUUID());
const call=(who,action,data={})=>db.transaction(async tx=>{
 await tx.exec('set local role service_role');
 return (await tx.query('select korlix_social_v1($1,$2,$3::jsonb) result',[users[who],action,JSON.stringify(data)])).rows[0].result;
});
before(async()=>{
 db=new PGlite();
 await db.exec(`create schema auth;create role anon;create role authenticated;create role service_role bypassrls;
 create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;`);
 for(const id of users)await db.query('insert into auth.users(id) values($1)',[id]);
 await db.exec(await readFile(new URL('./fixtures/social_native_push_sessions.sql',import.meta.url),'utf8'));
 const folder=new URL('../../supabase/migrations/',import.meta.url);
 for(const file of(await readdir(folder)).filter(f=>/_korlix_social(?:_|\.)/.test(f)).sort())await db.exec(await readFile(new URL(file,folder),'utf8'));
});
beforeEach(async()=>{
 await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade');
 profiles=[];
 for(let i=0;i<2;i++)profiles.push((await call(i,'save_profile',{name:`Presence ${i}`,handle:`presence_${i}`,color:'cyan',discoverable:true,show_online:false,accepted_rules:true})).profile);
});
after(async()=>await db?.close());
test('explicit toggle is acknowledged and immediately visible to another member',async()=>{
 assert.deepEqual(await call(0,'presence',{active:true}),{ok:true,show_online:false,online:false});
 assert.deepEqual(await call(0,'presence',{active:true,show_online:true}),{ok:true,show_online:true,online:true});
 assert.equal((await call(1,'members')).items.find(p=>p.id===profiles[0].id).online,true);
 assert.deepEqual(await call(0,'presence',{active:true,show_online:false}),{ok:true,show_online:false,online:false});
 assert.equal((await call(1,'members')).items.find(p=>p.id===profiles[0].id).online,false);
});
test('legacy heartbeat and another device cannot undo explicit offline preference',async()=>{
 await call(0,'presence',{active:true,show_online:true});
 await call(0,'presence',{active:true,show_online:false});
 for(let i=0;i<3;i++)assert.deepEqual(await call(0,'presence',{active:true}),{ok:true,show_online:false,online:false});
});
test('visibility update is actor-only and preserves other profile fields',async()=>{
 const before=(await db.query('select * from korlix_social_profiles order by id')).rows;
 await call(0,'presence',{active:true,show_online:true,peer:profiles[1].id,user_id:users[1],name:'Injected'});
 const after=(await db.query('select * from korlix_social_profiles order by id')).rows;
 for(let i=0;i<before.length;i++){
  if(before[i].user_id===users[0]){assert.equal(after[i].show_online,true);delete before[i].show_online;delete after[i].show_online;delete before[i].last_seen;delete after[i].last_seen;}
  assert.deepEqual(after[i],before[i]);
 }
});
test('expired lease and background state do not claim online',async()=>{
 await call(0,'presence',{active:true,show_online:true});
 await db.query("update korlix_social_profiles set last_seen=now()-interval '91 seconds' where id=$1",[profiles[0].id]);
 assert.equal((await call(1,'members')).items.find(p=>p.id===profiles[0].id).online,false);
 assert.deepEqual(await call(0,'presence',{active:false}),{ok:true,show_online:true,online:false});
});
test('invalid preferences, missing profile, suspended and public callers cannot change presence',async()=>{
 for(const value of [null,'true',1,{},[]])await assert.rejects(call(0,'presence',{active:true,show_online:value}),/true or false/);
 await assert.rejects(call(0,'presence',{show_online:true}),/true or false/);
 await assert.rejects(call(2,'presence',{active:true,show_online:true}));
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[profiles[0].id]);
 await assert.rejects(call(0,'presence',{active:true,show_online:true}));
 for(const role of ['anon','authenticated'])await assert.rejects(db.transaction(async tx=>{await tx.exec(`set local role ${role}`);await tx.query("select korlix_social_v1($1,'presence','{\"active\":true,\"show_online\":true}')",[users[1]]);}),/permission denied/);
 const fn=(await db.query("select prosecdef from pg_proc where oid='korlix_social_v1(uuid,text,jsonb)'::regprocedure")).rows[0];
 assert.equal(fn.prosecdef,false);
});
