import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import express from 'express';
import {PGlite} from '@electric-sql/pglite';
import {webStripe} from '../web_billing/stripe.mjs';
import {registerWebBilling} from '../web_billing/routes.mjs';
import {billingStore, PLAN_VERSION} from '../web_billing/core.mjs';

const owner='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const env={KORLIX_WEB_STRIPE_SECRET_KEY:'sk_live_fixture',KORLIX_WEB_STRIPE_WEBHOOK_SECRET:'whsec_fixture',
  KORLIX_WEB_STRIPE_ENABLED:'true',KORLIX_WEB_STRIPE_PORTAL_CONFIGURATION_ID:'bpc_fixture',
  KORLIX_WEB_STRIPE_PRO_PRICE_ID:'price_pro',KORLIX_WEB_STRIPE_ULTRA_PRICE_ID:'price_ultra'};
const m={user_id:owner,generation:other,livemode:true,requested_tier:'pro',requested_price:'price_pro',
  checkout_email:'test@example.invalid',checkout_expires:new Date(Date.now()+3600000).toISOString()};
const metadata=membership=>({korlix_web_user:membership.user_id,generation:membership.generation,plan_version:PLAN_VERSION});
function session(membership=m) {return {id:'cs_live_fixture',mode:'subscription',livemode:true,client_reference_id:membership.user_id,
  metadata:metadata(membership),amount_subtotal:3499,currency:'usd',status:'open',url:'https://checkout.stripe.com/c/pay/fixture',
  line_items:{data:[{quantity:1,price:{id:'price_pro'}}]}};}
function subscription(membership=m) {return {id:'sub_fixture',customer:'cus_fixture',livemode:true,metadata:metadata(membership),status:'active',
  items:{data:[{quantity:1,current_period_end:Math.floor(Date.now()/1000)+86400*30,price:{id:'price_pro',currency:'usd',unit_amount:3499,
    recurring:{interval:'month',interval_count:1,usage_type:'licensed'}}}]},
  latest_invoice:{id:'in_fixture',customer:'cus_fixture',livemode:true,currency:'usd',parent:{subscription_details:{subscription:'sub_fixture'}},
    status:'paid',amount_remaining:0,amount_due:3499,amount_paid:3499}};}
const normalizer=webStripe(env);
test('catalog, ownership, generation, invoice, mode and quantity are independently checked',()=>{
  assert.equal(normalizer.subscriptionValue(subscription(),m).paid,true);
  for(const change of [s=>s.metadata.korlix_web_user=other,s=>s.metadata.generation=owner,s=>s.livemode=false,
    s=>s.items.data[0].quantity=2,s=>s.items.data[0].price.unit_amount=1,s=>s.items.data[0].price.recurring.interval='year']) {
    const s=subscription();change(s);assert.throws(()=>normalizer.subscriptionValue(s,m));
  }
  const s=subscription();s.latest_invoice.parent.subscription_details.subscription='sub_foreign';
  assert.equal(normalizer.subscriptionValue(s,m).paid,false);
  s.latest_invoice=subscription().latest_invoice;s.latest_invoice.status='open';
  assert.equal(normalizer.subscriptionValue(s,m).paid,false);
});
test('paid proration is accepted; paused collection and unpaid updates cannot grant access',()=>{
  const s=subscription();s.latest_invoice.amount_due=500;s.latest_invoice.amount_paid=500;
  assert.equal(normalizer.subscriptionValue(s,m).paid,true);
  s.pause_collection={behavior:'void'};
  assert.equal(normalizer.subscriptionValue(s,m).state,'paused');
  assert.equal(normalizer.subscriptionValue(s,m).paid,false);
});
test('Checkout response and redirect must match the exact bound account and plan',()=>{
  assert.equal(normalizer.sessionValue(session(),m).id,'cs_live_fixture');
  for(const change of [s=>s.client_reference_id=other,s=>s.amount_subtotal=1,s=>s.line_items.data[0].price.id='price_ultra',
    s=>s.url='https://checkout.stripe.com.evil.invalid/pay',s=>s.url='https://user@checkout.stripe.com/pay']) {
    const s=session();change(s);assert.throws(()=>normalizer.sessionValue(s,m));
  }
});
test('Checkout posts fixed prices, dynamic payment methods and a stable idempotency key',async()=>{
  const calls=[];
  const provider=webStripe(env,{fetcher:async(url,options)=>{
    calls.push({url,options});
    const body=url.includes('configurations/')?{id:'bpc_fixture',active:true,livemode:true,metadata:{korlix_feature:'web_subscriptions'},
      features:{subscription_cancel:{enabled:true,mode:'at_period_end'},subscription_update:{enabled:true,proration_behavior:'always_invoice',
        products:[{prices:['price_pro','price_ultra']}]}}}:session();
    return {ok:true,json:async()=>body};
  }});
  await provider.checkout(m);await provider.checkout(m);
  const posts=calls.filter(x=>x.options.method==='POST');
  assert.equal(posts.length,2);assert.equal(posts[0].options.headers['Idempotency-Key'],posts[1].options.headers['Idempotency-Key']);
  const params=new URLSearchParams(posts[0].options.body);
  assert.equal(params.get('line_items[0][price]'),'price_pro');
  assert.equal(params.get('subscription_data[billing_mode][type]'),'flexible');
  assert.equal(params.has('payment_method_types[0]'),false);
  assert.equal(params.get('metadata[korlix_web_user]'),owner);
});
test('risk events map a charge through invoice payments without touching unrelated subscriptions',async()=>{
  const provider=webStripe(env,{fetcher:async(url)=>({ok:true,json:async()=>url.includes('/charges/')?
    {livemode:true,payment_intent:'pi_fixture'}:{has_more:false,data:[{invoice:subscription().latest_invoice}]}})});
  assert.deepEqual(await provider.chargeSubscriptions('ch_fixture'),['sub_fixture']);
});

let db,store,server,origin,provider,calls,paid=false,currentSession,clock=Date.now();
async function raw(action,p={}) {return store.command(owner,action,p);}
async function request(path,{method='POST',body={},user=owner,headers={}}={}) {
  const response=await fetch(origin+path,{method,headers:{'Content-Type':'application/json',...(user?{'x-user':user}:{}),...headers},
    ...(method==='GET'?{}:{body:JSON.stringify(body)})});
  return {status:response.status,data:await response.json()};
}
async function event(type,object,id='evt_fixture',changes={}) {
  const body={id,type,livemode:true,data:{object},...changes};
  const t=Math.floor(Date.now()/1000),signature=createHmac('sha256','whsec_fixture').update(t+'.'+JSON.stringify(body)).digest('hex');
  return request('/webhook',{body,user:null,headers:{'stripe-signature':`t=${t},v1=${signature}`}});
}
const checkout=()=>request('/checkout',{body:{tier:'pro',version:PLAN_VERSION,acceptRecurring:true,amount:1,user_id:other,customer:'cus_foreign'}});
test.before(async()=>{
  db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);
    create table user_profiles(id uuid primary key,tier text not null default 'basic',is_disabled boolean default false);
    create table subscriptions(user_id uuid,tier text,status text,current_period_end timestamptz);
    grant select,insert,update on user_profiles,subscriptions to service_role;`);
  for(const file of ['202607130001_apple_subscriptions_build130.sql','20261004203621_web_plan_subscriptions.sql'])
    await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  for(const id of [owner,other]) {await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles(id) values($1)',[id]);}
  store=billingStore({rpc:async(name,p)=>{
    try {const q=name==='korlix_web_billing_command'?['select korlix_web_billing_command($1,$2,$3::jsonb) value',[p.p_actor,p.p_action,JSON.stringify(p.p)]]:
      ['select korlix_web_billing_profile($1) value',[p.p_user_id]];
      return {data:(await db.query(...q)).rows[0].value};
    }catch(error){return {error};}
  }});
  provider={...normalizer,
    checkConnection:async()=> 'verified',
    checkout:async(membership)=>{calls.push(membership);currentSession=session(membership);return currentSession;},
    session:async()=>paid?{...currentSession,status:'complete',subscription:'sub_fixture',url:null}:currentSession,
    subscription:async(sub,membership)=>normalizer.subscriptionValue(subscription({...membership}),membership),
    portal:async()=> 'https://billing.stripe.com/p/session/fixture',
    cancel:async()=>{},expire:async()=>{currentSession={...currentSession,status:'expired',url:null};return currentSession;},
    chargeSubscriptions:async()=>['sub_fixture']};
  const app=express();app.use(express.json({verify:(req,_res,buf)=>req.korlixWebBillingRawBody=buf}));
  registerWebBilling(app,{store,provider,autoStart:false,now:()=>clock,requireUser:async(req)=>({id:req.headers['x-user'],email:'test@example.invalid',email_confirmed_at:'2026-10-01'})});
  server=await new Promise(resolve=>{const s=app.listen(0,'127.0.0.1',()=>resolve(s));});
  origin=`http://127.0.0.1:${server.address().port}/api/billing/web`;
});
test.beforeEach(async()=>{
  if(!db)return;
  await db.exec("delete from korlix_web_billing_events;delete from korlix_web_billing_accounts;update user_profiles set tier='basic',is_disabled=false;");
  calls=[];paid=false;currentSession=null;clock+=60001;
});
test.after(async()=>{await new Promise(resolve=>server.close(resolve));await db.close();});
test('routes require verified identity; redirect query never grants access and no billing ids leak',async()=>{
  assert.equal((await request('/status',{method:'GET',user:null})).status,403);
  const status=await request('/status?billing=return',{method:'GET'});
  assert.equal(status.data.tier,'basic');assert.equal(status.data.canPurchase,true);
  assert.equal(JSON.stringify(status.data).includes('customer_id'),false);
  await db.query('update user_profiles set is_disabled=true where id=$1',[owner]);
  assert.equal((await checkout()).status,403);
});
test('consent is required and forged client billing details are ignored',async()=>{
  assert.equal((await request('/checkout',{body:{tier:'pro'}})).status,400);
  assert.equal((await checkout()).status,200);
  assert.equal(calls[0].user_id,owner);assert.equal(calls[0].requested_price,'price_pro');
  assert.equal(calls[0].customer_id,null);
  assert.equal((await raw('snapshot')).profile.tier,'basic');
});
test('authenticated refresh grants independently verified payment; retries reuse checkout',async()=>{
  await checkout();await checkout();assert.equal(calls.length,1);
  paid=true;const r=await request('/refresh');assert.equal(r.status,200);assert.equal(r.data.tier,'pro');
  assert.equal(r.data.canPurchase,false);assert.equal(r.data.canManage,true);
  assert.equal((await checkout()).status,409);
  assert.equal((await request('/status',{method:'GET',user:other})).data.tier,'basic');
});
test('signed webhooks are idempotent; invalid and wrong-mode events never grant access',async()=>{
  await checkout();paid=true;
  assert.equal((await request('/webhook',{body:{},user:null})).status,400);
  assert.equal((await event('checkout.session.completed',currentSession,'evt_wrong',{livemode:false})).status,400);
  const object={...currentSession,subscription:'sub_fixture',status:'complete'};
  assert.equal((await event('checkout.session.completed',object)).status,200);
  assert.equal((await event('checkout.session.completed',object)).status,200);
  assert.equal((await raw('snapshot')).profile.tier,'pro');
  assert.equal((await db.query('select count(*)::int n from korlix_web_billing_events')).rows[0].n,1);
});
test('refund event holds access; reordered success event cannot re-grant it',async()=>{
  await checkout();paid=true;await request('/refresh');
  assert.equal((await event('charge.refunded',{id:'ch_fixture'},'evt_refund')).status,200);
  await event('customer.subscription.updated',{id:'sub_fixture'},'evt_later');
  const s=await raw('snapshot');assert.equal(s.profile.tier,'basic');assert.equal(s.membership.held,true);
});
test('closing an unpaid checkout permits another plan without discarding a completed payment',async()=>{
  await checkout();assert.equal((await request('/abandon-checkout',{body:{confirm:true}})).status,200);
  assert.equal((await raw('snapshot')).membership.state,'expired');
  assert.equal((await raw('checkout_start',{tier:'ultra',price_id:'price_ultra',email:'test@example.invalid',livemode:true})).requested_tier,'ultra');
});
