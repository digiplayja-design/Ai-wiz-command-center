import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const a='10000000-0000-4000-8000-000000000001';
const b='10000000-0000-4000-8000-000000000002';
test('video reservations enforce immutable ownership, atomic quotas, and client isolation', async t=>{
  const db=new PGlite();
  const as=async(role,action)=>{await db.exec('set role '+role);try{return await action();}finally{await db.exec('reset role');}};
  const call=async(name,args)=>{
    const placeholders=args.map((_,i)=>'$'+(i+1)).join(',');
    return (await as('service_role',()=>db.query(`select public.${name}(${placeholders}) as result`,args))).rows[0].result;
  };
  const summary=user=>call('korlix_video_credit_summary',[user]);
  const reserve=(user,kind='text_to_video')=>call('korlix_video_reserve',[user,kind,'openai']);
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth;
      grant usage on schema public,auth to anon,authenticated,service_role;
      create table auth.users(id uuid primary key);
      create table public.user_profiles(id uuid primary key,tier text,video_generation_limit_override integer);
      create table public.video_credit_ledger(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
        delta integer not null check(delta<>0),source text not null,product_id text,purchase_token_hash text unique,
        description text,metadata jsonb not null default '{}',created_at timestamptz not null default now());
      create table public.generation_history(id uuid primary key default gen_random_uuid(),user_id uuid,response text,result_type text,created_at timestamptz default now());
      create table public.korlix_video_generation_limits(tier_key text primary key,monthly_limit integer,enabled boolean default true);
      insert into public.korlix_video_generation_limits values('basic',1,true),('pro',1,true),('ultra_premium',30,true);
      create table public.korlix_monthly_video_usage(user_id uuid,month_key text,tier_key text,used_count integer,last_job_kind text,created_at timestamptz,updated_at timestamptz,primary key(user_id,month_key));
      create function public.korlix_normalize_video_tier(t text) returns text language sql immutable as $$
        select case when lower(t) like '%ultra%' then 'ultra_premium' when lower(t) in ('pro','professional') then 'pro' else 'basic' end
      $$;
      create function public.korlix_video_month_key(t timestamptz) returns text language sql stable as $$ select to_char(t at time zone 'UTC','YYYY-MM') $$;
    `);
    await db.exec(await readFile(new URL('./fixtures/video_quota_legacy.sql',import.meta.url),'utf8'));
    await db.query('insert into auth.users values ($1),($2)',[a,b]);
    await db.query("insert into public.user_profiles values ($1,'pro',null),($2,'basic',null)",[a,b]);
    await db.query("insert into public.generation_history(user_id,response,result_type) values ($1,'Video generation started. Video ID: video_legacy','video')",[a]);
    await db.query("insert into public.video_credit_ledger(user_id,delta,source) values($1,1,'support_grant')",[b]);
    const directory=new URL('../../supabase/migrations/',import.meta.url);
    const name=(await readdir(directory)).find(f=>f.endsWith('_video_access_security.sql'));
    const migration=await readFile(process.env.VIDEO_ACCESS_MIGRATION || (name ? new URL(name,directory) : '/tmp/korlix-video-access-migration.sql'),'utf8');
    await db.exec(migration);
    await t.test('trusted legacy history backfills exact ownership and monthly count',async()=>{
      const jobs=(await db.query('select user_id,provider_job_id,status from public.korlix_video_jobs')).rows;
      assert.deepEqual(jobs,[{user_id:a,provider_job_id:'video_legacy',status:'submitted'}]);
      assert.equal((await summary(a)).usedThisMonth,1);
    });
    await t.test('deleting display history cannot restore video quota',async()=>{
      await db.query('delete from public.generation_history where user_id=$1',[a]);
      assert.equal((await summary(a)).usedThisMonth,1);
      assert.equal((await summary(a)).includedRemaining,1);
    });
    await t.test('one remaining included slot yields only one successful reservation',async()=>{
      const first=await reserve(a);
      const second=await reserve(a);
      assert.equal(first.ok,true);
      assert.equal(second.ok,false);
      assert.equal((await summary(a)).usedThisMonth,2);
    });
    let purchased;
    await t.test('one purchased credit is debited before provider creation and cannot be spent twice',async()=>{
      purchased=await reserve(b);
      assert.equal(purchased.ok,true);
      assert.equal(purchased.spent_purchased_credit,true);
      assert.equal((await summary(b)).purchasedVideoCredits,0);
      assert.equal((await reserve(b)).ok,false);
      assert.equal((await db.query('select count(*)::int as count from public.video_credit_ledger where user_id=$1 and delta=-1',[b])).rows[0].count,1);
    });
    await t.test('image allowance remains separate: Basic and Pro keep one each without spending purchased credits',async()=>{
      for(const user of [a,b]) {
        assert.equal((await reserve(user,'image_to_video')).ok,true);
        assert.equal((await reserve(user,'image_to_video')).ok,false);
      }
      assert.equal((await summary(a)).usedThisMonth,2);
      assert.equal((await summary(b)).usedThisMonth,1);
    });
    await t.test('Ultra image allowance stays 30 and existing monthly usage is retained',async()=>{
      await db.query("update public.user_profiles set tier='ultra' where id=$1",[a]);
      await db.query("update public.korlix_monthly_video_usage set used_count=29 where user_id=$1",[a]);
      assert.equal((await reserve(a,'image_to_video')).ok,true);
      assert.equal((await reserve(a,'image_to_video')).ok,false);
      const usage=(await db.query('select used_count from public.korlix_monthly_video_usage where user_id=$1',[a])).rows[0];
      assert.equal(usage.used_count,30);
      assert.equal((await summary(a)).monthlyLimit,10);
    });
    await t.test('null image limit preserves the previous fallback of one rather than becoming unlimited',async()=>{
      await db.exec("update public.korlix_video_generation_limits set monthly_limit=null where tier_key='basic'");
      assert.equal((await reserve(b,'image_to_video')).ok,false);
    });
    await t.test('only reservation owner can attach result and binding is immutable',async()=>{
      assert.equal((await call('korlix_video_attach',[a,purchased.reservation_id,'video_b'])).ok,false);
      assert.equal((await call('korlix_video_attach',[b,purchased.reservation_id,'video_b'])).ok,true);
      assert.equal((await call('korlix_video_attach',[b,purchased.reservation_id,'video_b'])).ok,true);
      assert.equal((await call('korlix_video_attach',[b,purchased.reservation_id,'video_elsewhere'])).ok,false);
    });
    await t.test('anonymous and authenticated roles cannot read, insert, delete, reserve, attach or summarize',async()=>{
      for(const role of ['anon','authenticated']) {
        await as(role,async()=>{
          for(const sql of ["select * from public.korlix_video_jobs","delete from public.korlix_video_jobs",
            `insert into public.korlix_video_jobs(user_id,kind,provider,charged_source) values('${a}','text_to_video','openai','included')`,
            `select public.korlix_video_credit_summary('${a}')`,
            `select public.korlix_video_reserve('${a}','text_to_video','openai')`,
            `select public.korlix_video_attach('${b}','${purchased.reservation_id}','video_b')`]) {
            await assert.rejects(()=>db.exec(sql),error=>error.code==='42501');
          }
        });
      }
    });
    await t.test('rerunning migration cannot replenish reservations or debit purchased credits again',async()=>{
      const before=await summary(b);
      await db.exec(migration);
      assert.deepEqual(await summary(b),before);
    });
  } finally {await db.close();}
});
