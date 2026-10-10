import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {settings} from '../receptionist/core.mjs';
import {hash,secret,booking} from '../scheduling/core.mjs';
import {receptionistBooking} from '../receptionist/booking.mjs';

let db;const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),admin=randomUUID();
const migration='20261010025335_business_passport_receptionist.sql';
const limits={tier:'enterprise',monthlySessions:100,monthlySeconds:72000,monthlyTokens:20000000};
const rpc=async(actor,action,id=null,p={},isAdmin=false)=>(await db.query('select korlix_receptionist_command($1,$2,$3,$4,$5) r',[actor,isAdmin,action,id,p])).rows[0].r;
const schedule=async(actor,action,id=null,data={})=>(await db.query('select korlix_schedule_owner_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const pub=async(action,slug,data)=>(await db.query('select korlix_schedule_public_v1($1,$2,$3) r',[action,slug,data])).rows[0].r;
const config=(extra={})=>settings({version:0,enabled:true,processing_consent:true,voice:'coral',monthly_minutes:120,max_call_minutes:5,knowledge:'Office open weekdays.',...extra});
async function business(actor=owner){const id=randomUUID();await db.query("insert into korlix_directory_businesses(id,owner_id,slug,draft,published,state) values($1,$2,$3,$4,$4,'published')",[id,actor,'fixture-'+id,{name:'Fixture Service',description:'Fixture services',email:'fixture@example.test',city:'Kingston',category:'Other'}]);return id;}
async function line(id){const provider=randomUUID();await rpc(admin,'bind_line',id,{provider_id:provider,number:'+1555'+String(Math.floor(Math.random()*1e7)).padStart(7,'0')},true);return provider;}
async function start(id,phone){return rpc(null,'start',id,{provider_id:phone,caller_number:'+15550102030',limits,remaining_seconds:72000});}
test.before(async()=>{
  db=new PGlite();await db.exec("create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,is_anonymous boolean);create table public.user_profiles(id uuid primary key,tier text,is_disabled boolean);create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);grant usage on schema public,auth to service_role,anon,authenticated;grant all on auth.users,user_profiles to service_role;");
  for(const file of ['202607120001_live_convo_limits_build129.sql','20260930152919_scheduling_engine.sql','20260930163605_scheduling_connected.sql','20261002184255_business_directory_verified_membership.sql',migration])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  await db.exec('set role service_role');
  for(const id of [owner,other,basic,admin]){await db.query('insert into auth.users values($1,now(),false)',[id]);await db.query('insert into user_profiles values($1,$2,false)',[id,id===basic?'basic':'enterprise']);}
});
test.after(async()=>db?.close());
test('free profiles do not grant a receptionist; ownership and client role boundaries are enforced',async()=>{
  const id=await business(),free=await business(basic);
  await assert.rejects(rpc(other,'get',id),/REC403/);
  await assert.rejects(rpc(basic,'get',free),/REC402/);
  await assert.rejects(rpc(basic,'save',free,config()),/REC402/);
  await assert.rejects(rpc(owner,'bind_line',id,{provider_id:'fake',number:'+15550123'}),/REC403/);
  await db.exec('reset role');
  const rows=(await db.query("select proname,prosecdef,has_function_privilege('anon',oid,'execute') anon,has_function_privilege('authenticated',oid,'execute') authed from pg_proc where proname like 'korlix_receptionist_%' ")).rows;
  assert.equal(rows.length,2);for(const r of rows){assert.equal(r.prosecdef,false);assert.equal(r.anon,false);assert.equal(r.authed,false);}
  for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(db.query('select * from korlix_receptionist_calls'),/permission denied/);await assert.rejects(rpc(owner,'get',id),/permission denied/);await db.exec('reset role');}
  await db.exec('set role service_role');
});
test('settings require publication and consent; edits reject stale versions and foreign events',async()=>{
  const id=await business();await rpc(owner,'save',id,config());
  const saved=await rpc(owner,'get',id);assert.equal(saved.version,1);assert(saved.consent_at);assert.equal(saved.settings.enabled,true);
  await assert.rejects(rpc(owner,'save',id,config()),/REC409/);
  await assert.rejects(rpc(owner,'save',id,config({version:1,booking_enabled:true,event_ids:[randomUUID()]})),/REC409/);
  await db.query("update korlix_directory_businesses set state='hidden',published=null where id=$1",[id]);
  await assert.rejects(rpc(owner,'save',id,config({version:1})),/REC409/);
  await rpc(owner,'pause',id);assert.equal((await rpc(owner,'get',id)).settings.enabled,false);
});
test('provider retries reserve once; calls and inboxes stay isolated; end reports meter once',async()=>{
  const id=await business(),phone=await line(id),call=randomUUID();await rpc(owner,'save',id,config());
  const before=(await db.query('select coalesce(sum(session_count),0)::integer n from korlix_live_convo_monthly_usage where user_id=$1',[owner])).rows[0].n;
  await start(call,phone);await start(call,phone);
  assert.equal((await db.query('select session_count from korlix_live_convo_monthly_usage where user_id=$1',[owner])).rows[0].session_count,before+1);
  await assert.rejects(start(randomUUID(),phone),/REC409/);
  const lease=randomUUID();await rpc(null,'claim',call,{lease});await assert.rejects(rpc(null,'claim',call,{lease:randomUUID()}),/REC409/);
  await assert.rejects(rpc(null,'note',call,{lease:randomUUID(),note:{message:'wrong turn'}}),/REC409/);
  await rpc(null,'note',call,{lease,note:{name:'Fixture caller',message:'Please call back'}});
  await rpc(null,'finish',call,{lease,reply:'Your message was saved.',input:20,output:10});
  await rpc(null,'end',call,{seconds:42,reason:'ended'});await rpc(null,'end',call,{seconds:200,reason:'duplicate'});
  const data=await rpc(owner,'get',id);assert.equal(data.calls[0].duration_seconds,42);assert.equal(data.calls[0].note.message,'Please call back');assert.equal(data.calls[0].snapshot,undefined);assert.equal(data.calls[0].limits,undefined);
  await assert.rejects(rpc(other,'handled',id,{call_id:call}),/REC403/);
  await rpc(owner,'handled',id,{call_id:call});assert((await rpc(owner,'get',id)).calls[0].handled_at);
});
test('downgrade stops calls immediately while pause remains available',async()=>{
  const id=await business(other),phone=await line(id);await rpc(other,'save',id,config());const call=randomUUID();await start(call,phone);
  await db.query("update user_profiles set tier='ultra' where id=$1",[other]);
  await assert.rejects(rpc(null,'claim',call,{lease:randomUUID()}),/REC402/);
  await assert.rejects(start(randomUUID(),phone),/REC402/);
  await rpc(other,'pause',id);await rpc(null,'end',call,{seconds:3});await db.query("update user_profiles set tier='enterprise' where id=$1",[other]);
});
test('a response completing after hangup or pause is metered once without delivering stale speech',async()=>{
  for(const stop of ['end','pause']){
    const id=await business(),phone=await line(id),call=randomUUID(),lease=randomUUID();
    await rpc(owner,'save',id,config());await start(call,phone);await rpc(null,'claim',call,{lease});
    if(stop==='end')await rpc(null,'end',call,{seconds:8});else await rpc(owner,'pause',id);
    const result=await rpc(null,'finish',call,{lease,reply:'A late answer.',input:123,output:45});
    assert.equal(result.deliver,false);
    const c=await rpc(null,'call_get',call);assert.equal(c.input_tokens,123);assert.equal(c.output_tokens,45);assert.equal(c.last_response,null);
    if(stop==='end')assert.equal(c.duration_seconds,8);
    const usage=(await db.query('select input_tokens,output_tokens from korlix_live_convo_sessions where id=$1',[call])).rows[0];assert.equal(Number(usage.input_tokens),123);assert.equal(Number(usage.output_tokens),45);
    await assert.rejects(rpc(null,'finish',call,{lease,input:123,output:45}),/REC409/);
    await rpc(null,'end',call,{seconds:8});
  }
});
test('phone quota, missing end reconciliation and retention prevent unbounded calls or caller storage',async()=>{
  const id=await business(),phone=await line(id);await rpc(owner,'save',id,config({monthly_minutes:1,max_call_minutes:1}));const call=randomUUID();await start(call,phone);
  await db.query("update korlix_receptionist_calls set started_at=now()-interval '5 minutes',caller_number='+15550102030' where id=$1",[call]);
  await rpc(null,'cleanup');assert.equal((await rpc(null,'call_get',call)).duration_seconds,60);
  await assert.rejects(start(randomUUID(),phone),/REC429/);
  await db.query("update korlix_receptionist_calls set started_at=now()-interval '91 days' where id=$1",[call]);await rpc(null,'cleanup');
  const cleared=await rpc(null,'call_get',call);assert.deepEqual(cleared.snapshot,{});assert.equal(cleared.caller_number,'');assert.equal((await rpc(owner,'get',id)).calls.length,0);
});
test('a real 2MEETU booking requires the readback and confirmation and cannot be repeated',async()=>{
  const weekly=Array.from({length:7},(_,day)=>({day,windows:[[540,1020]]}));
  await schedule(owner,'save_profile',null,{revision:0,display_name:'Fixture Host',timezone:'UTC',weekly,overrides:[]});
  let event=await schedule(owner,'save_event',null,{revision:0,title:'Service consultation',slug:'test-'+secret().slice(0,16),description:'Discuss work',kind:'one_to_one',duration_minutes:30,interval_minutes:30,buffer_before:0,buffer_after:0,notice_minutes:0,horizon_days:365,daily_limit:8,capacity:1,cancel_notice_minutes:0,location_kind:'phone',location_detail:'Business calls guest',questions:[],color:'#117788',routing_mode:'single',host_ids:[],price_cents:0,currency:'USD',refund_policy:'Contact the business to discuss changes.'});
  event=await schedule(owner,'event_state',event.id,{revision:event.revision,state:'published',confirmed:true});
  const id=await business(),phone=await line(id);await rpc(owner,'save',id,config({booking_enabled:true,event_ids:[event.id]}));const call=randomUUID();await start(call,phone);
  const context={token_hash:hash(secret()),browser_hash:hash(secret())};await pub('context',event.slug,context);
  const slots=await pub('slots',event.slug,{...context,date:new Date(Date.now()+3*86400000).toISOString().slice(0,10)});assert(slots.slots.length);
  const data={...booking({request_id:randomUUID(),manage_token:secret(),starts_at:slots.slots[0].starts_at,guest_name:'Fixture Guest',guest_email:'guest@example.test',guest_timezone:'UTC',answers:{},confirmed:true}),...context,payments_ready:false};
  const pending={data,event_id:event.id,slug:event.slug,event_title:event.title,timezone:'UTC',readback:'Readback fixture: confirm booking.',expires_at:new Date(Date.now()+180000).toISOString()};
  let lease=randomUUID();await rpc(null,'claim',call,{lease});await rpc(null,'pending',call,{lease,pending});
  await assert.rejects(rpc(null,'confirm',call,{lease,confirmed:true}),/REC409/);
  await rpc(null,'finish',call,{lease,reply:pending.readback});lease=randomUUID();await rpc(null,'claim',call,{lease});
  await assert.rejects(rpc(null,'confirm',call,{lease,confirmed:false}),/REC409/);
  const booked=await rpc(null,'confirm',call,{lease,confirmed:true});assert.equal(booked.state,'confirmed');assert.equal(booked.guest_name,'Fixture Guest');
  assert.equal((await rpc(null,'confirm',call,{lease,confirmed:true})).id,booked.id);
  assert.equal((await db.query('select count(*)::integer n from korlix_schedule_bookings where request_id=$1',[data.request_id])).rows[0].n,1);
  assert.equal(booked.manage_hash,undefined);await rpc(null,'end',call,{seconds:20});
});
test('the phone booking bridge refreshes real slots, previews safely and confirms only after explicit consent',async()=>{
  const event={...(await db.query("select * from korlix_schedule_events where owner_id=$1 and state='published' limit 1",[owner])).rows[0],timezone:'UTC'};
  const id=await business(),phone=await line(id);await rpc(owner,'save',id,config({booking_enabled:true,event_ids:[event.id]}));
  const call=randomUUID();await start(call,phone);let refreshes=0;
  const bridge=receptionistBooking({scheduling:{publicCall:pub,connected:{checkAvailability:async()=>{refreshes++;}},notifications:{seal:()=> 'test-sealed-credential'}},command:rpc});
  const date=new Date(Date.now()+4*86400000).toISOString().slice(0,10);
  const found=await bridge.apply({plan:{action:'find_slots',event_id:event.id,date},eventList:[event]});assert(found.slots.length);
  const plan={action:'prepare_booking',event_id:event.id,starts_at:found.slots[0].starts_at,guest_name:'Bridge Guest',guest_email:'bridge@example.test',guest_timezone:'UTC',answers:[]};
  const preview=await bridge.apply({plan,call:await rpc(null,'call_get',call),eventList:[event],preview:true});assert.match(preview.reply,/Preview only/);assert.equal((await rpc(null,'call_get',call)).pending,null);
  let lease=randomUUID();let c=await rpc(null,'claim',call,{lease});
  const prepared=await bridge.apply({plan,call:c,eventList:[event],lease});assert.match(prepared.reply,/Bridge Guest/);
  await rpc(null,'finish',call,{lease,reply:prepared.reply});lease=randomUUID();c=await rpc(null,'claim',call,{lease});
  const rejected=await bridge.apply({plan:{action:'confirm_booking'},call:c,eventList:[event],lease,lastUser:'I am not sure'});assert.equal(rejected.booking,undefined);
  const result=await bridge.apply({plan:{action:'confirm_booking'},call:c,eventList:[event],lease,lastUser:'Yes, confirm booking.'});assert.equal(result.booking.state,'confirmed');assert.equal(result.booking.guest_name,'Bridge Guest');assert.match(result.reply,/is confirmed/);assert.equal(result.booking.manage_hash,undefined);
  assert.equal(refreshes,4);await rpc(null,'end',call,{seconds:30});
});
