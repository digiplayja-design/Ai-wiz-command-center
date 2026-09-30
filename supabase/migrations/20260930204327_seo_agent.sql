begin;
-- Private SEO monitoring. Only the server can claim work or consume allowance.
create table public.korlix_seo_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=50000),
 monitoring_enabled boolean not null default false,
 next_run_at timestamptz, consent_at timestamptz, pause_reason text,
 updated_at timestamptz not null default now(),
 check(not monitoring_enabled or (next_run_at is not null and consent_at is not null))
);
create table public.korlix_seo_runs (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'queued' check(state in('queued','running','completed','failed')),
 source text not null check(source in('manual','weekly')),
 scheduled_for timestamptz,
 input jsonb not null check(jsonb_typeof(input)='object' and octet_length(input::text)<=60000),
 phase text not null default 'Queued for website audit',
 result jsonb not null default '{}' check(jsonb_typeof(result)='object' and octet_length(result::text)<=600000),
 progress jsonb not null default '{"completedActions":[],"notes":""}' check(octet_length(progress::text)<=20000),
 usage_id uuid references public.usage_counters(id) on delete set null,
 charged integer not null default 3 check(charged in(0,3)),
 lease_token uuid, lease_until timestamptz, error text,
 created_at timestamptz not null default now(), completed_at timestamptz,
 check(source<>'weekly' or scheduled_for is not null),
 check(state<>'running' or (lease_token is not null and lease_until is not null))
);
create index korlix_seo_runs_owner on public.korlix_seo_runs(user_id,created_at desc,id);
create index korlix_seo_runs_usage on public.korlix_seo_runs(usage_id);
create index korlix_seo_runs_queued on public.korlix_seo_runs(created_at,id) where state='queued';
create index korlix_seo_runs_expired on public.korlix_seo_runs(lease_until,id) where state='running';
-- Minimal attempt receipts survive report deletion so failures cannot bypass rate caps.
create table public.korlix_seo_attempts (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create index korlix_seo_attempts_owner_time on public.korlix_seo_attempts(user_id,created_at);
create unique index korlix_seo_one_active on public.korlix_seo_runs(user_id) where state in('queued','running');
create unique index korlix_seo_weekly_once on public.korlix_seo_runs(user_id,scheduled_for) where source='weekly';
create index korlix_seo_due on public.korlix_seo_profiles(next_run_at,user_id) where monitoring_enabled;
alter table public.korlix_seo_profiles enable row level security;
alter table public.korlix_seo_runs enable row level security;
alter table public.korlix_seo_attempts enable row level security;
revoke all on public.korlix_seo_profiles,public.korlix_seo_runs,public.korlix_seo_attempts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_seo_profiles,public.korlix_seo_runs,public.korlix_seo_attempts to service_role;

create function public.korlix_seo_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare p public.korlix_seo_profiles; r public.korlix_seo_runs; old public.korlix_seo_runs;
 allowed boolean; source_name text; scheduled timestamptz; uid uuid; outcome jsonb;
begin
 if p_actor is null then raise exception 'Sign in to use SEO Agent.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':seo-agent',0));
 -- Expired processing is never blindly retried: refund once and require a new run.
 for old in select * from korlix_seo_runs where user_id=p_actor and
   ((state='running' and lease_until<now()) or (state='queued' and created_at<now()-interval '24 hours')) for update loop
  if old.charged=3 then
   update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-3),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=old.usage_id and user_id=p_actor;
  end if;
  update korlix_seo_runs set state='failed',charged=0,phase='Audit interrupted',error='This audit was interrupted. Its reserved credits were returned. Start a new audit.',completed_at=now(),lease_token=null,lease_until=null where id=old.id;
 end loop;
 if p_action='recover' then return '{}'::jsonb;end if;
 select * into p from korlix_seo_profiles where user_id=p_actor for update;
 if p_action='list' then
  return jsonb_build_object('profile',case when p.user_id is null then null else to_jsonb(p) end,'runs',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id) from (select id,state,source,phase,(result-'pages'-'actions'-'drafts'-'sources'-'findings')||jsonb_build_object('ai',coalesce(result->'ai','{}')-'actions'-'drafts'-'opportunities') as result,progress,error,charged,created_at,completed_at from korlix_seo_runs where user_id=p_actor order by created_at desc,id limit 60) q),'[]'::jsonb));
 elsif p_action='profile_save' then
  if p.data->>'website' is distinct from p_data->>'website' and p.monitoring_enabled then
   update korlix_seo_profiles set monitoring_enabled=false,next_run_at=null,pause_reason='Website changed. Review and enable weekly monitoring again.' where user_id=p_actor;
   for old in select * from korlix_seo_runs where user_id=p_actor and source='weekly' and state='queued' for update loop
    perform korlix_seo_v1(p_actor,'fail',old.id,jsonb_build_object('error','Website changed before this scheduled audit started.'));
   end loop;
  end if;
  insert into korlix_seo_profiles(user_id,data) values(p_actor,p_data)
   on conflict(user_id) do update set data=excluded.data,updated_at=now() returning * into p;
  return to_jsonb(p);
 elsif p_action in('monitoring','pause') then
  if p.user_id is null then raise exception 'Save your business setup first.' using errcode='40001';end if;
  if p_action='monitoring' and p_data->>'enabled'='true' then
   if p_data->>'consent' is distinct from 'true' then raise exception 'Confirm weekly audits and AI data sharing before enabling monitoring.';end if;
   if not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier)) in('ultra','enterprise')) then raise exception 'SEO Agent requires Ultra Premium or Enterprise.' using errcode='42501';end if;
   update korlix_seo_profiles set monitoring_enabled=true,consent_at=now(),next_run_at=case when monitoring_enabled then next_run_at else now()+interval '7 days' end,pause_reason=null,updated_at=now() where user_id=p_actor returning * into p;
  else
   update korlix_seo_profiles set monitoring_enabled=false,next_run_at=null,pause_reason=left(coalesce(p_data->>'reason','Weekly monitoring paused.'),300),updated_at=now() where user_id=p_actor returning * into p;
   for old in select * from korlix_seo_runs where user_id=p_actor and source='weekly' and state='queued' for update loop
    perform korlix_seo_v1(p_actor,'fail',old.id,jsonb_build_object('error','Weekly monitoring was paused before this audit started.'));
   end loop;
  end if;
  return to_jsonb(p);
 elsif p_action='enqueue' then
  select * into r from korlix_seo_runs where id=p_id and user_id=p_actor;
  if found then return to_jsonb(r)||jsonb_build_object('replayed',true);end if;
  if exists(select 1 from korlix_seo_attempts where id=p_id) then raise exception 'This audit request was already used. Start a new audit.' using errcode='40001';end if;
  if p.user_id is null then raise exception 'Save your business setup first.' using errcode='40001';end if;
  if not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier)) in('ultra','enterprise')) then raise exception 'SEO Agent requires Ultra Premium or Enterprise.' using errcode='42501';end if;
  source_name:=coalesce(p_data->>'source','manual');
  if source_name not in('manual','weekly') then raise exception 'Invalid audit source.';end if;
  if source_name='manual' and p_data->>'consent' is distinct from 'true' then raise exception 'Confirm AI data sharing before auditing your website.';end if;
  if source_name='weekly' then
   if not p.monitoring_enabled or p.next_run_at>now() or p.consent_at is null then raise exception 'This weekly audit is paused or not due.' using errcode='40001';end if;
   scheduled:=p.next_run_at;
  end if;
  if exists(select 1 from korlix_seo_runs where user_id=p_actor and state in('queued','running')) then raise exception 'An SEO audit is already queued or running.' using errcode='40001';end if;
  if (select count(*) from korlix_seo_attempts where user_id=p_actor and created_at>now()-interval '1 hour')>=3 then raise exception 'Please wait before starting more SEO audits.' using errcode='54000';end if;
  uid:=(p_data->>'usage_id')::uuid;
  update usage_counters set credits_used=coalesce(credits_used,0)+3,standard_generations=coalesce(standard_generations,0)+1,updated_at=now()
   where id=uid and user_id=p_actor and coalesce(credits_used,0)+3<=(p_data->>'credit_limit')::integer
   and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)+1<=(p_data->>'request_limit')::integer;
  if not found then raise exception 'Your generation allowance is unavailable. Weekly monitoring can be resumed after reviewing your allowance.' using errcode='54000';end if;
  delete from korlix_seo_attempts where user_id=p_actor and created_at<now()-interval '24 hours';
  insert into korlix_seo_attempts(id,user_id) values(p_id,p_actor);
  delete from korlix_seo_runs where user_id=p_actor and state not in('queued','running') and id in(select id from korlix_seo_runs where user_id=p_actor order by created_at desc,id offset 59);
  insert into korlix_seo_runs(id,user_id,source,scheduled_for,input,usage_id) values(p_id,p_actor,source_name,scheduled,jsonb_build_object('profile',p.data,'profileUpdatedAt',p.updated_at),uid) returning * into r;
  if source_name='weekly' then update korlix_seo_profiles set next_run_at=now()+interval '7 days',updated_at=now() where user_id=p_actor;end if;
  return to_jsonb(r)||jsonb_build_object('replayed',false);
 elsif p_action='clear' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm before clearing SEO Agent.';end if;
  if exists(select 1 from korlix_seo_runs where user_id=p_actor and state='running') then raise exception 'Wait for the running audit before clearing SEO Agent.' using errcode='40001';end if;
  for old in select * from korlix_seo_runs where user_id=p_actor and state='queued' for update loop
   perform korlix_seo_v1(p_actor,'fail',old.id,jsonb_build_object('error','Audit cancelled by owner.'));
  end loop;
  delete from korlix_seo_runs where user_id=p_actor;delete from korlix_seo_profiles where user_id=p_actor;return '{}'::jsonb;
 end if;
 select * into r from korlix_seo_runs where id=p_id and user_id=p_actor for update;
 if not found then raise exception 'This SEO audit was not found.' using errcode='P0002';end if;
 if p_action='get' then return to_jsonb(r);
 elsif p_action='claim' then
  if r.state<>'queued' then raise exception 'This audit was already claimed or completed.' using errcode='40001';end if;
  if not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier)) in('ultra','enterprise')) then raise exception 'SEO Agent requires Ultra Premium or Enterprise.' using errcode='42501';end if;
  if r.source='weekly' and (p.user_id is null or not p.monitoring_enabled or p.data->>'website' is distinct from r.input->'profile'->>'website') then raise exception 'Weekly monitoring changed before this audit started.' using errcode='40001';end if;
  if p_data->>'lease_token' is null then raise exception 'Audit lease is required.';end if;
  update korlix_seo_runs set state='running',phase='Inspecting your website',lease_token=(p_data->>'lease_token')::uuid,lease_until=now()+interval '6 minutes' where id=r.id returning * into r;
 elsif p_action in('phase','finish','fail') then
  if r.state not in('queued','running') then return to_jsonb(r);end if;
  if r.state='running' and r.lease_token is distinct from (p_data->>'lease_token')::uuid then raise exception 'This audit lease changed.' using errcode='40001';end if;
  if p_action='phase' then
   if r.state<>'running' then raise exception 'This audit is not running.' using errcode='40001';end if;
   update korlix_seo_runs set phase=left(p_data->>'phase',150) where id=r.id returning * into r;
  elsif p_action='finish' then
   if r.state<>'running' then raise exception 'This audit is not running.' using errcode='40001';end if;
   update korlix_seo_runs set state='completed',phase='Audit ready',result=p_data->'result',completed_at=now(),lease_token=null,lease_until=null where id=r.id returning * into r;
  else
   if r.charged=3 then update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-3),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=r.usage_id and user_id=p_actor;end if;
   update korlix_seo_runs set state='failed',phase='Audit could not finish',error=left(coalesce(p_data->>'error','The audit could not finish. Reserved credits were returned.'),300),charged=0,completed_at=now(),lease_token=null,lease_until=null where id=r.id returning * into r;
  end if;
 elsif p_action='progress' then
  if r.state<>'completed' then raise exception 'Wait for a completed audit before updating its actions.' using errcode='40001';end if;
  if jsonb_typeof(p_data->'completedActions') is distinct from 'array' or jsonb_array_length(p_data->'completedActions')>30 or coalesce(length(p_data->>'notes'),0)>2000 then raise exception 'Invalid action progress.';end if;
  if exists(select 1 from jsonb_array_elements_text(p_data->'completedActions') x where not exists(select 1 from jsonb_array_elements(coalesce(r.result->'ai'->'actions',r.result->'actions','[]')) a where a->>'id'=x)) then raise exception 'Choose actions from this audit.';end if;
  update korlix_seo_runs set progress=jsonb_build_object('completedActions',p_data->'completedActions','notes',coalesce(p_data->>'notes','')) where id=r.id returning * into r;
 elsif p_action='remove' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm before removing this audit.';end if;
  if r.state in('queued','running') then raise exception 'Wait for this audit before removing it.' using errcode='40001';end if;
  delete from korlix_seo_runs where id=r.id;return '{}'::jsonb;
 else raise exception 'Unknown SEO Agent action.';end if;
 return to_jsonb(r);
end $$;

-- Discovery only. All mutations recheck state under an owner transaction lock.
create function public.korlix_seo_due_v1() returns jsonb
language sql security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'profiles',coalesce((select jsonb_agg(x) from(select user_id from korlix_seo_profiles where monitoring_enabled and next_run_at<=now() order by next_run_at,user_id limit 20)x),'[]'::jsonb),
  'runs',coalesce((select jsonb_agg(x) from(select id,user_id from korlix_seo_runs where state='queued' or (state='running' and lease_until<now()) order by created_at,id limit 20)x),'[]'::jsonb)
 );
$$;
revoke all on function public.korlix_seo_v1(uuid,text,uuid,jsonb),public.korlix_seo_due_v1() from public,anon,authenticated;
grant execute on function public.korlix_seo_v1(uuid,text,uuid,jsonb),public.korlix_seo_due_v1() to service_role;
commit;
