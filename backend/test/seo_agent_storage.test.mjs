import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSeoAgent} from '../seo_agent/routes.mjs';
import {createSeoRunner} from '../seo_agent/runner.mjs';
import {SeoError} from '../seo_agent/core.mjs';

let db,owner,other,usage,server,base,registration,database,allowed=true,scanCalls=0,gate,failScan=false,reservedCalls=0;
const profile={businessName:'Bright Pine',website:'https://brightpine.example.com/',services:'Office cleaning',market:'Columbus',facts:'Evening cleaning.'};
const result={summary:'Measured page sample.',score:80,coverage:{pagesScanned:1},pages:[{url:profile.website}],findings:[],ai:{summary:'Clarify services.',actions:[{id:'action-1',title:'Clarify services'}],drafts:[{body:'Draft'}]}};
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_seo_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const due=async()=>(await db.query('select public.korlix_seo_due_v1() r')).rows[0].r;
const enqueue=(id=randomUUID(),extra={},actor=owner)=>rpc('enqueue',id,{source:'manual',consent:true,usage_id:usage,credit_limit:30,request_limit:10,...extra},actor);
const claim=(id,token=randomUUID(),actor=owner)=>rpc('claim',id,{lease_token:token},actor);
const credits=async()=>(await db.query('select credits_used,standard_generations from usage_counters where id=$1',[usage])).rows[0];
const fixture=async(id=owner)=>rpc('profile_save',null,profile,id);
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){
 const response=await fetch(base+path,{method,headers:{Authorization:actor||'','Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 const data=await response.json();assert.equal(response.status,status,JSON.stringify(data));assert.equal(response.headers.get('cache-control'),'no-store');return data;
}
async function waitRun(id){for(let i=0;i<200;i++){const r=await rpc('get',id);if(['completed','failed'].includes(r.state))return r;await new Promise(r=>setTimeout(r,5));}throw Error('Run did not finish');}
const access=async(user,{reserved=false}={})=>{
 if(reserved)reservedCalls++;
 const entry=(await db.query('select id from usage_counters where user_id=$1',[user.id])).rows[0];
 return {allowed,status:403,reason:'Upgrade required',usageId:entry?.id,creditLimit:30,requestLimit:10};
};
test.before(async()=>{
 db=new PGlite();
 await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table public.user_profiles(id uuid primary key references auth.users(id) on delete cascade,tier text);create table public.usage_counters(id uuid primary key,user_id uuid references auth.users(id) on delete cascade,credits_used integer default 0,standard_generations integer default 0,live_search_generations integer default 0,pdf_generations integer default 0,updated_at timestamptz default now());grant all on public.user_profiles,public.usage_counters to service_role;grant usage on schema auth to service_role;grant select on auth.users to service_role;');
 await db.exec(await readFile(new URL('../../supabase/migrations/20260930204327_seo_agent.sql',import.meta.url),'utf8'));
 database={rpc:async(name,p)=>{try{return {data:name==='korlix_seo_due_v1'?await due():await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){return {error};}},auth:{admin:{getUserById:async id=>({data:{user:(await db.query('select id from auth.users where id=$1',[id])).rows[0]}})}}};
 const app=express();app.use(express.json());
 registration=registerSeoAgent(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,aiAccess:access,
  scan:async({onPhase,signal})=>{scanCalls++;await onPhase('Inspecting page evidence');if(gate)await gate;signal.throwIfAborted();if(failScan)throw Error('provider offline');return result;},logger:{warn(){}}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/seo-agent';
});
test.beforeEach(async()=>{
 await registration.runner.idle();await db.exec('reset role;delete from auth.users');
 owner=randomUUID();other=randomUUID();usage=randomUUID();
 for(const id of [owner,other]){await db.query('insert into auth.users values($1)',[id]);await db.query("insert into user_profiles values($1,'ultra')",[id]);}
 await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);
 await db.query('insert into usage_counters(id,user_id) values($1,$2)',[randomUUID(),other]);
 await db.exec('set role service_role');allowed=true;scanCalls=0;gate=null;failScan=false;reservedCalls=0;
});
test.after(async()=>{registration.stop();await registration.runner.idle();await new Promise(r=>server.close(r));await db.close();});

test('private setup, reports and mutation IDs are scoped to authenticated owner',async()=>{
 await api('',null,'GET','',401);await api('/profile',{...profile,user_id:other},'PUT');
 assert.equal((await api()).profile.data.website,profile.website);assert.equal((await api('',null,'GET',other)).profile,null);
 const run=await enqueue();await api('/runs/'+run.id,null,'GET',other,404);
 await assert.rejects(rpc('claim',run.id,{lease_token:randomUUID()},other),/not found/);
 await db.exec('reset role;set role authenticated');
 await assert.rejects(db.query('select * from korlix_seo_profiles'),/permission denied/);
 await assert.rejects(rpc('list'),/permission denied/);await assert.rejects(due(),/permission denied/);
 await db.exec('reset role;set role service_role');
 const tables=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_seo_profiles','korlix_seo_runs')")).rows;
 assert.equal(tables.length,2);assert(tables.every(r=>r.relrowsecurity));
});

test('manual enqueue reserves once and atomically enforces available credits and request cap',async()=>{
 await fixture();const id=randomUUID();await enqueue(id);assert.equal((await enqueue(id)).replayed,true);
 assert.deepEqual(await credits(),{credits_used:3,standard_generations:1});await assert.rejects(enqueue(),/already queued/);
 await rpc('fail',id,{error:'failed'});await rpc('fail',id,{error:'again'});assert.deepEqual(await credits(),{credits_used:0,standard_generations:0});
 await assert.rejects(enqueue(randomUUID(),{credit_limit:2}),/allowance/);
 await assert.rejects(enqueue(randomUUID(),{request_limit:0}),/allowance/);
 assert.deepEqual(await credits(),{credits_used:0,standard_generations:0});
});

test('deleted run keys and cleared history cannot erase recent attempt receipts',async()=>{
 await fixture();const run=await enqueue();await rpc('fail',run.id);await rpc('remove',run.id,{confirmed:true});
 await assert.rejects(enqueue(run.id),/already used/);
 for(let i=0;i<2;i++){const r=await enqueue();await rpc('fail',r.id);await rpc('remove',r.id,{confirmed:true});}
 await rpc('clear',null,{confirmed:true});await fixture();await assert.rejects(enqueue(),/Please wait/);
 assert.equal((await credits()).credits_used,0);
});

test('claims are exclusive and only the current lease can finish or refund',async()=>{
 await fixture();const run=await enqueue(),lease=randomUUID();await claim(run.id,lease);
 await assert.rejects(claim(run.id),/already claimed/);
 await assert.rejects(rpc('finish',run.id,{lease_token:randomUUID(),result}),/lease changed/);
 await assert.rejects(rpc('fail',run.id,{error:'bad'}),/lease changed/);
 await rpc('finish',run.id,{lease_token:lease,result});await rpc('finish',run.id,{lease_token:lease,result});
 assert.equal((await rpc('get',run.id)).state,'completed');assert.equal((await credits()).credits_used,3);
});

test('expired lease refunds once and stale successful completion cannot overwrite failure',async()=>{
 await fixture();const run=await enqueue(),lease=randomUUID();await claim(run.id,lease);
 await db.query("update korlix_seo_runs set lease_until=now()-interval '1 second' where id=$1",[run.id]);
 assert((await due()).runs.some(r=>r.id===run.id));await rpc('recover');await rpc('recover');
 assert.equal((await rpc('finish',run.id,{lease_token:lease,result})).state,'failed');assert.deepEqual(await credits(),{credits_used:0,standard_generations:0});
});

test('weekly consent, due time and atomic advancement prevent overlapping scheduler duplicates',async()=>{
 await fixture();await assert.rejects(rpc('monitoring',null,{enabled:true}),/Confirm weekly/);
 const saved=await rpc('monitoring',null,{enabled:true,consent:true});assert(saved.monitoring_enabled);assert(Date.parse(saved.next_run_at)>Date.now()+6*86400000);
 await assert.rejects(enqueue(randomUUID(),{source:'weekly'}),/not due/);
 await db.query("update korlix_seo_profiles set next_run_at=now()-interval '1 minute' where user_id=$1",[owner]);
 const attempts=await Promise.allSettled([enqueue(randomUUID(),{source:'weekly'}),enqueue(randomUUID(),{source:'weekly'})]);
 assert.equal(attempts.filter(v=>v.status==='fulfilled').length,1);assert.equal((await credits()).credits_used,3);
 const p=(await rpc('list')).profile;assert(Date.parse(p.next_run_at)>Date.now()+6*86400000);assert.equal((await due()).profiles.length,0);
});

test('pausing monitoring or changing website cancels unstarted weekly work and returns its reservation',async()=>{
 await fixture();await rpc('monitoring',null,{enabled:true,consent:true});
 await db.query("update korlix_seo_profiles set next_run_at=now()-interval '1 minute' where user_id=$1",[owner]);
 const run=await enqueue(randomUUID(),{source:'weekly'});await rpc('profile_save',null,{...profile,website:'https://new.example.com/'});
 const state=await rpc('list');assert.equal(state.profile.monitoring_enabled,false);assert.match(state.profile.pause_reason,/Website changed/);
 assert.equal((await rpc('get',run.id)).state,'failed');assert.equal((await credits()).credits_used,0);
 await rpc('monitoring',null,{enabled:true,consent:true});await db.query("update korlix_seo_profiles set next_run_at=now()-interval '1 minute' where user_id=$1",[owner]);
 const next=await enqueue(randomUUID(),{source:'weekly'});await rpc('monitoring',null,{enabled:false});
 assert.equal((await rpc('get',next.id)).state,'failed');assert.equal((await credits()).credits_used,0);
});

test('tier downgrade blocks enqueue and processing even when browser or earlier access is stale',async()=>{
 await fixture();const run=await enqueue();await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 await assert.rejects(claim(run.id),/Ultra Premium/);await rpc('fail',run.id,{error:'tier changed'});
 await assert.rejects(enqueue(),/Ultra Premium/);await assert.rejects(rpc('monitoring',null,{enabled:true,consent:true}),/Ultra Premium/);
});

test('hourly limit includes failures; clearing queued work refunds but active work cannot be removed',async()=>{
 await fixture();for(let i=0;i<3;i++){const r=await enqueue();await rpc('fail',r.id);}
 await assert.rejects(enqueue(),/Please wait/);await rpc('clear',null,{confirmed:true});
 await fixture();await assert.rejects(enqueue(),/Please wait/);
 await db.query("update korlix_seo_attempts set created_at=now()-interval '2 hours' where user_id=$1",[owner]);
 await fixture();const q=await enqueue();await assert.rejects(rpc('remove',q.id,{confirmed:true}),/Wait/);
 await rpc('clear',null,{confirmed:true});assert.equal((await credits()).credits_used,0);
 await fixture();const r=await enqueue();await claim(r.id);await assert.rejects(rpc('clear',null,{confirmed:true}),/running audit/);
});

test('nested AI action progress is report-owned; history omits large measured and drafted content',async()=>{
 await fixture();const run=await enqueue(),lease=randomUUID();await claim(run.id,lease);await rpc('finish',run.id,{lease_token:lease,result});
 const updated=await api('/runs/'+run.id,{completedActions:['action-1'],notes:'Reviewed.'},'PATCH');
 assert.deepEqual(updated.run.progress.completedActions,['action-1']);await api('/runs/'+run.id,{completedActions:['invented'],notes:''},'PATCH',owner,400);
 const row=(await api()).runs[0];assert.equal(row.result.pages,undefined);assert.equal(row.result.ai.drafts,undefined);assert.equal(row.result.ai.summary,result.ai.summary);
 assert.equal(updated.run.input,undefined);assert.equal(updated.run.usage_id,undefined);assert.equal(updated.run.lease_token,undefined);
});

test('durable queued manual runs resume under a new runner and use reserved access check',async()=>{
 await fixture();const run=await enqueue();
 await registration.runner.tick();await registration.runner.idle();assert.equal((await rpc('get',run.id)).state,'completed');
 await registration.runner.tick();await registration.runner.idle();assert.equal(scanCalls,1);assert(reservedCalls>0);assert.equal((await credits()).credits_used,3);
});

test('two scheduler instances cannot both process a queued audit',async()=>{
 await fixture();const run=await enqueue();let count=0;
 const options={database,call:registration.call,aiAccess:access,scan:async()=>{count++;await new Promise(r=>setTimeout(r,5));return result;},logger:{warn(){}}};
 const first=createSeoRunner(options),second=createSeoRunner(options);
 await Promise.all([first.tick(),second.tick()]);await Promise.all([first.idle(),second.idle()]);
 assert.equal(count,1);assert.equal((await rpc('get',run.id)).state,'completed');assert.equal((await credits()).credits_used,3);
 first.stop();second.stop();
});

test('queued audit is refunded when current worker entitlement is denied',async()=>{
 await fixture();const run=await enqueue();allowed=false;
 await registration.runner.tick();await registration.runner.idle();
 assert.equal((await rpc('get',run.id)).state,'failed');assert.equal(scanCalls,0);assert.equal((await credits()).credits_used,0);
});

test('weekly runner autonomously enqueues due profile and pauses when current access is denied',async()=>{
 await fixture();await rpc('monitoring',null,{enabled:true,consent:true});await db.query("update korlix_seo_profiles set next_run_at=now()-interval '1 minute' where user_id=$1",[owner]);
 await registration.runner.tick();await registration.runner.idle();let state=await rpc('list');assert.equal(state.runs[0].source,'weekly');assert.equal(state.runs[0].state,'completed');
 await db.query("update korlix_seo_profiles set next_run_at=now()-interval '1 minute' where user_id=$1",[owner]);allowed=false;
 await registration.runner.tick();state=await rpc('list');assert.equal(state.profile.monitoring_enabled,false);assert.match(state.profile.pause_reason,/Upgrade/);assert.equal(scanCalls,1);
});

test('failed generation refunds and manual routes enforce consent and idempotency',async()=>{
 await api('/profile',profile,'PUT');await api('/runs',{request_key:randomUUID(),consent:false},'POST',owner,400);
 failScan=true;const id=randomUUID();await api('/runs',{request_key:id,consent:true},'POST',owner,202);
 assert.equal((await waitRun(id)).state,'failed');await api('/runs',{request_key:id,consent:true},'POST',owner,200);
 assert.equal(scanCalls,1);assert.equal((await credits()).credits_used,0);
});

test('worker timeout returns reserved allowance and cannot accept a late result',async()=>{
 await fixture();const run=await enqueue();let release;
 const delayed=new Promise(r=>release=r);
 const runner=createSeoRunner({database,call:registration.call,aiAccess:access,scan:async()=>{await delayed;return result;},timeoutMs:20,logger:{warn(){}}});
 await runner.tick();await runner.idle();assert.equal((await rpc('get',run.id)).state,'failed');assert.equal((await credits()).credits_used,0);
 release();await new Promise(r=>setTimeout(r,5));assert.equal((await rpc('get',run.id)).state,'failed');runner.stop();
});
