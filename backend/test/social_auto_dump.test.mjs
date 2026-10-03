import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocial} from '../social/routes.mjs';
let db,server,base,a,b,c;
const users=[randomUUID(),randomUUID(),randomUUID()];
const call=async(actor,action,data={})=>(await db.query(`select ${(action==='groups'||action.startsWith('group_'))?'korlix_social_groups_v1':action.startsWith('call_')?'korlix_social_calls_v1':action.startsWith('dump_')?'korlix_social_dump_v1':['send','messages','message'].includes(action)?'korlix_social_chat_v1':'korlix_social_v1'}($1,$2,$3::jsonb) result`,[actor,action,JSON.stringify(data)])).rows[0].result;
const profile=(handle,extra={})=>({handle,name:handle,bio:'A community member',color:'cyan',discoverable:true,show_online:true,accepted_rules:true,...extra});
const stored=new Map();
const rpc={storage:{from:()=>({
 upload:async(path,buffer,options)=>{stored.set(path,{buffer,options});return {data:{path}};},
 remove:async(paths)=>{for(const path of paths)stored.delete(path);return {data:[]};},
 createSignedUrls:async(paths,ttl)=>({data:paths.map(path=>({path,signedUrl:`https://fixture.test/${path}?expires=${ttl}`}))}),
 createSignedUrl:async(path,ttl,options={})=>({data:{signedUrl:`https://fixture.test/${path}?expires=${ttl}&download=${encodeURIComponent(options.download||'')}`}})
})},rpc:async(n,p)=>{try{return {data:n==='korlix_social_avatar'?(await db.query('select korlix_social_avatar($1,$2,$3) result',[p.p_actor,p.p_action,p.p_path??null])).rows[0].result:(await db.query(`select ${n}($1,$2,$3::jsonb) result`,[p.p_actor,p.p_action,JSON.stringify(p.p_data)])).rows[0].result};}catch(e){return {error:{code:e.code,message:e.message}};}}};
const api=async(action,data={},actor=users[0],method='POST',status=200)=>{const res=await fetch(base+action+(method==='GET'?'?'+new URLSearchParams(data):''),{method,headers:{Authorization:actor,'Content-Type':'application/json'},body:method==='POST'?JSON.stringify(data):undefined});const result=await res.json();assert.equal(res.status,status,JSON.stringify(result));assert.equal(res.headers.get('cache-control'),'no-store');return result;};
const connect=async()=>{await call(users[0],'request',{peer:b.id});await call(users[1],'accept',{peer:a.id});};
const send=async(actor=users[0],peer=b.id,body='Hello',id=randomUUID())=>call(actor,'send',{peer,body,id});
const topic=async(actor=users[0])=>call(actor,'create_topic',{id:randomUUID(),category:'sports',title:'Match day',body:'Who are you supporting?'});
before(async()=>{
 db=new PGlite();await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key);');
 for(const u of users)await db.query('insert into auth.users values($1)',[u]);
 const folder=new URL('../../supabase/migrations/',import.meta.url),file=(await readdir(folder)).find(f=>f.endsWith('_korlix_social.sql'));
 await db.exec(await readFile(new URL(file,folder),'utf8'));
 await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant all on storage.objects to anon,authenticated;create policy fixture_existing_allow on storage.objects to anon,authenticated using(true) with check(true);");
 const extension=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_profiles_calls.sql'));
 await db.exec(await readFile(new URL(extension,folder),'utf8'));
 const replies=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_message_replies.sql'));
 await db.exec(await readFile(new URL(replies,folder),'utf8'));
 const groups=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_groups.sql'));
 await db.exec(await readFile(new URL(groups,folder),'utf8'));
 const attachments=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_attachments.sql'));
 await db.exec(await readFile(new URL(attachments,folder),'utf8'));
 const albums=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_albums.sql'));
 await db.exec(await readFile(new URL(albums,folder),'utf8'));
 const wall=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_wall_profiles.sql'));
 await db.exec(await readFile(new URL(wall,folder),'utf8'));
 const wallVoice=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_wall_voice_replies.sql'));
 await db.exec(await readFile(new URL(wallVoice,folder),'utf8'));
 const autoDump=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_auto_dump.sql'));
 await db.exec(await readFile(new URL(autoDump,folder),'utf8'));
 const app=express();app.use(express.json({limit:'250kb'}));registerSocial(app,{database:rpc,requireUser:async q=>{if(!users.includes(q.headers.authorization))throw Error();return {id:q.headers.authorization,email_confirmed_at:'2026-01-01'};},logger:{warn(){}}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{await db.exec('truncate korlix_social_profiles,korlix_social_connections,korlix_social_blocks,korlix_social_messages,korlix_social_topics,korlix_social_replies,korlix_social_reports,korlix_social_limits,korlix_social_moderators restart identity cascade;');
 a=(await call(users[0],'save_profile',profile('alice'))).profile;b=(await call(users[1],'save_profile',profile('bruno'))).profile;c=(await call(users[2],'save_profile',profile('chris'))).profile;
});
after(async()=>{if(server)await new Promise(r=>server.close(r));await db?.close();});

const schedule=(id,seconds=15,extra={})=>({id,peer:b.id,seconds,request_id:randomUUID(),...extra});
const expire=async(id,viewer=a.id,scope='direct')=>db.query("update korlix_social_message_dumps set dump_at=now()-interval '1 second' where viewer=$1 and scope=$2 and message_id=$3",[viewer,scope,id]);
test('the six requested delays use the server clock and are private to one viewer',async()=>{
 await connect();const m=await send();
 for(const seconds of [15,45,60,900,3600,86400]){
  const r=await api('dump_schedule',schedule(m.id,seconds));
  assert.equal(r.id,m.id);assert.equal(r.dumped,false);
  assert.equal(Date.parse(r.dump_at)-Date.parse(r.server_time),seconds*1000);
  const own=await api('message',{id:m.id,peer:b.id},users[0],'GET');
  const other=await api('message',{id:m.id,peer:a.id},users[1],'GET');
  assert.equal(own.message.dump_at,r.dump_at);assert.equal(other.message.dump_at,null);
  assert(Number.isFinite(Date.parse(own.server_time)));
 }
});
test('GET cannot mutate schedules and malformed/unsupported durations cannot create one',async()=>{
 await connect();const m=await send();
 await api('dump_schedule',schedule(m.id),users[0],'GET',404);
 await api('dump_cancel',{id:m.id,peer:b.id,request_id:randomUUID()},users[0],'GET',404);
 for(const seconds of [0,-1,14,16,44,46,59,61,3601,86401,15.5,null,'abc'])
  await api('dump_schedule',schedule(m.id,seconds),users[0],'POST',400);
 await api('dump_schedule',{...schedule(m.id),request_id:null},users[0],'POST',400);
 await api('dump_schedule',{...schedule(m.id),group:randomUUID()},users[0],'POST',400);
 assert.equal((await db.query('select count(*)::int n from korlix_social_message_dumps')).rows[0].n,0);
});
test('retry preserves deadline and old schedule replay after cancellation never re-arms',async()=>{
 await connect();const m=await send();const first=schedule(m.id,45);
 const r=await call(users[0],'dump_schedule',first);
 assert.equal((await call(users[0],'dump_schedule',first)).dump_at,r.dump_at);
 const cancel={id:m.id,peer:b.id,request_id:randomUUID()};
 assert.equal((await call(users[0],'dump_cancel',cancel)).dump_at,null);
 assert.equal((await call(users[0],'dump_schedule',first)).dump_at,null);
 assert.equal((await call(users[0],'dump_cancel',cancel)).dump_at,null);
 const second=await call(users[0],'dump_schedule',schedule(m.id,900));
 assert.equal((await call(users[0],'dump_cancel',cancel)).dump_at,second.dump_at);
 assert.equal((await call(users[0],'dump_schedule',first)).dump_at,second.dump_at);
 await assert.rejects(call(users[0],'dump_schedule',{...first,seconds:15}),e=>e.code==='23505');
 await assert.rejects(call(users[0],'dump_cancel',{...cancel,request_id:first.request_id}),e=>e.code==='23505');
});
test('expiry cannot be cancelled or rescheduled; same sender and receiver keep independent history',async()=>{
 await connect();const m=await send();await call(users[0],'dump_schedule',schedule(m.id));
 await expire(m.id);
 for(const [action,data] of [['dump_cancel',{id:m.id,peer:b.id,request_id:randomUUID()}],['dump_schedule',schedule(m.id,86400)]]){
  const r=await call(users[0],action,data);assert.equal(r.dumped,true);assert(r.dump_at);
 }
 assert.equal((await call(users[0],'messages',{peer:b.id})).items.length,0);
 assert.equal((await call(users[1],'messages',{peer:a.id})).items[0].body,'Hello');
 await call(users[1],'dump_schedule',schedule(m.id,15,{peer:a.id}));
 await expire(m.id,b.id);
 assert.equal((await call(users[1],'messages',{peer:a.id})).items.length,0);
 const original=(await db.query('select body,deleted from korlix_social_messages where id=$1',[m.id])).rows[0];
 assert.deepEqual(original,{body:'Hello',deleted:false});
});
test('expiry clears unread, latest message preview, single-message lookup and quoted text',async()=>{
 await connect();const old=await send(users[1],a.id,'Previous');const m=await send(users[1],a.id,'Secret');
 const quote=await call(users[0],'send',{id:randomUUID(),peer:b.id,body:'A reply',reply_to:m.id});
 await call(users[0],'dump_schedule',schedule(m.id));
 const before=await call(users[0],'message',{id:quote.id,peer:b.id});assert(before.message.reply.dump_at);
 await expire(m.id);
 const r=await call(users[0],'messages',{peer:b.id});assert.deepEqual(r.dumped_ids,[m.id]);
 assert.equal(r.items.find(x=>x.id===quote.id).reply,null);
 assert.equal(r.items.find(x=>x.id===quote.id).reply_to,null);
 assert.equal((await call(users[0],'connections')).items[0].unread,1);
 await assert.rejects(call(users[0],'message',{id:m.id,peer:b.id}),e=>e.code==='P0002');
 await assert.rejects(call(users[0],'send',{id:randomUUID(),peer:b.id,body:'Quote again',reply_to:m.id}),/no longer available/);
 assert.equal((await call(users[1],'message',{id:quote.id,peer:a.id})).message.reply.body,'Secret');
 await call(users[0],'dump_schedule',schedule(quote.id));await expire(quote.id);
 assert.equal((await call(users[0],'connections')).items[0].last_message,'Previous');
});
test('new table/functions remain service-only and normal role executes full authorized flow',async()=>{
 const r=await db.query(`select
 has_table_privilege('authenticated','korlix_social_message_dumps','select') table_access,
 has_table_privilege('anon','korlix_social_dump_requests','insert') ledger_access,
 has_function_privilege('authenticated','korlix_social_dump_v1(uuid,text,jsonb)','execute') rpc_access,
 has_function_privilege('anon','korlix_social_dump_at(uuid,text,uuid)','execute') helper_access,
 (select relrowsecurity from pg_class where oid='korlix_social_message_dumps'::regclass) rls,
 (select prosecdef from pg_proc where proname='korlix_social_dump_v1') definer`);
 assert.deepEqual(r.rows[0],{table_access:false,ledger_access:false,rpc_access:false,helper_access:false,rls:true,definer:false});
 await connect();const m=await send();await db.exec('set role service_role');
 try{assert.equal((await call(users[0],'dump_schedule',schedule(m.id))).dumped,false);}finally{await db.exec('reset role');}
});
test('API actor is exclusively the authenticated user and blocked/unrelated access is denied',async()=>{
 await connect();const m=await send();
 await api('dump_schedule',schedule(m.id),users[2],'POST',403);
 await api('dump_schedule',{...schedule(m.id),actor:users[1],viewer:b.id},users[0]);
 assert.equal((await db.query('select viewer from korlix_social_message_dumps')).rows[0].viewer,a.id);
 await call(users[1],'block',{peer:a.id});
 await api('dump_cancel',{id:m.id,peer:b.id,request_id:randomUUID()},users[0],'POST',403);
});
test('pending schedules cover older pages and cancellation updates the authoritative map',async()=>{
 await connect();const m=await send();
 await db.query("insert into korlix_social_messages(id,sender,recipient,body) select gen_random_uuid(),$1,$2,'Later '||n from generate_series(1,60)n",[a.id,b.id]);
 const scheduled=await call(users[0],'dump_schedule',schedule(m.id,900));
 let history=await call(users[0],'messages',{peer:b.id});
 assert.equal(history.items.some(x=>x.id===m.id),false);
 assert.equal(history.dump_schedules[m.id],scheduled.dump_at);
 assert.deepEqual((await call(users[1],'messages',{peer:a.id})).dump_schedules,{});
 await call(users[0],'dump_cancel',{id:m.id,peer:b.id,request_id:randomUUID()});
 history=await call(users[0],'messages',{peer:b.id});assert.deepEqual(history.dump_schedules,{});
});
test('read and cancel honor wall clock after a transaction crosses the deadline',async()=>{
 await connect();const m=await send();await call(users[0],'dump_schedule',schedule(m.id));
 await db.exec('begin');
 try{
  await db.query("update korlix_social_message_dumps set dump_at=clock_timestamp()+interval '40 milliseconds' where viewer=$1 and message_id=$2",[a.id,m.id]);
  await new Promise(resolve=>setTimeout(resolve,80));
  const history=await call(users[0],'messages',{peer:b.id});
  assert.equal(history.items.length,0);assert.deepEqual(history.dumped_ids,[m.id]);
  assert.deepEqual(history.dump_schedules,{});
  const cancel=await call(users[0],'dump_cancel',{id:m.id,peer:b.id,request_id:randomUUID()});
  assert.equal(cancel.dumped,true);
 }finally{await db.exec('rollback');}
});
