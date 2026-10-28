import {test,before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocial} from '../social/routes.mjs';
let db,profiles,server,base,lifecycle;
const users=Array.from({length:4},()=>randomUUID());
const rpc=async(who,action,data={},fn='korlix_social_v1')=>db.transaction(async tx=>{
 await tx.exec('set local role service_role');
 return (await tx.query(`select ${fn}($1,$2,$3::jsonb) result`,[users[who],action,JSON.stringify(data)])).rows[0].result;
});
const chat=(who,action,data)=>rpc(who,action,data,'korlix_social_media_chat_v1');
const group=(who,action,data)=>rpc(who,action,data,'korlix_social_groups_v1');
const react=(who,data)=>rpc(who,'react',data,'korlix_social_react_v1');
const send=async(body='A hello 👋🏽 world',formatting=[])=>{
 const data={id:randomUUID(),peer:profiles[1].id,body,formatting};await chat(0,'send',data);return data;
};
const room=async()=>{const groupId=randomUUID();await group(0,'group_create',{group:groupId,name:'Reactions',members:[profiles[1].id,profiles[2].id]});for(const who of [1,2])await group(who,'group_accept',{group:groupId});return groupId;};
before(async()=>{
 db=new PGlite();await db.exec(`create schema auth;create role anon;create role authenticated;create role service_role bypassrls;
 create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;`);
 for(const id of users)await db.query('insert into auth.users(id) values($1)',[id]);
 await db.exec(await readFile(new URL('./fixtures/social_native_push_sessions.sql',import.meta.url),'utf8'));
 const folder=new URL('../../supabase/migrations/',import.meta.url);
 for(const file of (await readdir(folder)).filter(f=>/_korlix_social(?:_|\.)/.test(f)).sort())await db.exec(await readFile(new URL(file,folder),'utf8'));
 const database={rpc:async(name,p)=>{try{return {data:await db.transaction(async tx=>{
  await tx.exec('set local role service_role');return (await tx.query(`select ${name}($1,$2,$3::jsonb) result`,[p.p_actor,p.p_action,JSON.stringify(p.p_data)])).rows[0].result;
 })};}catch(e){return {error:{code:e.code,message:e.message}};}}};
 const app=express();app.use(express.json());lifecycle=registerSocial(app,{database,autoStart:false,logger:{info(){},warn(){}},requireUser:async req=>{if(!users.includes(req.headers.authorization))throw Error();return {id:req.headers.authorization,email_confirmed_at:'2026-01-01'};}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{
 await db.exec('truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits restart identity cascade');profiles=[];
 for(let i=0;i<users.length;i++)profiles.push((await rpc(i,'save_profile',{handle:`reactions_${i}`,name:`Member ${i}`,color:'cyan',discoverable:true,show_online:true,accepted_rules:true})).profile);
 for(const [a,b] of [[0,1],[0,2],[1,2]]){await rpc(a,'request',{peer:profiles[b].id});await rpc(b,'accept',{peer:profiles[a].id});}
});
after(async()=>{lifecycle?.stop();if(server)await new Promise(r=>server.close(r));await db?.close();});

test('direct reactions persist, count users, replace and remove idempotently',async()=>{
 const {id}=await send();const d={id,peer:profiles[1].id,emoji:'👍'};
 for(let i=0;i<2;i++)await react(0,d);
 await react(1,{...d,peer:profiles[0].id});
 let m=(await chat(0,'message',{id,peer:profiles[1].id})).message;
 assert.deepEqual(m.reactions,[{emoji:'👍',count:2,mine:true}]);
 await react(0,{...d,emoji:'😂'});m=(await chat(1,'messages',{peer:profiles[0].id})).items[0];
 assert.equal(m.reactions.length,2);assert(m.reactions.some(r=>r.emoji==='😂'&&!r.mine));
 for(let i=0;i<2;i++)await react(0,{...d,emoji:null});
 assert.deepEqual((await chat(0,'message',{id,peer:profiles[1].id})).message.reactions,[{emoji:'👍',count:1,mine:false}]);
});

test('Unicode formatting is exact, combined, immutable on retries and present in quotes',async()=>{
 const body='Hi 👋🏽 世界';const styles=[{start:3,end:5,style:'bold'},{start:6,end:8,style:'highlight'},{start:3,end:5,style:'italic'}];
 const sent=await send(body,styles);await chat(0,'send',sent);
 const read=(await chat(1,'messages',{peer:profiles[0].id})).items[0];assert.equal(read.body,body);assert.equal(read.formatting.length,3);
 await assert.rejects(chat(0,'send',{...sent,formatting:[]}),e=>e.code==='23505');
 const quote=await chat(1,'send',{id:randomUUID(),peer:profiles[0].id,body:'Agreed',reply_to:sent.id});
 assert.deepEqual((await chat(0,'message',{id:quote.id,peer:profiles[1].id})).message.reply.formatting,read.formatting);
 assert.deepEqual((await chat(1,'message',{id:sent.id,peer:profiles[0].id})).message.formatting,read.formatting);
});

test('malformed styles fail atomically before message delivery',async()=>{
 for(const formatting of [null,{},[{start:0,end:500,style:'bold'}],[{start:-1,end:1,style:'italic'}],[{start:1,end:1,style:'strike'}],[{start:0,end:1,style:'script'}],[{start:'0',end:1,style:'bold'}],Array(101).fill({start:0,end:1,style:'bold'})]){
  await assert.rejects(chat(0,'send',{id:randomUUID(),peer:profiles[1].id,body:'Hi',formatting}));
 }
 assert.equal((await chat(0,'messages',{peer:profiles[1].id})).items.length,0);
});

test('unrelated, blocked, deleted, dumped and suspended content cannot receive reactions',async()=>{
 const {id}=await send();const d={id,peer:profiles[1].id,emoji:'❤️'};
 await assert.rejects(react(2,d));await assert.rejects(react(0,{...d,peer:profiles[2].id}));
 await react(0,d);await rpc(1,'block',{peer:profiles[0].id});await assert.rejects(react(0,d));
 await rpc(1,'unblock',{peer:profiles[0].id});await rpc(0,'request',{peer:profiles[1].id});await rpc(1,'accept',{peer:profiles[0].id});
 await rpc(0,'dump_schedule',{id,peer:profiles[1].id,seconds:15,request_id:randomUUID()},'korlix_social_dump_v1');
 await db.query("update korlix_social_message_dumps set dump_at=now()-interval '1 second' where message_id=$1",[id]);
 await assert.rejects(react(0,d));await react(1,{...d,peer:profiles[0].id});
 const next=await send('another',[{start:0,end:7,style:'strike'}]);await react(0,{...d,id:next.id});
 await rpc(0,'delete_message',{id:next.id});await assert.rejects(react(0,{...d,id:next.id}));
 const removed=(await chat(1,'message',{id:next.id,peer:profiles[0].id})).message;
 assert.deepEqual(removed.reactions,[]);assert.deepEqual(removed.formatting,[]);
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[profiles[0].id]);await assert.rejects(react(0,d));
});

test('group history, membership and blocked reactor visibility are enforced',async()=>{
 const groupId=await room();const id=randomUUID();await chat(0,'group_send',{id,group:groupId,body:'Welcome',formatting:[{start:0,end:7,style:'bold'}]});
 for(const who of [0,1,2])await react(who,{id,group:groupId,emoji:'🎉'});
 assert.deepEqual((await chat(1,'group_message',{id,group:groupId})).message.reactions,[{emoji:'🎉',count:3,mine:true}]);
 await rpc(1,'block',{peer:profiles[2].id});
 assert.deepEqual((await chat(1,'group_message',{id,group:groupId})).message.reactions,[{emoji:'🎉',count:2,mine:true}]);
 await group(2,'group_leave',{group:groupId});await assert.rejects(react(2,{id,group:groupId,emoji:'😂'}));
 await rpc(1,'unblock',{peer:profiles[2].id});
 await db.query("update korlix_social_group_members set invited_at=now()-interval '2 hours' where group_id=$1 and member=$2",[groupId,profiles[2].id]);
 await group(0,'group_invite',{group:groupId,members:[profiles[2].id]});await group(2,'group_accept',{group:groupId});
 await assert.rejects(react(2,{id,group:groupId,emoji:'😂'}));
 assert.equal((await chat(0,'group_message',{id,group:groupId})).message.formatting[0].style,'bold');
});

test('service-only RLS, HTTP actor binding, method checks and payload validation',async()=>{
 const privileges=(await db.query(`select has_table_privilege('authenticated','korlix_social_message_reactions','select') client,
 has_function_privilege('anon','korlix_social_react_v1(uuid,text,jsonb)','execute') rpc,
 (select relrowsecurity from pg_class where oid='korlix_social_message_reactions'::regclass) rls,
 (select prosecdef from pg_proc where proname='korlix_social_react_v1') definer`)).rows[0];
 assert.deepEqual(privileges,{client:false,rpc:false,rls:true,definer:false});
 const {id}=await send();const data={id,peer:profiles[1].id,emoji:'👍',reactor:profiles[1].id,p_actor:users[1]};
 const response=await fetch(base+'react',{method:'POST',headers:{Authorization:users[0],'Content-Type':'application/json'},body:JSON.stringify(data)});
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
 assert.equal((await db.query('select reactor from korlix_social_message_reactions')).rows[0].reactor,profiles[0].id);
 assert.equal((await fetch(base+'react',{headers:{Authorization:users[0]}})).status,404);
 for(const emoji of ['',42,'<script>',{},'wrong'])await assert.rejects(react(0,{...data,emoji}));
 const missing={...data};delete missing.emoji;await assert.rejects(react(0,missing));
 await assert.rejects(react(0,{...data,group:randomUUID()}));
});
