-- Private authoritative video ownership and quota. Deleting display history
-- cannot erase a reservation or replenish the included allowance.
create table if not exists public.korlix_video_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('text_to_video','image_to_video')),
  provider text not null check (provider in ('openai','kling','generic')),
  provider_job_id text check (provider_job_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'),
  status text not null default 'reserved' check (status in ('reserved','submitted')),
  charged_source text not null check (charged_source in ('included','purchased','legacy')),
  legacy_history_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_job_id)
);
create index if not exists korlix_video_jobs_owner_month on public.korlix_video_jobs(user_id,created_at);
alter table public.korlix_video_jobs enable row level security;
revoke all on public.korlix_video_jobs from public, anon, authenticated;
grant all on public.korlix_video_jobs to service_role;
drop policy if exists korlix_video_jobs_server_only on public.korlix_video_jobs;
create policy korlix_video_jobs_server_only on public.korlix_video_jobs as restrictive
  for all to anon,authenticated using(false) with check(false);

-- Existing history INSERT is blocked by RLS for client roles. Only exact
-- server-written legacy responses establish a provider ID; ambiguous IDs do not.
with historical as (
  select gh.id::text as history_id, gh.user_id, gh.created_at,
    substring(gh.response from '^Video generation started[.] Video ID: ([A-Za-z0-9][A-Za-z0-9_.:-]{0,199})$') as job_id
  from public.generation_history gh join auth.users u on u.id=gh.user_id
  where gh.result_type='video'
), unique_jobs as (
  select *, case when count(*) over(partition by job_id)=1 then job_id end as safe_job_id
  from historical
)
insert into public.korlix_video_jobs(user_id,kind,provider,provider_job_id,status,charged_source,legacy_history_id,created_at)
select user_id,'text_to_video','openai',safe_job_id,
  case when safe_job_id is null then 'reserved' else 'submitted' end,
  'legacy',history_id,created_at from unique_jobs
on conflict do nothing;

create or replace function public.korlix_video_credit_summary(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  profile jsonb; plan text; monthly_limit integer; used_count bigint;
  credit_balance bigint; override_text text;
begin
  if p_user_id is null then raise exception 'User required' using errcode='22023'; end if;
  select to_jsonb(p) into profile from public.user_profiles p where p.id=p_user_id;
  if profile is null then raise exception 'Profile unavailable' using errcode='P0001'; end if;
  plan := lower(coalesce(profile->>'tier','basic'));
  monthly_limit := case plan when 'pro' then 2 when 'ultra' then 10 when 'ultra_premium' then 10 when 'enterprise' then 25 else 0 end;
  override_text := profile->>'video_generation_limit_override';
  if override_text ~ '^[0-9]{1,7}([.][0-9]{1,4})?$' and override_text::numeric>0 then
    monthly_limit := ceil(override_text::numeric)::integer;
  end if;
  select count(*) into used_count from public.korlix_video_jobs
    where user_id=p_user_id and kind='text_to_video' and created_at >= (date_trunc('month',now() at time zone 'UTC') at time zone 'UTC');
  select coalesce(sum(delta),0) into credit_balance from public.video_credit_ledger where user_id=p_user_id;
  return jsonb_build_object('tier',plan,'monthlyLimit',monthly_limit,'usedThisMonth',used_count,
    'includedRemaining',greatest(monthly_limit-used_count,0),'purchasedVideoCredits',credit_balance,
    'canGenerateVideo',used_count<monthly_limit or credit_balance>0,
    'packs',jsonb_build_object('korlix_video_credits_3',3,'korlix_video_credits_10',10,'korlix_video_credits_25',25));
end $$;

create or replace function public.korlix_video_reserve(p_user_id uuid,p_kind text,p_provider text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare summary jsonb; reservation uuid; spend boolean := false; canonical_tier text;
begin
  if p_user_id is null or p_kind not in ('text_to_video','image_to_video') or p_provider not in ('openai','kling','generic') then
    raise exception 'Invalid video request' using errcode='22023';
  end if;
  -- One transaction decides allowance and debits purchased credit before any
  -- provider call. Parallel tabs/processes cannot spend the same allowance.
  perform pg_advisory_xact_lock(hashtextextended('korlix-video:'||p_user_id::text,0));
  if p_kind='image_to_video' then
    -- Preserve the separately configured image-video allowances and their
    -- existing monthly usage. Only the server-owned profile supplies the tier.
    select p.tier into canonical_tier from public.user_profiles p where p.id=p_user_id;
    if not found then raise exception 'Profile unavailable' using errcode='P0001'; end if;
    summary := public.korlix_claim_monthly_video_generation(p_user_id,canonical_tier,p_kind);
    if (summary->>'ok')::boolean is distinct from true then return jsonb_build_object('ok',false); end if;
  else
    summary := public.korlix_video_credit_summary(p_user_id);
    if not (summary->>'canGenerateVideo')::boolean then return jsonb_build_object('ok',false); end if;
    spend := (summary->>'includedRemaining')::bigint<=0;
  end if;
  insert into public.korlix_video_jobs(user_id,kind,provider,charged_source)
    values(p_user_id,p_kind,p_provider,case when spend then 'purchased' else 'included' end) returning id into reservation;
  if spend then
    insert into public.video_credit_ledger(user_id,delta,source,description,metadata)
      values(p_user_id,-1,'video_generation','Reserved 1 purchased video credit for video generation',
        jsonb_build_object('reservation_id',reservation,'kind',p_kind,'provider',p_provider));
  end if;
  return jsonb_build_object('ok',true,'reservation_id',reservation,'spent_purchased_credit',spend);
end $$;

create or replace function public.korlix_video_attach(p_user_id uuid,p_reservation_id uuid,p_job_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare job public.korlix_video_jobs;
begin
  if p_job_id is null or p_job_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$' then
    raise exception 'Invalid video ID' using errcode='22023';
  end if;
  select * into job from public.korlix_video_jobs where id=p_reservation_id and user_id=p_user_id for update;
  if not found then return jsonb_build_object('ok',false); end if;
  if job.status='submitted' then return jsonb_build_object('ok',job.provider_job_id=p_job_id); end if;
  update public.korlix_video_jobs set provider_job_id=p_job_id,status='submitted',updated_at=now() where id=job.id;
  return jsonb_build_object('ok',true);
end $$;

revoke all on function public.korlix_video_credit_summary(uuid) from public,anon,authenticated;
revoke all on function public.korlix_video_reserve(uuid,text,text) from public,anon,authenticated;
revoke all on function public.korlix_video_attach(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.korlix_video_credit_summary(uuid),public.korlix_video_reserve(uuid,text,text),public.korlix_video_attach(uuid,uuid,text) to service_role;
