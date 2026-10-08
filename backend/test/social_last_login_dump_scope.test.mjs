import {test,before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db,p;
const users=Array.from({length:4},()=>randomUUID());
const call=async(who,action,data={},fn='korlix_social_v1')=>db.transaction(async tx=>{
 await tx.exec('set local role service_role');
 return (await tx.query(`select ${fn}($1,$2,$3::jsonb) result`,[users[who],action,JSON.stringify(data)])).rows[0].result;
});
const chat=(who,action,data)=>call(who,action,data,'korlix_social_media_chat_v1');
const group=(who,action,data)=>call(who,action,data,'korlix_social_groups_v1');
const dump=(who,data,action='dump_schedule')=>call(who,action,{request_id:randomUUID(),...(action==='dump_schedule'?{seconds:15}:{}),...data},'korlix_social_dump_v1');
const send=(who,peer,body='Hello',extra={})=>chat(who,'send',{id:randomUUID(),peer:p[peer].id,body,...extra});
const expire=async(id,scope='direct',who=null)=>who===null
 ? db.query("update korlix_social_shared_message_dumps set dump_at=clock_timestamp()-interval '1 second' where scope=$1 and message_id=$2",[scope,id])
 : db.query("update korlix_social_message_dumps set dump_at=clock_timestamp()-interval '1 second' where scope=$1 and message_id=$2 and viewer=$3",[scope,id,p[who].id]);
const profile=(i,extra={})=>({handle:`scope_audit_${i}`,name:`Scope ${i}`,color:'cyan',discoverable:true,show_online:true,accepted_rules:true,...extra});
const room=async()=>{const id=randomUUID();await group(0,'group_create',{group:id,name:'Scope group',members:[p[1].id,p[2].id]});for(const i of [1,2])await group(i,'group_accept',{group:id});return id;};
before(async()=>{
 db=new PGlite();await db.exec(`create schema auth;create role anon;create role authenticated;create role service_role bypassrls;
 create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;`);
 for(const id of users)await db.query('insert into auth.users(id) values($1)',[id]);
 const folder=new URL('../../supabase/migrations/',import.meta.url);
 for(const file of(await readdir(folder)).filter(f=>/_korlix_social(?:_|\.)/.test(f)).sort())await db.exec(await readFile(new URL(file,folder),'utf8'));
});
beforeEach(async()=>{
 await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade;update auth.users set last_sign_in_at=null;');
 p=[];for(let i=0;i<users.length;i++)p.push((await call(i,'save_profile',profile(i))).profile);
 for(const [a,b] of [[0,1],[0,2],[1,2]]){await call(a,'request',{peer:p[b].id});await call(b,'accept',{peer:p[a].id});}
});
after(async()=>await db?.close());

test('real latest auth login is exposed to eligible members; heartbeat and supplied timestamp cannot change it',async()=>{
 const at='2026-10-07T18:21:32+00:00';await db.query('update auth.users set last_sign_in_at=$1 where id=$2',[at,users[1]]);
 let member=(await call(0,'members')).items.find(x=>x.id===p[1].id);assert.equal(Date.parse(member.last_login_at),Date.parse(at));
 await call(1,'presence',{active:true,last_login_at:'2099-01-01'});await call(1,'save_profile',profile(1,{last_login_at:'2099-01-01'}));
 member=(await call(0,'members')).items.find(x=>x.id===p[1].id);assert.equal(Date.parse(member.last_login_at),Date.parse(at));
 assert.equal((await call(0,'members')).items.find(x=>x.id===p[2].id).last_login_at,null);
 assert.equal(Date.parse((await chat(0,'messages',{peer:p[1].id})).peer.last_login_at),Date.parse(at));
 const gid=await room();const roster=(await group(0,'group_details',{group:gid})).members;assert.equal(Date.parse(roster.find(x=>x.profile.id===p[1].id).profile.last_login_at),Date.parse(at));
 const gm=await chat(1,'group_send',{id:randomUUID(),group:gid,body:'Login author'});assert.equal(Date.parse((await chat(0,'group_message',{group:gid,id:gm.id})).message.author.last_login_at),Date.parse(at));
 const encoded=JSON.stringify(member);assert(!encoded.includes(users[1]));assert(!encoded.includes('email'));
});
test('last login respects presence preference, discoverability, blocks and suspended cards',async()=>{
 await db.query('update auth.users set last_sign_in_at=now()');
 await call(1,'save_profile',profile(1,{show_online:false}));assert.equal((await call(0,'members')).items.find(x=>x.id===p[1].id).last_login_at,null);
 await call(1,'save_profile',profile(1,{discoverable:false}));assert(!(await call(0,'members')).items.some(x=>x.id===p[1].id));
 await call(0,'block',{peer:p[1].id});assert.equal((await call(0,'blocks')).items[0].last_login_at,null);
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[p[2].id]);assert(!(await call(0,'members')).items.some(x=>x.id===p[2].id));
});
test('omitted scope remains personal and recipient may only manage their own copy',async()=>{
 const m=await send(0,1);const own=await dump(1,{id:m.id,peer:p[0].id});assert.equal(own.dump_scope,'self');assert.equal(own.everyone_dump_at,null);
 assert.equal((await chat(0,'message',{id:m.id,peer:p[1].id})).message.dump_at,null);
 for(const action of ['dump_schedule','dump_cancel'])await assert.rejects(dump(1,{id:m.id,peer:p[0].id,dump_scope:'everyone'},action),/Only the sender/);
 for(const scope of ['both','all',3,{},''])await assert.rejects(dump(0,{id:m.id,peer:p[1].id,dump_scope:scope}),/Choose Only me/);
});
test('everyone schedule is sender-only, visible to both participants and idempotently scoped',async()=>{
 const m=await send(0,1);const request={id:m.id,peer:p[1].id,dump_scope:'everyone',request_id:randomUUID(),seconds:45};
 const a=await dump(0,request),retry=await dump(0,request);assert.equal(a.dump_at,retry.dump_at);assert.equal(a.dump_scope,'everyone');
 assert.equal(Date.parse(a.dump_at)-Date.parse(a.server_time),45000);
 const other=(await chat(1,'message',{id:m.id,peer:p[0].id})).message;assert.equal(other.everyone_dump_at,a.dump_at);assert.equal(other.self_dump_at,null);
 await assert.rejects(dump(0,{...request,dump_scope:'self'}),/different content/);
 await assert.rejects(dump(3,{...request,peer:p[0].id}),/connection/i);
});
test('independent timers use earliest expiry; cancellation and stale replay preserve the other timer',async()=>{
 const m=await send(0,1),target={id:m.id,peer:p[1].id};const self=await dump(0,{...target,seconds:15});const allRequest={...target,seconds:45,dump_scope:'everyone',request_id:randomUUID()};const all=await dump(0,allRequest);
 assert.equal(all.dump_at,self.dump_at);assert.equal(all.dump_scope,'self');assert.notEqual(all.self_dump_at,all.everyone_dump_at);
 const recipient=(await chat(1,'messages',{peer:p[0].id}));assert.deepEqual(recipient.dump_self_schedules,{});assert.equal(recipient.dump_everyone_schedules[m.id],all.everyone_dump_at);
 const cancel={...target,dump_scope:'everyone',request_id:randomUUID()};const cancelled=await dump(0,cancel,'dump_cancel');assert.equal(cancelled.dump_at,self.dump_at);assert.equal(cancelled.everyone_dump_at,null);
 assert.equal((await dump(0,allRequest)).everyone_dump_at,null);
 const again=await dump(0,{...target,dump_scope:'everyone',seconds:60});await dump(0,target,'dump_cancel');const visible=(await chat(0,'message',target)).message;assert.equal(visible.self_dump_at,null);assert.equal(visible.dump_at,again.everyone_dump_at);
});
test('everyone expiry removes direct body, quotes, unread, preview, original and new reply access for both',async()=>{
 const m=await send(0,1,'UNIQUE REMOVED DIRECT');const reply=await send(1,0,'Reply',{reply_to:m.id});await dump(0,{id:m.id,peer:p[1].id,dump_scope:'everyone'});await expire(m.id);
 for(const [who,peer] of [[0,1],[1,0]]){
  const h=await chat(who,'messages',{peer:p[peer].id});assert(!JSON.stringify(h).includes('UNIQUE REMOVED DIRECT'));assert(h.dumped_ids.includes(m.id));assert.equal(h.items.find(x=>x.id===reply.id).reply,null);
  await assert.rejects(chat(who,'message',{peer:p[peer].id,id:m.id}),/not found/);await assert.rejects(send(who,peer,'Forbidden',{reply_to:m.id}),/no longer available/);
 }
 const connections=(await call(1,'connections')).items.find(x=>x.id===p[0].id);assert.equal(connections.unread,0);assert.equal(connections.last_message,'Reply');
 assert.equal((await db.query('select body from korlix_social_messages where id=$1',[m.id])).rows[0].body,'UNIQUE REMOVED DIRECT');
 for(const audience of ['self','everyone'])for(const action of ['dump_schedule','dump_cancel'])assert.equal((await dump(0,{id:m.id,peer:p[1].id,dump_scope:audience},action)).dumped,true);
});
test('group everyone expires for every accepted member; recipients and group owners cannot remove someone else message',async()=>{
 const id=await room(),m=await chat(1,'group_send',{id:randomUUID(),group:id,body:'UNIQUE REMOVED GROUP'});const reply=await chat(2,'group_send',{id:randomUUID(),group:id,body:'Group reply',reply_to:m.id});
 await assert.rejects(dump(0,{id:m.id,group:id,dump_scope:'everyone'}),/Only the sender/);await dump(1,{id:m.id,group:id,dump_scope:'everyone'});
 for(const who of [0,1,2])assert((await chat(who,'group_messages',{group:id})).dump_everyone_schedules[m.id]);await expire(m.id,'group');
 for(const who of [0,1,2]){const h=await chat(who,'group_messages',{group:id});assert(!JSON.stringify(h).includes('UNIQUE REMOVED GROUP'));assert(h.dumped_ids.includes(m.id));assert.equal(h.items.find(x=>x.id===reply.id).reply,null);await assert.rejects(chat(who,'group_message',{group:id,id:m.id}),/not found/);}
 await assert.rejects(dump(3,{id:m.id,group:id,dump_scope:'everyone'}),/unavailable/);
});
test('block, connection removal and suspended sender deny audience changes',async()=>{
 const m=await send(0,1);await call(1,'block',{peer:p[0].id});await assert.rejects(dump(0,{id:m.id,peer:p[1].id,dump_scope:'everyone'}),/unavailable/);await call(1,'unblock',{peer:p[0].id});
 await call(0,'request',{peer:p[1].id});await call(1,'accept',{peer:p[0].id});await call(0,'remove',{peer:p[1].id});await assert.rejects(dump(0,{id:m.id,peer:p[1].id,dump_scope:'everyone'}),/connection/);
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[p[0].id]);await assert.rejects(dump(0,{id:m.id,peer:p[1].id,dump_scope:'everyone'}),/active Social/);
});
test('new shared tables, helpers and auth timestamps remain inaccessible to browser roles',async()=>{
 for(const role of ['anon','authenticated']){
  const result=(await db.query(`select has_table_privilege($1,'korlix_social_shared_message_dumps','select') table_access,has_function_privilege($1,'korlix_social_dump_metadata(uuid,text,uuid)','execute') helper_access,has_function_privilege($1,'korlix_social_dump_snapshot(uuid,text,uuid,bigint)','execute') snapshot_access,has_column_privilege($1,'auth.users','last_sign_in_at','select') auth_access`,[role])).rows[0];assert.deepEqual(result,{table_access:false,helper_access:false,snapshot_access:false,auth_access:false});
 }
 assert.equal((await db.query("select relrowsecurity enabled from pg_class where oid='korlix_social_shared_message_dumps'::regclass")).rows[0].enabled,true);
});
