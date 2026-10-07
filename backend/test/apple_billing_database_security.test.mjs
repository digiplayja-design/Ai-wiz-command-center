import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

let db;
const alice='11111111-1111-4111-8111-111111111111', bob='22222222-2222-4222-8222-222222222222';
const epoch=Date.now()-600000, purchase=new Date(epoch-86400000).toISOString(), expires=new Date(epoch+86400000).toISOString();
const migration=process.env.KORLIX_APPLE_SECURITY_MIGRATION || new URL('../../supabase/migrations/20261007015513_apple_billing_security.sql',import.meta.url);
async function apply(p={}) {
  const v={user:alice,product:'com.korlixdeveloper.korlixai.pro.monthly',tier:'pro',status:'active',environment:'Production',original:'original-a',transaction:'transaction-a',purchase,expires,revoked:null,token:alice,signed:epoch,...p};
  const payload=v.signed==null?{}:{transaction:{signedDate:v.signed}};
  const args=[v.user,v.product,v.tier,v.status,v.environment,v.original,v.transaction,v.purchase,v.expires,v.revoked,v.token,'PURCHASED',true,'signed.fixture',null,null,JSON.stringify(payload)];
  return (await db.query(`select public.korlix_apply_apple_subscription_entitlement(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;
}
const record=async ()=>(await db.query('select * from apple_subscription_entitlements where user_id=$1',[alice])).rows[0];
test.before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create table auth.users(id uuid primary key);
 create table public.user_profiles(id uuid primary key references auth.users(id),tier text not null default 'basic',is_disabled boolean default false);
 create table public.subscriptions(user_id uuid,tier text,status text,current_period_end timestamptz);
 grant usage on schema public,auth to service_role;grant select,insert,update on public.user_profiles,public.subscriptions to service_role;`);
 for(const path of ['202607130001_apple_subscriptions_build130.sql','20261004203621_web_plan_subscriptions.sql'])
   await db.exec(await readFile(new URL('../../supabase/migrations/'+path,import.meta.url),'utf8'));
 for(const id of [alice,bob]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into user_profiles(id) values($1)',[id]);}
 // Backfill preserves historical ownership even when old payloads lack signedDate.
 await db.query("insert into apple_subscription_entitlements(user_id,product_id,tier,original_transaction_id,environment,status,expires_at) values($1,'legacy','pro','legacy-original','Production','active',$2)",[alice,expires]);
 await db.exec(await readFile(migration,'utf8'));
 const bound=(await db.query("select * from korlix_apple_transaction_bindings where original_transaction_id='legacy-original'")).rows[0];
 assert.equal(bound.user_id,alice);assert.equal(bound.last_signed_date,0);
});
test.beforeEach(async()=>{
 await db.exec("reset role;delete from korlix_apple_transaction_bindings;delete from apple_subscription_entitlements;delete from korlix_web_billing_accounts;update user_profiles set tier='basic';set role service_role;");
});
test.after(async()=>db?.close());
test('new purchase must carry a verified token matching its account',async()=>{
 await assert.rejects(apply({token:null}),/no verified link/);
 await assert.rejects(apply({token:bob}),/different Korlix/);
 const granted=await apply();assert.equal(granted.active,true);assert.equal(granted.tier,'pro');
});
test('database atomically rejects rebinding an original purchase to another account',async()=>{
 await apply();
 await assert.rejects(apply({user:bob,token:bob,signed:epoch+1}),/already linked/);
 assert.equal((await record()).user_id,alice);
});
test('original purchase remains bound after switching the current subscription',async()=>{
 await apply();
 await apply({original:'original-new',transaction:'transaction-new',signed:epoch+1});
 await assert.rejects(apply({user:bob,token:bob,signed:epoch+2}),/already linked/);
 const count=(await db.query('select count(*)::int n from korlix_apple_transaction_bindings where user_id=$1',[alice])).rows[0].n;
 assert.equal(count,2);
});
test('legacy purchase without a token can restore only its durable owner',async()=>{
 await apply();
 await apply({token:null,signed:epoch+1});
 await assert.rejects(apply({user:bob,token:null,signed:epoch+2}),/already linked/);
});
test('replaying an old active notification cannot undo a newer revocation',async()=>{
 await apply();
 await apply({status:'revoked',revoked:new Date(epoch+1).toISOString(),signed:epoch+2});
 const replay=await apply();assert.equal(replay.ignored,true);assert.equal(replay.active,false);assert.equal(replay.status,'revoked');assert.equal(replay.tier,'basic');
 assert.equal((await record()).status,'revoked');
});
test('equal signed timestamps are idempotent and cannot overwrite stored state',async()=>{
 await apply({status:'revoked',revoked:new Date(epoch).toISOString()});
 assert.equal((await apply()).ignored,true);assert.equal((await record()).status,'revoked');
});
test('duplicate receipt still expires the stored Apple grant by wall clock',async()=>{
 await apply();
 // Simulate the persisted expiry crossing the wall clock without a new signed
 // provider message. Replaying a receipt must not restore its claimed period.
 await db.query('update apple_subscription_entitlements set expires_at=$1 where user_id=$2',[new Date(epoch-1).toISOString(),alice]);
 const expired=await apply();assert.equal(expired.ignored,true);assert.equal(expired.active,false);assert.equal(expired.tier,'basic');
 assert.equal((await db.query('select tier from user_profiles where id=$1',[alice])).rows[0].tier,'basic');
});
test('older purchase cannot overwrite a newer renewal even with a later JWS signature',async()=>{
 await apply({purchase:new Date(epoch-3600000).toISOString(),transaction:'latest-renewal'});
 const stale=await apply({signed:epoch+100});assert.equal(stale.ignored,true);assert.equal(stale.transactionId,'latest-renewal');
});
test('a missing, invalid or future timestamp cannot bypass freshness checks',async()=>{
 await apply();
 for(const signed of [null,-1,'not-a-time',Date.now()+600000])await assert.rejects(apply({signed}),/timestamp/);
});
test('sandbox and production references cannot replace the same original purchase',async()=>{
 await apply();await assert.rejects(apply({environment:'Sandbox',signed:epoch+1}),/environment changed/);
});
test('browser roles cannot read bindings, forge receipts, or call the entitlement function',async()=>{
 for(const role of ['anon','authenticated']){
  await db.exec('reset role;set role '+role);
  await assert.rejects(db.query('select * from korlix_apple_transaction_bindings'),/permission denied/);
  await assert.rejects(apply(),/permission denied/);
 }
});
test('existing independent enterprise access remains intact',async()=>{
 await db.query("update user_profiles set tier='enterprise' where id=$1",[alice]);
 const existing=await apply({status:'expired',expires:new Date(epoch-1).toISOString()});assert.equal(existing.tier,'enterprise');
});
test('Apple revocation preserves an independently paid web subscription',async()=>{
 const command=async(action,p={})=>(await db.query('select public.korlix_web_billing_command($1,$2,$3::jsonb) result',[alice,action,JSON.stringify(p)])).rows[0].result;
 const m=await command('checkout_start',{tier:'ultra',price_id:'price_ultra',livemode:true,email:'fixture@example.invalid'});
 const leased=await command('claim');
 await command('apply',{generation:m.generation,sync_token:leased.sync_token,livemode:true,subscription_id:'sub_fixture',customer_id:'cus_fixture',
   state:'active',tier:'ultra',amount:12499,paid:true,paid_until:expires,invoice_id:'in_fixture',cancel_at_period_end:false});
 const expired=await apply({status:'revoked',revoked:new Date(epoch).toISOString()});
 assert.equal(expired.tier,'ultra');
 assert.equal((await command('snapshot')).membership.base_tier,'basic');
});
