import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {BRAIN_CATALOG,appleFacts,googleFacts,brainAccountId} from '../brain_voice/billing/catalog.mjs';
import {createBrainBilling} from '../brain_voice/billing/routes.mjs';
const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
const future=()=>Date.now()+86400000;
const apple=(extra={})=>({bundleId:'com.korlix.brain',appAccountToken:owner,productId:BRAIN_CATALOG[1].apple,transactionId:'123456',originalTransactionId:'123456',quantity:1,type:'Consumable',environment:'Production',...extra});
const google=(extra={})=>({obfuscatedExternalAccountId:brainAccountId(owner),purchaseStateContext:{purchaseState:'PURCHASED'},productLineItem:[{productId:BRAIN_CATALOG[1].google,productOfferDetails:{quantity:1,consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],...extra});
test('three approved GAS products and the 60-minute monthly plan are fixed',()=>{
 assert.deepEqual(BRAIN_CATALOG.map(x=>[x.seconds,x.usdCents]),[[3600,3499],[3600,3000],[7200,5500],[10800,8000]]);
});
test('store facts reject another account, app, product, quantity and non-approved sandbox',()=>{
 assert.equal(appleFacts(apple(),owner).seconds,3600);
 for(const extra of [{bundleId:'other.app'},{appAccountToken:other},{quantity:2},{productId:'unknown'},{type:'Non-Consumable'}])assert.throws(()=>appleFacts(apple(extra),owner));
 assert.throws(()=>appleFacts(apple({environment:'Sandbox'}),owner,{}),/testing/);
 assert.equal(appleFacts(apple({revocationDate:Date.now()}),owner).active,false);
 assert.throws(()=>googleFacts(google(),other,'valid-purchase-token',BRAIN_CATALOG[1].google),/different/);
 assert.equal(googleFacts(google({purchaseStateContext:{purchaseState:'PENDING'}}),owner,'valid-purchase-token',BRAIN_CATALOG[1].google).active,false);
 assert.equal(googleFacts(google({purchaseStateContext:{purchaseState:'CANCELLED'}}),owner,'valid-purchase-token',BRAIN_CATALOG[1].google).revoked,true);
});

async function database(t){
 const db=new PGlite();t.after(()=>db.close());
 await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);');
 await db.exec(await readFile(new URL('../../supabase/migrations/20261101113614_brain_voice_store_billing.sql',import.meta.url),'utf8'));
 await db.query('insert into auth.users values($1),($2)',[owner,other]);
 const call=async(actor,action,p={})=>(await db.query("select public.korlix_brain_billing_command($1,$2,$3) result",[actor,action,JSON.stringify(p)])).rows[0].result;
 return {db,call};
}
test('credits are durable and idempotent; refunds remove remaining GAS and cannot cross accounts',async t=>{
 const {db,call}=await database(t),facts=appleFacts(apple(),owner);
 assert.equal((await call(owner,'apply',facts)).gasSeconds,3600);
 assert.equal((await call(owner,'apply',facts)).gasSeconds,3600);
 await assert.rejects(call(other,'apply',facts),/linked/);
 const revoked={...facts,active:false,revoked:true,observed_at:new Date(Date.now()+1000).toISOString()};
 assert.equal((await call(owner,'apply',revoked)).gasSeconds,0);
 assert.equal((await call(owner,'apply',facts)).gasSeconds,0,'older active observation cannot undo refund');
 await db.exec('set role authenticated');
 await assert.rejects(call(owner,'snapshot'),/permission denied/);
 await assert.rejects(db.query('select * from public.korlix_brain_minute_grants'),/permission denied/);
});
test('renewals add one allowance per verified period and never reset used minutes on restore',async t=>{
 const {call,db}=await database(t);
 const facts=appleFacts(apple({type:'Auto-Renewable Subscription',productId:BRAIN_CATALOG[0].apple,expiresDate:future()}),owner);
 await call(owner,'apply',facts);
 await db.query('update korlix_brain_minute_grants set used_seconds=600');
 assert.equal((await call(owner,'apply',facts)).includedSeconds,3000);
 await db.query("update korlix_brain_minute_grants set expires_at=now()-interval '1 second'");
 const renewed={...facts,grant_key:'apple:Production:123457',observed_at:new Date(Date.now()+1000).toISOString()};
 assert.equal((await call(owner,'apply',renewed)).includedSeconds,3600);
});
test('reservation uses included minutes first, bills server time, and returns unused GAS once',async t=>{
 const {call,db}=await database(t);
 await call(owner,'apply',appleFacts(apple(),owner));
 await call(owner,'apply',appleFacts(apple({transactionId:'654321',originalTransactionId:'654321',type:'Auto-Renewable Subscription',productId:BRAIN_CATALOG[0].apple,expiresDate:future()}),owner));
 await db.query("update korlix_brain_minute_grants set used_seconds=3540 where kind='subscription'");
 const r=await call(owner,'reserve');assert.equal(r.maxSessionSeconds,3600);
 await assert.rejects(call(owner,'reserve'),/other Live Conversation/);
 await assert.rejects(call(other,'session',{sessionId:r.sessionId}),/not found/);
 await call(owner,'start',{sessionId:r.sessionId,callId:'rtc_fixture'});
 await db.query("update korlix_brain_voice_sessions set started_at=now()-interval '90 seconds' where id=$1",[r.sessionId]);
 await call(owner,'usage',{sessionId:r.sessionId,durationSeconds:999999});
 const first=await call(owner,'end',{sessionId:r.sessionId});
 assert(first.chargedSeconds>=90&&first.chargedSeconds<=92);
 const balance=await call(owner,'snapshot');assert.equal(balance.includedSeconds,0);
 assert.equal(balance.gasSeconds,3660-first.chargedSeconds);
 await call(owner,'end',{sessionId:r.sessionId});
 assert.deepEqual(await call(owner,'snapshot'),balance);
});
test('a failed provider connection releases all reserved minutes without charging',async t=>{
 const {call}=await database(t);await call(owner,'apply',appleFacts(apple(),owner));
 const r=await call(owner,'reserve');await call(owner,'end',{sessionId:r.sessionId});
 assert.equal((await call(owner,'snapshot')).gasSeconds,3600);
});
test('deadline terminates the provider and cannot charge beyond purchased seconds',async t=>{
 const {call,db}=await database(t);await call(owner,'apply',appleFacts(apple(),owner));
 const r=await call(owner,'reserve');await call(owner,'start',{sessionId:r.sessionId,callId:'rtc_deadline'});
 await db.query("update korlix_brain_voice_sessions set started_at=now()-interval '2 hours',deadline=now()-interval '1 hour' where id=$1",[r.sessionId]);
 const calls=[];const billing=createBrainBilling({store:call,autoStart:false,environment:{KORLIX_BRAIN_BILLING_ENABLED:'true',OPENAI_API_KEY:'fixture'},fetcher:async(url)=>{calls.push(url);return new Response(null,{status:200});}});
 const result=await billing.usage(owner,{sessionId:r.sessionId,durationSeconds:0});
 assert.equal(result.chargedSeconds,3600);assert.equal(result.allowed,false);
 assert.equal((await call(owner,'snapshot')).gasSeconds,0);
 assert.equal(calls.length,1);assert.match(calls[0],/rtc_deadline\/hangup$/);
 await billing.tick();assert.equal(calls.length,1);
 await assert.rejects(call(owner,'reserve'),/run out/);
});
test('refund termination failure survives in the durable worker queue for retry',async t=>{
 const {call,db}=await database(t);const facts=appleFacts(apple(),owner);await call(owner,'apply',facts);
 const r=await call(owner,'reserve');await call(owner,'start',{sessionId:r.sessionId,callId:'rtc_refund'});
 await call(owner,'apply',{...facts,active:false,revoked:true,observed_at:new Date(Date.now()+1000).toISOString()});
 let failHangup=true,calls=0;
 const billing=createBrainBilling({store:call,autoStart:false,environment:{KORLIX_BRAIN_BILLING_ENABLED:'true',OPENAI_API_KEY:'fixture'},fetcher:async()=>{calls++;return new Response(null,{status:failHangup?503:200});}});
 await assert.rejects(billing.usage(owner,{sessionId:r.sessionId}),/voice stopped/);
 assert.equal((await call(null,'stale_sessions')).length,1);
 failHangup=false;await billing.tick();
 assert.equal(calls,2);assert.equal((await call(null,'stale_sessions')).length,0);
 assert.equal((await call(owner,'snapshot')).gasSeconds,0);
 assert.equal((await db.query('select sum(reserved_seconds) n from korlix_brain_minute_grants')).rows[0].n,0);
});
test('verification ignores client user ID; store consumption follows durable grant',async t=>{
 const operations=[];const app=express();app.use(express.json());
 const billing=createBrainBilling({autoStart:false,requireUser:async()=>({id:owner,email_confirmed_at:'yes'}),store:async(actor,action)=>{operations.push(action);assert.equal(actor,owner);return{};},provider:{verify:async(_p,args)=>{assert.equal(args.userId,owner);return{provider:'google',active:true};},finish:async()=>operations.push('consume')}});
 billing.register(app);const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>server.close());
 const result=await fetch(`http://127.0.0.1:${server.address().port}/api/brain/billing/verify`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({provider:'google',productId:BRAIN_CATALOG[1].google,userId:other})});
 assert.equal(result.status,200);assert.deepEqual(operations,['apply','consume']);
});
