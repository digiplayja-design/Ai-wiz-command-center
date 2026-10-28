import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {registerAutoEmailMailboxRoutes} from '../auto_email/mailboxes.mjs';
import {autoEmailAppRouteAllowed} from '../security/auto_email_app.mjs';
import {createMailboxCipher,browserProof,verifyBrowserProof,digest,connectionBinding,MAILBOX_ROOT} from '../auto_email/mailbox-security.mjs';
import {authorizationUrl,exchangeMailboxCode} from '../auto_email/mailbox-providers.mjs';
const owner='12345678-1234-1234-8234-123456789012',other='22345678-1234-1234-8234-123456789012',device='fixture_auto_email_device';
const KEY='a4'.repeat(32),now=()=>Date.now();
const env={KORLIX_AUTO_EMAIL_MAILBOX_OAUTH_ENABLED:'true',KORLIX_AUTO_EMAIL_TOKEN_KEY:KEY,KORLIX_AUTO_EMAIL_GOOGLE_CLIENT_ID:'google-fixture',KORLIX_AUTO_EMAIL_GOOGLE_CLIENT_SECRET:'fixture-secret',KORLIX_AUTO_EMAIL_MICROSOFT_CLIENT_ID:'ms-fixture',KORLIX_AUTO_EMAIL_MICROSOFT_CLIENT_SECRET:'fixture-secret',KORLIX_AUTO_EMAIL_APP_ORIGIN:'https://app.example.test',KORLIX_AUTO_EMAIL_API_ORIGIN:'https://api.example.test',KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'private-assistant'};
class Store {
 flows=new Map();connections=new Map();generations=new Map();
 key(c,p=c.provider){return [c.user_id,c.agent_id,p].join(':');}
 async cleanup(){}
 async list(c){return [...this.connections.values()].filter(r=>r.user_id===c.user_id&&r.agent_id===c.agent_id);}
 async begin(f){const k=this.key(f),g=(this.generations.get(k)||0)+1;this.generations.set(k,g);for(const row of this.flows.values())if(this.key(row)===k){row.status='cancelled';row.secrets=null;}this.flows.set(f.id,{...f,generation:g,status:'pending',expires_at:new Date(now()+600000).toISOString()});return{id:f.id,expiresAt:new Date(now()+600000).toISOString()};}
 async claim(p,s,b,time){const f=[...this.flows.values()].find(f=>f.provider===p&&f.state_hash===s&&f.browser_hash===b&&f.status==='pending'&&Date.parse(f.expires_at)>time);if(!f)return null;f.status='exchanging';f.state_hash=null;return structuredClone(f);}
 async complete(f,values,time){const row=this.flows.get(f.id);if(row.status!=='exchanging'||Date.parse(row.expires_at)<=time)return null;Object.assign(row,values);return{id:f.id};}
 async getFlow(c,id){const f=this.flows.get(id);return f&&this.key(f)===this.key(c,f.provider)&&f.device_hash===c.device_hash?structuredClone(f):null;}
 async confirm(c,id,secrets){const f=this.flows.get(id),k=this.key(f);if(f.status!=='review'||f.generation!==this.generations.get(k))return{confirmed:false};this.connections.set(k,{...c,provider:f.provider,identity:f.identity,secrets,status:'connected'});f.secrets=null;f.status='confirmed';return{confirmed:true,identity:f.identity};}
 async cancel(c,id){const f=this.flows.get(id);if(['pending','exchanging','review'].includes(f.status)){f.status='cancelled';f.secrets=null;return{id};}return null;}
 async disconnect(c,p){const k=this.key(c,p);this.generations.set(k,(this.generations.get(k)||0)+1);this.connections.delete(k);for(const f of this.flows.values())if(this.key(f)===k){f.status='cancelled';f.secrets=null;f.identity=null;}}
}
async function fixture(t,{environment=env,exchange}={}){
 const store=new Store(),app=express();app.use(express.json());let exchanges=0;
 registerAutoEmailMailboxRoutes(app,{environment,store,cleanup:false,requireUser:async req=>{if(!req.headers.authorization)throw Object.assign(Error('private'),{statusCode:401});assert(autoEmailAppRouteAllowed(req));return{id:req.headers.authorization};},exchange:exchange|| (async()=>{exchanges++;return{identity:{accountId:'mailbox-123',email:'owner@example.test',displayName:'Owner'},tokens:{accessToken:'secret-access',refreshToken:'secret-refresh'},scopes:['fixture']};})});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>new Promise(r=>server.close(r)));const base=`http://127.0.0.1:${server.address().port}${MAILBOX_ROOT}`;
 const request=(path='',{method='GET',body,user=owner,deviceId=device,headers={}}={})=>fetch(base+path,{method,redirect:'manual',headers:{authorization:user,'x-korlix-device-id':deviceId,'content-type':'application/json',...headers},...(body?{body:JSON.stringify(body)}:{})});
 async function start(p='google'){
  const bootstrap=await request(`/oauth/${p}/bootstrap`),location=new URL(bootstrap.headers.get('location')),cookie=bootstrap.headers.get('set-cookie').split(';')[0],proof=new URLSearchParams(location.hash.slice(1)).get('proof');
  assert.match(bootstrap.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Lax/);assert.equal(location.origin,'https://app.example.test');
  const r=await request(`/${p}/authorize`,{method:'POST',body:{browserProof:proof}});assert.equal(r.status,200);const result=await r.json(),url=new URL(result.authorizationUrl);assert.equal(url.searchParams.get('code_challenge_method'),'S256');assert(!JSON.stringify(result).includes('fixture-secret'));return{...result,state:url.searchParams.get('state'),cookie};
 }
 return{store,request,start,base,exchanges:()=>exchanges};
}
test('credentials are encrypted, bound to owner/provider, and browser proofs reject forgery or expiry',()=>{
 const cipher=createMailboxCipher(KEY),binding='one-owner:google',e=cipher.encrypt({refreshToken:'super-secret'},binding);assert(!JSON.stringify(e).includes('super-secret'));assert.deepEqual(cipher.decrypt(e,binding),{refreshToken:'super-secret'});assert.throws(()=>cipher.decrypt(e,'another-owner:google'));assert.throws(()=>cipher.decrypt({...e,tag:'x'},binding));
 const n=now(),proof=browserProof(KEY,{provider:'google',browserHash:digest('cookie'),expiresAt:n+60000});assert.equal(verifyBrowserProof(KEY,proof,'google',n),digest('cookie'));assert.throws(()=>verifyBrowserProof(KEY,proof,'microsoft',n));assert.throws(()=>verifyBrowserProof(KEY,proof,'google',n+60001));assert.throws(()=>verifyBrowserProof(KEY,proof.slice(0,-8)+'AAAAAAAA','google',n));
});
test('full consent callback requires its browser cookie, explicit review, owner and device; tokens never enter responses',async t=>{
 const f=await fixture(t),s=await f.start();
 assert.equal((await f.request(`/oauth/google/callback?state=${s.state}&code=fixture`)).status,400);assert.equal(f.exchanges(),0);
 assert.equal((await f.request(`/oauth/microsoft/callback?state=${s.state}&code=fixture`,{headers:{cookie:s.cookie}})).status,400);
 const cb=await f.request(`/oauth/google/callback?state=${s.state}&code=fixture`,{headers:{cookie:s.cookie}});assert.equal(cb.status,303);assert.equal(f.exchanges(),1);assert.match(cb.headers.get('location'),new RegExp(s.flowId+'$'));assert.equal(f.store.connections.size,0);
 assert.equal((await f.request(`/oauth/google/callback?state=${s.state}&code=fixture`,{headers:{cookie:s.cookie}})).status,400);assert.equal(f.exchanges(),1);
 assert.equal((await f.request(`/flows/${s.flowId}`,{user:other})).status,403);assert.equal((await f.request(`/flows/${s.flowId}`,{deviceId:'another_fixture_device'})).status,404);
 const review=await(await f.request(`/flows/${s.flowId}`)).json();assert.equal(review.status,'review');assert.equal(review.identity.email,'owner@example.test');assert(!JSON.stringify(review).includes('secret-'));
 assert.equal((await f.request(`/flows/${s.flowId}/confirm`,{method:'POST',body:{accountId:'someone-else'}})).status,409);
 const response=await f.request(`/flows/${s.flowId}/confirm`,{method:'POST',body:{accountId:'mailbox-123'}});assert.equal(response.status,200);const result=await response.json();assert.equal(result.sending,false);assert(!JSON.stringify(result).includes('secret-'));
 const row=[...f.store.connections.values()][0];assert.equal(createMailboxCipher(KEY).decrypt(row.secrets,connectionBinding(row)).refreshToken,'secret-refresh');assert.equal(f.store.flows.get(s.flowId).secrets,null);
 assert.equal((await f.request(`/flows/${s.flowId}/confirm`,{method:'POST',body:{accountId:'mailbox-123'}})).status,409);
 await f.request('/google/disconnect',{method:'POST',body:{}});assert.equal(f.store.connections.size,0);
});
test('cancel, declined consent, and disconnect during exchange cannot activate a mailbox',async t=>{
 let release,entered;const waiting=new Promise(r=>entered=r),hold=new Promise(r=>release=r);
 const f=await fixture(t,{exchange:async()=>{entered();await hold;return{identity:{accountId:'x',email:'x@example.test'},tokens:{refreshToken:'r'},scopes:[]};}}),s=await f.start();
 const callback=f.request(`/oauth/google/callback?state=${s.state}&code=fixture`,{headers:{cookie:s.cookie}});await waiting;await f.request('/google/disconnect',{method:'POST',body:{}});release();assert.equal((await callback).status,400);assert.equal(f.store.connections.size,0);assert.equal(f.store.flows.get(s.flowId).secrets,null);
 const declined=await f.start();await f.request(`/oauth/google/callback?state=${declined.state}&error=access_denied&error_description=SECRET`,{headers:{cookie:declined.cookie}});const status=await(await f.request(`/flows/${declined.flowId}`)).json();assert.equal(status.errorCode,'consent_declined');assert(!JSON.stringify(status).includes('SECRET'));assert.equal(f.store.flows.get(declined.flowId).secrets,null);
});
test('unconfigured providers fail closed and mixed routes, methods and caller-supplied destinations are refused',async t=>{
 const f=await fixture(t,{environment:{...env,KORLIX_AUTO_EMAIL_MAILBOX_OAUTH_ENABLED:'false'}});const status=await(await f.request()).json();assert(status.providers.every(p=>!p.available));assert.equal((await f.request('/google/authorize',{method:'POST',body:{browserProof:'anything'}})).status,503);assert.equal((await f.request('',{user:''})).status,401);
 const live=await fixture(t);assert.equal((await live.request('/oauth/google/bootstrap?return_to=https://evil.example')).status,400);assert.equal((await live.request('/google/send',{method:'POST',body:{}})).status,404);assert.equal((await live.request('/google/authorize',{method:'POST',body:{returnTo:'https://evil.example'}})).status,400);
 assert.equal(autoEmailAppRouteAllowed({method:'POST',originalUrl:'/api/auto-email/mailboxes/google/send'}),false);
});
test('provider exchanges bind PKCE, check sending scopes and read identity only from fixed authenticated endpoints',async()=>{
 for(const id of ['google','microsoft']){
  const requests=[],config={id,clientId:'client',clientSecret:'server-secret',tenant:'organizations',redirectUri:'https://api.example.test/callback'},scopes=id==='google'?'openid email https://www.googleapis.com/auth/gmail.send':'Mail.Send User.Read';
  const fetcher=async(url,options)=>{requests.push([url,options]);return new Response(JSON.stringify(requests.length===1?{access_token:'a',refresh_token:'r',expires_in:3600,token_type:'Bearer',scope:scopes}:id==='google'?{sub:'g1',email:'me@example.test',email_verified:true}:{id:owner,mail:'me@example.test',displayName:'Me'}));};
  const result=await exchangeMailboxCode(config,'code','verifier',{fetcher});assert.equal(result.identity.email,'me@example.test');assert.equal(new URLSearchParams(requests[0][1].body).get('code_verifier'),'verifier');assert.equal(requests[1][1].headers.Authorization,'Bearer a');assert(requests.every(r=>r[1].redirect==='error'));assert(!authorizationUrl(config,{state:'state',verifier:'verifier'}).includes('server-secret'));
 }
 const config={id:'google',clientId:'c',clientSecret:'s',redirectUri:'https://api.example.test/callback'};
 for(const token of [{access_token:'a',expires_in:3600,token_type:'Bearer',scope:'openid email'}, {access_token:'a',refresh_token:'r',expires_in:3600,token_type:'Bearer',scope:'openid email'}, {access_token:'a',refresh_token:'r',expires_in:3600,token_type:'Bearer',scope:'https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly'}]){
  await assert.rejects(exchangeMailboxCode(config,'c','v',{fetcher:async()=>new Response(JSON.stringify(token))}));
 }
});
