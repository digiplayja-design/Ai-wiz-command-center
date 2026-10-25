import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocial} from '../social/routes.mjs';
let db,server,base,a,b,c;
const users=[randomUUID(),randomUUID(),randomUUID()];
const call=async(actor,action,data={})=>(await db.query(`select ${action==='messenger_inbox'?'korlix_messenger_inbox_v1':(action==='groups'||action.startsWith('group_'))?'korlix_social_groups_v1':action.startsWith('call_')?'korlix_social_calls_v1':action.startsWith('dump_')?'korlix_social_dump_v1':['send','messages','message'].includes(action)?'korlix_social_chat_v1':'korlix_social_v1'}($1,$2,$3::jsonb) result`,[actor,action,JSON.stringify(data)])).rows[0].result;
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
 db=new PGlite();await db.exec('create schema auth; create role anon; create role authenticated; create role service_role bypassrls; create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;');
 for(const u of users)await db.query('insert into auth.users(id) values($1)',[u]);
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
 const dumpScope=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_last_login_dump_scope.sql'));
 await db.exec(await readFile(new URL(dumpScope,folder),'utf8'));
 const inbox=(await readdir(folder)).find(f=>f.endsWith('_korlix_messenger_inbox.sql'));
 await db.exec(await readFile(new URL(inbox,folder),'utf8'));
 const app=express();app.use(express.json({limit:'250kb'}));registerSocial(app,{database:rpc,requireUser:async q=>{if(!users.includes(q.headers.authorization))throw Error();return {id:q.headers.authorization,email_confirmed_at:'2026-01-01'};},logger:{warn(){}}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{await db.exec('truncate korlix_social_profiles,korlix_social_connections,korlix_social_blocks,korlix_social_messages,korlix_social_topics,korlix_social_replies,korlix_social_reports,korlix_social_limits,korlix_social_moderators restart identity cascade;');
 a=(await call(users[0],'save_profile',profile('alice'))).profile;b=(await call(users[1],'save_profile',profile('bruno'))).profile;c=(await call(users[2],'save_profile',profile('chris'))).profile;
});
after(async()=>{if(server)await new Promise(r=>server.close(r));await db?.close();});

const inbox=(actor=users[0],data={})=>call(actor,'messenger_inbox',data);
test('inbox lists accepted conversations by latest message, ahead of unused connections',async()=>{
 await connect();await call(users[0],'request',{peer:c.id});
 assert.deepEqual((await inbox()).items.map(p=>p.id),[b.id]);
 await call(users[2],'accept',{peer:a.id});
 await send(users[0],b.id,'First');await send(users[2],a.id,'Newest');
 assert.deepEqual((await inbox()).items.map(p=>p.id),[c.id,b.id]);
 await send(users[0],b.id,'Now most recent');
 const rows=(await inbox()).items;assert.deepEqual(rows.map(p=>p.id),[b.id,c.id]);
 assert.equal(rows[0].last_message_mine,true);assert.equal(rows[1].last_message_mine,false);
 assert(Number.isFinite(Date.parse(rows[0].last_message_at)));
});
test('unread and search filters are server-side and do not mark messages read',async()=>{
 await connect();await send(users[1],a.id,'Dinner at six?');
 const result=await inbox(users[0],{filter:'unread',q:'DINNER'});
 assert.equal(result.items.length,1);assert.equal(result.items[0].unread,1);
 assert.equal((await inbox(users[1],{filter:'unread'})).items.length,0);
 assert.equal((await inbox(users[0],{q:'Bruno'})).items.length,1);
 assert.equal((await inbox(users[0],{q:'missing'})).items.length,0);
 assert.equal((await inbox()).items[0].unread,1);
 await assert.rejects(inbox(users[0],{filter:'everything'}),/filter/);
});
test('route is read-only, uses verified actor, and rejects absent or suspended profiles',async()=>{
 await connect();await send(users[1],a.id,'Private');
 await api('messenger_inbox',{},'', 'GET',401);
 await api('messenger_inbox',{},users[0],'POST',404);
 assert.equal((await api('messenger_inbox',{p_actor:users[0],actor:users[0]},users[2],'GET')).items.length,0);
 assert.equal((await api('messenger_inbox',{},users[0],'GET')).items[0].last_message,'Private');
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[a.id]);
 await api('messenger_inbox',{},users[0],'GET',403);
 await db.query('delete from korlix_social_profiles where id=$1',[c.id]);
 await assert.rejects(inbox(users[2]),/profile/);
});
test('expired self and shared dumps remove message previews, timestamps, search hits and unread counts',async()=>{
 await connect();await send(users[1],a.id,'Earlier');const hidden=await send(users[1],a.id,'Hidden secret');
 await db.query("insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at) values($1,'direct',$2,now()-interval '1 second')",[a.id,hidden.id]);
 let row=(await inbox()).items[0];assert.equal(row.last_message,'Earlier');assert.equal(row.unread,1);
 assert.equal((await inbox(users[0],{q:'Hidden secret'})).items.length,0);
 assert.equal((await inbox(users[1])).items[0].last_message,'Hidden secret');
 await db.query("insert into korlix_social_shared_message_dumps(scope,message_id,sender,dump_at) values('direct',$1,$2,now()-interval '1 second')",[hidden.id,b.id]);
 assert.equal((await inbox(users[1])).items[0].last_message,'Earlier');
});
test('deleted messages reveal only a removal placeholder, including attachment metadata',async()=>{
 await connect();const message=await send(users[1],a.id,'Secret text');
 await db.query('update korlix_social_messages set deleted=true where id=$1',[message.id]);
 const row=(await inbox()).items[0];assert.equal(row.last_message,'Message removed');assert.equal(row.unread,0);
 assert.equal(row.last_message_kind,'text');assert.equal(row.last_message_duration_ms,null);
 assert.equal((await inbox(users[0],{q:'Secret text'})).items.length,0);
});
test('voice previews include duration without storage paths or URLs',async()=>{
 await connect();const message=await send(users[1],a.id,'Voice note');
 await db.query("insert into korlix_social_attachments(id,owner,peer,direct_message,kind,filename,content_type,size_bytes,duration_ms,object_path,checksum,state) values($1,$2,$3,$4,'voice','voice.m4a','audio/mp4',2000,18000,'private/voice.m4a',$5,'attached')",[randomUUID(),b.id,a.id,message.id,'a'.repeat(64)]);
 const row=(await inbox()).items[0];assert.equal(row.last_message_kind,'voice');assert.equal(row.last_message_duration_ms,18000);
 assert(!JSON.stringify(row).includes('private/voice'));assert(!JSON.stringify(row).includes('object_path'));
});
test('blocking, suspension and private presence are honored in both directions',async()=>{
 await connect();await send(users[1],a.id,'Hello');
 await db.query('update korlix_social_profiles set show_online=false,last_seen=now() where id=$1',[b.id]);
 assert.equal((await inbox()).items[0].online,false);
 await call(users[1],'block',{peer:a.id});assert.equal((await inbox()).items.length,0);assert.equal((await inbox(users[1])).items.length,0);
 await call(users[1],'unblock',{peer:a.id});await db.query('update korlix_social_profiles set suspended=true where id=$1',[b.id]);
 assert.equal((await inbox()).items.length,0);
});
test('pagination is deterministic with 41-row lookahead and no repeated rows on static data',async()=>{
 for(let i=0;i<45;i++){
  const user=randomUUID(),peer=randomUUID();await db.query('insert into auth.users(id) values($1)',[user]);
  await db.query("insert into korlix_social_profiles(id,user_id,handle,name) values($1,$2,$3,$3)",[peer,user,`friend${i.toString().padStart(2,'0')}`]);
  await db.query("insert into korlix_social_connections(requester,recipient,state) values($1,$2,'accepted')",[a.id,peer]);
 }
 const first=(await inbox()).items,second=(await inbox(users[0],{offset:40})).items;
 assert.equal(first.length,41);assert.equal(second.length,5);assert.equal(first[40].id,second[0].id);
 assert.equal(new Set([...first.slice(0,40),...second].map(p=>p.id)).size,45);
});
test('RPC is service-only, uses invoker rights, and executes with service_role permissions',async()=>{
 for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_function_privilege($1,'korlix_messenger_inbox_v1(uuid,text,jsonb)','execute') allowed",[role])).rows[0].allowed,false);
 const proc=(await db.query("select prosecdef,proconfig from pg_proc where oid='korlix_messenger_inbox_v1(uuid,text,jsonb)'::regprocedure")).rows[0];
 assert.equal(proc.prosecdef,false);assert(proc.proconfig.some(v=>v.startsWith('search_path=')));
 await connect();await db.exec('set role service_role');
 try{assert.equal((await inbox()).items.length,1);}finally{await db.exec('reset role');}
});
