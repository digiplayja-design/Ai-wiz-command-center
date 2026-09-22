import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes,createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {createMetaStore,registerMeta,metaConfiguration,tokenCipher,digest,createMetaProvider,verifiedMetaEvent} from '../funnels/meta.mjs';
import {FunnelError} from '../funnels/core.mjs';
let db,store,server,base,exchanges=0,accountReads=0;
const owner=randomUUID(),other=randomUUID(),basic=randomUUID();
const env={KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'app-secret-fixture-not-real',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback'};
const cfg=metaConfiguration(env);
const command=(u,a,d={})=>store.command(u,a,d);
const req=(path,body,actor=owner,method='POST')=>fetch(base+'/api/funnels/meta'+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
const acc={id:'act_1234',name:'Test business',currency:'USD',timezone:'America/New_York',status:1};
const provider={authorizationUrl:s=>'https://www.facebook.com/v26.0/dialog/oauth?state='+s,exchange:async()=>{exchanges++;return {token:'fixture-token',meta_user_id:'10101',expires_at:new Date(Date.now()+86400000).toISOString()};},accounts:async()=>{accountReads++;return [acc];},account:async()=>acc};
async function begin(user=owner){const r=await req('/begin',{},user);assert.equal(r.status,200);return r.json();}
async function callback(a){return fetch(base+'/api/funnels/meta/callback?state='+encodeURIComponent(new URL(a.authorization_url).searchParams.get('state'))+'&code=fixture-code');}
async function connect(){const a=await begin();assert.equal((await callback(a)).status,200);const r=await req('/finish',{id:a.id,proof:a.proof});assert.equal(r.status,200);return r.json();}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);grant usage on schema public to anon,authenticated,service_role;grant select on user_profiles to service_role;');
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 await db.exec(await readFile(new URL('../../supabase/migrations/20260922111502_funnel_meta_connection.sql',import.meta.url),'utf8'));
 store=createMetaStore({rpc:async(_name,p)=>{try{return {data:(await db.query('select korlix_meta_v1($1,$2,$3) r',[p.p_actor,p.p_action,JSON.stringify(p.p_data)])).rows[0].r};}catch(error){return {error};}}});
 const app=express();app.use(express.json());
 const ownerRoute=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const u=q.headers.authorization;if(!u)return r.status(401).json({error:'Sign in'});await fn(q,r,u);}catch(e){r.status(e instanceof FunnelError?e.status:503).json({error:e.message});}};
 registerMeta(app,{base:'/api/funnels',owner:ownerRoute,metaStore:store,metaProvider:provider,environment:env});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{await db.exec('delete from korlix_meta_connections;delete from korlix_meta_oauth_attempts;');exchanges=0;accountReads=0;});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server?.close(r));await db?.close();});
test('Configuration fails closed and encrypted tokens are owner and attempt bound',()=>{
 assert.equal(cfg.ready,true);for(const key of ['KORLIX_META_APP_ID','KORLIX_META_APP_SECRET','KORLIX_META_LOGIN_CONFIG_ID','KORLIX_META_TOKEN_KEY','KORLIX_META_REDIRECT_URI','KORLIX_META_ENABLED'])assert.equal(metaConfiguration({...env,[key]:''}).ready,false);
 assert.equal(metaConfiguration({...env,KORLIX_META_REDIRECT_URI:'http://example.com/api/funnels/meta/callback'}).ready,false);
 const c=tokenCipher(env.KORLIX_META_TOKEN_KEY),sealed=c.seal('secret','owner:attempt');assert(!JSON.stringify(sealed).includes('secret'));assert.equal(c.open(sealed,'owner:attempt'),'secret');assert.throws(()=>c.open(sealed,'other:attempt'));assert.throws(()=>c.open({...sealed,tag:'X'.repeat(22)},'owner:attempt'));
});
test('Database access is private; status is owner-only and current Enterprise is required',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  await assert.rejects(db.query('select * from korlix_meta_connections'),/permission denied/);
  await assert.rejects(db.query('select korlix_meta_v1($1,$2,$3)',[owner,'status','{}']),/permission denied/);
  await db.exec('reset role');
 }
 assert.equal((await req('/connection',null,'','GET')).status,401);
 assert.equal((await req('/connection',null,basic,'GET')).status,403);
 assert.equal((await req('/begin',{},basic)).status,403);
 await db.exec('set role service_role');
 assert.equal((await command(owner,'status')).connection,null);
 await db.exec('reset role');
 await connect();const status=await(await req('/connection',null,other,'GET')).json();assert.equal(status.connection,null);
});
test('OAuth state is single-use, finish requires the initiating owner and private proof, tokens never reach UI',async()=>{
 const a=await begin();assert.equal((await req('/begin',{})).status,429);
 assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,409);
 const callbackResponse=await callback(a);assert.equal(callbackResponse.status,200);assert(!((await callbackResponse.text()).includes('fixture-token')));
 assert.equal((await callback(a)).status,409);assert.equal(exchanges,1);
 assert.equal((await req('/finish',{id:a.id,proof:a.proof},other)).status,409);
 assert.equal((await req('/finish',{id:a.id,proof:randomBytes(32).toString('base64url')})).status,409);
 const result=await(await req('/finish',{id:a.id,proof:a.proof})).json();assert(result.connection);assert.equal(result.ad_publishing_ready,false);
 const json=JSON.stringify(result);for(const field of ['sealed','fixture-token','proof_hash','state_hash','config_hash'])assert(!json.includes(field));
 assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,409);
 const saved=await command(owner,'secret');assert.equal(tokenCipher(cfg.key).open(saved.sealed,`korlix-meta:${owner}:${a.id}`),'fixture-token');
});
test('Cancelled, expired and superseded authorization cannot overwrite or restore a disconnected connection',async()=>{
 let a=await begin();const state=new URL(a.authorization_url).searchParams.get('state');
 assert.equal((await fetch(base+'/api/funnels/meta/callback?state='+state+'&error=access_denied')).status,400);assert.equal(exchanges,0);
 assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,400);
 await db.exec("update korlix_meta_oauth_attempts set created_at=now()-interval '1 minute'");
 a=await begin();await db.exec("update korlix_meta_oauth_attempts set expires_at=now()-interval '1 second'");assert.equal((await callback(a)).status,409);
 a=await begin();assert.equal((await req('/disconnect',{confirmed:true})).status,200);assert.equal((await callback(a)).status,404);
 assert.equal((await req('/connection',null,owner,'GET')).status,200);
});
test('Account refresh and selection are versioned and selection rechecks provider access',async()=>{
 await connect();assert.equal((await req('/accounts',{})).status,200);let state=await(await req('/connection',null,owner,'GET')).json();assert.deepEqual(state.connection.accounts,[acc]);assert.equal(accountReads,1);
 assert.equal((await req('/select',{account_id:'act_9999',version:state.connection.version})).status,400);
 assert.equal((await req('/select',{account_id:acc.id,version:state.connection.version})).status,200);
 assert.equal((await req('/select',{account_id:acc.id,version:state.connection.version})).status,409);
 assert.equal((await req('/disconnect',{confirmed:true,version:state.connection.version})).status,409);
 state=await(await req('/connection',null,owner,'GET')).json();assert.equal(state.connection.selected_account,acc.id);
 assert.equal((await req('/disconnect',{confirmed:true,version:state.connection.version})).status,200);
 assert.equal((await req('/accounts',{})).status,404);
});
test('Expired credentials and configuration changes report reconnect; concurrent completion is rejected',async()=>{
 await connect();let c=await command(owner,'secret');
 await db.exec("update korlix_meta_connections set expires_at=now()-interval '1 second'");
 assert.equal((await(await req('/connection',null,owner,'GET')).json()).connection.needs_reconnect,true);
 assert.equal((await req('/accounts',{})).status,409);
 await db.exec("update korlix_meta_connections set expires_at=now()+interval '1 day'");
 assert.equal((await command(owner,'status',{config_hash:'changed'})).connection.needs_reconnect,true);
 await command(owner,'disconnect',{version:c.version});
 await assert.rejects(command(owner,'accounts',{version:c.version,accounts:[acc]}),/connection changed/);
 const fresh=await connect();assert.notEqual(fresh.connection.version,c.version);
 await assert.rejects(command(owner,'accounts',{version:c.version,accounts:[acc]}),/connection changed/);
 await assert.rejects(command(owner,'invalid',{version:c.version}),/connection changed/);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await req('/accounts',{})).status,403);
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Graph adapter checks app, scope and expiry, uses appsecret proof, and never follows provider paging URLs',async()=>{
 const calls=[];const pages=[{access_token:'short'},{access_token:'long'},{data:{app_id:cfg.id,is_valid:true,type:'USER',user_id:'101',scopes:['ads_read'],expires_at:Math.floor(Date.now()/1000)+3600}},{data:[{id:'act_1',name:'A',currency:'USD',timezone_name:'UTC',account_status:1}],paging:{next:'https://evil.example/steal',cursors:{after:'next-cursor'}}},{data:[]}];
 const p=createMetaProvider(cfg,{fetchImpl:async(url,options)=>{calls.push({url,options});return {ok:true,json:async()=>pages.shift()};}});
 const x=await p.exchange('code');assert.equal(x.token,'long');assert.equal((await p.accounts('long')).length,1);
 for(const call of calls){assert.equal(call.url.hostname,'graph.facebook.com');assert.equal(call.options.redirect,'error');}
 assert.equal(calls[3].options.headers.Authorization,'Bearer long');assert(calls[3].url.searchParams.get('appsecret_proof'));assert.equal(calls[4].url.searchParams.get('after'),'next-cursor');assert(!calls[3].url.searchParams.has('access_token'));
 const bad=createMetaProvider(cfg,{fetchImpl:async()=>({ok:true,json:async()=>({access_token:'t',data:{app_id:'wrong',is_valid:true}})})});await assert.rejects(bad.exchange('code'),/Approve read access/);
 const denied=createMetaProvider(cfg,{fetchImpl:async()=>({ok:false,json:async()=>({error:{code:190,message:'sensitive provider response'}})})});await assert.rejects(denied.accounts('x'),e=>e.message.includes('Reconnect')&&!e.message.includes('sensitive'));
});
test('Signed deauthorization is validated; old events cannot delete a newer connection',async()=>{
 const event={algorithm:'HMAC-SHA256',user_id:'10101',issued_at:Math.floor(Date.now()/1000)};
 const payload=Buffer.from(JSON.stringify(event)).toString('base64url');const signed=createHmac('sha256',cfg.secret).update(payload).digest('base64url')+'.'+payload;
 assert.equal(verifiedMetaEvent(signed,cfg.secret).meta_user_id,'10101');assert.throws(()=>verifiedMetaEvent(signed+'x',cfg.secret));
 await connect();await command(null,'deauthorize',{meta_user_id:'10101',issued_at:event.issued_at-10});assert((await command(owner,'status')).connection);
 await db.exec("update korlix_meta_connections set connected_at=now()-interval '1 minute'");
 assert.equal((await req('/deauthorize',{signed_request:signed})).status,200);assert.equal((await command(owner,'status')).connection,null);
 assert.equal((await req('/deauthorize',{signed_request:'fake'})).status,400);
});
