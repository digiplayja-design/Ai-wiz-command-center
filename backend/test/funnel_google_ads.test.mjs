import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerFunnels} from '../funnels/routes.mjs';
import {createGoogleAdsStore} from '../funnels/google_ads.mjs';
import {googleAdsConfiguration,googleTokenCipher,googleChallenge,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN:'fixture-developer-token',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'};
const cfg=googleAdsConfiguration(env),[owner,other,basic]=Array.from({length:3},()=>randomUUID());
const root='1234567890',id='9876543210',account={id,name:'Fixture advertiser',currency:'USD',timezone:'America/New_York',manager:false,status:'ENABLED',test_account:false};
let db,store,server,base,clock=Date.now(),calls=[],hook,exchangeHook,availableRoots;
const provider={
 authorizationUrl:(s,c)=>'https://accounts.google.com/o/oauth2/v2/auth?'+new URLSearchParams({state:s,code_challenge:c}),
 exchange:async(code,verifier)=>{calls.push(['exchange',code,verifier]);if(exchangeHook)await exchangeHook();return{refresh_token:'private-refresh-fixture',refresh_expires_at:null};},
 refresh:async t=>{calls.push(['refresh',t]);if(hook)await hook('refresh');return'private-access-fixture';},
 roots:async()=>{calls.push(['roots']);if(hook)await hook('roots');return availableRoots;},
 accounts:async(_t,r)=>{calls.push(['accounts',r]);if(hook)await hook('accounts');return{root:{...account,id:root,name:'Fixture manager',manager:true},accounts:[account]};},
 performance:async(_t,a,r,range)=>{calls.push(['performance',a.id,r,range]);if(hook)await hook('performance');return{rows:[{date:range.to,spend:'12.345678',impressions:100,clicks:3}],totals:{spend:'12.345678',impressions:100,clicks:3},reported_days:1};},
 account:async(_t,a,r)=>{calls.push(['account',a,r]);if(hook)await hook('account');return account;},
};
const command=(u,a,d={})=>store.command(u,a,d);
const req=(path,body,actor=owner,method='POST')=>fetch(base+'/api/funnels/google-ads'+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
async function begin(actor=owner){const r=await req('/begin',{},actor);assert.equal(r.status,200);return r.json();}
const callback=(a,extra='&code=fixture-code')=>fetch(base+'/api/funnels/google-ads/callback?state='+encodeURIComponent(new URL(a.authorization_url).searchParams.get('state'))+extra);
async function connect(){const a=await begin();assert.equal((await callback(a)).status,200);const r=await req('/finish',{id:a.id,proof:a.proof});assert.equal(r.status,200);return(await r.json()).connection;}
async function load(){let c=await connect();let r=await req('/roots',{version:c.version});assert.equal(r.status,200);c=(await r.json()).connection;r=await req('/accounts',{version:c.version,root_id:root});assert.equal(r.status,200);return(await r.json()).connection;}
const select=c=>req('/select',{version:c.version,root_id:root,account_id:id});
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);grant usage on schema public to anon,authenticated,service_role;grant select on user_profiles to service_role;');
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 await db.exec(await readFile(new URL('../../supabase/migrations/20260922233935_funnel_google_ads_connection.sql',import.meta.url),'utf8'));
 store=createGoogleAdsStore({rpc:async(name,p)=>{assert.equal(name,'korlix_google_ads_v1');try{return{data:await db.transaction(async tx=>{await tx.exec('set local role service_role');return(await tx.query('select korlix_google_ads_v1($1,$2,$3) r',[p.p_actor,p.p_action,JSON.stringify(p.p_data)])).rows[0].r;})};}catch(error){return{error};}}});
 const app=express();app.use(express.json());registerFunnels(app,{googleAdsStore:store,googleAdsProvider:provider,environment:env,now:()=>clock,requireUser:async q=>{const id=q.headers.authorization;if(![owner,other,basic].includes(id))throw Error();return{id};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{clock+=60000;calls=[];hook=null;exchangeHook=null;availableRoots=[root];await db.exec('delete from korlix_google_ads_connections;delete from korlix_google_ads_oauth_attempts;');await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server?.close(r));await db?.close();});
test('Tables, sequence and RPC are private; function is invoker and tables have RLS',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  for(const table of ['korlix_google_ads_connections','korlix_google_ads_oauth_attempts'])await assert.rejects(db.query('select * from '+table),/permission denied/);
  await assert.rejects(db.query("select nextval('korlix_google_ads_version_seq')"),/permission denied/);
  await assert.rejects(db.query('select korlix_google_ads_v1($1,$2,$3)',[owner,'status','{}']),/permission denied/);await db.exec('reset role');
 }
 const tables=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_google_ads_connections','korlix_google_ads_oauth_attempts')")).rows;assert.equal(tables.length,2);assert(tables.every(t=>t.relrowsecurity));
 assert.equal((await db.query("select prosecdef from pg_proc where proname='korlix_google_ads_v1'")).rows[0].prosecdef,false);
 assert.equal((await command(owner,'status')).connection,null);
});
test('Real owner middleware rejects missing authentication and database checks current Enterprise',async()=>{
 for(const path of ['/connection','/begin','/finish','/roots','/accounts','/select','/disconnect'])assert.equal((await req(path,path==='/connection'?null:{},'',path==='/connection'?'GET':'POST')).status,401);
 assert.equal((await req('/connection',null,basic,'GET')).status,403);assert.equal((await req('/begin',{},basic)).status,403);
 await connect();assert.equal((await(await req('/connection',null,other,'GET')).json()).connection,null);
 const readiness=await req('/readiness',null,'','GET');assert.equal(readiness.headers.get('cache-control'),'no-store');assert.deepEqual(await readiness.json(),{configured:true,ad_publishing_ready:false});
});
test('Single-use state, PKCE and private owner proof bind the original window; public projections have no credentials',async()=>{
 const a=await begin();assert.equal((await req('/begin',{})).status,429);assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,409);
 const saved=(await db.query('select * from korlix_google_ads_oauth_attempts')).rows[0];assert.notEqual(saved.state_hash,new URL(a.authorization_url).searchParams.get('state'));assert(!JSON.stringify(saved).includes(a.proof));
 const cb=await callback(a);assert.equal(cb.status,200);assert.equal(cb.headers.get('referrer-policy'),'no-referrer');assert.match(cb.headers.get('content-security-policy'),/frame-ancestors 'none'/);
 const verifier=calls.find(c=>c[0]==='exchange')[2];assert.equal(googleChallenge(verifier),new URL(a.authorization_url).searchParams.get('code_challenge'));assert(!JSON.stringify(saved).includes(verifier));
 assert.equal((await db.query('select verifier_sealed from korlix_google_ads_oauth_attempts')).rows[0].verifier_sealed,null);
 assert.equal((await callback(a)).status,409);assert.equal(calls.filter(c=>c[0]==='exchange').length,1);
 assert.equal((await req('/finish',{id:a.id,proof:a.proof},other)).status,409);assert.equal((await req('/finish',{id:a.id,proof:randomBytes(32).toString('base64url')})).status,409);
 const result=await(await req('/finish',{id:a.id,proof:a.proof})).json();assert(result.connection);const json=JSON.stringify(result)+(await cb.text());
 for(const secret of ['private-refresh-fixture','private-access-fixture','verifier_sealed','candidate','sealed','proof_hash','state_hash','config_hash','binding_id'])assert(!json.includes(secret));
 const c=await command(owner,'secret');assert.equal(googleTokenCipher(cfg.key).open(c.sealed,`korlix-google-ads:refresh:${owner}:${a.id}`),'private-refresh-fixture');
 assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,409);
});
test('Cancelled, expired, malformed and superseded callbacks never exchange or restore credentials',async()=>{
 const a=await begin();assert.equal((await callback(a,'&error=access_denied')).status,400);assert.equal(calls.length,0);assert.equal((await req('/finish',{id:a.id,proof:a.proof})).status,400);
 await db.exec("update korlix_google_ads_oauth_attempts set created_at=now()-interval '1 minute'");const b=await begin();assert.equal((await callback(a)).status,404);
 await db.exec("update korlix_google_ads_oauth_attempts set expires_at=now()-interval '1 second'");assert.equal((await callback(b)).status,409);
 assert.equal((await fetch(base+'/api/funnels/google-ads/callback?state=a&state=b&code=secret')).status,400);assert.equal(calls.length,0);
 await req('/disconnect',{confirmed:true});const c=await begin();await req('/disconnect',{confirmed:true});assert.equal((await callback(c)).status,404);
});
test('Disconnect and downgrade during exchange prevent candidate completion',async()=>{
 let a=await begin();exchangeHook=()=>command(owner,'disconnect');assert.equal((await callback(a)).status,409);assert.equal((await command(owner,'status')).connection,null);
 a=await begin();exchangeHook=()=>db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await callback(a)).status,403);assert.equal((await db.query('select count(*)::int n from korlix_google_ads_connections')).rows[0].n,0);
});
test('Account browsing and selection preserve manager context and enforce cache and current versions',async()=>{
 const c=await load();assert.equal(c.login_customer_id,root);assert.deepEqual(c.accounts,[account]);
 assert.equal((await req('/accounts',{root_id:id,version:c.version})).status,400);
 assert.equal((await req('/select',{root_id:root,account_id:'1111111111',version:c.version})).status,400);
 assert.equal((await select(c)).status,200);assert.deepEqual(calls.find(x=>x[0]==='account'),['account',id,root]);
 const before=calls.length;assert.equal((await select(c)).status,409);assert.equal(calls.length,before);
 const state=await command(owner,'status',{config_hash:cfg.hash});assert.equal(state.connection.selected_account,id);assert.notEqual(state.connection.version,c.version);
});
test('Removed direct access blocks browsing and selection without persisting new data',async()=>{
 const c=await load();availableRoots=[];assert.equal((await select(c)).status,409);assert.equal((await req('/accounts',{root_id:root,version:c.version})).status,409);assert.equal((await command(owner,'secret')).selected_account,null);
 assert.equal(calls.filter(c=>c[0]==='account').length,0);
});
for(const changed of ['disconnect','select','downgrade'])test('Late account selection is discarded after '+changed,async()=>{
 const c=await load();hook=async action=>{if(action!=='account')return;
  if(changed==='downgrade')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
  else await command(owner,changed,changed==='disconnect'?{version:c.version}:{version:c.version,config_hash:cfg.hash,root_id:root,account_id:id});
 };
 const r=await select(c);assert.equal(r.status,changed==='downgrade'?403:409);assert(!(await r.text()).includes(account.name));
});
test('Revoked authorization marks reconnect, clears account snapshots, and cannot poison a newer connection',async()=>{
 let c=await load();hook=async action=>{if(action==='refresh')throw new GoogleAdsAccessError();};assert.equal((await select(c)).status,409);
 let invalid=await command(owner,'secret');assert(invalid.needs_reconnect);assert.deepEqual(invalid.accounts,[]);assert.deepEqual(invalid.roots,[]);
 hook=null;await command(owner,'disconnect',{version:invalid.version});const fresh=await connect();assert.notEqual(fresh.version,c.version);await assert.rejects(command(owner,'invalid',{version:c.version}),/changed/);
});
test('Configuration or refresh expiry requires reconnect; unknown expiry remains usable',async()=>{
 const c=await connect();assert.equal((await command(owner,'status',{config_hash:cfg.hash})).connection.needs_reconnect,false);
 assert.equal((await command(owner,'status',{config_hash:'changed'})).connection.needs_reconnect,true);
 await db.exec("update korlix_google_ads_connections set refresh_expires_at=now()-interval '1 second'");assert.equal((await req('/roots',{version:c.version})).status,409);assert.equal(calls.filter(c=>c[0]==='refresh').length,0);
});
test('Refresh clears stale selected account and disconnect requires explicit current-version confirmation',async()=>{
 let c=await load();c=(await(await select(c)).json()).connection;let r=await req('/roots',{version:c.version});assert.equal(r.status,200);const fresh=(await r.json()).connection;assert.equal(fresh.selected_account,null);assert.deepEqual(fresh.accounts,[]);
 assert.equal((await req('/disconnect',{version:fresh.version})).status,400);assert.equal((await req('/disconnect',{version:c.version,confirmed:true})).status,409);
 assert.equal((await req('/disconnect',{version:fresh.version,confirmed:true})).status,200);assert.equal((await command(owner,'status')).connection,null);
 assert.equal((await db.query('select count(*)::int n from korlix_google_ads_oauth_attempts')).rows[0].n,0);
});
test('Google owner commands are rate limited before more provider work',async()=>{
 const c=await connect();let limited=false;
 for(let i=0;i<20;i++){const r=await req('/roots',{version:c.version});if(r.status===429){limited=true;break;}}
 assert(limited);assert.equal(calls.filter(c=>c[0]==='roots').length,1);
});

async function reportConnection(){let c=await load();return(await(await select(c)).json()).connection;}
const performance=(c,actor=owner,extra={})=>req('/performance?'+new URLSearchParams({days:'7',version:String(c.version),root_id:root,account_id:id,...extra}),null,actor,'GET');
test('Google performance is owner-scoped and selected-account scoped with no report persistence or credentials',async()=>{
 const c=await reportConnection();const before=(await db.query('select to_jsonb(c) value from korlix_google_ads_connections c')).rows;
 const r=await performance(c);assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');const body=await r.json();assert.equal(body.source,'google_ads');assert.equal(body.scope,'account');assert.equal(body.connection_version,c.version);assert.equal(body.root_id,root);assert.equal(body.account.id,id);assert.equal(body.totals.spend,'12.345678');
 for(const secret of ['sealed','config_hash','binding_id','private-refresh-fixture','private-access-fixture'])assert(!JSON.stringify(body).includes(secret));
 assert.deepEqual((await db.query('select to_jsonb(c) value from korlix_google_ads_connections c')).rows,before);
 assert.equal((await performance(c,'')).status,401);assert.equal((await performance(c,other)).status,404);assert.equal((await performance(c,basic)).status,403);
 assert.equal(calls.filter(c=>c[0]==='performance').length,1);
});
test('Invalid or stale Google report identity fails before token refresh or reporting',async()=>{
 const c=await reportConnection();calls=[];
 for(const change of [{version:String(c.version+1)},{root_id:id},{account_id:root},{days:'365'},{query:'secret'}])assert([400,409].includes((await performance(c,owner,change)).status));
 await db.exec('update korlix_google_ads_connections set selected_account=null');assert.equal((await performance(c)).status,409);assert.equal(calls.length,0);
});
for(const change of ['disconnect','select','roots','downgrade'])test('A '+change+' while Google reporting discards the late result',async()=>{
 const c=await reportConnection();hook=async action=>{if(action!=='performance')return;
  if(change==='downgrade')await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
  else await command(owner,change,{version:c.version,config_hash:cfg.hash,root_id:root,account_id:id,roots:[root]});
 };
 const r=await performance(c);assert([403,404,409].includes(r.status));assert(!(await r.text()).includes('12.345678'));
});
test('Removed Google manager access and revoked reporting permissions fail closed',async()=>{
 const c=await reportConnection();availableRoots=[];assert.equal((await performance(c)).status,409);assert.equal(calls.filter(c=>c[0]==='performance').length,0);
 availableRoots=[root];hook=async action=>{if(action==='performance')throw new GoogleAdsAccessError();};assert.equal((await performance(c)).status,409);const state=await command(owner,'secret');assert(state.needs_reconnect);assert.equal(state.selected_account,null);
});
test('Google performance has a separate ten-request owner rate limit',async()=>{
 const c=await reportConnection();for(let i=0;i<10;i++)assert.equal((await performance(c)).status,200);assert.equal((await performance(c)).status,429);assert.equal(calls.filter(c=>c[0]==='performance').length,10);
});
