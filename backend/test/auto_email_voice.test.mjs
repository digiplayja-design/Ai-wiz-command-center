import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {EventEmitter} from 'node:events';
import {createAutoEmailVoiceBridge,autoEmailVoiceReady,autoEmailVoiceTools,autoEmailVoiceInstructions} from '../auto_email/voice.mjs';
import {autoEmailAppRouteAllowed} from '../security/auto_email_app.mjs';

const owner='12345678-1234-1234-8234-123456789012',sessionId='22345678-1234-1234-8234-123456789012',device='email_fixture_device_123';
const env={KORLIX_VAPI_NOVA_OWNER_UID:owner,KORLIX_VAPI_NOVA_AGENT_ID:'nova',KORLIX_VAPI_NOVA_ASSISTANT_ID:'fixture',KORLIX_LIVE_CONVO_ENABLED:'true',OPENAI_API_KEY:'fixture-server-only-key'};
function response(){const res=new EventEmitter();res.headers={};res.set=(key,v)=>res.headers[key.toLowerCase()]=v;res.getHeader=key=>res.headers[key.toLowerCase()];res.writableFinished=true;return res;}
function setup(t){let clock=Date.now(),timer,stopped=false,calls=[];const bridge=createAutoEmailVoiceBridge({environment:env,requireUser:async req=>{if(!req.headers.authorization)throw Object.assign(Error('Sign in.'),{statusCode:401});return{id:req.headers.authorization};},now:()=>clock,fetcher:async(url,options)=>{calls.push({url,options});return new Response(null,{status:200});},setTimer:(fn,ms)=>{timer={fn,ms};return {unref(){}};},clearTimer:()=>{stopped=true;}});t.after(()=>bridge.close());return{bridge,calls,clock:n=>clock+=n,timer:()=>timer,stopped:()=>stopped};}
async function server(t,bridge){const app=express();app.use(express.json());app.use(bridge.alias);app.post('/api/live-convo/session',express.text({type:'application/sdp'}),(req,res)=>{req.korlixLiveConvoBuild129={sessionId};const limits=bridge.limits(req,{maxSessionSeconds:600,maxResponses:30,remainingSeconds:900});res.set('X-Korlix-Live-Convo-Session-Id',sessionId);bridge.started(req,res,new Response(null,{headers:{location:'/v1/realtime/calls/rtc_fixture'}}));res.json({original:req.originalUrl,isolated:!!req.korlixAutoEmailVoice,limits,sdp:req.body});});app.post('/api/live-convo/usage',(req,res)=>res.json({ok:true,sessionId:req.body.sessionId}));app.get('/api/live-convo/usage',(req,res)=>res.json({ok:true}));const s=app.listen(0,'127.0.0.1');await new Promise(r=>s.once('listening',r));t.after(()=>new Promise(r=>s.close(r)));return`http://127.0.0.1:${s.address().port}`;}
const headers={authorization:owner,'x-korlix-device-id':device,'content-type':'application/json'};

test('voice routes retain owner authorization, exact app scope, and reject mixed modes before reservation',async t=>{
 const {bridge}=setup(t),base=await server(t,bridge);
 for(const path of ['status','usage']){assert.equal((await fetch(base+'/api/auto-email/voice/'+path)).status,401);assert.equal((await fetch(base+'/api/auto-email/voice/'+path,{headers:{...headers,authorization:'other-user'}})).status,403);}
 assert.equal((await fetch(base+'/api/auto-email/voice/session?crm=1',{method:'POST',headers})).status,400);
 assert.equal((await fetch(base+'/api/auto-email/voice/session/extra',{method:'POST',headers})).status,404);
 assert.equal((await fetch(base+'/api/auto-email/voice/status',{headers})).status,200);
 for(const [method,path] of [['POST','session'],['POST','end'],['POST','usage'],['GET','status'],['GET','usage']])assert(autoEmailAppRouteAllowed({method,originalUrl:'/api/auto-email/voice/'+path}));
 assert(!autoEmailAppRouteAllowed({method:'POST',originalUrl:'/api/live-convo/session'}));assert(!autoEmailAppRouteAllowed({method:'POST',originalUrl:'/api/live-convo/usage'}));
});

test('signed call proof binds usage and provider hangup to the issued owner, device, and session',async t=>{
 const ctx=setup(t),base=await server(t,ctx.bridge);
 const started=await fetch(base+'/api/auto-email/voice/session',{method:'POST',headers:{...headers,'content-type':'application/sdp'},body:'v=0\r\nfixture-offer'});assert.equal(started.status,200);
 const proof=started.headers.get('x-korlix-auto-email-voice-proof'),body=await started.json();assert.equal(body.sdp,'v=0\r\nfixture-offer');assert.equal(body.original,'/api/auto-email/voice/session');assert(body.isolated);assert.equal(body.limits.maxSessionSeconds,180);assert.equal(body.limits.maxResponses,20);assert.equal(ctx.timer().ms,180000);assert(!proof.includes(env.OPENAI_API_KEY));
 const post=(path,extra={},value={sessionId})=>fetch(base+'/api/auto-email/voice/'+path,{method:'POST',headers:{...headers,'x-korlix-auto-email-voice-proof':proof,...extra},body:JSON.stringify(value)});
 assert.equal((await post('usage')).status,200);
 assert.equal((await post('usage',{'x-korlix-device-id':'different_device_123'})).status,403);
 assert.equal((await post('usage',{}, {sessionId:owner})).status,403);
 assert.equal((await post('usage',{'x-korlix-auto-email-voice-proof':proof.slice(0,-4)+'xxxx'})).status,403);
 assert.equal((await post('end')).status,200);assert(ctx.stopped());assert.equal(ctx.calls[0].url,'https://api.openai.com/v1/realtime/calls/rtc_fixture/hangup');
 ctx.clock(21*60*1000);assert.equal((await post('usage')).status,403);
});

test('provider locations cannot redirect hangup requests; deadline hangs up the server-issued call',async t=>{
 const ctx=setup(t),req={korlixAutoEmailVoice:{userId:owner,device},korlixLiveConvoBuild129:{sessionId}};
 for(const location of ['https://attacker.example/rtc_fake','/v1/realtime/calls/../secret','/v1/realtime/calls/rtc_bad?redirect=1',''])assert.throws(()=>ctx.bridge.started(req,response(),new Response(null,{headers:{location}})));
 ctx.bridge.started(req,response(),new Response(null,{headers:{location:'https://api.openai.com/v1/realtime/calls/rtc_valid'}}));ctx.timer().fn();await new Promise(r=>setImmediate(r));assert.equal(ctx.calls.length,1);assert.equal(ctx.calls[0].options.redirect,'error');
});

test('voice readiness fails closed; only an unsaved proposal tool is offered',()=>{
 assert(autoEmailVoiceReady(env));assert(!autoEmailVoiceReady({...env,OPENAI_API_KEY:''}));assert(!autoEmailVoiceReady({...env,KORLIX_LIVE_CONVO_ENABLED:'false'}));
 assert.deepEqual(autoEmailVoiceTools.map(x=>x.name),['prepare_email_draft']);assert.deepEqual(Object.keys(autoEmailVoiceTools[0].parameters.properties),['subject','textBody']);assert.match(autoEmailVoiceInstructions(),/Spoken confirmation cannot save or send/);
});
