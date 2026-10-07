import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import express from 'express';
import {sandboxWebhookProbe} from '../directory/webhook_probe.mjs';
import {registerDirectory} from '../directory/routes.mjs';
import {directoryBilling} from '../directory/billing.mjs';

const probeId='a'.repeat(32),sandboxSecret='whsec_sandboxfixture';
const liveCredentials={KORLIX_DIRECTORY_STRIPE_SECRET_KEY:'rk_live_fixture',KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET:'whsec_livefixture'};
const environment=now=>({...liveCredentials,KORLIX_DIRECTORY_STRIPE_SANDBOX_WEBHOOK_SECRET:sandboxSecret,KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_ID:probeId,KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_EXPIRES:new Date(now+3600000).toISOString()});
const event=()=>({livemode:false,type:'customer.subscription.updated',data:{object:{id:'sub_synthetic',metadata:{korlix_directory:'11111111-1111-4111-8111-111111111111',korlix_directory_delivery_probe:probeId}}}});
function signed(value,time,secret=sandboxSecret){const raw=Buffer.from(JSON.stringify(value)),t=Math.floor(time/1000);return {raw,signature:`t=${t},v1=${createHmac('sha256',secret).update(t+'.').update(raw).digest('hex')}`};}

test('sandbox delivery requires a fresh intact signature, test mode and exact probe metadata',()=>{
 const time=Date.now(),probe=sandboxWebhookProbe(environment(time),()=>time),good=signed(event(),time);
 assert.equal(probe.receive(good.raw,'forged'),null);
 assert.equal(probe.receive(Buffer.from('{}'),good.signature),null);
 const stale=signed(event(),time-301000);assert.equal(probe.receive(stale.raw,stale.signature),null);
 for(const value of [{...event(),livemode:true},{...event(),livemode:undefined}]){
  const s=signed(value,time);assert.equal(probe.receive(s.raw,s.signature).status,400);
 }
 for(const value of [{...event(),type:'customer.subscription.created'},{...event(),data:{object:{metadata:{korlix_directory_delivery_probe:'wrong'}}}}]){
  const s=signed(value,time);assert.equal(probe.receive(s.raw,s.signature).status,200);assert.equal(probe.status().verified,false);
 }
 assert.equal(probe.receive(good.raw,good.signature).status,200);
 assert.deepEqual(probe.status(),{enabled:true,verified:true,receivedAt:new Date(time).toISOString(),eventType:'customer.subscription.updated'});
 assert(!JSON.stringify(probe.status()).includes(probeId));assert(!JSON.stringify(probe.status()).includes(sandboxSecret));
});

test('delivery check defaults off, rejects shared secrets and expires within two hours',()=>{
 let time=Date.now();const env=environment(time);
 for(const invalid of [{},{...env,KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_ID:''},{...env,KORLIX_DIRECTORY_STRIPE_SANDBOX_WEBHOOK_SECRET:liveCredentials.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET},{...env,KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_EXPIRES:new Date(time-1).toISOString()},{...env,KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_EXPIRES:new Date(time+7200001).toISOString()}]){
  const probe=sandboxWebhookProbe(invalid,()=>time),s=signed(event(),time);
  assert.equal(probe.status().enabled,false);assert.equal(probe.receive(s.raw,s.signature),null);
 }
 const probe=sandboxWebhookProbe(env,()=>time);time+=3600000;
 const s=signed(event(),time);assert.equal(probe.status().enabled,false);assert.equal(probe.receive(s.raw,s.signature),null);
});

test('sandbox HTTP delivery never reads the provider or writes memberships; live reconciliation still works',async()=>{
 let time=Date.now(),providerReads=0;const writes=[];
 const business='11111111-1111-4111-8111-111111111111';
 const billing=directoryBilling(liveCredentials,{fetcher:async()=>{providerReads++;return {ok:true,json:async()=>({id:'sub_livefixture',customer:'cus_livefixture',livemode:true,status:'active',metadata:{korlix_directory:business,generation:'22222222-2222-4222-8222-222222222222'},items:{data:[{quantity:1,current_period_end:2000000000,price:{currency:'usd',unit_amount:499,recurring:{interval:'month',interval_count:1}}}]},latest_invoice:{id:'in_livefixture',customer:'cus_livefixture',livemode:true,currency:'usd',subscription:'sub_livefixture',status:'paid',amount_paid:499,amount_due:499,amount_remaining:0}})};}});
 const app=express();app.use(express.json({verify:(q,r,b)=>q.korlixDirectoryRawBody=Buffer.from(b)}));
 registerDirectory(app,{environment:environment(time),now:()=>time,billing,store:{command:async(...args)=>{writes.push(args);return {ok:true};}}});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 const root='http://127.0.0.1:'+server.address().port+'/api/directory';
 const post=async(s)=>fetch(root+'/billing/webhook',{method:'POST',headers:{'Content-Type':'application/json','stripe-signature':s.signature},body:s.raw});
 try{
  assert.equal((await post(signed(event(),time))).status,200);
  assert.equal((await post(signed({...event(),livemode:true},time))).status,400);
  assert.equal(providerReads,0);assert.equal(writes.length,0);
  const health=await(await fetch(root+'/health')).json();assert.equal(health.sandboxWebhookProbe.verified,true);assert.equal(health.livePayments,true);assert.equal(health.checkoutEnabled,false);
  assert(!JSON.stringify(health).includes(probeId));assert(!JSON.stringify(health).includes('whsec_'));
  assert.equal((await post(signed({...event(),livemode:true},time,liveCredentials.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET))).status,200);
  assert.equal(providerReads,1);assert.equal(writes.length,1);assert.equal(writes[0][2],'billing_apply');assert.equal(writes[0][4].livemode,true);
  time+=3600000;assert.equal((await post(signed(event(),time))).status,400);
  assert.equal(providerReads,1);assert.equal(writes.length,1);
 }finally{await new Promise(r=>server.close(r));}
});
