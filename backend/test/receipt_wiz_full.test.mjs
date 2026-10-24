import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {observation, accountId, tokenHash} from '../google_play/core.mjs';
import {googlePlay} from '../google_play/provider.mjs';
import {RECEIPT_PACKAGE, RECEIPT_PRODUCTS, receiptAccountId, registerReceiptBilling} from '../receipt_wiz/billing.mjs';

let db, owner, other;
const future=()=>new Date(Date.now()+86400000).toISOString();
const google=(extra={})=>({externalAccountIdentifiers:{obfuscatedExternalAccountId:receiptAccountId(owner)},
 subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING',
 lineItems:[{productId:'receipt_wiz_full',expiryTime:future(),offerDetails:{basePlanId:'monthly'},autoRenewingPlan:{autoRenewEnabled:true}}],...extra});
const facts=(extra={})=>observation(google(extra),{userId:owner,token:'receipt-test-token-'+owner,products:RECEIPT_PRODUCTS,accountIdentifier:receiptAccountId});
const billing=async(actor,action,p={})=>(await db.query('select korlix_receipt_billing_command($1,$2,$3) result',[actor,action,p])).rows[0].result;
const vault=async(action,id=null,data={},actor=owner)=>(await db.query('select korlix_receipt_wiz_v1($1,$2,$3,$4) result',[actor,action,id,data])).rows[0].result;
const plan=async(actor=owner)=>(await billing(actor,'snapshot')).plan;
async function prepare(actor=owner){return billing(actor,'prepare',{account_id:receiptAccountId(actor)});}
async function apply(f=facts(),actor=owner){const lease=await billing(actor,'claim');try{return await billing(actor,'apply',{...f,sync_token:lease.sync_token});}finally{await billing(actor,'release',{sync_token:lease.sync_token,success:true});}}
async function receipt(){const id=randomUUID();const r=await vault('reserve',null,{request_key:id,filename:'fixture.jpg',mime_type:'image/jpeg',byte_size:10,sha256:tokenHash(id),preview_size:0,preview_sha256:null,pages:1});await vault('ready',r.receipt.id,{upload_token:r.upload_token});return r.receipt.id;}
async function scan(id,key=randomUUID(),failed=false){const r=await vault('scan_begin',id,{request_key:key});if(r.dispatch)await vault('scan_finish',id,{scan_id:r.scan_id,failed,details:{merchant:'Fixture',total:'1.00',currency:'USD'}});return r;}

test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create table auth.users(id uuid primary key);
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id text primary key,bucket_id text);alter table storage.objects enable row level security;
 create table public.user_profiles(id uuid primary key references auth.users(id),tier text default 'basic',is_disabled boolean default false,developer boolean default false);
 create table public.korlix_bookkeeping_businesses(id uuid primary key,owner_id uuid,name text);
 create table public.korlix_tax_workspaces(id uuid primary key,owner_id uuid,tax_year int);
 create function korlix_web_billing_profile(uuid) returns jsonb language sql as 'select to_jsonb(p) from user_profiles p where id=$1';
 create function korlix_has_unlimited_access(uuid) returns boolean language sql as 'select developer from user_profiles where id=$1';
 grant usage on schema public,auth,storage to service_role;
 grant select,insert,update on user_profiles to service_role;
 grant select on korlix_bookkeeping_businesses,korlix_tax_workspaces to service_role;`);
 await db.exec(await readFile(new URL('../../supabase/migrations/20261006171056_receipt_wiz_shared_inbox.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../receipt_wiz/subscription_schema.sql',import.meta.url),'utf8'));
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const id of [owner,other]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles(id)values($1)',[id]);}await db.exec('set role service_role');});
test.after(async()=>db.close());

test('Receipt Wiz purchases bind to a distinct account namespace and SKU',()=>{
 assert.equal(facts().tier,'full');assert.notEqual(receiptAccountId(owner),accountId(owner));
 assert.throws(()=>facts({externalAccountIdentifiers:{obfuscatedExternalAccountId:accountId(owner)}}),/different KORLIX/);
 assert.throws(()=>facts({lineItems:[{...google().lineItems[0],productId:'korlix_pro'}]}),/monthly plan/);
 assert.throws(()=>facts({lineItems:[{...google().lineItems[0],offerDetails:{basePlanId:'annual'}}]}),/monthly plan/);
 assert.throws(()=>facts({testPurchase:{}}),/designated test accounts/);
});
test('Full is included in every paid KORLIX tier and developer access without a duplicate purchase',async()=>{
 assert.equal((await plan()).monthly_scan_limit,20);
 for(const tier of ['pro','ultra','enterprise']){
  await db.query('update user_profiles set tier=$1 where id=$2',[tier,owner]);
  assert.equal((await plan()).monthly_scan_limit,1000);assert.equal((await plan()).included,true);
  await assert.rejects(prepare(),/already included/);
 }
 await db.query("update user_profiles set tier='basic',developer=true where id=$1",[owner]);
 assert.equal((await plan()).unlimited,true);assert.equal((await plan()).monthly_scan_limit,null);
});
test('Receipt purchase, cancellation and expiry never grant or remove a main-app tier',async()=>{
 await prepare();assert.equal((await apply()).active,true);
 assert.equal((await plan()).name,'full');assert.equal((await plan()).max_receipts,5000);
 assert.equal((await db.query('select tier from user_profiles where id=$1',[owner])).rows[0].tier,'basic');
 await assert.rejects(prepare(),/already included/);
 await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_CANCELED'}));assert.equal((await plan()).name,'full');
 await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_EXPIRED'}));assert.equal((await plan()).name,'free');
 await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
 await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_ON_HOLD'}));assert.equal((await plan()).name,'full');
 assert.equal((await db.query('select tier from user_profiles where id=$1',[owner])).rows[0].tier,'enterprise');
});
test('pending, held and paused purchases cannot unlock Full or start duplicate charges',async()=>{
 await prepare();
 for(const state of ['PENDING','ON_HOLD','PAUSED']){
  await apply(facts({subscriptionState:'SUBSCRIPTION_STATE_'+state}));
  assert.equal((await plan()).name,'free');assert.equal((await billing(owner,'snapshot')).canPurchase,false);
  await assert.rejects(prepare(),/Manage or restore/);
 }
});
test('tokens and replacement ownership cannot transfer to another KORLIX account',async()=>{
 await prepare();await prepare(other);await apply();
 await assert.rejects(apply({...facts(),account_id:receiptAccountId(other)},other),/another account/);
 const f={...facts(),purchase_token:'new-receipt-token',token_hash:tokenHash('new-receipt-token'),linked_hash:facts().token_hash};
 await apply(f);await apply({...f,active:false,state:'SUBSCRIPTION_STATE_EXPIRED'});await apply();
 assert.equal((await plan()).name,'free');
});
test('database leases reject concurrent or stale subscription results',async()=>{
 await prepare();const lease=await billing(owner,'claim');
 await assert.rejects(billing(owner,'claim'),/updating/);
 await assert.rejects(billing(owner,'apply',{...facts(),sync_token:randomUUID()}),/changed while verifying/);
 await db.query("update korlix_receipt_billing_accounts set sync_until=now()-interval '1 second' where user_id=$1",[owner]);
 await assert.rejects(billing(owner,'apply',{...facts(),sync_token:lease.sync_token}),/changed while verifying/);
});
test('20 monthly scans are enforced atomically; retries do not consume twice',async()=>{
 const id=await receipt();const key=randomUUID();await scan(id,key);await scan(id,key);
 assert.equal((await plan()).scans_this_month,1);
 for(let n=1;n<20;n++)await scan(id);
 assert.equal((await plan()).scans_remaining,0);
 await assert.rejects(vault('scan_begin',id,{request_key:randomUUID()}),/monthly AI scan allowance/);
 assert.equal((await vault('get',id)).receipt.id,id);
 await vault('save',id,{version:(await vault('get',id)).receipt.version,reviewed:true,details:{merchant:'Manual correction'}});
 assert.equal((await vault('export')).receipts.length,1);
});
test('failed and expired scan reservations return allowance exactly once',async()=>{
 const id=await receipt(), r=await scan(id,randomUUID(),true);
 assert.equal((await plan()).scans_this_month,0);
 await vault('scan_finish',id,{scan_id:r.scan_id,failed:true});assert.equal((await plan()).scans_this_month,0);
 const expired=await vault('scan_begin',id,{request_key:randomUUID()});
 await db.query("update korlix_receipt_wiz_scans set created_at=now()-interval '4 minutes' where id=$1",[expired.scan_id]);
 await scan(id);assert.equal((await plan()).scans_this_month,1);
 await vault('scan_finish',id,{scan_id:expired.scan_id,failed:true});assert.equal((await plan()).scans_this_month,1);
});
test('1,000 Full scans, calendar resets and account isolation are preserved',async()=>{
 const id=await receipt();await db.query("update user_profiles set tier='pro' where id=$1",[owner]);
 await db.query("insert into korlix_receipt_monthly_usage values($1,date_trunc('month',now() at time zone 'UTC')::date,999)",[owner]);
 await scan(id);assert.equal((await plan()).scans_this_month,1000);
 await assert.rejects(scan(id),/monthly AI scan allowance/);
 assert.equal((await plan(other)).scans_this_month,0);
 await db.query("update korlix_receipt_monthly_usage set month=(month-interval '1 month')::date where owner_id=$1",[owner]);
 assert.equal((await plan()).scans_this_month,0);await scan(id);assert.equal((await plan()).scans_this_month,1);
});
test('storage limits block only new files; duplicates and existing records remain usable',async()=>{
 const id=await receipt();
 await db.query("insert into korlix_receipt_wiz(owner_id,request_key,filename,mime_type,byte_size,sha256,pages,state) select $1,gen_random_uuid(),'fixture','image/jpeg',1,lpad(n::text,64,'0'),1,'ready' from generate_series(1,99)n",[owner]);
 await assert.rejects(receipt(),/storage allowance is full/);
 assert.equal((await vault('list')).total,100);assert.equal((await vault('export')).receipts.length,100);
 assert.equal((await vault('get',id)).receipt.id,id);
 await db.query("update user_profiles set tier='pro' where id=$1",[owner]);await receipt();
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 assert.equal((await vault('list')).total,101);await assert.rejects(receipt(),/storage allowance is full/);
 await vault('delete_begin',id,{confirmed:true});await vault('delete_finish',id);
});
test('browser roles cannot read tokens, alter usage or grant Full',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  for(const table of ['korlix_receipt_purchases','korlix_receipt_billing_accounts','korlix_receipt_monthly_usage'])
   await assert.rejects(db.query('select * from '+table),/permission denied/);
  await assert.rejects(billing(owner,'snapshot'),/permission denied/);
  await assert.rejects(vault('list'),/permission denied/);
 }
});
test('Receipt provider queries only its own Android package and full product',async()=>{
 const calls=[];const p=googlePlay({}, {packageName:RECEIPT_PACKAGE,products:RECEIPT_PRODUCTS,
  auth:{request:async req=>{calls.push(req.url);return {data:{productId:'receipt_wiz_full',basePlans:[{basePlanId:'monthly',state:'ACTIVE',autoRenewingBasePlanType:{billingPeriodDuration:'P1M'}}]}};}}});
 await p.catalog('receipt_wiz_full');assert.match(calls[0],/applications\/com\.korlixdeveloper\.receiptwiz\/subscriptions\/receipt_wiz_full$/);
 await assert.rejects(p.catalog('korlix_pro'),/Unsupported/);
});
test('Receipt HTTP verification saves its entitlement then acknowledges; restores use the same owner',async()=>{
 const calls=[];const provider={configured:true,ready:true,notificationsConfigured:true,catalog:async()=>true,
  subscription:async()=>google(),acknowledge:async()=>calls.push('acknowledge')};
 const store={command:async(actor,action,p)=>{calls.push(action);return billing(actor,action,p);}};
 const app=express();app.use(express.json());
 const registration=registerReceiptBilling(app,{provider,store,autoStart:false,requireUser:async()=>({id:owner,email_confirmed_at:'2026-10-24'})});
 const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 const root=`http://127.0.0.1:${server.address().port}/api/receipt-wiz/billing/google`;
 try{
  let r=await fetch(root+'/prepare',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({productId:'receipt_wiz_full'})});assert.equal(r.status,200);
  r=await fetch(root+'/verify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({productId:'receipt_wiz_full',source:'google_play',verificationData:'receipt-test-token-'+owner})});
  const data=await r.json();assert.equal(r.status,200);assert.equal(data.active,true);assert.equal(data.tier,'full');assert.equal(data.completePurchase,true);
  assert.ok(calls.indexOf('apply')<calls.indexOf('acknowledge'));assert.equal((await plan()).name,'full');
 }finally{registration.stop();await new Promise(r=>server.close(r));}
});
