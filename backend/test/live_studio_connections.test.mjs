import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerLiveStudio} from '../live_studio/routes.mjs';
import {createLiveConnections,liveConnectionCipher,liveConnectionSettings,YOUTUBE_SCOPE} from '../live_studio/connections.mjs';

let db,owner,other,connections,server,base,calls,scenario;
const channel='UCabcdefghijklmnopqrstuv',secondChannel='UC'+'z'.repeat(22);
const env={LIVE_STUDIO_TOKEN_KEY:randomBytes(32).toString('base64'),LIVE_STUDIO_YOUTUBE_CLIENT_ID:'test-client',LIVE_STUDIO_YOUTUBE_CLIENT_SECRET:'test-secret',LIVE_STUDIO_PUBLIC_ORIGIN:'https://studio.example.test',LIVE_STUDIO_YOUTUBE_ENABLED:'true'};
const settings=liveConnectionSettings(env),cipher=liveConnectionCipher(env);
const raw=async(actor,action,id=null,data={})=>(await db.query('select public.korlix_live_studio_connections_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const database={rpc:async(_name,p)=>{try{return {data:await raw(p.p_actor,p.p_action,p.p_id,p.p_data)};}catch(error){return {error};}}};
const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
async function fetcher(url,opts){
  calls.push({url,opts});
  if(url==='https://oauth2.googleapis.com/token'){
    if(scenario.delayRefresh&&opts.body.get('grant_type')==='refresh_token')await scenario.delayRefresh();
    if(scenario.invalidGrant)return reply({error:'invalid_grant'},400);
    return reply({access_token:opts.body.get('grant_type')==='refresh_token'?'refreshed-access':'test-access',refresh_token:opts.body.get('grant_type')==='refresh_token'?'rotated-refresh':'test-refresh',expires_in:3600,token_type:'Bearer',scope:scenario.denyScope?'https://www.googleapis.com/auth/youtube.readonly':YOUTUBE_SCOPE});
  }
  if(url.startsWith('https://www.googleapis.com/youtube/v3/channels')){
    if(scenario.delayIdentity)await scenario.delayIdentity(opts.signal);
    if(scenario.identityStatus)return reply({error:{errors:[{reason:scenario.identityReason||'backendError'}]}},scenario.identityStatus);
    return reply({items:scenario.noChannel?[]:[{id:scenario.channel||channel,snippet:{title:scenario.title||'Customer Channel'}}]});
  }
  if(url==='https://oauth2.googleapis.com/revoke')return scenario.revokeFails?reply({error:'unavailable'},503):new Response('',{status:200});
  throw Error('Unexpected provider request');
}
async function launch(actor=owner){
  const start=await connections.start(actor,{confirmed:true});
  const r=await fetch(base+new URL(start.url).pathname+new URL(start.url).search,{redirect:'manual'});
  assert.equal(r.status,303);
  const cookie=r.headers.get('set-cookie').split(';')[0],url=new URL(r.headers.get('location'));
  return {...start,cookie,url,launchUrl:start.url,cookieHeader:r.headers.get('set-cookie')};
}
async function callback(a,options={}){
  return fetch(base+'/api/live-studio/connect/youtube/callback?'+new URLSearchParams({state:a.url.searchParams.get('state'),code:'test-code',...options.query}),{headers:{cookie:options.cookie||a.cookie},redirect:'manual'});
}
async function connect(actor=owner){const a=await launch(actor);assert.equal((await callback(a)).status,200);await connections.confirm(actor,{id:a.id,confirmed:true});return (await connections.summary(actor)).connection;}
async function showFor(connection,{expiredGrant=false}={}){
  const id=randomUUID(),worker_token=randomUUID(),run_id=randomUUID();
  await db.query(`insert into korlix_live_studio_shows(id,owner_id,config,state,mode,run_id,worker_token,lease_until,deadline_at,connection_id,connection_revision,channel_id)
   values($1,$2,'{}','live','youtube',$3,$4,now()+interval '45 seconds',now()+interval '1 hour',$5,$6,$7)`,[id,owner,run_id,worker_token,connection.id,connection.revision,connection.channelId]);
  await db.query('insert into korlix_live_studio_runs(id,owner_id,claimed_at,grant_id,grant_period_start,grant_period_end) select $1,$2,now(),id,period_start,period_end from korlix_live_studio_grants where owner_id=$2',[run_id,owner]);
  if(expiredGrant){const c=(await db.query('select * from korlix_live_studio_connections where id=$1',[connection.id])).rows[0];const binding=`grant:${c.owner_id}:${c.id}:${c.channel_id}`,g=cipher.open(c.sealed_grant,binding);g.expires_at=new Date(Date.now()-60000).toISOString();await db.query('update korlix_live_studio_connections set sealed_grant=$2 where id=$1',[c.id,cipher.seal(g,binding)]);}
  return (await db.query('select * from korlix_live_studio_shows where id=$1',[id])).rows[0];
}

test.before(async()=>{
  db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key,banned_until timestamptz);create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);grant usage on schema public to anon,authenticated,service_role;');
  const dir=new URL('../../supabase/migrations/',import.meta.url),files=await readdir(dir);
  for(const suffix of ['_live_studio_pilot.sql','_live_studio_customer_workspaces.sql','_live_studio_connections.sql','_live_studio_connection_retention.sql'])await db.exec(await readFile(new URL(files.find(n=>n.endsWith(suffix)),dir),'utf8'));
  connections=createLiveConnections({database,env,fetcher});
  const app=express();connections.registerPublic(app);server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{
  await db.exec('reset role;truncate korlix_live_studio_shows cascade;truncate korlix_live_studio_runs,korlix_live_studio_grants,korlix_live_studio_connections,korlix_live_studio_oauth;');
  owner=randomUUID();other=randomUUID();calls=[];scenario={};await db.query('insert into auth.users(id) values($1),($2)',[owner,other]);await db.exec('set role service_role');await db.query("select public.korlix_live_studio_v2($1,'grant_developer')",[owner]);await db.query("select public.korlix_live_studio_v2($1,'grant_developer')",[other]);
});
test.after(async()=>{await new Promise(r=>server.close(r));await db.close();});

test('versioned encryption binds owner, connection, channel and product; invalid origin and disabled config fail closed',()=>{
  const binding=`grant:${owner}:${randomUUID()}:${channel}`,value=cipher.seal({refresh_token:'secret'},binding);
  assert(value.startsWith('v1.'));assert(!value.includes('secret'));assert.equal(cipher.open(value,binding).refresh_token,'secret');
  assert.throws(()=>cipher.open(value,binding+'other'));assert.throws(()=>cipher.open(value.replace('v1.','v2.'),binding));
  assert.throws(()=>liveConnectionCipher({...env,LIVE_STUDIO_TOKEN_KEY:randomBytes(32).toString('base64')}).open(value,binding));
  assert.equal(liveConnectionSettings({...env,LIVE_STUDIO_PUBLIC_ORIGIN:'http://unsafe.test'}).configured,false);
  assert.equal(liveConnectionSettings({...env,LIVE_STUDIO_PUBLIC_ORIGIN:'https://safe.test/?redirect=evil'}).configured,false);
  assert.equal(liveConnectionSettings({...env,LIVE_STUDIO_YOUTUBE_ENABLED:'false'}).configured,false);
});

test('OAuth uses one-use launch ticket, secure browser cookie and S256; no grant is active until owner confirms',async()=>{
  const a=await launch();assert.equal(a.url.origin,'https://accounts.google.com');assert.equal(a.url.searchParams.get('code_challenge_method'),'S256');
  assert.equal(a.url.searchParams.get('redirect_uri'),settings.callback);assert.equal(a.url.searchParams.get('scope'),YOUTUBE_SCOPE);
  assert.equal(a.url.searchParams.get('access_type'),'offline');
  assert.match(a.cookieHeader,/HttpOnly/);assert.match(a.cookieHeader,/Secure/);assert.match(a.cookieHeader,/SameSite=Lax/);assert.match(a.cookieHeader,/Max-Age=600/);
  const attempt=(await db.query('select * from korlix_live_studio_oauth where id=$1',[a.id])).rows[0];
  assert.equal(attempt.ticket_hash,null);assert(attempt.state_hash);assert(attempt.browser_hash);assert(!JSON.stringify(attempt).includes(a.cookie.split('=')[1]));
  const launchAgain=await fetch(base+new URL(a.launchUrl).pathname+new URL(a.launchUrl).search,{redirect:'manual'});assert.equal(launchAgain.status,409);
  const r=await callback(a);assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(r.headers.get('referrer-policy'),'no-referrer');assert(r.headers.get('content-security-policy').includes("frame-ancestors 'none'"));
  const exchange=calls.find(c=>c.url.endsWith('/token'));
  assert.equal(createHash('sha256').update(exchange.opts.body.get('code_verifier')).digest('base64url'),a.url.searchParams.get('code_challenge'));
  const pending=await connections.summary(owner);assert.equal(pending.connection,null);assert.equal(pending.pendingConnections[0].channelId,channel);assert(!JSON.stringify(pending).includes('sealed'));
  await assert.rejects(connections.confirm(other,{id:a.id,confirmed:true}),e=>e.status===404);
  await assert.rejects(connections.confirm(owner,{id:a.id,confirmed:false}),e=>e.status===400);
  const confirmed=await connections.confirm(owner,{id:a.id,confirmed:true});assert.equal(confirmed.connection.channelId,channel);
  assert.equal((await connections.confirm(owner,{id:a.id,confirmed:true})).connection.id,a.id);
  assert.equal((await callback(a)).status,409);assert.equal(calls.filter(c=>c.url.endsWith('/token')).length,1);
});

test('state and browser mismatches cannot consume a callback; provider denial and denied scope cannot produce a pending grant',async()=>{
  let a=await launch();assert.equal((await callback(a,{cookie:'__Secure-korlix_live_youtube='+randomBytes(32).toString('base64url')})).status,409);
  assert.equal((await callback(a,{query:{state:randomBytes(32).toString('base64url')}})).status,409);
  assert.equal(calls.length,0);assert.equal((await callback(a,{query:{error:'access_denied'}})).status,409);assert.equal(calls.length,0);
  a=await launch();scenario.denyScope=true;assert.equal((await callback(a)).status,409);assert.equal((await connections.summary(owner)).pendingConnections.length,0);assert.equal((await callback(a)).status,409);
});

test('channel identity must be singular and stable, and one channel cannot belong to two customers',async()=>{
  let a=await launch();scenario.noChannel=true;assert.equal((await callback(a)).status,409);scenario.noChannel=false;
  const c=await connect();assert.equal(c.channelId,channel);
  a=await launch(other);assert.equal((await callback(a)).status,200);
  await assert.rejects(connections.confirm(other,{id:a.id,confirmed:true}),e=>e.status===409&&/another KORLIX/.test(e.message));
  assert.equal((await connections.summary(other)).connection,null);
  scenario.channel=secondChannel;await assert.rejects(connections.confirm(other,{id:a.id,confirmed:true}),e=>e.status===409&&/changed/.test(e.message));
});

test('worker grant loading is owner, show, connection revision, channel and lease fenced',async()=>{
  const c=await connect(),show=await showFor(c),access=await connections.forShow(show);
  assert.equal(await access(),'test-access');
  for(const change of [{owner_id:other},{worker_token:randomUUID()},{connection_revision:2},{channel_id:secondChannel},{connection_id:randomUUID()}]){
    const fn=await connections.forShow({...show,...change});await assert.rejects(fn(),e=>e.status===409);
  }
  await db.query("update korlix_live_studio_shows set lease_until=now()-interval '1 second' where id=$1",[show.id]);await assert.rejects(access(),e=>e.status===409);
});

test('refresh rotates encrypted tokens, coalesces callers and rejects late writes after disconnect',async()=>{
  const c=await connect(),show=await showFor(c,{expiredGrant:true}),access=await connections.forShow(show);
  assert.deepEqual(await Promise.all([access(),access()]),['refreshed-access','refreshed-access']);
  assert.equal(calls.filter(x=>x.opts.body?.get('grant_type')==='refresh_token').length,1);
  let saved=(await db.query('select * from korlix_live_studio_connections where id=$1',[c.id])).rows[0];assert.equal(cipher.open(saved.sealed_grant,`grant:${owner}:${c.id}:${channel}`).refresh_token,'rotated-refresh');
  const grant=cipher.open(saved.sealed_grant,`grant:${owner}:${c.id}:${channel}`);grant.expires_at=new Date(Date.now()-1000).toISOString();await db.query('update korlix_live_studio_connections set sealed_grant=$2 where id=$1',[c.id,cipher.seal(grant,`grant:${owner}:${c.id}:${channel}`)]);
  scenario.delayRefresh=async()=>{await connections.disconnect(owner,{confirmed:true});};
  await assert.rejects(access(),e=>e.status===409);
  saved=(await db.query('select * from korlix_live_studio_connections where id=$1',[c.id])).rows[0];assert.equal(saved.sealed_grant,null);assert.equal(saved.state,'disconnected');
  const stopped=(await db.query('select * from korlix_live_studio_shows where id=$1',[show.id])).rows[0];assert.equal(stopped.state,'cancelled');assert.equal(stopped.worker_token,show.worker_token);
});

test('invalid refresh grant marks reconnect required and fences further access',async()=>{
  const c=await connect(),show=await showFor(c,{expiredGrant:true}),access=await connections.forShow(show);scenario.invalidGrant=true;
  await assert.rejects(access(),e=>e.status===409);const s=await connections.summary(owner);assert.equal(s.connection.state,'reconnect_required');
  const saved=(await db.query('select * from korlix_live_studio_connections where id=$1',[c.id])).rows[0];assert.equal(saved.sealed_grant,null);
  await assert.rejects(access(),e=>e.status===409);
});

test('changing client configuration requires reconnect; unavailable configuration still allows disconnect',async()=>{
  const c=await connect(),show=await showFor(c),changed=createLiveConnections({database,env:{...env,LIVE_STUDIO_YOUTUBE_CLIENT_SECRET:'changed'},fetcher});
  assert.equal((await changed.summary(owner)).connection.state,'reconnect_required');const access=await changed.forShow(show);await assert.rejects(access(),e=>e.status===409);
  const unconfigured=createLiveConnections({database,env:{},fetcher});assert.equal((await unconfigured.summary(owner)).connectionConfigured,false);
  const result=await unconfigured.disconnect(owner,{confirmed:true});assert.equal(result.disconnected,true);assert.equal(result.providerRevoked,false);assert.equal(result.connection,null);
});

test('failed revocation still removes local grants and releases only unclaimed usage reservations',async()=>{
  const c=await connect(),id=randomUUID(),run=randomUUID();await db.query("insert into korlix_live_studio_shows(id,owner_id,config,state,mode,run_id,connection_id,connection_revision,channel_id) values($1,$2,'{}','queued','youtube',$3,$4,1,$5)",[id,owner,run,c.id,channel]);await db.query('insert into korlix_live_studio_runs(id,owner_id) values($1,$2)',[run,owner]);
  scenario.revokeFails=true;const result=await connections.disconnect(owner,{confirmed:true});assert.equal(result.providerRevoked,false);assert.match(result.message,/could not be confirmed/);
  assert.equal((await db.query('select sealed_grant from korlix_live_studio_connections where id=$1',[c.id])).rows[0].sealed_grant,null);
  assert((await db.query('select released_at from korlix_live_studio_runs where id=$1',[run])).rows[0].released_at);
});

test('client roles cannot read grants, OAuth attempts or execute connection RPC',async()=>{
  await connect();
  for(const role of ['anon','authenticated']){
    await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_live_studio_connections'));await assert.rejects(db.query('select * from korlix_live_studio_oauth'));await assert.rejects(raw(owner,'list'));await db.exec('reset role;set role service_role');
  }
  const rows=(await db.query("select relname,relrowsecurity from pg_class where relname in ('korlix_live_studio_connections','korlix_live_studio_oauth')")).rows;assert(rows.every(r=>r.relrowsecurity));
});


test('revoked customer allowance and a newly banned account fence provider access immediately',async()=>{
  const c=await connect(),show=await showFor(c),access=await connections.forShow(show);
  await db.query('update korlix_live_studio_grants set enabled=false where owner_id=$1',[owner]);
  await assert.rejects(access(),e=>e.status===403);
  await db.query('update korlix_live_studio_grants set enabled=true where owner_id=$1',[owner]);
  await db.exec('reset role');await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[owner]);await db.exec('set role service_role');
  await assert.rejects(access(),e=>e.status===403);
  assert.equal(calls.filter(c=>c.url.endsWith('/token')).length,1);
});

test('refresh lease cannot be stolen and stale token writes cannot replace a stored grant',async()=>{
  const c=await connect(),show=await showFor(c),lease=randomUUID();
  const pinned={show_id:show.id,worker_token:show.worker_token,revision:c.revision,channel_id:c.channelId,config_hash:settings.fingerprint,lease};
  const before=await raw(owner,'token_claim',c.id,pinned);
  await assert.rejects(raw(owner,'token_claim',c.id,{...pinned,lease:randomUUID()}),e=>e.code==='40001');
  await assert.rejects(raw(owner,'token_store',c.id,{...pinned,lease:randomUUID(),sealed_grant:'wrong'}),e=>e.code==='40001');
  await db.query("update korlix_live_studio_connections set refresh_until=now()-interval '1 second' where id=$1",[c.id]);
  await assert.rejects(raw(owner,'token_store',c.id,{...pinned,sealed_grant:'late'}),e=>e.code==='40001');
  assert.equal((await db.query('select sealed_grant from korlix_live_studio_connections where id=$1',[c.id])).rows[0].sealed_grant,before.sealed_grant);
});


async function dueConnection(c,{days=2,expiredGrant=true}={}){
  await db.query("update korlix_live_studio_connections set last_verified_at=now()-make_interval(days=>$2),next_check_at=now()-interval '1 minute' where id=$1",[c.id,days]);
  if(expiredGrant){const saved=(await db.query('select * from korlix_live_studio_connections where id=$1',[c.id])).rows[0],binding=`grant:${saved.owner_id}:${saved.id}:${saved.channel_id}`,grant=cipher.open(saved.sealed_grant,binding);grant.expires_at=new Date(Date.now()-60000).toISOString();await db.query('update korlix_live_studio_connections set sealed_grant=$2 where id=$1',[c.id,cipher.seal(grant,binding)]);}
}
const connectionRow=async c=>(await db.query('select * from korlix_live_studio_connections where id=$1',[c.id])).rows[0];

test('idle daily maintenance revalidates channels, refreshes metadata and encrypted grant, and waits a day before repeating',async()=>{
  const c=await connect();await dueConnection(c);scenario.title='Customer Renamed Channel';calls=[];
  const first=connections.maintenanceTick(),same=connections.maintenanceTick();assert.equal(first,same);assert.equal((await first).verified,1);
  const saved=await connectionRow(c);assert.equal(saved.channel_title,'Customer Renamed Channel');assert.equal(saved.revision,c.revision);
  assert(Date.now()-Date.parse(saved.last_verified_at)<10000);assert(Date.parse(saved.next_check_at)>Date.now()+23*3600000);
  assert.equal(cipher.open(saved.sealed_grant,`grant:${owner}:${c.id}:${channel}`).refresh_token,'rotated-refresh');
  assert.equal(calls.filter(c=>c.url.includes('/channels?')).length,1);assert.equal(calls.filter(c=>c.url.endsWith('/token')).length,1);
  assert.equal((await connections.maintenanceTick()).verified,0);assert.equal(calls.length,2);
});

test('idle maintenance skips a claimed show and verifies once its worker has released it',async()=>{
  const c=await connect(),show=await showFor(c);await dueConnection(c);calls=[];
  assert.equal((await connections.maintenanceTick()).verified,0);assert.equal(calls.length,0);
  await db.query("update korlix_live_studio_shows set worker_token=null,lease_until=null,state='completed' where id=$1",[show.id]);
  assert.equal((await connections.maintenanceTick()).verified,1);
});

test('transient channel errors preserve token rotation without extending the retention deadline and back off',async()=>{
  const c=await connect();await dueConnection(c);const before=await connectionRow(c);scenario.identityStatus=403;scenario.identityReason='quotaExceeded';calls=[];
  const result=await connections.maintenanceTick();assert.equal(result.deferred,1);assert.equal(result.revoked,0);
  const saved=await connectionRow(c);assert.equal(saved.state,'connected');assert.equal(String(saved.last_verified_at),String(before.last_verified_at));assert(saved.maintenance_failures>0);
  assert(Date.parse(saved.next_check_at)>Date.now()+50*60000);assert.equal(cipher.open(saved.sealed_grant,`grant:${owner}:${c.id}:${channel}`).refresh_token,'rotated-refresh');
  assert.equal((await connections.maintenanceTick()).deferred,0);assert.equal(calls.length,2);
});

test('known-invalid authorization purges idle grants and channel metadata immediately',async()=>{
  const c=await connect();await dueConnection(c);scenario.invalidGrant=true;
  assert.equal((await connections.maintenanceTick()).revoked,1);const saved=await connectionRow(c);
  assert.equal(saved.state,'reconnect_required');assert.equal(saved.sealed_grant,null);assert.equal(saved.channel_id,null);assert.equal(saved.channel_title,null);
  const summary=await connections.summary(owner);assert.equal(summary.connection.channelTitle,'Reconnect YouTube');assert.equal(summary.connection.channelId,null);
});

test('changed channel and explicit insufficient YouTube permissions purge rather than defer',async()=>{
  let c=await connect();await dueConnection(c,{expiredGrant:false});scenario.channel=secondChannel;assert.equal((await connections.maintenanceTick()).revoked,1);assert.equal((await connectionRow(c)).channel_id,null);
  scenario={};c=await connect();await dueConnection(c,{expiredGrant:false});scenario.identityStatus=403;scenario.identityReason='insufficientPermissions';
  assert.equal((await connections.maintenanceTick()).revoked,1);assert.equal((await connectionRow(c)).sealed_grant,null);
});

test('disconnect during idle verification cannot restore returned tokens or channel metadata',async()=>{
  const c=await connect();await dueConnection(c);scenario.delayIdentity=async()=>{scenario.delayIdentity=null;await connections.disconnect(owner,{confirmed:true});};
  assert.equal((await connections.maintenanceTick()).verified,0);const saved=await connectionRow(c);
  assert.equal(saved.state,'disconnected');assert.equal(saved.sealed_grant,null);assert.equal(saved.channel_id,null);assert.equal(saved.channel_title,null);
});

test('periodic retention sweep removes stale data and expired attempts even when OAuth credentials are absent',async()=>{
  const c=await connect();await dueConnection(c,{days:29});const a=await launch(other);assert.equal((await callback(a)).status,200);
  await db.query("update korlix_live_studio_oauth set expires_at=now()-interval '1 minute' where id=$1",[a.id]);calls=[];
  const unconfigured=createLiveConnections({database,env:{},fetcher});assert.equal((await unconfigured.maintenanceTick()).ownersProcessed,2);
  const saved=await connectionRow(c);assert.equal(saved.sealed_grant,null);assert.equal(saved.channel_id,null);assert.equal(saved.channel_title,null);
  const attempt=(await db.query('select * from korlix_live_studio_oauth where id=$1',[a.id])).rows[0];
  if(attempt){assert.equal(attempt.sealed_grant,null);assert.equal(attempt.channel_id,null);assert.equal(attempt.channel_title,null);assert.equal(attempt.sealed_secrets,null);}
  assert.equal(calls.length,0);
});

test('a revoked pending confirmation immediately clears its stored grant and channel identity',async()=>{
  const a=await launch();assert.equal((await callback(a)).status,200);scenario.identityStatus=403;scenario.identityReason='insufficientPermissions';
  await assert.rejects(connections.confirm(owner,{id:a.id,confirmed:true}),e=>e.status===409);
  const attempt=(await db.query('select * from korlix_live_studio_oauth where id=$1',[a.id])).rows[0];
  assert.equal(attempt.sealed_grant,null);assert.equal(attempt.channel_id,null);assert.equal(attempt.channel_title,null);
  assert.equal((await connections.summary(owner)).pendingConnections.length,0);
});

test('maintenance lifecycle aborts an in-flight provider request and prevents subsequent ticks after stop',async()=>{
  const c=await connect();await dueConnection(c,{expiredGrant:false});let entered;const ready=new Promise(resolve=>{entered=resolve;});
  scenario.delayIdentity=signal=>new Promise((resolve,reject)=>{entered();if(signal.aborted)reject(Error('aborted'));else signal.addEventListener('abort',()=>reject(Error('aborted')),{once:true});});
  const managed=createLiveConnections({database,env,fetcher});managed.startMaintenance();await ready;await managed.stopMaintenance();
  assert.deepEqual(await managed.maintenanceTick(),{stopped:true});assert.equal((await connectionRow(c)).maintenance_lease,null);
});

test('API registration starts cleanup without providers and stops it with the rehearsal lifecycle',async()=>{
  let started=0,stopped=0;const stub={registerPublic(){},startMaintenance(){started++;},async stopMaintenance(){stopped++;}};
  const registered=registerLiveStudio(express(),{connections:stub,startWorker:false,startMaintenance:true});
  assert.equal(started,1);await registered.stop();assert.equal(stopped,1);
});
