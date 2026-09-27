-- Contract Radar: verified backend actors, private records, idempotent AI jobs.
create table public.korlix_radar_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=32768),
 updated_at timestamptz not null default now()
);
create table public.korlix_radar_opportunities (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 source_key text not null check(length(source_key)<=2100),
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=160000),
 stage text not null default 'saved' check(stage in ('saved','reviewing','preparing','submitted','won','closed')),
 notes text not null default '' check(length(notes)<=4000),
 review jsonb not null default '{}' check(octet_length(review::text)<=160000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(user_id,source_key)
);
create index korlix_radar_opportunities_owner on public.korlix_radar_opportunities(user_id,updated_at desc);
create table public.korlix_radar_jobs (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('discover','review')),
 state text not null default 'running' check(state in ('running','completed','failed')),
 opportunity_id uuid references public.korlix_radar_opportunities(id) on delete cascade,
 input jsonb not null check(octet_length(input::text)<=240000), signature text not null,
 usage_id uuid not null references public.usage_counters(id),
 result jsonb not null default '{}' check(octet_length(result::text)<=350000),
 charged integer not null default 0 check(charged in (0,1)), error text,
 created_at timestamptz not null default now(), completed_at timestamptz
);
create index korlix_radar_jobs_owner on public.korlix_radar_jobs(user_id,created_at desc);
create index korlix_radar_jobs_opportunity on public.korlix_radar_jobs(opportunity_id);
create index korlix_radar_jobs_usage on public.korlix_radar_jobs(usage_id);
create unique index korlix_radar_one_running on public.korlix_radar_jobs(user_id) where state='running';
alter table public.korlix_radar_profiles enable row level security;
alter table public.korlix_radar_opportunities enable row level security;
alter table public.korlix_radar_jobs enable row level security;
revoke all on public.korlix_radar_profiles,public.korlix_radar_opportunities,public.korlix_radar_jobs from public,anon,authenticated;
grant all on public.korlix_radar_profiles,public.korlix_radar_opportunities,public.korlix_radar_jobs to service_role;

create function public.korlix_radar_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public as $$
declare j public.korlix_radar_jobs; o public.korlix_radar_opportunities; p public.korlix_radar_profiles;
 v_input jsonb; v_charge integer;
begin
 if p_actor is null then raise exception 'Sign in to use Contract Radar.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,222));
 update korlix_radar_jobs set state='failed',error='This request was interrupted. No credit was charged. Start a new request.',completed_at=now()
 where user_id=p_actor and state='running' and created_at<now()-interval '8 minutes';
 if p_action='list' then
  return jsonb_build_object('profile',(select to_jsonb(x) from korlix_radar_profiles x where user_id=p_actor),
   'opportunities',coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from korlix_radar_opportunities x where user_id=p_actor),'[]'::jsonb),
   'jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from korlix_radar_jobs where user_id=p_actor order by created_at desc limit 12) x),'[]'::jsonb));
 elsif p_action='profile_save' then
  insert into korlix_radar_profiles(user_id,data) values(p_actor,p_data)
  on conflict(user_id) do update set data=excluded.data,updated_at=now() returning * into p; return to_jsonb(p);
 elsif p_action='opportunity_get' then
  select * into o from korlix_radar_opportunities where id=p_id and user_id=p_actor;
  if not found then raise exception 'This saved opportunity was not found.' using errcode='P0002'; end if;return to_jsonb(o);
 elsif p_action='opportunity_save' then
  select * into o from korlix_radar_opportunities where user_id=p_actor and source_key=p_data->>'source_key';
  if found then return to_jsonb(o);end if;
  if (select count(*) from korlix_radar_opportunities where user_id=p_actor)>=100 then raise exception 'Your radar has 100 saved opportunities. Remove one first.' using errcode='54000';end if;
  insert into korlix_radar_opportunities(id,user_id,source_key,data) values(p_id,p_actor,p_data->>'source_key',p_data->'data') returning * into o;return to_jsonb(o);
 elsif p_action='opportunity_update' then
  select * into o from korlix_radar_opportunities where id=p_id and user_id=p_actor;
  if not found then raise exception 'This saved opportunity was not found.' using errcode='P0002';end if;
  if exists(select 1 from korlix_radar_jobs where opportunity_id=p_id and user_id=p_actor and state='running') then raise exception 'Wait for Nova to finish reviewing this opportunity.' using errcode='40001';end if;
  update korlix_radar_opportunities set stage=coalesce(p_data->>'stage',stage),notes=coalesce(p_data->>'notes',notes),
   data=case when p_data ? 'noticeText' then data||jsonb_build_object('noticeText',p_data->>'noticeText') else data end,
   review=case when p_data ? 'noticeText' and coalesce(data->>'noticeText','')<>p_data->>'noticeText' then '{}'::jsonb else review end,updated_at=now()
  where id=p_id and user_id=p_actor returning * into o;return to_jsonb(o);
 elsif p_action='opportunity_delete' then
  if exists(select 1 from korlix_radar_jobs where user_id=p_actor and state='running' and opportunity_id=p_id) then raise exception 'Wait for the review to finish before removing this opportunity.' using errcode='40001';end if;
  delete from korlix_radar_opportunities where id=p_id and user_id=p_actor;
  if not found then raise exception 'This saved opportunity was not found.' using errcode='P0002';end if;return '{}'::jsonb;
 elsif p_action='clear' then
  if exists(select 1 from korlix_radar_jobs where user_id=p_actor and state='running') then raise exception 'Wait for Nova to finish before clearing your radar.' using errcode='40001';end if;
  delete from korlix_radar_jobs where user_id=p_actor;
  delete from korlix_radar_opportunities where user_id=p_actor;
  delete from korlix_radar_profiles where user_id=p_actor;return '{}'::jsonb;
 elsif p_action='job_get' then
  select * into j from korlix_radar_jobs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This radar request was not found.' using errcode='P0002';end if;return to_jsonb(j);
 elsif p_action='job_begin' then
  select * into j from korlix_radar_jobs where id=p_id and user_id=p_actor;
  if found then
   if j.signature<>p_data->>'signature' then raise exception 'Use a new request for changed inputs.' using errcode='40001';end if;
   return to_jsonb(j)||jsonb_build_object('replayed',true);
  end if;
  if exists(select 1 from korlix_radar_jobs where user_id=p_actor and state='running') then raise exception 'Nova is already working on your radar. Reopen it to follow progress.' using errcode='40001';end if;
  if (select count(*) from korlix_radar_jobs where user_id=p_actor and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before starting more radar requests.' using errcode='54000';end if;
  select * into p from korlix_radar_profiles where user_id=p_actor;
  if not found then raise exception 'Save your business profile first.';end if;
  if not exists(select 1 from usage_counters where id=(p_data->>'usage_id')::uuid and user_id=p_actor) then raise exception 'Usage is unavailable.' using errcode='40001';end if;
  v_input=jsonb_build_object('profile',p.data,'profileUpdatedAt',p.updated_at,'query',p_data->>'query');
  if p_data->>'kind'='review' then
   select * into o from korlix_radar_opportunities where id=(p_data->>'opportunity_id')::uuid and user_id=p_actor;
   if not found then raise exception 'Choose an opportunity saved to your own radar.' using errcode='P0002';end if;
   v_input=v_input||jsonb_build_object('opportunity',o.data);
  end if;
  delete from korlix_radar_jobs where user_id=p_actor and state<>'running' and id in
   (select id from korlix_radar_jobs where user_id=p_actor order by created_at desc offset 99);
  insert into korlix_radar_jobs(id,user_id,kind,opportunity_id,input,signature,usage_id)
  values(p_id,p_actor,p_data->>'kind',(p_data->>'opportunity_id')::uuid,v_input,p_data->>'signature',(p_data->>'usage_id')::uuid) returning * into j;
  return to_jsonb(j)||jsonb_build_object('replayed',false);
 elsif p_action='job_finish' then
  select * into j from korlix_radar_jobs where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'This radar request was not found.' using errcode='P0002';end if;
  if j.state<>'running' then return to_jsonb(j);end if;
  v_charge=case when j.kind='discover' and jsonb_array_length(p_data->'result'->'opportunities')=0 then 0 else 1 end;
  if j.kind='review' then
   update korlix_radar_opportunities set review=p_data->'result',updated_at=now() where id=j.opportunity_id and user_id=p_actor;
   if not found then raise exception 'This saved opportunity was not found.' using errcode='P0002';end if;
  end if;
  if v_charge=1 then
   update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=j.usage_id and user_id=p_actor;
   if not found then raise exception 'Usage is unavailable.' using errcode='40001';end if;
  end if;
  update korlix_radar_jobs set state='completed',result=p_data->'result',charged=v_charge,completed_at=now() where id=p_id returning * into j;return to_jsonb(j);
 elsif p_action='job_fail' then
  update korlix_radar_jobs set state='failed',error=left(p_data->>'error',300),completed_at=now() where id=p_id and user_id=p_actor and state='running' returning * into j;
  return coalesce(to_jsonb(j),'{}'::jsonb);
 end if;
 raise exception 'Unknown radar operation.';
end $$;
revoke all on function public.korlix_radar_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_radar_v1(uuid,text,uuid,jsonb) to service_role;
