import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db,a,b,c,webDefinitions;
const users=Array.from({length:3},()=>randomUUID());
const devices=Array.from({length:3},()=>randomUUID());
const ownerKey=i=>JSON.stringify(['https://fixture.supabase.co/auth/v1',users[i]]);
const rpc=async(name,actor,action,data={})=>(await db.query(`select ${name}($1,$2,$3::jsonb) result`,[actor,action,JSON.stringify(data)])).rows[0].result;
const native=(actor,action,data={})=>rpc('korlix_social_native_push_v1',actor,action,{client_app:'korlix_ai',...data});
const social=(actor,action,data={})=>rpc(action.startsWith('group_')?'korlix_social_groups_v1':action.startsWith('call_')?'korlix_social_calls_v1':['send','messages'].includes(action)?'korlix_social_chat_v1':'korlix_social_v1',actor,action,data);
const online=(actor,action,data={})=>rpc('korlix_social_online_v1',actor,action,data);
const count=async table=>(await db.query(`select count(*)::int n from ${table}`)).rows[0].n;
const sub=(i=1,extra={})=>({device:devices[i],binding:randomUUID(),owner_key:ownerKey(i),subscription:{provider:'fcm',token:'fixture-token:'+randomUUID(),app_id:'com.korlixdeveloper.korlixai',environment:'production'},messages:true,calls:true,online:false,...extra});
const connect=async()=>{await social(users[0],'request',{peer:b.id});await social(users[1],'accept',{peer:a.id});};
const send=async()=>social(users[0],'send',{id:randomUUID(),peer:b.id,body:'Private message text must never appear in a push'});
const claim=async()=>(await native(null,'claim')).items;
const authorize=async item=>(await native(null,'authorize',item)).delivery;
const firstDelivery=async()=>authorize((await claim())[0]);
const group=async()=>{await connect();const id=randomUUID();await social(users[0],'group_create',{group:id,name:'Private group',members:[b.id]});await social(users[1],'group_accept',{group:id});return id;};
const groupSend=async gid=>{const id=randomUUID();await social(users[0],'group_send',{group:gid,id,body:'Private group text'});return id;};
const definitions=async()=>(await db.query("select proname,prosrc from pg_proc where proname in('korlix_social_push_v1','korlix_social_push_allowed','korlix_social_push_enqueue','korlix_social_online_transition') order by proname")).rows;
before(async()=>{
 db=new PGlite();
 await db.exec('create schema auth;create role anon;create role authenticated;create role service_role bypassrls;create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;');
 for(const id of users)await db.query('insert into auth.users(id) values($1)',[id]);
 const folder=new URL('../../supabase/migrations/',import.meta.url),files=await readdir(folder);
 const apply=async suffix=>{const name=files.find(f=>f.endsWith(suffix));assert(name,suffix);await db.exec(await readFile(new URL(name,folder),'utf8'));};
 await apply('_korlix_social.sql');
 await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant all on storage.objects to anon,authenticated;create policy fixture_existing_allow on storage.objects to anon,authenticated using(true) with check(true);");
 for(const suffix of ['profiles_calls','message_replies','groups','attachments','albums','wall_profiles','wall_voice_replies','auto_dump','communication_upgrade','last_login_dump_scope','online_alerts','missed_call_counts','read_receipts'])await apply(`_korlix_social_${suffix}.sql`);
 await db.exec(await readFile(new URL('./fixtures/social_native_push_sessions.sql',import.meta.url),'utf8'));
 webDefinitions=await definitions();await apply('_korlix_social_native_push.sql');
});
beforeEach(async()=>{
 await db.exec('truncate korlix_social_profiles,korlix_social_limits restart identity cascade;');
 const profile=handle=>({handle,name:handle,bio:'Member',color:'cyan',discoverable:true,show_online:true,accepted_rules:true});
 [a,b,c]=await Promise.all(users.map(async(user,i)=>(await social(user,'save_profile',profile(['alice','bruno','chris'][i]))).profile));
});
after(async()=>{await db?.close();});

const messengerRegistration=async(i=1,extra={})=>{
 const session_id=randomUUID();
 await db.query("insert into korlix_receipt_app_sessions(session_id,user_id,client_app,status) values($1,$2,'korlix_messenger','active')",[session_id,users[i]]);
 const registration=sub(i,extra);
 return {...registration,client_app:'korlix_messenger',session_id,subscription:{...registration.subscription,app_id:'com.korlixdeveloper.messenger'}};
};
test('hub and Messenger registrations on the same device are independently scoped',async()=>{
 const hub=sub(),messenger=await messengerRegistration(1,{device:hub.device,binding:hub.binding});
 await native(users[1],'subscribe',hub);await native(users[1],'subscribe',messenger);
 for(const client_app of ['korlix_ai','korlix_messenger'])assert.equal((await native(users[1],'state',{client_app})).subscriptions.length,1);
 await native(users[1],'unsubscribe',hub);
 assert.equal((await native(users[1],'state')).subscriptions.length,0);
 assert.equal((await native(users[1],'state',{client_app:'korlix_messenger'})).subscriptions.length,1);
 await native(users[1],'unsubscribe',messenger);assert.equal(await count('korlix_social_native_push_subscriptions'),0);
});
test('Messenger enrollment rejects missing, foreign, revoked and wrong-app login bindings',async()=>{
 const valid=await messengerRegistration(),foreign=await messengerRegistration(0);
 for(const patch of [{session_id:null},{session_id:foreign.session_id},{client_app:'korlix_ai'},{subscription:sub().subscription}]){
  await assert.rejects(native(users[1],'subscribe',{...valid,...patch}));
 }
 await db.query("update korlix_receipt_app_sessions set status='revoked' where session_id=$1",[valid.session_id]);
 await assert.rejects(native(users[1],'subscribe',valid),{code:'42501'});
 const receipt=await messengerRegistration();await db.query("update korlix_receipt_app_sessions set client_app='receipt_wiz' where session_id=$1",[receipt.session_id]);
 await assert.rejects(native(users[1],'subscribe',receipt),{code:'42501'});
 await assert.rejects(native(users[1],'state',{client_app:null}),{code:'42501'});
});
test('Messenger login revocation cancels queued delivery without changing hub registrations',async()=>{
 await connect();const messenger=await messengerRegistration();await native(users[1],'subscribe',messenger);
 await send();const item=(await claim())[0];
 await db.query("update korlix_receipt_app_sessions set status='revoked' where session_id=$1",[messenger.session_id]);
 assert.equal(await authorize(item),null);
 const hub=sub();await native(users[1],'subscribe',hub);await claim();
 assert.equal((await native(users[1],'state',{client_app:'korlix_messenger'})).subscriptions.length,0);
 assert.equal((await native(users[1],'state')).subscriptions.length,1);
});
test('Messenger authorization includes trusted app scope and the new login replaces old queued work',async()=>{
 await connect();const old=await messengerRegistration();await native(users[1],'subscribe',old);await send();const item=(await claim())[0];
 const replacement=await messengerRegistration(1,{device:old.device});await native(users[1],'subscribe',replacement);
 assert.equal(await authorize(item),null);await send();const payload=await firstDelivery();
 assert.equal(payload.client_app,'korlix_messenger');assert.equal(payload.subscription.app_id,'com.korlixdeveloper.messenger');
 assert.equal(payload.binding,replacement.binding);assert.equal(payload.session_id,undefined);
});

test('native migration is additive and service-only, with RLS and no direct browser permissions',async()=>{
 assert.deepEqual(await definitions(),webDefinitions);
 for(const table of ['korlix_social_native_push_subscriptions','korlix_social_native_push_outbox']){
  assert.equal((await db.query('select relrowsecurity from pg_class where oid=$1::regclass',[table])).rows[0].relrowsecurity,true);
  for(const role of ['anon','authenticated'])assert.equal((await db.query('select has_table_privilege($1,$2,\'select,insert,update,delete\') yes',[role,table])).rows[0].yes,false);
 }
 for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_function_privilege($1,'korlix_social_native_push_v1(uuid,text,jsonb)','execute') yes",[role])).rows[0].yes,false);
 await db.exec('set role authenticated');
 await assert.rejects(native(users[1],'state'),{code:'42501'});await db.exec('reset role');
});
test('enrollment exposes metadata only, partitions accounts, and does not enroll web push',async()=>{
 const registration=sub();await native(users[1],'subscribe',registration);
 const state=await native(users[1],'state');assert.equal(state.subscriptions.length,1);
 assert.equal(state.subscriptions[0].binding,registration.binding);assert.equal(state.subscriptions[0].provider,'fcm');
 assert.equal(state.subscriptions[0].online,false);assert(!JSON.stringify(state).includes(registration.subscription.token));assert(!JSON.stringify(state).includes(ownerKey(1)));
 assert.equal((await native(users[0],'state')).subscriptions.length,0);assert.equal(await count('korlix_social_push_subscriptions'),0);
});
test('SQL validation rejects foreign owner keys, malformed flags and provider tokens',async()=>{
 for(const extra of [{owner_key:ownerKey(0)},{owner_key:'[]'},{owner_key:'null'},{owner_key:JSON.stringify(['http://bad.test',users[1]])},{messages:'true'},{online:null},{binding:null}])await assert.rejects(native(users[1],'subscribe',sub(1,extra)));
 for(const patch of [{provider:'web'},{token:'bad'},{token:'x'.repeat(2049)},{environment:'sandbox'},{app_id:'a'},{app_id:'com.bad app'}]){
  const registration=sub();registration.subscription={...registration.subscription,...patch};await assert.rejects(native(users[1],'subscribe',registration));
 }
 const apple=sub();apple.subscription={provider:'apns',token:'A'.repeat(66),app_id:'com.korlixdeveloper.korlixai',environment:'sandbox'};
 await native(users[1],'subscribe',apple);assert.equal((await db.query('select token from korlix_social_native_push_subscriptions')).rows[0].token,'a'.repeat(66));
});
test('a rotated token invalidates queued claims, increments revision, and stale unsubscribe cannot remove it',async()=>{
 await connect();const previous=sub();await native(users[1],'subscribe',previous);await send();const oldClaim=(await claim())[0];
 const replacement={...sub(),device:previous.device};await native(users[1],'subscribe',replacement);
 assert.equal((await db.query('select revision from korlix_social_native_push_subscriptions')).rows[0].revision,2);
 assert.equal(await authorize(oldClaim),null);await native(users[1],'unsubscribe',previous);assert.equal((await native(users[1],'state')).subscriptions.length,1);
 await native(users[0],'unsubscribe',replacement);assert.equal((await native(users[1],'state')).subscriptions.length,1);
 await native(users[1],'unsubscribe',replacement);assert.equal(await count('korlix_social_native_push_subscriptions'),0);
});
test('stable APNs token account handoff removes old owner registration and queued work atomically',async()=>{
 await connect();const old=sub();old.subscription={provider:'apns',token:'b'.repeat(64),app_id:'com.korlixdeveloper.korlixai',environment:'production'};
 await native(users[1],'subscribe',old);await send();const item=(await claim())[0];
 const next=sub(2,{subscription:old.subscription});await native(users[2],'subscribe',next);
 assert.equal((await native(users[1],'state')).subscriptions.length,0);assert.equal((await native(users[2],'state')).subscriptions.length,1);
 assert.equal(await authorize(item),null);await native(users[1],'unsubscribe',old);assert.equal((await native(users[2],'state')).subscriptions.length,1);
});
test('registration capacity and hourly enrollment rate are bounded',async()=>{
 for(let n=0;n<10;n++)await native(users[1],'subscribe',sub(1,{device:randomUUID()}));
 await assert.rejects(native(users[1],'subscribe',sub(1,{device:randomUUID()})),/old notification device/);
 const registration=sub(2);for(let n=0;n<30;n++)await native(users[2],'subscribe',registration);
 await assert.rejects(native(users[2],'subscribe',registration));
});
test('direct push uses opaque route identifiers and never includes content or names',async()=>{
 await connect();const registration=sub();await native(users[1],'subscribe',registration);const message=await send();const delivery=await firstDelivery();
 assert.deepEqual({kind:delivery.kind,id:delivery.id,type:delivery.type,event_id:delivery.event_id,owner:delivery.owner,binding:delivery.binding},
  {kind:'peer',id:a.id,type:'message',event_id:message.id,owner:ownerKey(1),binding:registration.binding});
 assert.equal(delivery.silent,false);assert(!JSON.stringify(delivery).includes('Private message'));assert(!JSON.stringify(delivery).includes('alice'));
});
for(const mutation of ['read','dump','deleted','blocked','disconnected','suspended','sender_suspended','preference'])test(`delivery is rechecked after ${mutation}`,async()=>{
 await connect();const registration=sub();await native(users[1],'subscribe',registration);const message=await send();const item=(await claim())[0];
 if(mutation==='read')await db.query('update korlix_social_messages set read_at=now() where id=$1',[message.id]);
 if(mutation==='dump')await db.query("insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at)values($1,'direct',$2,now()-interval '1 second')",[b.id,message.id]);
 if(mutation==='deleted')await db.query('update korlix_social_messages set deleted=true where id=$1',[message.id]);
 if(mutation==='blocked')await social(users[1],'block',{peer:a.id});
 if(mutation==='disconnected')await db.exec('delete from korlix_social_connections');
 if(mutation==='suspended'||mutation==='sender_suspended')await db.query('update korlix_social_profiles set suspended=true where id=$1',[mutation==='suspended'?b.id:a.id]);
 if(mutation==='preference')await db.exec('update korlix_social_native_push_subscriptions set messages=false');
 assert.equal(await authorize(item),null);
});
test('suspended accounts can still revoke a matching binding',async()=>{
 const registration=sub();await native(users[1],'subscribe',registration);await db.query('update korlix_social_profiles set suspended=true where id=$1',[b.id]);
 await assert.rejects(native(users[1],'state'),{code:'42501'});await native(users[1],'unsubscribe',registration);assert.equal(await count('korlix_social_native_push_subscriptions'),0);
});
test('calls take priority and stop being deliverable once answered',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();
 const call=(await social(users[0],'call_start',{id:randomUUID(),peer:b.id,mode:'audio',device:devices[0],protocol:2})).call;
 const jobs=await claim();const first=(await db.query('select kind,event_id from korlix_social_native_push_outbox where id=$1',[jobs[0].id])).rows[0];assert.equal(first.kind,'call');assert.equal(first.event_id,call.id);
 await social(users[1],'call_accept',{id:call.id,device:devices[1],protocol:2});assert.equal(await authorize(jobs[0]),null);
});
test('group routing remains per group and explicit read receipts cancel queued delivery',async()=>{
 const gid=await group();await native(users[1],'subscribe',sub());const first=await groupSend(gid);
 const delivery=await firstDelivery();assert.equal(delivery.kind,'group');assert.equal(delivery.id,gid);assert.equal(delivery.event_id,first);
 const second=await groupSend(gid);const item=(await claim())[0];
 await rpc('korlix_social_receipts_v1',users[1],'group_read',{group:gid,ids:[second]});assert.equal(await authorize(item),null);
});
for(const mutation of ['removed','archived','dumped','sender_left'])test(`group delivery is cancelled after ${mutation}`,async()=>{
 const gid=await group();await native(users[1],'subscribe',sub());const id=await groupSend(gid);const item=(await claim())[0];
 if(mutation==='removed')await db.query("update korlix_social_group_members set state='removed' where group_id=$1 and member=$2",[gid,b.id]);
 if(mutation==='archived')await db.query('update korlix_social_groups set archived=true where id=$1',[gid]);
 if(mutation==='dumped')await db.query("insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at)values($1,'group',$2,now()-interval '1 second')",[b.id,id]);
 if(mutation==='sender_left')await db.query("update korlix_social_group_members set state='left' where group_id=$1 and member=$2",[gid,a.id]);
 assert.equal(await authorize(item),null);
});
test('online alerts enqueue on both insert and upsert without replacing the web transition',async()=>{
 await connect();await native(users[1],'subscribe',sub(1,{online:true}));
 await online(users[1],'online_watch_set',{peer:a.id,enabled:true,sound:'silent'});await social(users[0],'presence',{active:true});
 const first=await firstDelivery();assert.equal(first.type,'online');assert.equal(first.silent,true);assert.equal(first.id,a.id);
 // Exercise the UPDATE branch directly with an active watch and still-online target.
 await db.query('update korlix_social_online_events set id=gen_random_uuid(),created_at=now(),expires_at=now()+interval \'90 seconds\' where watcher=$1 and target=$2',[b.id,a.id]);
 const second=await firstDelivery();assert.notEqual(second.event_id,first.event_id);
 await db.query('update korlix_social_online_events set id=gen_random_uuid() where watcher=$1 and target=$2',[b.id,a.id]);const item=(await claim())[0];
 await online(users[1],'online_watch_set',{peer:a.id,enabled:false,sound:'silent'});assert.equal(await authorize(item),null);
 assert.deepEqual(await definitions(),webDefinitions);
});
test('no watch and preference off never produce online notifications',async()=>{
 await connect();await native(users[1],'subscribe',sub());await online(users[1],'online_watch_set',{peer:a.id,enabled:true,sound:'bell'});await social(users[0],'presence',{active:true});
 assert.equal(await count('korlix_social_native_push_outbox'),0);
});
test('worker endpoints reject actors, stale leases and duplicate authorization',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();
 await assert.rejects(native(users[1],'claim'),{code:'42501'});const item=(await claim())[0];
 assert.equal(await authorize({...item,lease:randomUUID()}),null);assert(await authorize(item));assert.equal(await authorize(item),null);
 await native(null,'finish',{...item,status:'accepted'});await native(null,'finish',{...item,status:'retry'});
 assert.equal((await db.query('select status from korlix_social_native_push_outbox')).rows[0].status,'accepted');
});
test('crashed claims are reclaimable but a crashed sender is never replayed',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();const first=(await claim())[0];
 await db.exec("update korlix_social_native_push_outbox set lease_until=now()-interval '1 second'");const second=(await claim())[0];assert.notEqual(second.lease,first.lease);
 assert.equal(await authorize(first),null);assert(await authorize(second));
 await db.exec("update korlix_social_native_push_outbox set lease_until=now()-interval '1 second'");assert.equal((await claim()).length,0);
 assert.equal((await db.query('select status from korlix_social_native_push_outbox')).rows[0].status,'unknown');
});
test('invalid provider tokens are removed but stale finish cannot delete a replacement',async()=>{
 await connect();const registration=sub();await native(users[1],'subscribe',registration);await send();const item=(await claim())[0];await authorize(item);
 await native(users[1],'subscribe',sub());await native(null,'finish',{...item,status:'expired'});assert.equal(await count('korlix_social_native_push_subscriptions'),1);
 await send();const next=(await claim())[0];await authorize(next);await native(null,'finish',{...next,status:'expired'});assert.equal(await count('korlix_social_native_push_subscriptions'),0);
});
test('retry ceiling, expiry and stale subscriptions bound notification work',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();
 for(let n=0;n<3;n++){const item=(await claim())[0];assert(await authorize(item));await native(null,'finish',{...item,status:'retry'});await db.exec("update korlix_social_native_push_outbox set next_attempt=now()-interval '1 second'");}
 assert.equal((await claim()).length,0);assert.equal((await db.query('select status from korlix_social_native_push_outbox')).rows[0].status,'failed');
 await send();await db.exec("update korlix_social_native_push_outbox set expires_at=now()-interval '1 second' where status='pending'");assert.equal((await claim()).length,0);
 await db.exec("update korlix_social_native_push_subscriptions set updated_at=now()-interval '91 days'");await claim();assert.equal(await count('korlix_social_native_push_subscriptions'),0);
});
test('service role can enroll and unsubscribe without exposing device secrets',async()=>{
 const registration=sub();await db.exec('set role service_role');
 try{await native(users[1],'subscribe',registration);assert.equal((await native(users[1],'state')).subscriptions.length,1);await native(users[1],'unsubscribe',registration);}
 finally{await db.exec('reset role');}
});
test('coalescing preserves two separate group conversations and keeps only each latest burst',async()=>{
 const first=await group(),second=randomUUID();await social(users[0],'group_create',{group:second,name:'Other group',members:[b.id]});await social(users[1],'group_accept',{group:second});
 await native(users[1],'subscribe',sub());await groupSend(first);const other=await groupSend(second);const latest=await groupSend(first);
 const jobs=await claim();assert.equal(jobs.length,2);const deliveries=await Promise.all(jobs.map(authorize));
 assert.deepEqual(new Set(deliveries.map(x=>x.event_id)),new Set([other,latest]));assert.deepEqual(new Set(deliveries.map(x=>x.id)),new Set([first,second]));
});
test('a raced registration foreign-key revocation cancels only the alert, never its chat write',async()=>{
 await connect();await native(users[1],'subscribe',sub());
 await db.exec("create function native_push_fixture_revoked() returns trigger language plpgsql as $$ begin raise exception 'Device removed during enqueue' using errcode='23503';end $$;create trigger native_push_fixture_revoked before insert on korlix_social_native_push_outbox for each row execute function native_push_fixture_revoked();");
 try{const message=await send();assert(message.id);assert.equal(await count('korlix_social_messages'),1);assert.equal(await count('korlix_social_native_push_outbox'),0);}
 finally{await db.exec('drop trigger native_push_fixture_revoked on korlix_social_native_push_outbox;drop function native_push_fixture_revoked();');}
});
test('native enqueue does not swallow unrelated permission errors',async()=>{
 await connect();await native(users[1],'subscribe',sub());
 await db.exec("create function native_push_fixture_denied() returns trigger language plpgsql as $$ begin raise exception 'Unexpected permission failure' using errcode='42501';end $$;create trigger native_push_fixture_denied before insert on korlix_social_native_push_outbox for each row execute function native_push_fixture_denied();");
 try{await assert.rejects(send(),{code:'42501'});assert.equal(await count('korlix_social_messages'),0);}
 finally{await db.exec('drop trigger native_push_fixture_denied on korlix_social_native_push_outbox;drop function native_push_fixture_denied();');}
});
test('native retries respect provider Retry-After and exponential minimum delays',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();
 const first=(await claim())[0];await authorize(first);await native(null,'finish',{...first,status:'retry',retry_after_seconds:120});
 let row=(await db.query('select status,extract(epoch from next_attempt-now())::float8 delay from korlix_social_native_push_outbox where id=$1',[first.id])).rows[0];
 assert.equal(row.status,'retry');assert(row.delay>119&&row.delay<=120);assert.equal((await claim()).length,0);
 await db.exec("update korlix_social_native_push_outbox set next_attempt=now()-interval '1 second'");
 const second=(await claim())[0];await authorize(second);await native(null,'finish',{...second,status:'retry',retry_after_seconds:1});
 row=(await db.query('select status,extract(epoch from next_attempt-now())::float8 delay from korlix_social_native_push_outbox where id=$1',[second.id])).rows[0];
 assert.equal(row.status,'retry');assert(row.delay>119&&row.delay<=120);
});
test('native retry default is at least one minute and requests beyond event expiry fail',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();const first=(await claim())[0];await authorize(first);
 await native(null,'finish',{...first,status:'retry'});
 const row=(await db.query('select extract(epoch from next_attempt-now())::float8 delay from korlix_social_native_push_outbox where id=$1',[first.id])).rows[0];
 assert(row.delay>59&&row.delay<=60);
 await send();const short=(await claim())[0];await authorize(short);await db.query("update korlix_social_native_push_outbox set expires_at=now()+interval '30 seconds' where id=$1",[short.id]);
 await native(null,'finish',{...short,status:'retry',retry_after_seconds:120});
 assert.equal((await db.query('select status from korlix_social_native_push_outbox where id=$1',[short.id])).rows[0].status,'failed');
});
test('native retry delays reject negative, fractional and non-numeric values and cap at one day',async()=>{
 await connect();await native(users[1],'subscribe',sub());await send();const item=(await claim())[0];await authorize(item);
 for(const retry_after_seconds of [-1,1.5,'120','bad',null,{},true])await assert.rejects(native(null,'finish',{...item,status:'retry',retry_after_seconds}),/Invalid notification retry delay/);
 assert.equal((await db.query('select status from korlix_social_native_push_outbox where id=$1',[item.id])).rows[0].status,'sending');
 await db.query("update korlix_social_native_push_outbox set expires_at=now()+interval '2 days' where id=$1",[item.id]);
 await native(null,'finish',{...item,status:'retry',retry_after_seconds:100000});
 const row=(await db.query('select extract(epoch from next_attempt-now())::float8 delay from korlix_social_native_push_outbox where id=$1',[item.id])).rows[0];
 assert(row.delay>86399&&row.delay<=86400);
});
