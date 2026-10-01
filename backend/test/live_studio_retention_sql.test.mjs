import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db;
const fingerprint='a'.repeat(64);
const config={title:'Customer-owned topic',topic:'Communities',category:'technology',durationSeconds:900,hostCount:2};
const rpc=async(name,actor,action,id=null,data={})=>(await db.query(`select public.${name}($1,$2,$3,$4) result`,[actor,action,id,data])).rows[0].result;
const studio=(...args)=>rpc('korlix_live_studio_v2',...args);
const conn=(...args)=>rpc('korlix_live_studio_connections_v1',...args);
const sweep=()=>conn(null,'retention_sweep');
const connectionRow=async id=>(await db.query('select * from korlix_live_studio_connections where id=$1',[id])).rows[0];
const runRow=async id=>(await db.query('select * from korlix_live_studio_runs where id=$1',[id])).rows[0];
const showRow=async id=>(await db.query('select * from korlix_live_studio_shows where id=$1',[id])).rows[0];
async function customer(){
 const owner=randomUUID(),id=randomUUID(),channel='UC'+randomUUID().replaceAll('-','').slice(0,22);
 await db.query('insert into auth.users(id) values($1)',[owner]);await studio(owner,'grant_developer');
 await db.query("insert into korlix_live_studio_connections(id,owner_id,channel_id,channel_title,state,sealed_grant,config_hash,last_verified_at,next_check_at) values($1,$2,$3,'Channel API title','connected','sealed fixture',$4,now(),now()-interval '1 second')",[id,owner,channel,fingerprint]);
 return {owner,id,channel};
}
async function queue(c,{mode='youtube',showId=randomUUID(),scheduledAt}={}){
 await studio(c.owner,'save',showId,{config});
 return studio(c.owner,'queue',showId,{mode,requestId:randomUUID(),connectionId:c.id,connectionRevision:1,...(scheduledAt?{scheduledAt}:{})});
}
async function claim(c){const worker=randomUUID();await studio(null,'announce',worker,{mode:'youtube'});return studio(c.owner,'claim',null,{mode:'youtube',workerId:worker,token:randomUUID()});}
async function active(c){await queue(c);const s=await claim(c);assert(s.id);return s;}
async function event(s,kind,data){return studio(s.owner_id,'event',s.id,{token:s.worker_token,eventId:randomUUID(),kind,data});}
async function populate(s){
 await event(s,'destination',{broadcastId:'youtube-broadcast-id',streamId:'youtube-stream-id',watchUrl:'https://www.youtube.com/watch?v=youtube-broadcast-id'});
 await event(s,'segment',{text:'A YouTube chat-derived response'});
 await event(s,'dispatch',{dispatchId:randomUUID(),kind:'speech'});
 await event(s,'receipt',{dispatchId:randomUUID(),kind:'speech',status:'completed',usage:{tokens:20}});
 return studio(s.owner_id,'progress',s.id,{token:s.worker_token,started:true,watchUrl:'https://www.youtube.com/watch?v=youtube-broadcast-id',progress:{caption:'A chat response',seconds:12}});
}
async function maintenance(c){const lease=randomUUID(),claimed=await conn(null,'maintenance_claim',null,{lease,config_hash:fingerprint});assert.equal(claimed.id,c.id);return {lease,revision:claimed.revision,config_hash:fingerprint};}
const complete=(c,pin,data={})=>conn(c.owner,'maintenance_store',c.id,{...pin,channel_id:c.channel,channel_title:'Refreshed title',sealed_grant:'refreshed fixture',...data});

test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;
 create table auth.users(id uuid primary key,banned_until timestamptz);grant usage on schema auth to service_role;
 create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);`);
 const dir=new URL('../../supabase/migrations/',import.meta.url),files=await readdir(dir);
 for(const suffix of ['_live_studio_pilot.sql','_live_studio_customer_workspaces.sql','_live_studio_connections.sql','_live_studio_connection_retention.sql'])await db.exec(await readFile(new URL(files.find(f=>f.endsWith(suffix)),dir),'utf8'));
});
test.beforeEach(async()=>db.exec('reset role;truncate auth.users cascade;truncate korlix_live_studio_workers;'));
test.after(async()=>db?.close());

test('disconnect immediately purges YouTube data while retaining internal usage and customer configuration',async()=>{
 const c=await customer(),running=await active(c),before=await populate(running),usage=(await studio(c.owner,'workspace')).usage;
 const returned=await conn(c.owner,'disconnect');assert.equal(returned.sealed_grant,'sealed fixture');
 const row=await connectionRow(c.id);for(const key of ['channel_id','channel_title','sealed_grant','refresh_lease','maintenance_lease'])assert.equal(row[key],null);
 const s=await showRow(running.id),r=await runRow(running.run_id);
 assert.equal(s.state,'cancelled');assert.equal(s.channel_id,null);assert.equal(s.watch_url,null);assert.deepEqual(s.progress,{});assert.deepEqual(s.config,config);assert(s.version>before.version);
 assert.equal(s.worker_token,running.worker_token);assert.equal(new Date(s.lease_until).getTime(),new Date(running.lease_until).getTime());assert.equal(s.channel_fence,createHash('sha256').update(c.channel).digest('hex'));
 assert.equal(r.channel_id,null);assert(r.api_data_purged_at);assert.equal(r.generations_dispatched,1);assert.equal(r.broadcast_seconds_reserved,900);assert.equal(r.released_at,null);
 const kinds=(await db.query('select kind from korlix_live_studio_events where run_id=$1',[r.id])).rows.map(x=>x.kind);
 assert.deepEqual(new Set(kinds),new Set(['queue','dispatch','receipt']));assert.deepEqual((await studio(c.owner,'workspace')).usage,usage);
});

test('late worker destination/progress/finish cannot restore data after purge and cleanup clears the hash fence',async()=>{
 const c=await customer(),s=await active(c);await populate(s);await conn(c.owner,'disconnect');
 await assert.rejects(event(s,'destination',{broadcastId:'late-id'}));
 await assert.rejects(studio(c.owner,'progress',s.id,{token:s.worker_token,watchUrl:'https://www.youtube.com/watch?v=late',progress:{caption:'late'}}));
 // Defense in depth protects a future service bug too, without relying only on RPC checks.
 await db.query("update korlix_live_studio_shows set channel_id=$2,watch_url='https://www.youtube.com/watch?v=late',progress='{\"late\":true}' where id=$1",[s.id,c.channel]);
 await assert.rejects(db.query("insert into korlix_live_studio_events(id,show_id,run_id,kind,data) values($1,$2,$3,'destination','{\"broadcastId\":\"late\"}')",[randomUUID(),s.id,s.run_id]),e=>e.code==='40001');
 await studio(c.owner,'finish',s.id,{token:s.worker_token,error:'YouTube identifier leak',replayPath:'late-path'});
 const after=await showRow(s.id);assert.equal(after.channel_id,null);assert.equal(after.watch_url,null);assert.deepEqual(after.progress,{});assert.equal(after.channel_fence,null);assert.equal(after.replay_path,null);assert.notEqual(after.error,'YouTube identifier leak');
});

test('purged raw channel IDs still exclude a competing encoder until the cancelled worker finishes',async()=>{
 const a=await customer(),first=await active(a);await conn(a.owner,'disconnect');
 const b=await customer();await db.query('update korlix_live_studio_connections set channel_id=$2 where id=$1',[b.id,a.channel]);b.channel=a.channel;
 await queue(b);assert.deepEqual(await claim(b),{});
 await studio(a.owner,'finish',first.id,{token:first.worker_token});assert((await claim(b)).id);
});

test('maintenance and encoder claims exclude each other, including queued future schedules',async()=>{
 const a=await customer(),pin=await maintenance(a);await queue(a);
 assert.deepEqual(await claim(a),{});await complete(a,pin);const s=await claim(a);assert(s.id);
 await db.query("update korlix_live_studio_connections set next_check_at=now()-interval '1 second' where id=$1",[a.id]);
 assert.deepEqual(await conn(null,'maintenance_claim',null,{lease:randomUUID(),config_hash:fingerprint}),{});
 await studio(a.owner,'finish',s.id,{token:s.worker_token});
 await queue(a,{scheduledAt:new Date(Date.now()+3600000).toISOString()});
 const futurePin=await maintenance(a);assert(futurePin.lease);
});

test('a maintenance lease is exclusive, expires safely and fences the result of a delayed provider response',async()=>{
 const c=await customer(),old=await maintenance(c);
 assert.deepEqual(await conn(null,'maintenance_claim',null,{lease:randomUUID(),config_hash:fingerprint}),{});
 await db.query("update korlix_live_studio_connections set maintenance_until=now()-interval '1 second' where id=$1",[c.id]);
 const current=await maintenance(c);
 await assert.rejects(complete(c,old),e=>e.code==='40001');await complete(c,current);
 const row=await connectionRow(c.id);assert.equal(row.channel_title,'Refreshed title');assert.equal(row.maintenance_lease,null);assert(new Date(row.next_check_at)-new Date(row.last_verified_at)>=86400000);
});

test('maintenance failure preserves a rotated token but never extends verification freshness',async()=>{
 const c=await customer(),before=await connectionRow(c.id),pin=await maintenance(c);
 await conn(c.owner,'maintenance_fail',c.id,{...pin,revoked:false,sealed_grant:'rotated grant'});
 let row=await connectionRow(c.id);assert.equal(row.sealed_grant,'rotated grant');assert.equal(new Date(row.last_verified_at).getTime(),new Date(before.last_verified_at).getTime());assert.equal(row.maintenance_failures,1);assert.equal(row.maintenance_lease,null);
 assert(new Date(row.next_check_at)>Date.now()+3500000);
 for(let i=0;i<7;i++){
  await db.query("update korlix_live_studio_connections set next_check_at=now()-interval '1 second' where id=$1",[c.id]);
  const next=await maintenance(c);await conn(c.owner,'maintenance_fail',c.id,{...next,revoked:false});
 }
 row=await connectionRow(c.id);assert(new Date(row.next_check_at)-Date.now()<=86400000);assert.equal(new Date(row.last_verified_at).getTime(),new Date(before.last_verified_at).getTime());
});

test('known invalid grants purge immediately without spending or changing the customer allowance',async()=>{
 const c=await customer(),queued=await queue(c),before=(await studio(c.owner,'workspace')).entitlement,pin=await maintenance(c);
 await conn(c.owner,'maintenance_fail',c.id,{...pin,revoked:true});
 const row=await connectionRow(c.id);assert.equal(row.state,'reconnect_required');assert.equal(row.channel_id,null);assert.equal(row.sealed_grant,null);
 assert.equal((await showRow(queued.id)).state,'cancelled');assert((await runRow(queued.run_id)).released_at);
 assert.deepEqual((await studio(c.owner,'workspace')).entitlement,before);
 await assert.rejects(complete(c,pin),e=>e.code==='40001');
});

test('idle maintenance continues after product allowance expiry but never for a banned account',async()=>{
 const c=await customer();await db.query("update korlix_live_studio_grants set enabled=false where owner_id=$1",[c.owner]);
 await complete(c,await maintenance(c));assert.equal((await studio(c.owner,'workspace')).entitlement.enabled,false);
 await db.query("update korlix_live_studio_connections set next_check_at=now()-interval '1 second' where id=$1",[c.id]);
 await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[c.owner]);
 assert.deepEqual(await conn(null,'maintenance_claim',null,{lease:randomUUID(),config_hash:fingerprint}),{});
 await sweep();assert.equal((await connectionRow(c.id)).sealed_grant,null);
});

test('retention sweep runs without provider configuration and purges stale connections even with an in-flight stale lease',async()=>{
 const c=await customer(),pin=await maintenance(c);await queue(c);
 await db.query("update korlix_live_studio_connections set last_verified_at=now()-interval '28 days 1 second' where id=$1",[c.id]);
 await sweep();const row=await connectionRow(c.id);assert.equal(row.state,'reconnect_required');assert.equal(row.channel_title,null);assert.equal(row.maintenance_lease,null);
 await assert.rejects(complete(c,pin),e=>e.code==='40001');
});

test('expired OAuth data is purged without customer activity while rate-limit receipts remain',async()=>{
 const c=await customer();
 for(let i=0;i<10;i++)await db.query("insert into korlix_live_studio_oauth(id,owner_id,state,ticket_hash,sealed_grant,channel_id,channel_title,config_hash,created_at,expires_at) values($1,$2,'ready',$3,'pending-grant',$4,'Pending title',$5,now()-interval '11 minutes',now()-interval '1 minute')",[randomUUID(),c.owner,createHash('sha256').update(String(i)).digest('hex'),c.channel,fingerprint]);
 await sweep();const rows=(await db.query('select * from korlix_live_studio_oauth where owner_id=$1',[c.owner])).rows;assert.equal(rows.length,10);
 for(const row of rows)for(const key of ['channel_id','channel_title','sealed_grant','sealed_secrets','ticket_hash','state_hash','browser_hash'])assert.equal(row[key],null);
 await assert.rejects(conn(c.owner,'start',randomUUID(),{ticket_hash:'b'.repeat(64),state_hash:'c'.repeat(64),sealed_secrets:'fixture',config_hash:fingerprint}),e=>e.code==='54000');
 await db.query("update korlix_live_studio_oauth set created_at=now()-interval '2 days' where owner_id=$1",[c.owner]);await sweep();assert.equal((await db.query('select count(*)::int n from korlix_live_studio_oauth')).rows[0].n,0);
});

test('historical broadcast API data expires independently of a freshly verified connection and reused rehearsal',async()=>{
 const c=await customer(),old=await active(c);await populate(old);await studio(c.owner,'finish',old.id,{token:old.worker_token});
 await db.query("update korlix_live_studio_runs set created_at=now()-interval '29 days' where id=$1",[old.run_id]);
 const rehearsal=await queue(c,{mode:'rehearsal',showId:old.id});
 const running=await studio(c.owner,'claim',null,{mode:'rehearsal',token:randomUUID()});assert.equal(running.id,old.id);
 await studio(c.owner,'progress',running.id,{token:running.worker_token,started:true,progress:{caption:'Independent rehearsal'}});
 await sweep();assert.equal((await connectionRow(c.id)).state,'connected');
 assert.deepEqual((await showRow(old.id)).progress,{caption:'Independent rehearsal'});assert.equal((await showRow(old.id)).api_data_purged_at,null);
 assert.equal((await runRow(old.run_id)).channel_id,null);assert((await runRow(old.run_id)).api_data_purged_at);assert.equal((await runRow(rehearsal.run_id)).api_data_purged_at,null);
});

test('new runs of a purged saved show can produce new content without restoring old API data',async()=>{
 const c=await customer(),first=await active(c);await populate(first);await conn(c.owner,'disconnect');await studio(c.owner,'finish',first.id,{token:first.worker_token});
 await queue(c,{mode:'rehearsal',showId:first.id});const next=await studio(c.owner,'claim',null,{mode:'rehearsal',token:randomUUID()});assert(next.id);
 await studio(c.owner,'progress',next.id,{token:next.worker_token,started:true,progress:{caption:'New customer rehearsal'}});
 assert.equal((await showRow(next.id)).api_data_purged_at,null);assert.deepEqual((await showRow(next.id)).progress,{caption:'New customer rehearsal'});
 assert((await runRow(first.run_id)).api_data_purged_at);
});

test('maintenance and purge capabilities remain service only, with no auth table access or wider customer grants',async()=>{
 const c=await customer();
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  await assert.rejects(sweep(),e=>e.code==='42501');
  await assert.rejects(db.query('select korlix_live_private.purge_youtube_connection($1,$2)',[c.owner,c.id]),e=>e.code==='42501');
  await assert.rejects(db.query('select * from korlix_live_studio_connections'),e=>e.code==='42501');
  await db.exec('reset role');
 }
 await db.exec('set role service_role');await sweep();await assert.rejects(db.query('select * from auth.users'),e=>e.code==='42501');await db.exec('reset role');
 const flags=(await db.query("select relname,relrowsecurity from pg_class where relname in ('korlix_live_studio_connections','korlix_live_studio_oauth','korlix_live_studio_runs','korlix_live_studio_shows')")).rows;
 assert.equal(flags.length,4);assert(flags.every(r=>r.relrowsecurity));
});

test('stale verification cannot queue, claim, heartbeat or acquire a token before the next sweep',async()=>{
 const a=await customer(),queued=await queue(a);
 await db.query("update korlix_live_studio_connections set last_verified_at=now()-interval '29 days' where id=$1",[a.id]);
 await assert.rejects(queue(a),e=>e.code==='40001');assert.deepEqual(await claim(a),{});assert.equal((await showRow(queued.id)).state,'failed');
 const b=await customer(),running=await active(b);
 await db.query("update korlix_live_studio_connections set last_verified_at=now()-interval '29 days' where id=$1",[b.id]);
 await assert.rejects(studio(b.owner,'heartbeat',running.id,{token:running.worker_token}),e=>e.code==='42501');
 await assert.rejects(conn(b.owner,'token_claim',b.id,{show_id:running.id,worker_token:running.worker_token,revision:1,channel_id:b.channel,config_hash:fingerprint,lease:randomUUID()}),e=>e.code==='40001');
 const publicSummary=await conn(b.owner,'list');assert.equal(publicSummary.connection.state,'reconnect_required');assert.equal(publicSummary.connection.channel_id,null);
 assert.equal((await showRow(running.id)).state,'cancelled');
});

test('known invalid grant cleanup still succeeds if ban and retention expiry arrive during maintenance',async()=>{
 const c=await customer(),pin=await maintenance(c);
 await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[c.owner]);
 await db.query("update korlix_live_studio_connections set last_verified_at=now()-interval '29 days' where id=$1",[c.id]);
 await assert.rejects(complete(c,pin),e=>e.code==='40001');
 await assert.rejects(conn(c.owner,'maintenance_fail',c.id,pin),e=>e.code==='40001');
 await conn(c.owner,'maintenance_fail',c.id,{...pin,revoked:true});
 const row=await connectionRow(c.id);assert.equal(row.sealed_grant,null);assert.equal(row.channel_id,null);assert.equal(row.state,'reconnect_required');
});
