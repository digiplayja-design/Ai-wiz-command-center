import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

const owner='10000000-0000-4000-8000-000000000001',other='10000000-0000-4000-8000-000000000002';
const migrations=new URL('../../supabase/migrations/',import.meta.url);
const sql=name=>readFile(new URL(name,migrations),'utf8');
test('developer grants are isolated, revocable and keep reservations and ownership checks',async t=>{
 const db=new PGlite();
 const rpc=async(name,args)=>(await db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as result`,args)).rows[0].result;
 const grant=async enabled=>{await db.exec('reset role');await db.query('insert into korlix_developer_access(user_id,enabled) values($1,$2) on conflict(user_id) do update set enabled=excluded.enabled',[owner,enabled]);await db.exec('set role service_role');};
 const reserve=(id,kind='text_to_video')=>rpc('korlix_video_reserve',[id,kind,'openai']);
 const music=(id,limit=2147483647)=>rpc('korlix_music_v2',[id,'begin',randomUUID(),{payload:{idea:'Synthetic fixture'},limit}]);
 try {
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create schema auth;grant usage on schema public,auth to anon,authenticated,service_role;
    create table auth.users(id uuid primary key);
    create table public.user_profiles(id uuid primary key references auth.users(id),tier text not null default 'basic',is_disabled boolean default false,video_generation_limit_override integer);
    create table public.subscriptions(user_id uuid,tier text,status text,current_period_end timestamptz);
    grant select,insert,update on public.user_profiles,public.subscriptions to service_role;
    create table public.video_credit_ledger(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),delta integer not null check(delta<>0),source text not null,product_id text,purchase_token_hash text unique,description text,metadata jsonb not null default '{}',created_at timestamptz not null default now());
    create table public.generation_history(id uuid primary key default gen_random_uuid(),user_id uuid,response text,result_type text,created_at timestamptz default now());
    create table public.korlix_video_generation_limits(tier_key text primary key,monthly_limit integer,enabled boolean default true);
    insert into public.korlix_video_generation_limits values('basic',1,true),('pro',1,true),('ultra_premium',30,true);
    create table public.korlix_monthly_video_usage(user_id uuid,month_key text,tier_key text,used_count integer,last_job_kind text,created_at timestamptz,updated_at timestamptz,primary key(user_id,month_key));
    create function public.korlix_normalize_video_tier(t text) returns text language sql immutable as $$select case when lower(t) like '%ultra%' then 'ultra_premium' when lower(t)='pro' then 'pro' else 'basic' end$$;
    create function public.korlix_video_month_key(t timestamptz) returns text language sql stable as $$select to_char(t at time zone 'UTC','YYYY-MM')$$;`);
  await db.exec(await readFile(new URL('./fixtures/video_quota_legacy.sql',import.meta.url),'utf8'));
  for(const name of ['202607130001_apple_subscriptions_build130.sql','20261004203621_web_plan_subscriptions.sql','20260927214246_music_studio_library.sql','20261007015226_video_access_security.sql'])await db.exec(await sql(name));
  const migration=await sql((await readdir(migrations)).find(n=>n.endsWith('_developer_unlimited_access.sql')));
  const patchText=/\$patches\$\s*(\[[\s\S]*?\])\s*\$patches\$/.exec(migration)[1];
  const selected=new Set(['korlix_web_billing_profile','korlix_video_credit_summary','korlix_video_reserve','korlix_claim_monthly_video_generation','korlix_music_v2']);
  const patches=JSON.parse(patchText).filter(p=>selected.has(p.signature.split('.')[1].split('(')[0]));
  // Run the actual production migration loop against the baseline feature DDL.
  await db.exec(migration.replace(patchText,JSON.stringify(patches)));
  for(const id of [owner,other]){
   await db.query('insert into auth.users values($1)',[id]);
   await db.query("insert into user_profiles(id,tier)values($1,'pro')",[id]);
   await db.query("insert into video_credit_ledger(user_id,delta,source)values($1,2,'support_grant')",[id]);
  }
  await t.test('browser clients cannot grant themselves access or call the helper',async()=>{
   for(const role of ['anon','authenticated']){
    await db.exec('set role '+role);
    await assert.rejects(db.query('select * from korlix_developer_access'),/permission denied/);
    await assert.rejects(db.query('insert into korlix_developer_access(user_id,enabled)values($1,true)',[owner]),/permission denied/);
    await assert.rejects(rpc('korlix_has_unlimited_access',[owner]),/permission denied/);
    await db.exec('reset role');
   }
  });
  await grant(true);
  await t.test('only the granted account receives the profile and video entitlement',async()=>{
   assert.equal((await rpc('korlix_web_billing_profile',[owner])).developer_unlimited,true);
   assert.equal((await rpc('korlix_web_billing_profile',[other])).developer_unlimited,false);
   assert.equal((await rpc('korlix_video_credit_summary',[owner])).unlimited,true);
   assert.equal((await rpc('korlix_video_credit_summary',[other])).monthlyLimit,2);
  });
  await t.test('unlimited video still reserves owned jobs without debiting purchased credits',async()=>{
   for(const kind of ['text_to_video','image_to_video'])for(let i=0;i<4;i++){
    const v=await reserve(owner,kind);assert.equal(v.ok,true);assert.equal(v.spent_purchased_credit,false);
   }
   assert.equal((await rpc('korlix_video_credit_summary',[owner])).purchasedVideoCredits,2);
   assert.equal((await reserve(other,'image_to_video')).ok,true);
   assert.equal((await reserve(other,'image_to_video')).ok,false);
   const reservation=await reserve(owner);
   assert.equal((await rpc('korlix_video_attach',[other,reservation.reservation_id,'foreign_job'])).ok,false);
  });
  await t.test('music removes the monthly allowance but keeps the concurrent job bound',async()=>{
   await assert.rejects(music(other),/active Music Production add-on/);
   for(let i=0;i<3;i++)assert.equal((await music(owner)).replayed,false);
   await assert.rejects(music(owner),/Three creations/);
  });
  await t.test('disabled or revoked accounts lose unlimited entitlement immediately',async()=>{
   await db.query('update user_profiles set is_disabled=true where id=$1',[owner]);
   assert.equal(await rpc('korlix_has_unlimited_access',[owner]),false);
   await db.query('update user_profiles set is_disabled=false where id=$1',[owner]);
   await grant(false);
   assert.equal((await rpc('korlix_web_billing_profile',[owner])).developer_unlimited,false);
   assert.equal((await rpc('korlix_video_credit_summary',[owner])).unlimited,false);
   assert.equal((await reserve(owner,'image_to_video')).ok,false);
   await assert.rejects(music(owner),/active Music Production add-on/);
  });
 }finally{await db.close();}
});
