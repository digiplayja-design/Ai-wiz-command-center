import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {autoEmailAuthAlias, autoEmailAppRouteAllowed, registerAutoEmailAppRoutes} from '../security/auto_email_app.mjs';

test('Auto-Email permits only pilot draft operations, with exact methods and routes', () => {
  const id='12345678-1234-1234-8234-123456789012';
  const allowed=[['GET','/api/auto-email/session'],['GET','/api/live-convo/agents/nova/email/drafts?limit=100'],['GET','/api/live-convo/agents/nova/email/rules'],['POST','/api/live-convo/agents/nova/email/drafts'],['PATCH',`/api/live-convo/agents/nova/email/drafts/${id}`],['POST','/api/auto-email/auth/refresh']];
  for(const [method,originalUrl] of allowed) assert.equal(autoEmailAppRouteAllowed({method,originalUrl}),true,originalUrl);
  const denied=[['POST','/api/live-convo/agents'],['POST',`/api/live-convo/agents/nova/email/drafts/${id}/send`],['POST',`/api/live-convo/agents/nova/email/drafts/${id}/approve`],['PATCH',`/api/live-convo/agents/nova/email/rules/${id}`],['PUT','/api/live-convo/agents/nova/email/settings'],['POST','/api/live-convo/agents/nova/email/recipients'],['GET','/api/live-convo/agents/nova%2femail/drafts'],['GET','/api/auto-email/session/extra'],['GET','/api/me']];
  for(const [method,originalUrl] of denied) assert.equal(autoEmailAppRouteAllowed({method,originalUrl}),false,originalUrl);
});

test('Auto-Email auth aliases override spoofed scope and never expose another user’s workspace', async t => {
  const owner='12345678-1234-1234-8234-123456789012',other='22345678-1234-1234-8234-123456789012';
  const app=express();app.use(express.json());app.use(autoEmailAuthAlias);
  registerAutoEmailAppRoutes(app,{requireUser:async req=>{if(!req.headers.authorization)throw Object.assign(new Error('secret details'),{statusCode:401});return{id:req.headers.authorization,email:'fixture@example.test'};},loadProfile:async()=>({tier:'basic',full_name:'Pilot',is_admin:true}),environment:{KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'private-assistant'}});
  app.post('/api/auth/signin',(req,res)=>res.json({path:req.url,original:req.originalUrl,app:req.headers['x-korlix-app'],body:req.body}));
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>new Promise(r=>server.close(r)));
  const base=`http://127.0.0.1:${server.address().port}`;
  const response=await fetch(base+'/api/auto-email/auth/signin',{method:'POST',headers:{'content-type':'application/json','x-korlix-app':'korlix_ai'},body:JSON.stringify({client_app:'korlix_ai'})});
  const alias=await response.json();assert.equal(alias.app,'auto_email');assert.equal(alias.body.client_app,'auto_email');assert.equal(alias.original,'/api/auto-email/auth/signin');
  for(const path of ['/api/auto-email/auth/signup','/api/auto-email/auth/signin/extra']) assert.equal((await fetch(base+path,{method:'POST'})).status,404);
  assert.equal((await fetch(base+'/api/auto-email/session')).status,401);
  const own=await(await fetch(base+'/api/auto-email/session',{headers:{authorization:owner}})).json();
  assert.deepEqual(own.workspace,{agentId:'nova'});assert.equal(own.profile.is_admin,undefined);assert.equal(own.capabilities.sending,false);
  const otherSession=await(await fetch(base+'/api/auto-email/session',{headers:{authorization:other}})).json();assert.equal(otherSession.workspace,null);
  const status=await fetch(base+'/api/auto-email/status');assert.equal(status.headers.get('cache-control'),'no-store');assert.equal((await status.json()).mailboxOAuth,false);
});
