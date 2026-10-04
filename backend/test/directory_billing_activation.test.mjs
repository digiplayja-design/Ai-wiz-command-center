import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import express from 'express';
import {directoryBilling,DIRECTORY_STRIPE_API_VERSION} from '../directory/billing.mjs';
import {registerDirectory} from '../directory/routes.mjs';

const business='11111111-1111-4111-8111-111111111111';
const generation='22222222-2222-4222-8222-222222222222';
const credentials={KORLIX_DIRECTORY_STRIPE_SECRET_KEY:'rk_test_fixture',KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET:'whsec_fixture'};
const subscription=()=>({id:'sub_fixture',customer:'cus_fixture',livemode:false,status:'active',metadata:{korlix_directory:business,generation},items:{data:[{quantity:1,current_period_end:2000000000,price:{currency:'usd',unit_amount:499,recurring:{interval:'month',interval_count:1}}}]},latest_invoice:{id:'in_fixture',status:'paid',amount_paid:499}});

test('credential check verifies the expected account portal without creating payments',async()=>{
 let requests=0;
 const billing=directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_PORTAL_CONFIGURATION_ID:'bpc_fixture'},{fetcher:async(url,options)=>{
  requests++;assert.equal(options.method,'GET');assert(url.endsWith('/billing_portal/configurations/bpc_fixture'));
  await new Promise(r=>setImmediate(r));return {ok:true,json:async()=>({id:'bpc_fixture',livemode:false,active:true})};
 }});
 assert.deepEqual(await Promise.all([billing.checkConnection(),billing.checkConnection()]),['verified','verified']);
 assert.equal(await billing.checkConnection(),'verified');assert.equal(requests,1);assert.equal(billing.ready,false);
});

test('wrong-account credentials and provider failures do not open checkout or expose errors',async()=>{
 for(const result of [{ok:false,json:async()=>({error:{message:'private provider detail'}})},{ok:true,json:async()=>({id:'bpc_other',livemode:false,active:true})},{ok:true,json:async()=>({id:'bpc_fixture',livemode:true,active:true})}]){
  let requests=0;
  const billing=directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_ENABLED:'true',KORLIX_DIRECTORY_STRIPE_PORTAL_CONFIGURATION_ID:'bpc_fixture'},{fetcher:async(url)=>{requests++;assert(url.includes('/billing_portal/configurations/'));return result;}});
  assert.notEqual(await billing.checkConnection(),'verified');
  await assert.rejects(billing.checkout(business,{interval:'month'},'synthetic@example.invalid'),/could not be verified/);
  assert.equal(requests,1);
 }
 assert.equal(await directoryBilling({}).checkConnection(),'credentials_missing');
});

test('a failed credential check retries after its bounded cache expires',async()=>{
 let time=100000,requests=0;
 const billing=directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_PORTAL_CONFIGURATION_ID:'bpc_fixture'},{now:()=>time,fetcher:async()=>{requests++;return {ok:requests>1,json:async()=>({id:'bpc_fixture',livemode:false,active:true})};}});
 assert.equal(await billing.checkConnection(),'unavailable');
 time+=60001;assert.equal(await billing.checkConnection(),'verified');assert.equal(requests,2);
});

test('credentials alone never enable checkout, including cached checkout links',async()=>{
 let requests=0;
 for(const enabled of [undefined,'false','1','TRUE']){
  const billing=directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_ENABLED:enabled},{fetcher:async()=>{requests++;throw Error('Unexpected payment request');}});
  assert.equal(billing.configured,true);assert.equal(billing.ready,false);
  await assert.rejects(billing.checkout(business,{checkout_id:'cs_old',checkout_url:'https://checkout.stripe.com/c/pay/old'},'synthetic@example.invalid'),/paused/);
 }
 assert.equal(requests,0);
 for(const key of ['', 'pk_live_fixture','not-a-key'])assert.equal(directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_ENABLED:'true',KORLIX_DIRECTORY_STRIPE_SECRET_KEY:key}).ready,false);
 assert.equal(directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_ENABLED:'true'}).ready,true);
});

test('paused checkout preserves refresh, cancellation, billing portal and signature validation',async()=>{
 const requests=[];
 const billing=directoryBilling(credentials,{fetcher:async(url,options)=>{
  requests.push({url,options});
  return {ok:true,json:async()=>url.endsWith('/billing_portal/sessions')?{url:'https://billing.stripe.com/p/session/fixture'}:subscription()};
 }});
 assert.equal((await billing.refresh({subscription_id:'sub_fixture'})).state,'active');
 await billing.cancel('sub_fixture');
 assert.equal(new URLSearchParams(requests.find(x=>x.options.method==='POST').options.body).get('cancel_at_period_end'),'true');
 assert.match(await billing.portal('cus_fixture'),/^https:\/\/billing\.stripe\.com\//);
 const raw=Buffer.from('{}'),t=Math.floor(Date.now()/1000);
 const sig=createHmac('sha256',credentials.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET).update(t+'.').update(raw).digest('hex');
 assert.equal(billing.verify(raw,`t=${t},v1=${sig}`),true);
 assert.equal(billing.verify(Buffer.from('{"changed":true}'),`t=${t},v1=${sig}`),false);
 assert(requests.every(x=>x.options.headers['Stripe-Version']===DIRECTORY_STRIPE_API_VERSION));
});

test('monthly and yearly checkout use stable retry payloads and fixed server prices',async()=>{
 const requests=[];
 const billing=directoryBilling({...credentials,KORLIX_DIRECTORY_STRIPE_ENABLED:'true'},{fetcher:async(url,options)=>{
  requests.push({url,options});return {ok:true,json:async()=>({id:'cs_fixture',url:'https://checkout.stripe.com/c/pay/fixture',livemode:false,client_reference_id:business,metadata:{generation},mode:'subscription'})};
 }});
 for(const [interval,amount]of [['month','499'],['year','4900']]){
  const membership={generation,interval,checkout_expires:new Date(Date.now()+3600000).toISOString()};
  await billing.checkout(business,membership,'synthetic@example.invalid');
  await billing.checkout(business,membership,'synthetic@example.invalid');
  const last=requests.at(-1),form=new URLSearchParams(last.options.body);
  assert.equal(last.options.body,requests.at(-2).options.body);
  assert.equal(last.options.headers['Idempotency-Key'],'directory-'+generation);
  assert.equal(form.get('line_items[0][price_data][unit_amount]'),amount);
  assert.equal(form.get('subscription_data[billing_mode][type]'),'flexible');
  assert.match(form.get('integration_identifier'),/^korlix_directory_[a-z]{8}$/);
  assert.equal(form.has('payment_method_types'),false);
 }
 await assert.rejects(billing.checkout(business,{interval:'day'},'synthetic@example.invalid'),/monthly or yearly/);
 assert.equal(requests.length,4);
});

test('HTTP activation guard blocks new purchases but still reconciles signed events',async()=>{
 const calls=[];
 let providerSubscription=subscription();
 const billing=directoryBilling(credentials,{fetcher:async()=>({ok:true,json:async()=>providerSubscription})});
 const app=express();
 app.use(express.json({verify:(q,r,b)=>q.korlixDirectoryRawBody=Buffer.from(b)}));
 registerDirectory(app,{billing,environment:{},requireUser:async()=>({id:business}),store:{async command(actor,admin,action,id,p){calls.push({action,p});if(action==='get')return {business:{owner_id:business},membership:{subscription_id:'sub_fixture'}};return {ok:true};}}});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 const root='http://127.0.0.1:'+server.address().port+'/api/directory';
 try{
  const health=await(await fetch(root+'/health')).json();
  assert.equal(health.paymentsReady,false);assert.equal(health.paymentCredentialsConfigured,true);assert.equal(health.checkoutEnabled,false);
  assert(!JSON.stringify(health).includes('fixture'));
  const post=(path,body,headers={})=>fetch(root+path,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
  assert.equal((await post('/owner/'+business+'/membership',{action:'checkout',interval:'month',acceptRecurring:true})).status,503);
  assert(!calls.some(x=>x.action==='checkout_start'));
  assert.equal((await post('/owner/'+business+'/membership',{action:'refresh'})).status,200);
  const event={livemode:false,type:'customer.subscription.updated',data:{object:{id:'sub_fixture',metadata:{korlix_directory:business}}}};
  const raw=JSON.stringify(event),t=Math.floor(Date.now()/1000);
  const sig=createHmac('sha256',credentials.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET).update(t+'.'+raw).digest('hex');
  assert.equal((await post('/billing/webhook',event,{'stripe-signature':`t=${t},v1=${sig}`})).status,200);
  assert.equal(calls.filter(x=>x.action==='billing_apply').length,2);
  providerSubscription={...subscription(),status:'incomplete',latest_invoice:{id:'in_fixture',status:'open',amount_paid:0}};
  const failed={livemode:false,type:'checkout.session.async_payment_failed',data:{object:{subscription:'sub_fixture',metadata:{korlix_directory:business}}}};
  const failedSig=createHmac('sha256',credentials.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET).update(t+'.'+JSON.stringify(failed)).digest('hex');
  assert.equal((await post('/billing/webhook',failed,{'stripe-signature':`t=${t},v1=${failedSig}`})).status,200);
  assert.equal(calls.at(-1).p.state,'incomplete');assert.equal(calls.at(-1).p.paid_until,null);
 }finally{await new Promise(r=>server.close(r));}
});
