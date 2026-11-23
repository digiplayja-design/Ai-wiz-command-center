import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {accountId, PACKAGE} from '../google_play/core.mjs';
import {bindingHash} from '../store_measurement/first_charge.mjs';
import {registerFirstPaymentDelivery, EVENT} from '../store_measurement/delivery.mjs';

const db = new PGlite();
const id = randomUUID(), other = randomUUID(), instance = 'ab'.repeat(16);
const appleId = '1000011112222', token = 'isolated-fixture-token', baseOrder = 'GPA.1111-1111-1111-11111';
const iosSku = PACKAGE + '.pro.monthly';
const env = {KORLIX_STORE_PAYMENT_DELIVERY_ENABLED:'true', KORLIX_GA4_ANDROID_APP_ID:'1:123:android:aaa',
  KORLIX_GA4_IOS_APP_ID:'1:123:ios:bbb', KORLIX_GA4_IOS_API_SECRET:'test', KORLIX_GA4_ANDROID_API_SECRET:'test'};
const migration = new URL('../../supabase/migrations/20261123062217_korlix_first_paid_subscription_delivery.sql', import.meta.url);

test.before(async () => {
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create table korlix_apple_transaction_bindings(user_id uuid,environment text,original_transaction_id text);
    create table korlix_play_purchases(user_id uuid,purchase_token text,token_hash text,product_id text,test_purchase boolean);`);
  await db.query('insert into auth.users values ($1),($2)', [id,other]);
  await db.exec(await readFile(migration, 'utf8'));
});
test.beforeEach(() => db.exec('truncate korlix_measurement_checkouts,korlix_first_payment_deliveries,korlix_apple_transaction_bindings,korlix_play_purchases'));
test.after(() => db.close());

// Exercise the same query semantics as the service against actual PostgreSQL, including locks and RLS.
const database = {
  from(table) {
    let op = 'select', fields = '*', values = {}, single = false, max = 100;
    const where = [];
    return {
      select(cols) {fields=cols; return this;}, insert(data) {op='insert'; values=data; return this;},
      update(data) {op='update'; values=data; return this;}, delete() {op='delete';return this;},
      eq(key,value) {where.push([key,value]);return this;}, is(key,value) {where.push([key,value]);return this;},
      limit(n) {max=n; return this;}, single() {single=true;return this;}, maybeSingle() {single=true;return this;},
      then(ok, reject) {
        const args = [], param = value => '$' + args.push(value);
        let sql;
        if (op==='insert') sql = 'insert into '+table+' ('+Object.keys(values).join()+') values ('+Object.values(values).map(param).join()+')';
        else if (op==='update') sql = 'update '+table+' set '+Object.entries(values).map(([k,v])=>k+'='+param(v)).join();
        else sql = (op==='select'?'select '+fields+' from ':'delete from ')+table;
        if (where.length) sql += ' where '+where.map(([k,v])=>v===null?k+' is null':k+'='+param(v)).join(' and ');
        sql += op==='select'?' limit '+max:' returning '+fields;
        return db.query(sql,args).then(r=>ok({data:single?r.rows[0]??null:r.rows}),reject);
      },
    };
  },
  async rpc(name, args={}) {
    const parameters=Object.values(args);
    const r=await db.query('select * from '+name+'('+parameters.map((_,i)=>'$'+(i+1)).join()+')',parameters);
    return {data:r.rows};
  },
};

function harness({failSend=false, enabled=true}={}) {
  const routes = new Map(), sent = [];
  const paidAt = Date.now()-60_000, start = paidAt-3*86400_000;
  const state = {paid:false, refunded:false, broken:false};
  const apple = async () => ({
    library:{Order:{ASCENDING:'ASC'},ProductType:{AUTO_RENEWABLE:'sub'},GetTransactionHistoryVersion:{V2:'v2'}},
    productionClient:{getTransactionHistory:async()=>({hasMore:false, signedTransactions:state.paid?['trial','paid','renewal']:['trial']})},
    productionVerifier:{verifyAndDecodeTransaction:async item=>{
      if (state.broken) throw new Error('Invalid store evidence');
      return {bundleId:PACKAGE, environment:'Production', originalTransactionId:appleId,
        transactionId:item==='trial'?appleId:item, productId:iosSku, inAppOwnershipType:'PURCHASED',
        type:'Auto-Renewable Subscription', appAccountToken:id, price:item==='trial'?0:12000,
        currency:'USD', purchaseDate:item==='trial'?start:item==='paid'?paidAt:paidAt+20_000,
        revocationDate:state.refunded&&item==='paid'?paidAt+1:null};
    }},
  });
  const play={
    subscription:async()=>({externalAccountIdentifiers:{obfuscatedExternalAccountId:accountId(id)},lineItems:[{
      productId:'korlix_pro',offerDetails:{basePlanId:'monthly'},latestSuccessfulOrderId:baseOrder+(state.paid?'..1':'')}]}),
    order:async orderId=>({orderId,purchaseToken:token,state:'PROCESSED',total:{currencyCode:'USD',units:orderId===baseOrder?'0':'12'},
      orderHistory:{processedEvent:{eventTime:new Date(orderId===baseOrder?start:paidAt).toISOString()}},
      lineItems:[{productId:'korlix_pro',subscriptionDetails:{basePlanId:'monthly'}}]}),
  };
  const worker=registerFirstPaymentDelivery({post:(path,handler)=>routes.set(path,handler)}, {
    database, requireUser:async req=>({id:req.user,email_confirmed_at:'confirmed'}),env:{...env,KORLIX_STORE_PAYMENT_DELIVERY_ENABLED:String(enabled)},
    apple,play,autoStart:false,log:{warn(){}},deliver:async (config,msg)=>{sent.push({config,msg});if(failSend)throw Error('ambiguous send');},
  });
  async function post(action,body,user=id) {
    const res={code:200,set(){},status(code){this.code=code;return this;},json(data){this.data=data;}};
    await routes.get('/api/billing/measurement/'+action)({body,user},res);
    return res;
  }
  async function enroll(store) {
    const sku=store==='ios'?iosSku:'korlix_pro';
    const response=await post('checkout',{store,sku,instanceId:instance,consent:true});
    assert.equal(response.code,200);
    const checkoutId=response.data.checkoutId;
    // Simulate a real three-day trial without changing PostgreSQL's clock.
    await db.query('update korlix_measurement_checkouts set granted_at=$2 where id=$1',[checkoutId,new Date(start-60_000)]);
    const storeReference=store==='ios'?appleId:token;
    const purchase={store,sku,checkoutId,storeReference,environment:'Production'};
    assert.equal(await worker.bindVerified(id,purchase),false);
    if (store==='ios') await db.query("insert into korlix_apple_transaction_bindings values ($1,'Production',$2)",[id,appleId]);
    else await db.query("insert into korlix_play_purchases values ($1,$2,$3,'korlix_pro',false)",[id,token,bindingHash(token)]);
    assert.equal(await worker.bindVerified(other,purchase),false);
    assert.equal(await worker.bindVerified(id,{...purchase,environment:'Sandbox'}),false);
    assert.equal(await worker.bindVerified(id,purchase),true);
    return checkoutId;
  }
  const due=()=>db.exec("update korlix_measurement_checkouts set next_check_at=now()-interval '1 minute'");
  return {post,enroll,due,run:worker.run,sent,state,paidAt};
}

for (const store of ['ios','android']) {
  test(store+' paid trial emits one isolated event after checkout closes, with no receipt or account data', async () => {
    const h=harness();
    await h.enroll(store); await h.run(); assert.equal(h.sent.length,0);
    h.state.paid=true; await h.due(); await Promise.all([h.run(),h.run()]); await h.due(); await h.run();
    assert.deepEqual(h.sent.map(x=>x.msg),[{app_instance_id:instance,timestamp_micros:h.paidAt*1000,
      consent:{ad_user_data:'GRANTED',ad_personalization:'DENIED'},events:[{name:EVENT}]}]);
    assert.equal(h.sent[0].config.appId,env['KORLIX_GA4_'+store.toUpperCase()+'_APP_ID']);
    assert.deepEqual((await db.query('select state from korlix_first_payment_deliveries')).rows,[{state:'accepted'}]);
  });
}
test('withdrawal, refund, old restored chain and invalid signature each prevent delivery',async()=>{
  for(const reason of ['withdraw','refund','restore','invalid']){
    await db.exec('truncate korlix_measurement_checkouts,korlix_apple_transaction_bindings');
    const h=harness(); const c=await h.enroll('ios'); h.state.paid=true;
    if(reason==='withdraw') assert.equal((await h.post('withdraw',{store:'ios'})).code,200);
    if(reason==='refund') h.state.refunded=true;
    if(reason==='restore') await db.query('update korlix_measurement_checkouts set granted_at=now() where id=$1',[c]);
    if(reason==='invalid') h.state.broken=true;
    await h.run(); assert.equal(h.sent.length,0);
  }
});
test('an inactive sender permits withdrawal and an ambiguous result is never resent',async()=>{
  const h=harness({failSend:true}); await h.enroll('android'); h.state.paid=true;
  await h.run(); await h.due(); await h.run(); assert.equal(h.sent.length,1);
  assert.equal((await db.query('select state from korlix_first_payment_deliveries')).rows[0].state,'uncertain');
  const disabled=harness({enabled:false});
  assert.equal((await disabled.post('checkout',{store:'ios'})).code,503);
  assert.equal((await disabled.post('withdraw',{store:'ios'})).code,200);
});
test('RPC consumes the sole account reservation across stores and rechecks a withdrawal',async()=>{
  const h=harness(); const a=await h.enroll('ios'), g=await h.enroll('android');
  const dates=[new Date(Date.now()-3600_000),new Date(Date.now()-30_000)];
  const reserve=(checkout,store,sku,hash)=>db.query('select * from korlix_reserve_first_payment($1,$2,$3,$4,$5,$6)',[checkout,store,sku,hash,...dates]);
  assert.equal((await reserve(a,'ios',iosSku,bindingHash(appleId))).rows.length,1);
  assert.equal((await reserve(g,'android','korlix_pro',bindingHash(token))).rows.length,0);
  assert.equal((await reserve(a,'ios',iosSku,bindingHash(appleId))).rows.length,0);
});
test('private tables and delivery RPCs reject client roles; opt-in is explicit',async()=>{
  const h=harness();
  for(const role of ['authenticated','anon']){
    await db.exec('set role '+role);
    try {
      await assert.rejects(db.query('select * from korlix_measurement_checkouts'),/permission denied/);
      await assert.rejects(db.query('select * from korlix_first_payment_deliveries'),/permission denied/);
      await assert.rejects(db.query('select * from korlix_measurement_due()'),/permission denied/);
    } finally { await db.exec('reset role'); }
  }
  assert.equal((await h.post('checkout',{store:'ios',sku:iosSku,instanceId:instance})).code,400);
  assert.equal((await h.post('checkout',{store:'android',sku:'ai_gas',instanceId:instance,consent:true})).code,400);
  assert.equal((await h.post('checkout',{store:'ios',sku:iosSku,instanceId:'not-an-id',consent:true})).code,400);
});
