-- Private AI Visibility profiles and repeatable, idempotent report runs.
create table public.korlix_visibility_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=50000),
 updated_at timestamptz not null default now()
);
create table public.korlix_visibility_runs (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'running' check(state in ('running','completed','failed')),
 phase text not null default 'Checking three discovery questions',
 input jsonb not null check(octet_length(input::text)<=60000),
 usage_id uuid not null references public.usage_counters(id),
 result jsonb not null default '{}' check(octet_length(result::text)<=600000),
 progress jsonb not null default '{"completedActions":[],"inquiries":0,"bookings":0,"notes":""}' check(octet_length(progress::text)<=20000),
 charged integer not null default 0 check(charged in (0,3)), error text,
 created_at timestamptz not null default now(), completed_at timestamptz
);
create index korlix_visibility_runs_owner on public.korlix_visibility_runs(user_id,created_at desc);
create index korlix_visibility_runs_usage on public.korlix_visibility_runs(usage_id);
create unique index korlix_visibility_one_running on public.korlix_visibility_runs(user_id) where state='running';
alter table public.korlix_visibility_profiles enable row level security;
alter table public.korlix_visibility_runs enable row level security;
revoke all on public.korlix_visibility_profiles,public.korlix_visibility_runs from public,anon,authenticated;
grant all on public.korlix_visibility_profiles,public.korlix_visibility_runs to service_role;
create function public.korlix_visibility_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public as $$
declare r public.korlix_visibility_runs; p public.korlix_visibility_profiles;
begin
 if p_actor is null then raise exception 'Sign in to use AI Visibility.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,223));
 update korlix_visibility_runs set state='failed',phase='Interrupted',error='This scan was interrupted. No credits were charged. Start a new scan.',completed_at=now()
 where user_id=p_actor and state='running' and created_at<now()-interval '12 minutes';
 if p_action='list' then
  return jsonb_build_object('profile',(select to_jsonb(x) from korlix_visibility_profiles x where user_id=p_actor),
   'runs',coalesce((select jsonb_agg(to_jsonb(x)-'input'-'result'||jsonb_build_object('result',x.result-'samples'-'observations'-'actions'-'drafts'-'sources') order by x.created_at desc)
      from (select * from korlix_visibility_runs where user_id=p_actor order by created_at desc limit 60) x),'[]'::jsonb));
 elsif p_action='profile_save' then
  insert into korlix_visibility_profiles(user_id,data) values(p_actor,p_data)
  on conflict(user_id) do update set data=excluded.data,updated_at=now() returning * into p;return to_jsonb(p);
 elsif p_action='run_get' then
  select * into r from korlix_visibility_runs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This visibility report was not found.' using errcode='P0002';end if;return to_jsonb(r);
 elsif p_action='run_begin' then
  select * into r from korlix_visibility_runs where id=p_id and user_id=p_actor;
  if found then return to_jsonb(r)||jsonb_build_object('replayed',true);end if;
  if exists(select 1 from korlix_visibility_runs where user_id=p_actor and state='running') then raise exception 'KORLIX is already scanning your business. Reopen AI Visibility to follow progress.' using errcode='40001';end if;
  if (select count(*) from korlix_visibility_runs where user_id=p_actor and created_at>now()-interval '1 hour')>=6 then raise exception 'Please wait before starting more visibility scans.' using errcode='54000';end if;
  select * into p from korlix_visibility_profiles where user_id=p_actor;
  if not found then raise exception 'Save your business setup first.';end if;
  if not exists(select 1 from usage_counters where id=(p_data->>'usage_id')::uuid and user_id=p_actor) then raise exception 'Usage is unavailable.' using errcode='40001';end if;
  delete from korlix_visibility_runs where user_id=p_actor and state<>'running' and id in
   (select id from korlix_visibility_runs where user_id=p_actor order by created_at desc offset 59);
  insert into korlix_visibility_runs(id,user_id,input,usage_id) values(p_id,p_actor,jsonb_build_object('profile',p.data,'profileUpdatedAt',p.updated_at),(p_data->>'usage_id')::uuid) returning * into r;
  return to_jsonb(r)||jsonb_build_object('replayed',false);
 elsif p_action='run_phase' then
  update korlix_visibility_runs set phase=left(p_data->>'phase',150) where id=p_id and user_id=p_actor and state='running';return '{}'::jsonb;
 elsif p_action='run_finish' then
  select * into r from korlix_visibility_runs where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'This visibility report was not found.' using errcode='P0002';end if;
  if r.state<>'running' then return to_jsonb(r);end if;
  update usage_counters set credits_used=coalesce(credits_used,0)+3,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=r.usage_id and user_id=p_actor;
  if not found then raise exception 'Usage is unavailable.' using errcode='40001';end if;
  update korlix_visibility_runs set state='completed',phase='Report ready',result=p_data->'result',charged=3,completed_at=now() where id=p_id returning * into r;return to_jsonb(r);
 elsif p_action='run_fail' then
  update korlix_visibility_runs set state='failed',phase='Scan could not finish',error=left(p_data->>'error',300),completed_at=now() where id=p_id and user_id=p_actor and state='running' returning * into r;return coalesce(to_jsonb(r),'{}'::jsonb);
 elsif p_action='progress' then
  select * into r from korlix_visibility_runs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This visibility report was not found.' using errcode='P0002';end if;
  if r.state<>'completed' then raise exception 'Wait for a completed report before updating progress.' using errcode='40001';end if;
  update korlix_visibility_runs set progress=p_data where id=p_id and user_id=p_actor returning * into r;return to_jsonb(r);
 elsif p_action='remove' then
  if exists(select 1 from korlix_visibility_runs where id=p_id and user_id=p_actor and state='running') then raise exception 'Wait for this scan to finish before removing it.' using errcode='40001';end if;
  delete from korlix_visibility_runs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This visibility report was not found.' using errcode='P0002';end if;return '{}'::jsonb;
 elsif p_action='clear' then
  if exists(select 1 from korlix_visibility_runs where user_id=p_actor and state='running') then raise exception 'Wait for the scan to finish before clearing AI Visibility.' using errcode='40001';end if;
  delete from korlix_visibility_runs where user_id=p_actor;
  delete from korlix_visibility_profiles where user_id=p_actor;return '{}'::jsonb;
 end if;
 raise exception 'Unknown visibility operation.';
end $$;
revoke all on function public.korlix_visibility_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_visibility_v1(uuid,text,uuid,jsonb) to service_role;
