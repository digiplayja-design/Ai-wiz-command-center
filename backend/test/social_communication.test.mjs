import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createECDH,randomBytes} from 'node:crypto';
import {socialPushConfig,validateSocialPushSubscription} from '../social/push.mjs';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocial} from '../social/routes.mjs';
let db,server,base,a,b,c,push;
const ecdh=createECDH('prime256v1');ecdh.generateKeys();
const env={SOCIAL_WEB_PUSH_PUBLIC_KEY:ecdh.getPublicKey().toString('base64url'),SOCIAL_WEB_PUSH_PRIVATE_KEY:ecdh.getPrivateKey().toString('base64url'),SOCIAL_WEB_PUSH_SUBJECT:'https://www.korlixdeveloper.com'};
const devices=Array.from({length:3},()=>randomUUID());
const sends=[];let providerError=null;
const sender=async(...args)=>{sends.push(args);if(providerError)throw providerError;return {statusCode:201};};
const subscription=(suffix=randomUUID())=>{const k=createECDH('prime256v1');k.generateKeys();return {endpoint:'https://fcm.googleapis.com/fcm/send/'+suffix,keys:{p256dh:k.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')}};};
const enrollment=(who=1,extra={})=>({device:devices[who],binding:randomUUID(),subscription:subscription(),messages:true,calls:true,...extra});
const pushCall=async(actor,action,data={})=>(await db.query('select korlix_social_push_v1($1,$2,$3::jsonb) result',[actor,action,JSON.stringify(data)])).rows[0].result;
const users=[randomUUID(),randomUUID(),randomUUID()];
const call=async(actor,action,data={})=>(await db.query(`select ${(action==='groups'||action.startsWith('group_'))?'korlix_social_groups_v1':action.startsWith('call_')?'korlix_social_calls_v1':['send','messages','message'].includes(action)?'korlix_social_chat_v1':'korlix_social_v1'}($1,$2,$3::jsonb) result`,[actor,action,JSON.stringify(data)])).rows[0].result;
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
 const upgrade=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_communication_upgrade.sql'));
 await db.exec(await readFile(new URL(upgrade,folder),'utf8'));
 const dumpScope=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_last_login_dump_scope.sql'));
 await db.exec(await readFile(new URL(dumpScope,folder),'utf8'));
 const online=(await readdir(folder)).find(f=>f.endsWith('_korlix_social_online_alerts.sql'));
 await db.exec(await readFile(new URL(online,folder),'utf8'));
 const app=express();app.use(express.json({limit:'250kb'}));push=registerSocial(app,{database:rpc,env,pushSender:sender,autoStart:false,requireUser:async q=>{if(!users.includes(q.headers.authorization))throw Error();return {id:q.headers.authorization,email_confirmed_at:'2026-01-01'};},logger:{warn(){}}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{sends.length=0;providerError=null;await db.exec('truncate korlix_social_profiles,korlix_social_connections,korlix_social_blocks,korlix_social_messages,korlix_social_topics,korlix_social_replies,korlix_social_reports,korlix_social_limits,korlix_social_moderators restart identity cascade;');
 a=(await call(users[0],'save_profile',profile('alice'))).profile;b=(await call(users[1],'save_profile',profile('bruno'))).profile;c=(await call(users[2],'save_profile',profile('chris'))).profile;
});
after(async()=>{push?.stop();if(server)await new Promise(r=>server.close(r));await db?.close();});
const start=async(who=0,peer=b.id)=>call(users[who],'call_start',{id:randomUUID(),peer,mode:'audio',device:devices[who],protocol:2});
const callData=(id,who=0,extra={})=>({id,device:devices[who],...extra});
const signal=(id,who,kind,payload,signal_id=randomUUID())=>call(users[who],'call_signal',callData(id,who,{kind,payload,signal_id}));
const accept=async id=>call(users[1],'call_accept',callData(id,1,{protocol:2}));
const count=async table=>(await db.query(`select count(*)::int n from ${table}`)).rows[0].n;

test('configuration exposes only public VAPID key; absent/mismatched keys stay disabled',async()=>{
 assert.equal(socialPushConfig({}).enabled,false);
 assert.equal(socialPushConfig({...env,SOCIAL_WEB_PUSH_PRIVATE_KEY:randomBytes(32).toString('base64url')}).enabled,false);
 const result=await api('push_config',{},users[1],'GET');assert.equal(result.enabled,true);assert.equal(result.native,false);
 assert(!JSON.stringify(result).includes(env.SOCIAL_WEB_PUSH_PRIVATE_KEY));
 await api('push_config',{},'', 'GET',401);
 await api('push_subscribe',enrollment(),users[1],'GET',404);
});
test('subscription endpoints are browser-service allowlisted and elliptic keys validated',()=>{
 const valid=subscription();assert.deepEqual(validateSocialPushSubscription(valid),valid);
 for(const endpoint of ['http://fcm.googleapis.com/x','https://127.0.0.1/x','https://fcm.googleapis.com.evil.test/x','https://evil.test/x','https://fcm.googleapis.com:444/x','https://user@fcm.googleapis.com/x','https://fcm.googleapis.com/x#frag'])assert.throws(()=>validateSocialPushSubscription({...valid,endpoint}));
 assert.throws(()=>validateSocialPushSubscription({...valid,keys:{...valid.keys,auth:'x'}}));
 assert.throws(()=>validateSocialPushSubscription({...valid,keys:{...valid.keys,p256dh:Buffer.alloc(65).toString('base64url')}}));
});
test('registration is account-private, bounded and owner-only unsubscribe',async()=>{
 const registration=enrollment();await api('push_subscribe',registration,users[1]);
 const own=await api('push_state',{},users[1],'GET');assert.equal(own.subscriptions.length,1);assert.equal(own.subscriptions[0].device,devices[1]);
 assert(!JSON.stringify(own).includes(registration.subscription.endpoint));assert(!JSON.stringify(own).includes(registration.binding));
 assert.equal((await api('push_state',{},users[0],'GET')).subscriptions.length,0);
 await api('push_unsubscribe',{device:devices[1]},users[0]);assert.equal(await count('korlix_social_push_subscriptions'),1);
 await api('push_subscribe',{...registration,device:devices[0]},users[0],'POST',400);
 await api('push_unsubscribe',{device:devices[1]},users[1]);assert.equal(await count('korlix_social_push_subscriptions'),0);
});
test('messages enqueue only after opt-in, retries dedupe and payload has no sender or message text',async()=>{
 await connect();await send();assert.equal(await count('korlix_social_push_outbox'),0);
 const registration=enrollment();await api('push_subscribe',registration,users[1]);
 const id=randomUUID();await send(users[0],b.id,'My confidential contents',id);await send(users[0],b.id,'My confidential contents',id);
 assert.equal(await count('korlix_social_push_outbox'),1);await push.tick();await push.tick();assert.equal(sends.length,1);
 const payload=JSON.parse(sends[0][1]);assert.equal(payload.binding,registration.binding);assert.equal(payload.kind,'message');assert.equal(payload.eventId,id);
 assert(!sends[0][1].includes('confidential'));assert(!sends[0][1].includes('alice'));assert(!sends[0][1].includes(users[0]));
 assert(sends[0][2].TTL<=300);assert.equal((await db.query('select status from korlix_social_push_outbox')).rows[0].status,'accepted');
});
test('unread, delete, block, revoked connection and Auto Dump are rechecked before delivery',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);
 let m=await send();await call(users[1],'read',{peer:a.id,through:999999});await push.tick();assert.equal(sends.length,0);
 m=await send();await call(users[0],'delete_message',{id:m.id});await push.tick();assert.equal(sends.length,0);
 m=await send();await db.query("insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at)values($1,'direct',$2,now()-interval '1 second')",[b.id,m.id]);await push.tick();assert.equal(sends.length,0);
 await send();await call(users[1],'block',{peer:a.id});await push.tick();assert.equal(sends.length,0);
 assert.equal((await db.query("select count(*)::int n from korlix_social_push_outbox where status='cancelled'")).rows[0].n,4);
});
test('incoming call alerts expire and accepted/ended calls are suppressed',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);
 let c=(await start()).call;await accept(c.id);await push.tick();assert.equal(sends.length,0);await call(users[0],'call_end',callData(c.id));
 c=(await start()).call;await db.query("update korlix_social_push_outbox set expires_at=now()-interval '1 second' where event_id=$1",[c.id]);await push.tick();assert.equal(sends.length,0);await call(users[0],'call_end',callData(c.id));
 c=(await start()).call;await push.tick();assert.equal(sends.length,1);assert.equal(JSON.parse(sends[0][1]).kind,'call');assert(sends[0][2].TTL<=45);assert.equal(sends[0][2].urgency,'high');
});
test('unknown network outcomes are never automatically replayed; 410 removes stale browser',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);await send();providerError=new Error('fixture timeout');await push.tick();await push.tick();assert.equal(sends.length,1);
 assert.equal((await db.query('select status from korlix_social_push_outbox')).rows[0].status,'unknown');
 providerError=Object.assign(new Error('gone'),{statusCode:410});await send();await push.tick();assert.equal(await count('korlix_social_push_subscriptions'),0);
});
test('explicit 429 retries are bounded and crashed sending leases become unknown',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);await send();providerError=Object.assign(new Error('limited'),{statusCode:429});await push.tick();
 assert.equal((await db.query('select status from korlix_social_push_outbox')).rows[0].status,'retry');
 await db.exec("update korlix_social_push_outbox set next_attempt=now()-interval '1 second'");providerError=null;await push.tick();assert.equal(sends.length,2);
 await send();let q=(await pushCall(null,'claim')).items[0];await pushCall(null,'authorize',q);await db.exec("update korlix_social_push_outbox set lease_until=now()-interval '1 second' where status='sending'");await push.tick();assert.equal(sends.length,2);assert.equal((await db.query("select count(*)::int n from korlix_social_push_outbox where status='unknown'")).rows[0].n,1);
});
test('unsubscribe/profile deletion destroys queued secrets and changed binding cancels old work',async()=>{
 await connect();let settings=enrollment();await api('push_subscribe',settings,users[1]);await send();await api('push_subscribe',{...settings,binding:randomUUID()},users[1]);await push.tick();assert.equal(sends.length,0);
 await send();await api('push_unsubscribe',{device:devices[1]},users[1]);await push.tick();assert.equal(sends.length,0);assert.equal(await count('korlix_social_push_outbox'),0);
 await api('push_subscribe',enrollment(),users[1]);await send();await db.query('delete from korlix_social_profiles where id=$1',[b.id]);assert.equal(await count('korlix_social_push_subscriptions'),0);assert.equal(await count('korlix_social_push_outbox'),0);
});
test('group notifications require current accepted membership and respect read boundary',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);
 const group=randomUUID();await call(users[0],'group_create',{group,name:'Work',members:[b.id]});
 await call(users[1],'group_accept',{group});await call(users[0],'group_send',{group,id:randomUUID(),body:'Group message'});await push.tick();assert.equal(sends.length,1);assert.equal(JSON.parse(sends[0][1]).kind,'group_message');
 await call(users[0],'group_send',{group,id:randomUUID(),body:'Hidden'});await call(users[1],'group_leave',{group});await push.tick();assert.equal(sends.length,1);
});
test('call history retains 30 days, resolves missed calls, hides private signaling and isolates accounts',async()=>{
 await connect();const c=(await start()).call;await db.query("update korlix_social_calls set created_at=now()-interval '46 seconds' where id=$1",[c.id]);
 let h=await api('call_history',{device:devices[1]},users[1],'GET');assert.equal(h.items.length,1);assert.equal(h.items[0].state,'missed');assert.equal(h.items[0].incoming,true);assert.equal(h.items[0].can_call,true);
 assert(!JSON.stringify(h).includes(devices[0]));assert(!JSON.stringify(h).includes('sdp'));
 assert.equal((await api('call_history',{device:devices[2]},users[2],'GET')).items.length,0);
 await db.query("update korlix_social_calls set created_at=now()-interval '2 days' where id=$1",[c.id]);assert.equal((await call(users[1],'call_inbox',{device:devices[1]})).call,null);assert.equal(await count('korlix_social_calls'),1);
 await call(users[1],'block',{peer:a.id});h=await call(users[1],'call_history',{device:devices[1]});assert.equal(h.items[0].peer.name,'Unavailable member');assert.equal(h.items[0].can_call,false);
 await db.query("update korlix_social_calls set created_at=now()-interval '31 days' where id=$1",[c.id]);assert.equal((await call(users[1],'call_history',{device:devices[1]})).items.length,0);
});
test('ICE restart is caller-owned, generation-isolated and idempotent; old clients remain valid',async()=>{
 await connect();const c=(await start()).call;await accept(c.id);
 await signal(c.id,0,'offer',{sdp:'first'});await signal(c.id,1,'answer',{sdp:'answer'});
 await assert.rejects(call(users[1],'call_restart',callData(c.id,1,{generation:0})),/caller/);
 await signal(c.id,1,'restart_request',{generation:0});
 let restart=await call(users[0],'call_restart',callData(c.id,0,{generation:0}));assert.equal(restart.call.generation,1);
 assert.equal((await call(users[0],'call_restart',callData(c.id,0,{generation:0}))).call.generation,1);
 await assert.rejects(signal(c.id,0,'candidate',{candidate:'old',generation:0}),/expired/);
 await api('call_signal',callData(c.id,0,{kind:'candidate',payload:{candidate:'old',generation:0},signal_id:randomUUID()}),users[0],'POST',409);
 assert.equal((await call(users[0],'call_poll',callData(c.id))).call.state,'accepted');
 await signal(c.id,0,'offer',{sdp:'second',generation:1});await signal(c.id,1,'answer',{sdp:'new-answer',generation:1});await signal(c.id,0,'candidate',{candidate:'fresh',generation:1});
 const poll=await call(users[1],'call_poll',callData(c.id,1));assert.equal(poll.call.generation,1);assert(poll.signals.some(s=>s.generation===1&&s.kind==='offer'));
 await call(users[0],'call_end',callData(c.id));assert.equal(await count('korlix_social_call_signals'),0);assert.equal((await call(users[0],'call_history',{device:devices[0]})).items.length,1);
});
test('service-only tables and RPCs have RLS and no security-definer escape',async()=>{
 for(const table of ['korlix_social_push_subscriptions','korlix_social_push_outbox']) {
  const row=(await db.query("select has_table_privilege('authenticated',$1,'select') access,(select relrowsecurity from pg_class where oid=$1::regclass) rls",[table])).rows[0];assert.deepEqual(row,{access:false,rls:true});
 }
 assert.equal((await db.query("select has_function_privilege('anon','korlix_social_push_v1(uuid,text,jsonb)','execute') access")).rows[0].access,false);
 assert.equal((await db.query("select count(*)::int n from pg_proc where proname like 'korlix_social_push_%' and prosecdef")).rows[0].n,0);
 await db.exec('set role service_role');try{await pushCall(users[1],'state');}finally{await db.exec('reset role');}
});

test('legacy/new mixed calls keep generation zero and decline unsupported recovery',async()=>{
 await connect();
 const id=randomUUID();await call(users[0],'call_start',{id,peer:b.id,mode:'audio',device:devices[0]});await accept(id);
 await signal(id,0,'offer',{sdp:'legacy'});await signal(id,1,'answer',{sdp:'modern',generation:0});
 assert.equal((await call(users[0],'call_poll',callData(id))).call.recovery_supported,false);
 await assert.rejects(call(users[0],'call_restart',callData(id,0,{generation:0})),/latest/);
 await assert.rejects(signal(id,1,'restart_request',{generation:0}),/latest/);await call(users[0],'call_end',callData(id));
 const next=(await start()).call;await call(users[1],'call_accept',callData(next.id,1));
 await signal(next.id,0,'offer',{sdp:'modern',generation:0});await signal(next.id,1,'answer',{sdp:'legacy'});
 assert.equal((await call(users[1],'call_poll',callData(next.id,1))).call.recovery_supported,false);
});
test('unsent message bursts coalesce to latest generic alert; calls take priority',async()=>{
 await connect();await api('push_subscribe',enrollment(),users[1]);
 await send();const latest=await send();const c=(await start()).call;
 assert.equal(await count('korlix_social_push_outbox'),2);
 const q=await pushCall(null,'claim');const first=(await pushCall(null,'authorize',q.items[0])).delivery;
 assert.equal(first.kind,'call');assert.equal(first.event_id,c.id);
 const second=(await pushCall(null,'authorize',q.items[1])).delivery;assert.equal(second.kind,'message');assert.equal(second.event_id,latest.id);
});


test('old endpoint expiration cannot revoke a renewed subscription, even with reused binding',async()=>{
 await connect();const settings=enrollment();await api('push_subscribe',settings,users[1]);await send();
 const old=(await pushCall(null,'claim')).items[0];await pushCall(null,'authorize',old);
 const next={...settings,subscription:subscription()};await api('push_subscribe',next,users[1]);
 await pushCall(null,'finish',{...old,status:'expired'});
 let saved=(await db.query('select revision,subscription from korlix_social_push_subscriptions')).rows;
 assert.equal(saved.length,1);assert.equal(saved[0].revision,2);assert.equal(saved[0].subscription.endpoint,next.subscription.endpoint);
 assert.equal((await db.query('select status from korlix_social_push_outbox where id=$1',[old.id])).rows[0].status,'cancelled');
 await send();const another=(await pushCall(null,'claim')).items[0];await pushCall(null,'authorize',another);
 const fresh={...next,binding:randomUUID(),subscription:subscription()};await api('push_subscribe',fresh,users[1]);await pushCall(null,'finish',{...another,status:'expired'});
 saved=(await db.query('select revision,subscription from korlix_social_push_subscriptions')).rows;
 assert.equal(saved.length,1);assert.equal(saved[0].revision,3);assert.equal(saved[0].subscription.endpoint,fresh.subscription.endpoint);
 await send();await push.tick();assert.equal(sends.length,1);assert.equal(sends[0][0].endpoint,fresh.subscription.endpoint);
});

const online = async(actor, action, data={}) => (await db.query('select korlix_social_online_v1($1,$2,$3::jsonb) result',[actor,action,JSON.stringify(data)])).rows[0].result;
const watch = (peer=b.id, enabled=true, sound='bell', actor=users[0]) => online(actor,'online_watch_set',{peer,enabled,sound});
const events = actor => online(actor,'online_events');
const offline = async(peer=b.id) => db.query("update korlix_social_profiles set last_seen=now()-interval '2 minutes' where id=$1",[peer]);

test('online selections require accepted connections and cannot select self or act as another user',async()=>{
 await assert.rejects(watch(),{code:'42501'});
 await connect();await watch();
 assert.equal((await online(users[0],'online_watches')).items.length,1);
 assert.equal((await online(users[1],'online_watches')).items.length,0);
 await assert.rejects(watch(a.id));
 await api('online_watch_set',{peer:c.id,enabled:true,sound:'bell',p_actor:users[1]},users[0],'POST',403);
 await api('online_watches',{},'invalid','GET',401);
 await assert.rejects(watch(b.id,true,'alarm'));
 await assert.rejects(watch(b.id,'true','bell'));
});

test('online alerts begin at next arrival, deduplicate heartbeats and respect the 15 minute cooldown',async()=>{
 await connect();await call(users[1],'presence',{active:true});await watch();
 await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items.length,0);
 await offline();await call(users[1],'presence',{active:true});
 const first=(await events(users[0])).items[0];assert.equal(first.peer.id,b.id);assert.equal(first.peer.online,true);
 await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items[0].id,first.id);
 await offline();await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items.length,0);
 await db.exec("update korlix_social_online_watches set last_alert_at=now()-interval '16 minutes'");
 await offline();await call(users[1],'presence',{active:true});
 assert.notEqual((await events(users[0])).items[0].id,first.id);
 assert.equal(await count('korlix_social_online_events'),1);
});

test('online notification enrollment is separately opt-in and silent mode is delivered without a name',async()=>{
 await connect();await watch(b.id,true,'silent');
 const sub=enrollment(0);await pushCall(users[0],'subscribe',sub);
 await call(users[1],'presence',{active:true});assert.equal(await count('korlix_social_push_outbox'),0);
 await pushCall(users[0],'subscribe',{...sub,online:true});
 await db.exec("update korlix_social_online_watches set last_alert_at=now()-interval '16 minutes'");
 await offline();await call(users[1],'presence',{active:true});await push.tick();
 assert.equal(sends.length,1);const body=JSON.parse(sends[0][1]);
 assert.equal(body.kind,'online');assert.equal(body.silent,true);
 assert.ok(!sends[0][1].includes('bruno'));assert.ok(!sends[0][1].includes(b.id));
 assert(sends[0][2].TTL<=90);
});

test('hidden, suspended and offline members cannot produce or retain online alerts',async()=>{
 await connect();await watch();
 await db.query('update korlix_social_profiles set show_online=false where id=$1',[b.id]);
 await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items.length,0);
 await db.query('update korlix_social_profiles set show_online=true where id=$1',[b.id]);
 await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items.length,1);
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[b.id]);
 assert.equal((await events(users[0])).items.length,0);
});

test('online push rechecks visibility and watch choice after the worker claims it',async()=>{
 await connect();await watch();await pushCall(users[0],'subscribe',enrollment(0,{online:true}));
 await call(users[1],'presence',{active:true});const item=(await pushCall(null,'claim')).items[0];
 await db.query('update korlix_social_profiles set show_online=false where id=$1',[b.id]);
 assert.equal((await pushCall(null,'authorize',item)).delivery,null);
 assert.equal(sends.length,0);
});

test('removal and blocking erase online selections and pending events; reconnecting does not restore them',async()=>{
 await connect();await watch();await watch(a.id,true,'bell',users[1]);
 await call(users[1],'presence',{active:true});
 await call(users[0],'remove',{peer:b.id});
 assert.equal(await count('korlix_social_online_watches'),0);assert.equal(await count('korlix_social_online_events'),0);
 await connect();assert.equal((await online(users[0],'online_watches')).items.length,0);
 await watch();await call(users[1],'block',{peer:a.id});
 assert.equal(await count('korlix_social_online_watches'),0);
});

test('disabling a watch revokes events and queued push even with messages and calls enabled',async()=>{
 await connect();await watch();await pushCall(users[0],'subscribe',enrollment(0,{online:true}));
 await call(users[1],'presence',{active:true});assert.equal((await events(users[0])).items.length,1);
 await watch(b.id,false);await push.tick();
 assert.equal(sends.length,0);assert.equal((await events(users[0])).items.length,0);
});

test('online events are bounded and expire, and client roles cannot read watches or invoke privileged RPCs',async()=>{
 await connect();await watch();await call(users[1],'presence',{active:true});
 await db.exec("update korlix_social_online_events set expires_at=now()-interval '1 second'");
 assert.equal((await events(users[0])).items.length,0);
 await pushCall(null,'claim');assert.equal(await count('korlix_social_online_events'),0);
 for (const role of ['anon','authenticated']) {
  const permission=(await db.query("select has_table_privilege($1,'korlix_social_online_watches','select') watches,has_table_privilege($1,'korlix_social_online_events','select') events,has_function_privilege($1,'korlix_social_online_v1(uuid,text,jsonb)','execute') rpc",[role])).rows[0];
  assert.deepEqual(permission,{watches:false,events:false,rpc:false});
 }
 const rows=(await db.query("select relrowsecurity from pg_class where oid in ('korlix_social_online_watches'::regclass,'korlix_social_online_events'::regclass)")).rows;
 assert(rows.every(row=>row.relrowsecurity));
});

test('online selections are capped at 50 and updating an existing sound remains allowed',async()=>{
 for(let i=0;i<51;i++) {
  const user=randomUUID(),id=randomUUID();await db.query('insert into auth.users(id) values($1)',[user]);
  await db.query("insert into korlix_social_profiles(id,user_id,handle,name) values($1,$2,$3,$3)",[id,user,'online_limit_'+i]);
  await db.query("insert into korlix_social_connections(requester,recipient,state) values($1,$2,'accepted')",[a.id,id]);
  if(i<50)await watch(id);else await assert.rejects(watch(id),/up to 50/);
 }
 const first=(await online(users[0],'online_watches')).items[0];await watch(first.peer.id,true,'ring');
 assert.equal((await online(users[0],'online_watches')).items.length,50);
});
