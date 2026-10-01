import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

let db;
const config={title:'Customer studio',topic:'Community technology',category:'technology',durationSeconds:900,hostCount:2};
const rpc=async(actor,action,id=null,data={})=>(await db.query('select public.korlix_live_studio_v2($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const save=async owner=>rpc(owner,'save',randomUUID(),{config});
const queue=async(s,data={})=>{
 let pin={};
 if(data.mode==='youtube'){
  const connection=(await db.query("select id,revision from korlix_live_studio_connections where owner_id=$1 and state='connected'",[s.owner_id])).rows[0];
  if(connection)pin={connectionId:connection.id,connectionRevision:connection.revision};
 }
 return rpc(s.owner_id,'queue',s.id,{mode:'rehearsal',requestId:randomUUID(),...pin,...data});
};
const claim=async(owner=null,data={})=>rpc(owner,'claim',null,{mode:'rehearsal',token:randomUUID(),...data});
const stop=async s=>rpc(s.owner_id,'control',s.id,{action:'end',requestId:randomUUID()});
const finish=async s=>rpc(s.owner_id,'finish',s.id,{token:s.worker_token});
const row=async(id)=>(await db.query('select * from korlix_live_studio_runs where id=$1',[id])).rows[0];
async function user({grant=true,limits={}}={}){
 const id=randomUUID();
 await db.query('insert into auth.users(id) values($1)',[id]);
 if(grant){
  await rpc(id,'grant_developer');
  for(const [column,value] of Object.entries(limits)){
   assert(['max_daily_starts','rehearsal_limit','broadcast_seconds_limit','generation_limit'].includes(column));
   await db.query(`update korlix_live_studio_grants set ${column}=$1 where owner_id=$2`,[value,id]);
  }
 }
 return id;
}
async function connection(owner,channel='UC'+randomUUID().replaceAll('-','').slice(0,22)){
 const id=randomUUID();
 await db.query("insert into korlix_live_studio_connections(id,owner_id,channel_id,channel_title,state,revision,sealed_grant,config_hash) values($1,$2,$3,'Customer channel','connected',1,'encrypted fixture',repeat('a',64))",[id,owner,channel]);
 return {id,channel};
}
async function worker(){const id=randomUUID();await rpc(null,'announce',id,{mode:'youtube'});return id;}

test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create schema storage;
 create table auth.users(id uuid primary key,banned_until timestamptz);
 grant usage on schema auth to service_role;
 create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);`);
 const dir=new URL('../../supabase/migrations/',import.meta.url),files=await readdir(dir);
 for(const suffix of ['_live_studio_pilot.sql','_live_studio_customer_workspaces.sql','_live_studio_connections.sql']){
  await db.exec(await readFile(new URL(files.find(f=>f.endsWith(suffix)),dir),'utf8'));
 }

});
test.after(async()=>db?.close());
test.beforeEach(async()=>{await db.exec('reset role;truncate auth.users cascade;truncate korlix_live_studio_workers;');});

test('workspace is denied without a service grant and developer grant never resets an existing allowance',async()=>{
 const owner=await user({grant:false});
 assert.equal((await rpc(owner,'workspace')).entitlement.enabled,false);
 await assert.rejects(queue(await save(owner)),e=>e.code==='42501');
 await rpc(owner,'grant_developer');const first=await rpc(owner,'workspace');
 assert.equal(first.entitlement.enabled,true);assert.equal(first.usage.rehearsalsRemaining,30);
 await db.query("update korlix_live_studio_grants set enabled=false,period_end=now()+interval '1 day',generation_limit=0 where owner_id=$1",[owner]);
 await rpc(owner,'grant_developer');const unchanged=await rpc(owner,'workspace');
 assert.equal(unchanged.entitlement.enabled,false);assert.equal(unchanged.entitlement.generationLimit,0);
 assert.equal(unchanged.entitlement.periodStart,first.entitlement.periodStart);
});

test('two customers can claim independently while each customer has only one executing show',async()=>{
 const a=await user(),b=await user();
 const a1=await queue(await save(a)),a2=await queue(await save(a)),b1=await queue(await save(b));
 const claims=await Promise.all([claim(),claim()]);
 assert.deepEqual(new Set(claims.map(x=>x.owner_id)),new Set([a,b]));
 assert.equal(claims.find(x=>x.owner_id===a).id,a1.id);assert.equal(claims.find(x=>x.owner_id===b).id,b1.id);
 assert.deepEqual(await claim(),{});
 await finish(claims.find(x=>x.owner_id===a));
 assert.equal((await claim()).id,a2.id);
});

test('future schedules do not block due shows from the same or another customer',async()=>{
 const a=await user(),b=await user();
 const future=await queue(await save(a),{scheduledAt:new Date(Date.now()+3600000).toISOString()});
 const dueA=await queue(await save(a)),dueB=await queue(await save(b));
 const claims=[await claim(),await claim()];
 assert.deepEqual(new Set(claims.map(x=>x.id)),new Set([dueA.id,dueB.id]));
 assert.equal((await rpc(a,'get',future.id)).state,'queued');
});

test('customer ownership fences every show action and run receipts survive show deletion',async()=>{
 const a=await user(),b=await user(),s=await queue(await save(a));
 for(const action of ['get','events','delete','queue','heartbeat','finish']){
  await assert.rejects(rpc(b,action,s.id,{token:randomUUID(),mode:'rehearsal',requestId:randomUUID()}),e=>e.code==='P0002');
 }
 await assert.rejects(rpc(b,'save',s.id,{config}),e=>e.code==='P0002');
 assert.equal((await rpc(b,'list')).shows.length,0);
 await stop(s);await rpc(a,'delete',s.id);
 const receipt=await row(s.run_id);assert.equal(receipt.owner_id,a);assert(receipt.released_at);
 assert.equal((await rpc(a,'workspace')).usage.dailyStarts,1);
});

test('queue retry reserves once, changed payload conflicts, and concurrent overreservation is rejected',async()=>{
 const a=await user({limits:{rehearsal_limit:1,generation_limit:10}}),s=await save(a),requestId=randomUUID();
 const data={mode:'rehearsal',requestId};
 await rpc(a,'queue',s.id,data);await rpc(a,'queue',s.id,data);
 assert.equal((await rpc(a,'workspace')).usage.rehearsalsUsed,1);
 await assert.rejects(rpc(a,'queue',s.id,{...data,scheduledAt:new Date(Date.now()+3600000).toISOString()}),e=>e.code==='40001');
 const next=await save(a);await assert.rejects(queue(next),e=>e.code==='54000');
 await stop(await rpc(a,'get',s.id));
 const results=await Promise.allSettled([queue(next),queue(await save(a))]);
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(results.find(x=>x.status==='rejected').reason.code,'54000');
 const usage=(await rpc(a,'workspace')).usage;assert.equal(usage.rehearsalsUsed,1);assert.equal(usage.generationsReserved,10);
});

test('unclaimed cancellation releases period capacity while claimed or uncertain work keeps its full reservation',async()=>{
 const a=await user(),s=await queue(await save(a));
 await stop(s);let usage=(await rpc(a,'workspace')).usage;
 assert.equal(usage.rehearsalsUsed,0);assert.equal(usage.dailyStarts,1);
 const claimed=await claim(a,{}).then(async empty=>{assert.deepEqual(empty,{});await queue(await save(a));return claim(a);});
 await stop(claimed);await finish(claimed);
 usage=(await rpc(a,'workspace')).usage;assert.equal(usage.rehearsalsUsed,1);assert.equal(usage.generationsReserved,10);
 assert.equal((await row(claimed.run_id)).released_at,null);
});

test('dispatch receipts enforce the reserved generation budget exactly once',async()=>{
 const a=await user();await queue(await save(a));const s=await claim(a);
 const first={token:s.worker_token,eventId:randomUUID(),kind:'dispatch',data:{operation:'voice'}};
 await rpc(a,'event',s.id,first);await rpc(a,'event',s.id,first);
 assert.equal((await row(s.run_id)).generations_dispatched,1);
 for(let i=1;i<10;i++)await rpc(a,'event',s.id,{...first,eventId:randomUUID()});
 await assert.rejects(rpc(a,'event',s.id,{...first,eventId:randomUUID()}),e=>e.code==='54000');
 assert.equal((await row(s.run_id)).generations_dispatched,10);
 await assert.rejects(rpc(a,'event',s.id,{...first,data:{operation:'changed'}}),e=>e.code==='40001');
});

test('wrong or expired tokens cannot write, and cancellation holds the customer slot until cleanup',async()=>{
 const a=await user();await queue(await save(a));const s=await claim(a),next=await queue(await save(a));
 await assert.rejects(rpc(a,'heartbeat',s.id,{token:randomUUID()}),e=>e.code==='40001');
 await stop(s);assert.deepEqual(await claim(a),{});
 await finish(s);const claimed=await claim(a);assert.equal(claimed.id,next.id);
 await db.query("update korlix_live_studio_shows set lease_until=now()-interval '1 second' where id=$1",[claimed.id]);
 await assert.rejects(rpc(a,'event',claimed.id,{token:claimed.worker_token,eventId:randomUUID(),kind:'dispatch',data:{}}),e=>e.code==='40001');
 await rpc(null,'sweep');assert.equal((await rpc(a,'get',claimed.id)).state,'failed');
 assert.equal((await row(claimed.run_id)).released_at,null);
});

test('expiry, revocation, period changes and banned users prevent claim without spending',async()=>{
 for(const mutate of [
  id=>db.query("update korlix_live_studio_grants set period_start=now()-interval '2 days',period_end=now()-interval '1 day' where owner_id=$1",[id]),
  id=>db.query('update korlix_live_studio_grants set enabled=false where owner_id=$1',[id]),
  id=>db.query("update korlix_live_studio_grants set period_end=period_end+interval '1 day' where owner_id=$1",[id]),
  id=>db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[id]),
 ]){
  const a=await user(),s=await queue(await save(a));await mutate(a);
  assert.deepEqual(await claim(a),{});assert.equal((await rpc(a,'get',s.id)).state,'failed');
  const receipt=await row(s.run_id);assert.equal(receipt.claimed_at,null);assert(receipt.released_at);
 }
});

test('revoking an allowance stops heartbeats and dispatch but still allows emergency end, cleanup and reads',async()=>{
 const a=await user();await queue(await save(a));const s=await claim(a);
 await db.query('update korlix_live_studio_grants set enabled=false where owner_id=$1',[a]);
 await assert.rejects(rpc(a,'heartbeat',s.id,{token:s.worker_token}),e=>e.code==='42501');
 await assert.rejects(rpc(a,'event',s.id,{token:s.worker_token,eventId:randomUUID(),kind:'dispatch',data:{}}),e=>e.code==='42501');
 await stop(s);assert.equal((await finish(s)).state,'cancelled');assert.equal((await rpc(a,'list')).shows.length,1);
});

test('YouTube starts pin the customer channel and reserve duration plus generation capacity',async()=>{
 const a=await user({limits:{broadcast_seconds_limit:900,generation_limit:200}}),c=await connection(a),w=await worker();
 const s=await queue(await save(a),{mode:'youtube'});
 assert.equal(s.connection_id,c.id);assert.equal(s.channel_id,c.channel);assert.equal(s.connection_revision,1);
 assert.equal((await rpc(a,'workspace')).usage.broadcastSecondsReserved,900);
 await assert.rejects(queue(await save(a),{mode:'youtube'}),e=>e.code==='54000');
 const claimed=await claim(null,{mode:'youtube',workerId:w});assert.equal(claimed.id,s.id);
 await db.query('update korlix_live_studio_connections set revision=2 where id=$1',[c.id]);
 await assert.rejects(rpc(a,'heartbeat',s.id,{token:claimed.worker_token}),e=>e.code==='42501');
 await assert.rejects(rpc(a,'event',s.id,{token:claimed.worker_token,eventId:randomUUID(),kind:'dispatch',data:{}}),e=>e.code==='42501');
 await finish(claimed);
});

test('worker capacity is one active job per UUID, independent workers serve independent customers',async()=>{
 const a=await user(),b=await user();await connection(a);await connection(b);
 const a1=await queue(await save(a),{mode:'youtube'}),b1=await queue(await save(b),{mode:'youtube'});
 const w1=await worker(),w2=await worker();
 await assert.rejects(claim(null,{mode:'youtube'}),e=>e.code==='42501');
 assert.deepEqual(await claim(null,{mode:'youtube',workerId:randomUUID()}),{});
 const first=await claim(null,{mode:'youtube',workerId:w1});assert.equal(first.id,a1.id);
 await rpc(null,'announce',w1,{mode:'youtube'});assert.deepEqual(await claim(null,{mode:'youtube',workerId:w1}),{});
 const second=await claim(null,{mode:'youtube',workerId:w2});assert.equal(second.id,b1.id);
 await rpc(null,'retire',w1);assert.equal((await rpc(a,'workspace')).workerReady,true);
 await rpc(null,'retire',w2);assert.equal((await rpc(a,'workspace')).workerReady,false);
 assert.equal((await rpc(a,'heartbeat',first.id,{token:first.worker_token})).id,first.id);
 await finish(first);assert.equal((await db.query('select run_id from korlix_live_studio_workers where id=$1',[w1])).rows[0].run_id,null);
});

test('changed or disconnected channel fails a queued run without releasing a running encoder slot',async()=>{
 const a=await user(),c=await connection(a),w=await worker(),s=await queue(await save(a),{mode:'youtube'});
 await db.query("update korlix_live_studio_connections set state='disconnected' where id=$1",[c.id]);
 assert.deepEqual(await claim(a,{mode:'youtube',workerId:w}),{});
 assert.equal((await rpc(a,'get',s.id)).state,'failed');assert((await row(s.run_id)).released_at);
});

test('a future schedule cannot escape the allowance period and old v1 cannot bypass grants',async()=>{
 const a=await user(),s=await save(a);
 await db.query("update korlix_live_studio_grants set period_end=now()+interval '1 hour' where owner_id=$1",[a]);
 await assert.rejects(queue(s,{scheduledAt:new Date(Date.now()+7200000).toISOString()}),e=>e.code==='22023');
 const b=await user({grant:false}),other=await save(b);
 await assert.rejects(db.query('select korlix_live_studio_v1($1,$2,$3,$4)',[b,'queue',other.id,{mode:'rehearsal',requestId:randomUUID()}]),e=>e.code==='42501');
});

test('new and old customer tables and RPCs remain service only with row-level security',async()=>{
 const owner=await user(),s=await save(owner);
 const tables=['korlix_live_studio_grants','korlix_live_studio_runs','korlix_live_studio_workers','korlix_live_studio_shows','korlix_live_studio_events'];
 for(const table of tables){
  assert.equal((await db.query('select relrowsecurity from pg_class where oid=$1::regclass',[table])).rows[0].relrowsecurity,true);
  for(const role of ['anon','authenticated']){
   await db.exec('set role '+role);
   await assert.rejects(db.query(`select * from ${table}`),e=>e.code==='42501');
   await assert.rejects(rpc(owner,'get',s.id),e=>e.code==='42501');
   await assert.rejects(db.query('select korlix_live_private.account_available($1)',[owner]),e=>e.code==='42501');
   await db.exec('reset role');
  }
 }
 await db.exec('set role service_role');
 assert.equal((await rpc(owner,'workspace')).entitlement.enabled,true);
 await assert.rejects(db.query('select * from auth.users'),e=>e.code==='42501');
 assert.equal((await db.query('select korlix_live_private.account_available($1) available',[owner])).rows[0].available,true);
 assert.equal((await rpc(owner,'get',s.id)).id,s.id);
 await db.exec('reset role');
});

test('YouTube start confirmation cannot silently follow a different channel revision',async()=>{
 const a=await user(),c=await connection(a),s=await save(a);
 await assert.rejects(rpc(a,'queue',s.id,{mode:'youtube',requestId:randomUUID()}),e=>e.code==='22023');
 await db.query('update korlix_live_studio_connections set revision=2 where id=$1',[c.id]);
 await assert.rejects(queue(s,{mode:'youtube',connectionRevision:1}),e=>e.code==='40001');
 const b=await user(),other=await connection(b);
 await assert.rejects(queue(s,{mode:'youtube',connectionId:other.id,connectionRevision:1}),e=>e.code==='40001');
 assert.equal((await rpc(a,'workspace')).usage.broadcastSecondsReserved,0);
 assert.equal((await queue(s,{mode:'youtube',connectionRevision:2})).connection_revision,2);
});

test('deleting an account cannot leave a worker slot permanently stranded',async()=>{
 const a=await user(),b=await user();await connection(a);await connection(b);
 const w=await worker();await queue(await save(a),{mode:'youtube'});
 const running=await claim(a,{mode:'youtube',workerId:w});assert.equal(running.owner_id,a);
 await db.query('delete from auth.users where id=$1',[a]);
 const next=await queue(await save(b),{mode:'youtube'});
 assert.equal((await claim(b,{mode:'youtube',workerId:w})).id,next.id);
 assert.equal((await db.query('select korlix_live_private.account_available($1) available',[a])).rows[0].available,false);
});

test('new runs of old saved shows use queue time for due and expiry, including requeues',async()=>{
 const a=await user(),s=await save(a);
 await db.query("update korlix_live_studio_shows set created_at=now()-interval '10 days' where id=$1",[s.id]);
 const first=await queue(s);assert(first.queued_at);
 await rpc(null,'sweep');assert.equal((await rpc(a,'get',s.id)).state,'queued');
 const running=await claim(a);assert.equal(running.id,s.id);await finish(running);
 await db.query("update korlix_live_studio_shows set queued_at=now()-interval '2 days' where id=$1",[s.id]);
 const second=await queue(s);assert.notEqual(second.run_id,first.run_id);
 await rpc(null,'sweep');assert.equal((await claim(a)).id,s.id);
});

test('a cancelled heartbeat reports the stop after revocation without extending the worker lease',async()=>{
 const a=await user(),c=await connection(a),w=await worker();await queue(await save(a),{mode:'youtube'});
 const running=await claim(a,{mode:'youtube',workerId:w});await stop(running);
 await db.query("update korlix_live_studio_connections set state='disconnected' where id=$1",[c.id]);
 await db.query('update korlix_live_studio_grants set enabled=false where owner_id=$1',[a]);
 const heartbeat=await rpc(a,'heartbeat',running.id,{token:running.worker_token});
 assert.equal(heartbeat.state,'cancelled');assert.equal(heartbeat.command.action,'end');
 assert.equal(heartbeat.lease_until,running.lease_until);
 await assert.rejects(rpc(a,'heartbeat',running.id,{token:randomUUID()}),e=>e.code==='40001');
 await assert.rejects(rpc(a,'event',running.id,{token:running.worker_token,eventId:randomUUID(),kind:'dispatch',data:{}}),e=>e.code==='42501');
 await finish(running);
});
