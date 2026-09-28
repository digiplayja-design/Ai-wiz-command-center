import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocial} from '../social/routes.mjs';
import sharp from 'sharp';
import { socialCallConfig } from '../social/calls.mjs';
let db,server,base,a,b,c;
const users=[randomUUID(),randomUUID(),randomUUID()];
const call=async(actor,action,data={})=>(await db.query(`select ${(action==='groups'||action.startsWith('group_'))?'korlix_social_groups_v1':action.startsWith('call_')?'korlix_social_calls_v1':['send','messages','message'].includes(action)?'korlix_social_chat_v1':'korlix_social_v1'}($1,$2,$3::jsonb) result`,[actor,action,JSON.stringify(data)])).rows[0].result;
const profile=(handle,extra={})=>({handle,name:handle,bio:'A community member',color:'cyan',discoverable:true,show_online:true,accepted_rules:true,...extra});
const stored=new Map();
const rpc={storage:{from:()=>({
 upload:async(path,buffer,options)=>{stored.set(path,{buffer,options});return {data:{path}};},
 remove:async(paths)=>{for(const path of paths)stored.delete(path);return {data:[]};},
 createSignedUrls:async(paths,ttl)=>({data:paths.map(path=>({path,signedUrl:`https://fixture.test/${path}?expires=${ttl}`}))})
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
 const app=express();app.use(express.json({limit:'250kb'}));registerSocial(app,{database:rpc,requireUser:async q=>{if(!users.includes(q.headers.authorization))throw Error();return {id:q.headers.authorization,email_confirmed_at:'2026-01-01'};},logger:{warn(){}}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{await db.exec('truncate korlix_social_profiles,korlix_social_connections,korlix_social_blocks,korlix_social_messages,korlix_social_topics,korlix_social_replies,korlix_social_reports,korlix_social_limits,korlix_social_moderators restart identity cascade;');
 a=(await call(users[0],'save_profile',profile('alice'))).profile;b=(await call(users[1],'save_profile',profile('bruno'))).profile;c=(await call(users[2],'save_profile',profile('chris'))).profile;
});
after(async()=>{if(server)await new Promise(r=>server.close(r));await db?.close();});
test('GET/POST routes require a verified account; actor spoofing is ignored',async()=>{await api('bootstrap',{},'', 'GET',401);const r=await api('bootstrap',{actor:users[1]},users[0],'GET');assert.equal(r.profile.id,a.id);await api('send',{},users[0],'GET',404);await api('bootstrap',{},users[0],'POST',404);});
test('bootstrap exposes categories and opt-in profile only, never auth identity or email',async()=>{const r=await call(users[0],'bootstrap');assert.equal(r.categories.length,8);assert.equal(r.moderator,false);assert(!JSON.stringify(r).includes(users[0]));assert.equal(r.profile.show_online,true);});
test('new profiles require explicit community agreement and handles are unique',async()=>{await db.query('delete from korlix_social_profiles where user_id=$1',[users[2]]);assert.equal((await call(users[2],'bootstrap')).profile,null);await assert.rejects(call(users[2],'save_profile',profile('newone',{accepted_rules:false})),/Accept/);await assert.rejects(call(users[2],'members'),/Create/);await assert.rejects(call(users[2],'save_profile',profile('alice')),/unique/);await assert.rejects(call(users[2],'save_profile',profile('!!invalid')),/handle/);});
test('discoverability and online status are independently controlled and presence expires',async()=>{await call(users[1],'presence',{active:true});let list=(await call(users[0],'members',{online:true})).items;assert.equal(list.length,1);assert.equal(list[0].id,b.id);await db.exec("update korlix_social_profiles set last_seen=now()-interval '2 minutes'");assert.equal((await call(users[0],'members',{online:true})).items.length,0);await call(users[1],'save_profile',profile('bruno',{discoverable:false}));assert.equal((await call(users[0],'members')).items.length,1);await assert.rejects(call(users[0],'request',{peer:b.id}),/not accepting/);});
test('pending, self, cross-account and forged acceptance cannot unlock messages',async()=>{await assert.rejects(call(users[0],'request',{peer:a.id}),/another/);await assert.rejects(send(),/accepted/);await call(users[0],'request',{peer:b.id});await assert.rejects(send(),/Wait/);await assert.rejects(call(users[0],'accept',{peer:b.id}),/recipient/);await assert.rejects(call(users[2],'accept',{peer:a.id}),/accepted/);await call(users[1],'request',{peer:a.id});assert.equal((await call(users[0],'connections')).items[0].connection,'pending');});
test('accepted followers can talk in either direction; unrelated members cannot read',async()=>{await connect();await send();await send(users[1],a.id,'Reply');assert.equal((await call(users[0],'messages',{peer:b.id})).items.length,2);await assert.rejects(call(users[2],'messages',{peer:a.id}),/accepted/);assert.equal((await call(users[2],'connections')).items.length,0);});
test('message retries are idempotent and an ID cannot be hijacked by another sender',async()=>{await connect();const id=randomUUID();await send(users[0],b.id,'Hello',id);await send(users[0],b.id,'Hello',id);assert.equal((await call(users[0],'messages',{peer:b.id})).items.length,1);await assert.rejects(send(users[1],a.id,'Spoof',id),/new message ID/);});
test('unread markers apply only through the viewed sequence, not unseen messages',async()=>{await connect();await send();const r=await call(users[1],'messages',{peer:a.id});await send();await call(users[1],'read',{peer:a.id,through:r.items[0].seq});assert.equal((await call(users[1],'connections')).items[0].unread,1);await call(users[1],'read',{peer:a.id,through:999});assert.equal((await call(users[1],'connections')).items[0].unread,0);});
test('remove, block and rejection close messaging; unblocking does not restore consent',async()=>{await connect();await send();await call(users[1],'remove',{peer:a.id});await assert.rejects(send(),/accepted/);await connect();await call(users[1],'block',{peer:a.id});await assert.rejects(send(),/unavailable/);assert.equal((await call(users[0],'members')).items.length,1);assert.equal((await call(users[1],'blocks')).items.length,1);await call(users[1],'unblock',{peer:a.id});await assert.rejects(send(),/accepted/);await call(users[0],'request',{peer:b.id});await call(users[1],'decline',{peer:a.id});assert.equal((await call(users[0],'connections')).items.length,0);});
test('topics support categories, literal partial search, replies and own-content editing',async()=>{const t=await topic();assert.equal((await call(users[1],'topics',{category:'sports',q:'match'})).items.length,1);assert.equal((await call(users[1],'topics',{q:'%'})).items.length,0);const id=randomUUID();await call(users[1],'reply',{id:t.id,reply_id:id,body:'Blue team'});await call(users[1],'reply',{id:t.id,reply_id:id,body:'Blue team'});assert.equal((await call(users[0],'topic',{id:t.id})).items.length,1);await call(users[1],'edit_reply',{id,body:'Red team'});await call(users[0],'edit_topic',{id:t.id,title:'Final day',body:'New post'});assert.equal((await call(users[2],'topic',{id:t.id})).topic.title,'Final day');await assert.rejects(call(users[2],'delete_topic',{id:t.id}),/own/);await assert.rejects(call(users[2],'edit_reply',{id,body:'Hijack'}),/not found/);});
test('block removes forum content both ways; deleting topics closes their replies',async()=>{const t=await topic();await call(users[1],'block',{peer:a.id});assert.equal((await call(users[1],'topics')).items.length,0);await assert.rejects(call(users[1],'topic',{id:t.id}),/not found/);await call(users[0],'delete_topic',{id:t.id});await assert.rejects(call(users[2],'reply',{id:t.id,reply_id:randomUUID(),body:'Late'}),/not found/);});
test('message deletion is owner-only and removes the body',async()=>{await connect();const m=await send();await assert.rejects(call(users[1],'delete_message',{id:m.id}),/not found/);await call(users[0],'delete_message',{id:m.id});const r=(await call(users[1],'messages',{peer:a.id})).items[0];assert.equal(r.body,'');assert.equal(r.deleted,true);});
test('reports do not expose private messages to unrelated users; moderators only receive reported snapshots',async()=>{await connect();const m=await send();await assert.rejects(call(users[2],'report',{id:randomUUID(),kind:'message',target:m.id,reason:'test'}),/unavailable/);const id=randomUUID();await call(users[1],'report',{id,kind:'message',target:m.id,reason:'Spam'});await assert.rejects(call(users[0],'reports'),/Moderator/);await assert.rejects(call(users[0],'moderate',{id,decision:'remove'}),/Moderator/);await db.query('insert into korlix_social_moderators values($1)',[users[2]]);const r=await call(users[2],'reports');assert.equal(r.items[0].snapshot.body,'Hello');await call(users[2],'moderate',{id,decision:'remove'});assert.equal((await call(users[1],'messages',{peer:a.id})).items[0].deleted,true);assert.equal((await call(users[2],'reports')).items.length,0);});
test('moderator lock and suspension are enforced server-side',async()=>{const t=await topic(),id=randomUUID();await db.query('insert into korlix_social_moderators values($1)',[users[2]]);await call(users[1],'report',{id,kind:'topic',target:t.id,reason:'Review'});await call(users[2],'moderate',{id,decision:'lock'});await assert.rejects(call(users[1],'reply',{id:t.id,reply_id:randomUUID(),body:'Locked'}),/locked/);const report=randomUUID();await call(users[1],'report',{id:report,kind:'member',target:a.id,reason:'Review member'});await call(users[2],'moderate',{id:report,decision:'suspend'});await assert.rejects(call(users[0],'bootstrap'),/suspended/);assert.equal((await call(users[1],'topics')).items.length,0);});
test('rate limits are durable and enforced across requests',async()=>{await connect();for(let i=0;i<60;i++)await send();await assert.rejects(send(),/limit/);await api('send',{peer:b.id,id:randomUUID(),body:'over limit'},users[0],'POST',429);});
test('message paging has no duplicates or gaps',async()=>{await connect();for(let i=0;i<55;i++)await send();const page=(await call(users[0],'messages',{peer:b.id})).items;assert.equal(page.length,51);const older=(await call(users[0],'messages',{peer:b.id,before:page[0].seq})).items;assert.equal(older.length,4);assert.equal(new Set([...page,...older].map(m=>m.id)).size,55);});
test('public roles cannot read social data or invoke privileged functions; no definer functions',async()=>{const r=await db.query("select has_table_privilege('authenticated','korlix_social_messages','select') as table_access,has_function_privilege('anon','korlix_social_v1(uuid,text,jsonb)','execute') as rpc_access,(select relrowsecurity from pg_class where oid='korlix_social_messages'::regclass) as rls,(select prosecdef from pg_proc where proname='korlix_social_v1') as definer");assert.deepEqual(r.rows[0],{table_access:false,rpc_access:false,rls:true,definer:false});await db.exec('set role service_role');try{assert.equal((await call(users[0],'bootstrap')).profile.id,a.id);}finally{await db.exec('reset role');}});
const devices=users.map(()=>randomUUID());
const avatar=async(actor,action,path=null)=>{const r=await rpc.rpc('korlix_social_avatar',{p_actor:actor,p_action:action,p_path:path});if(r.error)throw Error(r.error.message);return r.data;};
const callData=(id,who=0,extra={})=>({id,device:devices[who],...extra});
const start=async()=>call(users[0],'call_start',callData(randomUUID(),0,{peer:b.id,mode:'video'}));
const signal=(id,who,kind,payload,signal_id=randomUUID())=>call(users[who],'call_signal',callData(id,who,{kind,payload,signal_id}));
test('profession is optional, bounded, searchable and present on member cards',async()=>{
 const saved=await call(users[1],'save_profile',profile('bruno',{profession:'  Registered Nurse  '}));assert.equal(saved.profile.profession,'Registered Nurse');
 assert.equal((await call(users[0],'members',{q:'nurs'})).items[0].id,b.id);
 await assert.rejects(call(users[1],'save_profile',profile('bruno',{profession:'a'.repeat(101)})),/100/);
 await call(users[1],'save_profile',profile('bruno'));assert.equal((await call(users[1],'bootstrap')).profile.profession,'Registered Nurse');
 await call(users[1],'block',{peer:a.id});assert.equal((await call(users[0],'members',{q:'nurs'})).items.length,0);
});
test('emoji sequences and non-Latin text survive send, retry, read and previews',async()=>{
 await connect();const body='Hi 👋🏽 👨‍👩‍👧‍👦 ❤️ مرحبا 你好';await send(users[0],b.id,body);
 assert.equal((await api('messages',{peer:a.id},users[1],'GET')).items[0].body,body);
 assert.equal((await call(users[1],'connections')).items[0].last_message,body);
});
test('photos accept real images, strip metadata, resize, replace and remove owned objects',async()=>{
 stored.clear(); const bytes=await sharp({create:{width:600,height:900,channels:3,background:'#12bbdd'}}).withMetadata({exif:{IFD0:{Artist:'Private metadata'}}}).png().toBuffer();
 const upload=async(buffer,status=200)=>{const form=new FormData();form.append('photo',new Blob([buffer]),'picture.png');const res=await fetch(base+'profile_photo',{method:'POST',headers:{Authorization:users[0]},body:form});const result=await res.json();assert.equal(res.status,status,JSON.stringify(result));return result;};
 await upload(Buffer.from('<svg>not a bitmap</svg>'),400);assert.equal(stored.size,0);
 const r=await upload(bytes);assert.match(r.profile.avatar_url,/fixture.test/);assert.equal(r.profile.avatar_path,undefined);
 assert.equal(stored.size,1);const file=[...stored.values()][0];const meta=await sharp(file.buffer).metadata();assert.equal(meta.width,512);assert.equal(meta.height,512);assert.equal(meta.format,'jpeg');assert.equal(meta.exif,undefined);
 await upload(bytes);assert.equal(stored.size,1);
 await api('profile_photo',{remove:true});assert.equal(stored.size,0);
 assert.equal((await call(users[0],'bootstrap')).profile.avatar_path,null);
 await assert.rejects(avatar(users[1],'save',`${a.id}/${randomUUID()}.jpg`),/path/);
 const untouched=await call(users[1],'save_profile',profile('bruno',{avatar_path:'https://evil.test/file'}));assert.equal(untouched.profile.avatar_path,null);
 await api('profile_photo',{remove:true},'', 'POST',401);
});
test('calls require accepted connections; only the recipient can answer and inbox exposes no device IDs or signals',async()=>{
 await assert.rejects(start(),/accepted/);await connect();const {call:c}=await start();assert.equal(c.state,'ringing');
 const inbox=await api('call_inbox',{device:devices[1]},users[1],'GET');assert.equal(inbox.call.id,c.id);assert.equal(inbox.call.peer.id,a.id);
 assert(!JSON.stringify(inbox).includes(devices[0]));assert.equal(inbox.signals,undefined);
 await assert.rejects(call(users[0],'call_accept',callData(c.id)),/recipient/);
 await assert.rejects(call(users[2],'call_poll',callData(c.id,2)),/not found/);
 await assert.rejects(signal(c.id,0,'offer',{sdp:'offer'}),/not connected/);
 const accepted=await call(users[1],'call_accept',callData(c.id,1));assert.equal(accepted.call.state,'accepted');
 await assert.rejects(call(users[1],'call_poll',{id:c.id,device:randomUUID()}),/another device/);
});
test('signaling enforces sender roles, idempotent IDs, paging cursor and call ownership',async()=>{
 await connect();const {call:c}=await start();await call(users[1],'call_accept',callData(c.id,1));
 await assert.rejects(signal(c.id,1,'offer',{sdp:'forged'}),/sender/);
 const sid=randomUUID();await signal(c.id,0,'offer',{sdp:'v=0\r\n'},sid);await signal(c.id,0,'offer',{sdp:'v=0\r\n'},sid);
 await assert.rejects(signal(c.id,1,'answer',{sdp:'changed'},sid),/ID/);
 await signal(c.id,0,'candidate',{candidate:'candidate:123',sdpMid:'0',sdpMLineIndex:0});
 let p=await api('call_poll',callData(c.id,1),users[1],'GET');assert.equal(p.signals.length,2);assert.equal(p.signals[0].kind,'offer');
 assert.equal((await call(users[1],'call_poll',callData(c.id,1,{after:p.signals[1].seq}))).signals.length,0);
 await signal(c.id,1,'answer',{sdp:'answer'});assert.equal((await call(users[0],'call_poll',callData(c.id))).signals[0].kind,'answer');
 await assert.rejects(signal(c.id,0,'candidate',{candidate:'x'.repeat(4001)}),/candidate/);
 await call(users[1],'call_end',callData(c.id,1));assert.equal((await call(users[0],'call_poll',callData(c.id))).call.state,'ended');
 assert.equal((await db.query('select count(*)::int n from korlix_social_call_signals')).rows[0].n,0);
 await assert.rejects(signal(c.id,0,'media',{camera:true,microphone:true}),/not connected/);
});
test('busy calls, crossed invitations, decline and retry cannot auto-answer or duplicate calls',async()=>{
 await connect();const id=randomUUID(),data=callData(id,0,{peer:b.id,mode:'audio'});
 await call(users[0],'call_start',data);await call(users[0],'call_start',data);
 await assert.rejects(call(users[1],'call_start',callData(randomUUID(),1,{peer:a.id,mode:'audio'})),/already/);
 await call(users[1],'call_end',callData(id,1));assert.equal((await call(users[0],'call_poll',callData(id))).call.state,'declined');
 assert.equal((await call(users[1],'call_accept',callData(id,1))).call.state,'declined');
 assert.equal((await start()).call.state,'ringing');
});
test('ring timeout, abandoned accepted calls and revoked consent end access',async()=>{
 await connect();let c=(await start()).call;
 await db.query("update korlix_social_calls set created_at=now()-interval '46 seconds' where id=$1",[c.id]);
 assert.equal((await call(users[1],'call_inbox',{device:devices[1]})).call,null);
 assert.equal((await call(users[0],'call_poll',callData(c.id))).call.state,'missed');
 c=(await start()).call;await call(users[1],'call_accept',callData(c.id,1));
 await db.query("update korlix_social_calls set callee_seen=now()-interval '61 seconds' where id=$1",[c.id]);
 assert.equal((await call(users[0],'call_poll',callData(c.id))).call.state,'ended');
 c=(await start()).call;await call(users[1],'call_accept',callData(c.id,1));await call(users[1],'block',{peer:a.id});
 assert.equal((await call(users[0],'call_poll',callData(c.id))).call.state,'ended');
 await assert.rejects(signal(c.id,0,'offer',{sdp:'late'}),/not connected/);
});
test('call attempts are rate limited and private tables/functions are unavailable to browser roles',async()=>{
 await connect();for(let i=0;i<10;i++){const c=(await start()).call;await call(users[0],'call_end',callData(c.id));}
 await assert.rejects(start(),/limit/);
 for(const table of ['korlix_social_calls','korlix_social_call_signals']) {
 const {rows}=await db.query("select has_table_privilege('authenticated',$1,'select') access,(select relrowsecurity from pg_class where oid=$1::regclass) rls",[table]);assert.deepEqual(rows[0],{access:false,rls:true});
 }
 const r=await db.query("select has_function_privilege('anon','korlix_social_calls_v1(uuid,text,jsonb)','execute') calls,has_function_privilege('authenticated','korlix_social_avatar(uuid,text,text)','execute') photos");assert.deepEqual(r.rows[0],{calls:false,photos:false});
 await db.exec('set role service_role');try{assert.equal((await call(users[1],'call_inbox',{device:devices[1]})).call,null);}finally{await db.exec('reset role');}
});
test('call config authenticates, exposes optional relay correctly and supports the operational kill switch',async()=>{
 const direct=socialCallConfig({});assert.equal(direct.enabled,true);assert.equal(direct.relay,false);
 const relay=socialCallConfig({SOCIAL_ICE_SERVERS:JSON.stringify([{urls:'turns:relay.example:443',username:'test',credential:'test-password'}])});assert.equal(relay.relay,true);
 assert.equal(socialCallConfig({SOCIAL_CALLS_ENABLED:'false'}).enabled,false);
 await api('call_config',{},'', 'GET',401);const r=await api('call_config',{},users[0],'GET');assert.equal(r.enabled,true);
});

test('private photo bucket stays denied even if another storage policy permits arbitrary buckets',async()=>{
 await db.exec("insert into storage.objects values(gen_random_uuid(),'korlix-social-avatars','private.jpg'),(gen_random_uuid(),'fixture-other','public.jpg');set role authenticated");
 try {
  const r=await db.query("select * from storage.objects where bucket_id='korlix-social-avatars'");assert.equal(r.rows.length,0);
  assert((await db.query("select * from storage.objects where bucket_id='fixture-other'")).rows.length>0);
  await assert.rejects(db.exec("insert into storage.objects values(gen_random_uuid(),'korlix-social-avatars','forged.jpg')"),/row-level security/);
 } finally {await db.exec('reset role');}
});

test('specific message replies preserve Unicode, survive paging, and support idempotent retry',async()=>{
 await connect();const original=await send(users[1],a.id,'Meeting at 3? 👋🏽');
 const id=randomUUID(),payload={id,peer:b.id,body:'Yes, 3 works!',reply_to:original.id};
 await api('send',payload);await api('send',payload);
 const messages=(await api('messages',{peer:a.id},users[1],'GET')).items;
 assert.equal(messages.length,2);assert.equal(messages[1].reply_to,original.id);
 assert.deepEqual(messages[1].reply,{id:original.id,seq:messages[0].seq,sender:b.id,deleted:false,body:'Meeting at 3? 👋🏽'});
 for(let i=0;i<52;i++)await send();
 const viewed=await api('message',{peer:b.id,id:original.id},users[0],'GET');assert.equal(viewed.message.body,'Meeting at 3? 👋🏽');
 await api('send',{...payload,reply_to:null},users[0],'POST',409);
 await api('send',{...payload,body:'different'},users[0],'POST',409);
});
test('reply targets and original-message views cannot cross conversations or bypass a block',async()=>{
 await connect();await call(users[0],'request',{peer:c.id});await call(users[2],'accept',{peer:a.id});
 const privateMessage=await send(users[2],a.id,'Only Alice and Chris');
 await api('send',{id:randomUUID(),peer:b.id,body:'forged quote',reply_to:privateMessage.id},users[0],'POST',400);
 await api('message',{peer:b.id,id:privateMessage.id},users[0],'GET',404);
 const original=await send();await call(users[1],'block',{peer:a.id});
 await api('send',{id:randomUUID(),peer:b.id,body:'blocked',reply_to:original.id},users[0],'POST',403);
 await api('message',{peer:b.id,id:original.id},users[0],'GET',403);
 await api('message',{peer:b.id,id:original.id},'', 'GET',401);
});
test('removed original text disappears from quoted replies and new replies are rejected',async()=>{
 await connect();const original=await send(users[1],a.id,'Remove this private text');
 const response=await api('send',{id:randomUUID(),peer:b.id,body:'My response',reply_to:original.id});
 await call(users[1],'delete_message',{id:original.id});
 const r=await api('messages',{peer:b.id},users[0],'GET');
 assert(!JSON.stringify(r).includes('Remove this private text'));
 assert.equal(r.items[1].reply.deleted,true);assert.equal(r.items[1].reply.body,'');
 await api('send',{id:randomUUID(),peer:b.id,body:'too late',reply_to:original.id},users[0],'POST',400);
 await call(users[0],'delete_message',{id:response.id});
 const removed=await api('message',{peer:b.id,id:response.id},users[0],'GET');
 assert.equal(removed.message.reply,null);assert.equal(removed.message.body,'');
});
test('reply RPCs stay invoker-only and unavailable to browser roles',async()=>{
 for(const name of ['korlix_social_chat_v1(uuid,text,jsonb)','korlix_social_message_card(korlix_social_messages)']){
  const r=await db.query("select has_function_privilege('anon',$1,'execute') anon,has_function_privilege('authenticated',$1,'execute') authenticated,(select prosecdef from pg_proc where oid=$1::regprocedure) definer",[name]);
  assert.deepEqual(r.rows[0],{anon:false,authenticated:false,definer:false});
 }
 await connect();await db.exec('set role service_role');
 try{const original=await send();await call(users[1],'send',{id:randomUUID(),peer:a.id,body:'Service works',reply_to:original.id});assert.equal((await call(users[0],'messages',{peer:b.id})).items.length,2);}finally{await db.exec('reset role');}
});

const connectAll=async()=>{await connect();await call(users[0],'request',{peer:c.id});await call(users[2],'accept',{peer:a.id});};
const createGroup=async(members=[b.id,c.id],id=randomUUID())=>api('group_create',{group:id,name:'Our circle',members});
const groupSend=async(group,actor=users[0],body='Hello group 👋🏽',extra={})=>api('group_send',{group,id:randomUUID(),body,...extra},actor);
test('groups invite several connections atomically, require consent, and exclude earlier messages',async()=>{
 await connectAll();const {group}=await createGroup();assert.equal(group.member_count,1);assert.equal(group.invited_count,2);
 const invitation=(await api('groups',{},users[1],'GET')).items[0];assert.equal(invitation.state,'invited');assert(!JSON.stringify(invitation).includes(users[0]));
 const before=await groupSend(group.id);
 await api('group_details',{group:group.id},users[1],'GET',403);
 await api('group_messages',{group:group.id},users[1],'GET',403);
 await api('group_send',{group:group.id,id:randomUUID(),body:'not accepted'},users[1],'POST',403);
 await api('group_accept',{group:group.id},users[1]);
 assert.equal((await api('group_messages',{group:group.id},users[1],'GET')).items.length,0);
 await api('group_message',{group:group.id,id:before.id},users[1],'GET',404);
 await groupSend(group.id,users[1],'I joined');
 assert.equal((await api('group_messages',{group:group.id},users[0],'GET')).items.length,2);
 await api('group_decline',{group:group.id},users[2]);assert.equal((await api('groups',{},users[2],'GET')).items.length,0);
});
test('group creation and invitation retries are idempotent and invalid batches roll back',async()=>{
 await connect();const id=randomUUID();await api('group_create',{group:id,name:'Invalid batch',members:[b.id,c.id]},users[0],'POST',400);
 assert.equal((await api('groups',{},users[0],'GET')).items.length,0);
 await call(users[0],'request',{peer:c.id});await call(users[2],'accept',{peer:a.id});await createGroup([b.id,c.id,b.id],id);await createGroup([c.id,b.id],id);
 assert.equal((await api('groups',{},users[0],'GET')).items.length,1);
 assert.equal((await api('groups',{},users[1],'GET')).items.length,1);
 await api('group_create',{group:id,name:'Changed',members:[b.id,c.id]},users[0],'POST',409);
 await api('group_create',{group:id,name:'Our circle',members:[b.id,c.id]},users[1],'POST',409);
 await api('group_invite',{group:id,members:[b.id,c.id]});assert.equal((await api('group_details',{group:id},users[0],'GET')).members.length,3);
});
test('only owners manage groups; leaving or removal immediately closes reads and writes',async()=>{
 await connectAll();const {group}=await createGroup();await api('group_accept',{group:group.id},users[1]);
 await api('group_rename',{group:group.id,name:'Hijack'},users[1],'POST',403);
 await api('group_invite',{group:group.id,members:[c.id]},users[1],'POST',403);
 await api('group_remove',{group:group.id,member:a.id},users[1],'POST',403);
 await api('group_rename',{group:group.id,name:'Friday team'});
 assert.equal((await api('groups',{},users[1],'GET')).items[0].name,'Friday team');
 const m=await groupSend(group.id);
 await api('group_remove',{group:group.id,member:b.id});
 await api('group_messages',{group:group.id},users[1],'GET',403);
 await api('group_message',{group:group.id,id:m.id},users[1],'GET',403);
 await api('group_send',{group:group.id,id:randomUUID(),body:'removed'},users[1],'POST',403);
 await api('group_accept',{group:group.id},users[1],'POST',403);
 await api('group_accept',{group:group.id},users[2]);
 await api('group_leave',{group:group.id},users[2]);
 await api('group_details',{group:group.id},users[2],'GET',403);
});
test('ownership transfers to a joined member or the last owner closes the group',async()=>{
 await connectAll();const {group}=await createGroup();await api('group_accept',{group:group.id},users[1]);
 await api('group_leave',{group:group.id});
 assert.equal((await api('group_details',{group:group.id},users[1],'GET')).group.owner,b.id);
 await api('group_leave',{group:group.id},users[1]);
 assert.equal((await api('groups',{},users[2],'GET')).items.length,0);
 await api('group_accept',{group:group.id},users[2],'POST',403);
});
test('group replies cannot cross rooms, membership history, or duplicate request identity',async()=>{
 await connectAll();const first=(await createGroup()).group,second=(await createGroup()).group;
 await api('group_accept',{group:first.id},users[1]);
 const original=await groupSend(first.id);const id=randomUUID();
 await groupSend(first.id,users[1],'A specific reply',{id,reply_to:original.id});
 await groupSend(first.id,users[1],'A specific reply',{id,reply_to:original.id});
 const page=(await api('group_messages',{group:first.id},users[0],'GET')).items;
 assert.equal(page.length,2);assert.equal(page[1].reply.body,'Hello group 👋🏽');assert.equal(page[1].author.name,'bruno');
 await api('group_send',{group:first.id,id,body:'Changed',reply_to:original.id},users[1],'POST',409);
 await api('group_send',{group:second.id,id:randomUUID(),body:'Cross room',reply_to:original.id},users[0],'POST',400);
 await api('group_message',{group:second.id,id:original.id},users[0],'GET',404);
 await api('group_accept',{group:first.id},users[2]);
 await api('group_send',{group:first.id,id:randomUUID(),body:'Before joining',reply_to:original.id},users[2],'POST',400);
 await groupSend(first.id,users[0],'Refers to older message',{reply_to:original.id});
 const late=(await api('group_messages',{group:first.id},users[2],'GET')).items[0];assert.equal(late.reply,null);assert.equal(late.reply_to,null);
 await api('group_delete_message',{group:first.id,id:original.id});
 assert.equal((await api('group_message',{group:first.id,id},users[1],'GET')).message.reply.body,'');
});
test('group blocks hide sender text and quotes; blocked invitations cannot be accepted',async()=>{
 await connectAll();const {group}=await createGroup();await api('group_accept',{group:group.id},users[1]);await api('group_accept',{group:group.id},users[2]);
 const m=await groupSend(group.id,users[1],'Hidden after blocking');
 await groupSend(group.id,users[0],'A quote',{reply_to:m.id});
 await call(users[2],'block',{peer:b.id});
 const page=await api('group_messages',{group:group.id},users[2],'GET');assert(!JSON.stringify(page).includes('Hidden after blocking'));
 assert.equal(page.items[0].deleted,true);assert.equal(page.items[1].reply,null);
 const other=(await createGroup([b.id])).group;await call(users[1],'block',{peer:a.id});
 await api('group_accept',{group:other.id},users[1],'POST',403);
 assert(!(await api('groups',{},users[1],'GET')).items.some(g=>g.id===other.id));
});
test('group unread cursors, paging and fresh-join history boundaries remain consistent',async()=>{
 await connectAll();const {group}=await createGroup();await api('group_accept',{group:group.id},users[1]);
 for(let i=0;i<55;i++)await groupSend(group.id,users[0],`Message ${i}`);
 assert.equal((await api('groups',{},users[1],'GET')).items[0].unread,55);
 const recent=(await api('group_messages',{group:group.id},users[1],'GET')).items;
 const older=(await api('group_messages',{group:group.id,before:recent[0].seq},users[1],'GET')).items;
 assert.equal(new Set([...recent,...older].map(m=>m.id)).size,55);
 await api('group_read',{group:group.id,through:recent.at(-1).seq},users[1]);
 await groupSend(group.id);assert.equal((await api('groups',{},users[1],'GET')).items[0].unread,1);
 await api('group_leave',{group:group.id},users[1]);
 await api('group_invite',{group:group.id,members:[b.id]},users[0],'POST',400);
 await db.query("update korlix_social_group_members set invited_at=now()-interval '2 hours' where group_id=$1 and member=$2",[group.id,b.id]);
 await api('group_invite',{group:group.id,members:[b.id]});await api('group_accept',{group:group.id},users[1]);
 assert.equal((await api('group_messages',{group:group.id},users[1],'GET')).items.length,0);
});
test('group reports share only an authorized snapshot and moderators can remove reported content',async()=>{
 await connectAll();const {group}=await createGroup([b.id]);await api('group_accept',{group:group.id},users[1]);const m=await groupSend(group.id);
 const id=randomUUID();await api('report',{id,kind:'group_message',target:m.id,reason:'Please review'},users[2],'POST',403);
 await api('report',{id,kind:'group_message',target:m.id,reason:'Please review'},users[1]);
 await api('moderate',{id,decision:'remove'},users[1],'POST',403);
 await db.query('insert into korlix_social_moderators values($1)',[users[2]]);
 const reports=await api('reports',{},users[2],'GET');assert.equal(reports.items[0].kind,'group_message');assert.equal(reports.items[0].snapshot.body,'Hello group 👋🏽');
 await api('moderate',{id,decision:'remove'},users[2]);
 assert.equal((await api('group_message',{group:group.id,id:m.id},users[1],'GET')).message.deleted,true);
});
test('group tables and RPCs stay service-only with RLS, bounded batches and authenticated routes',async()=>{
 for(const table of ['groups','group_members','group_messages']) {
  const r=await db.query("select has_table_privilege('authenticated',$1,'select') access,(select relrowsecurity from pg_class where oid=$1::regclass) rls",[`korlix_social_${table}`]);assert.deepEqual(r.rows[0],{access:false,rls:true});
 }
 for(const f of ['korlix_social_groups_v1(uuid,text,jsonb)','korlix_social_group_card(korlix_social_groups,uuid)','korlix_social_group_message_card(korlix_social_group_messages,uuid,bigint)']) {
  const r=await db.query("select has_function_privilege('anon',$1,'execute') anon,has_function_privilege('authenticated',$1,'execute') authenticated,(select prosecdef from pg_proc where oid=$1::regprocedure) definer",[f]);assert.deepEqual(r.rows[0],{anon:false,authenticated:false,definer:false});
 }
 await api('groups',{},'','GET',401);await connectAll();
 await api('group_create',{group:randomUUID(),name:'Too many',members:Array.from({length:50},()=>randomUUID())},users[0],'POST',400);
 await db.exec('set role service_role');try{const {group}=await call(users[0],'group_create',{group:randomUUID(),name:'Works',members:[b.id,c.id]});assert.equal(group.invited_count,2);}finally{await db.exec('reset role');}
});
test('group capacity includes pending invitations and cannot be exceeded by later batches',async()=>{
 await connectAll();const targets=[b.id,c.id];
 for(let i=0;i<48;i++){
  const user=randomUUID();await db.query('insert into auth.users values($1)',[user]);
  const member=(await call(user,'save_profile',profile(`capacity_${i}`))).profile;
  await db.query("insert into korlix_social_connections(requester,recipient,state)values($1,$2,'accepted')",[a.id,member.id]);targets.push(member.id);
 }
 const {group}=await createGroup(targets.slice(0,49));assert.equal(group.invited_count,49);
 await api('group_invite',{group:group.id,members:[targets[49]]},users[0],'POST',400);
 assert.equal((await api('group_details',{group:group.id},users[0],'GET')).members.length,50);
});
