-- The service role intentionally cannot SELECT auth.users. This private, narrow
-- capability checks only existence and the current ban expiry for scheduled work.
create schema if not exists korlix_live_private;
revoke all on schema korlix_live_private from public,anon,authenticated;
grant usage on schema korlix_live_private to service_role;
create function korlix_live_private.account_available(p_actor uuid)
returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from auth.users where id=p_actor
  and coalesce(banned_until,'-infinity'::timestamptz)<=pg_catalog.clock_timestamp())
$$;
revoke all on function korlix_live_private.account_available(uuid) from public,anon,authenticated;
grant execute on function korlix_live_private.account_available(uuid) to service_role;

-- Customer allowances are service-managed records, never inferred from user metadata.
-- Reservations remain charged after claim (including uncertain provider outcomes).
-- Cancellation before claim releases period capacity but keeps the daily start receipt.
create table public.korlix_live_studio_grants (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references auth.users(id) on delete cascade,
 label text not null default 'Live Studio access' check(length(label) between 1 and 80),
 enabled boolean not null default false,
 period_start timestamptz not null, period_end timestamptz not null,
 max_daily_starts integer not null check(max_daily_starts between 0 and 100),
 rehearsal_limit integer not null check(rehearsal_limit between 0 and 10000),
 broadcast_seconds_limit integer not null check(broadcast_seconds_limit between 0 and 10000000),
 generation_limit integer not null check(generation_limit between 0 and 1000000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(period_start<period_end)
);
alter table public.korlix_live_studio_grants enable row level security;
revoke all on public.korlix_live_studio_grants from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_live_studio_grants to service_role;

alter table public.korlix_live_studio_runs
 add column grant_id uuid,
 add column grant_period_start timestamptz,
 add column grant_period_end timestamptz,
 add column show_id uuid,
 add column mode text check(mode in ('rehearsal','youtube')),
 add column rehearsal_reserved integer not null default 0 check(rehearsal_reserved between 0 and 1),
 add column broadcast_seconds_reserved integer not null default 0 check(broadcast_seconds_reserved between 0 and 1800),
 add column generations_reserved integer not null default 0 check(generations_reserved between 0 and 200),
 add column generations_dispatched integer not null default 0 check(generations_dispatched between 0 and 200),
 add column claimed_at timestamptz,
 add column released_at timestamptz,
 add column worker_id uuid,
 add column connection_id uuid,
 add column connection_revision integer,
 add column channel_id text;
create index korlix_live_studio_runs_period on public.korlix_live_studio_runs(owner_id,grant_id,grant_period_start,grant_period_end) where released_at is null;
alter table public.korlix_live_studio_shows
 add column queued_at timestamptz,
 add column worker_id uuid,
 add column connection_id uuid,
 add column connection_revision integer,
 add column channel_id text;
-- Legacy queued requests were not authorized against customer grants. Never run them.
update public.korlix_live_studio_shows set state='cancelled',error='Review your customer allowance and start this show again.',updated_at=now(),version=version+1 where state='queued';
drop index public.korlix_live_studio_single_run;
-- A cancelled encoder retains its slot until its worker finishes or its lease expires.
create unique index korlix_live_studio_owner_execution on public.korlix_live_studio_shows(owner_id) where worker_token is not null;
create unique index korlix_live_studio_channel_execution on public.korlix_live_studio_shows(channel_id) where worker_token is not null and channel_id is not null;
create unique index korlix_live_studio_worker_execution on public.korlix_live_studio_shows(worker_id) where worker_token is not null and worker_id is not null;
-- No deployed customer worker depends on the pilot's singleton readiness record.
drop table public.korlix_live_studio_workers;
create table public.korlix_live_studio_workers (
 id uuid primary key, mode text not null check(mode='youtube'),
 ready_until timestamptz not null, run_id uuid, updated_at timestamptz not null default now()
);
alter table public.korlix_live_studio_workers enable row level security;
revoke all on public.korlix_live_studio_workers from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_live_studio_workers to service_role;

create function public.korlix_live_studio_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 s public.korlix_live_studio_shows; candidate record; expired record;
 g public.korlix_live_studio_grants; r public.korlix_live_studio_runs;
 existing public.korlix_live_studio_events; w public.korlix_live_studio_workers;
 connection_uuid uuid; connection_revision_value integer; channel_value text;
 t timestamptz:=clock_timestamp(); token uuid; worker uuid; action text;
 reserved_rehearsals bigint; reserved_seconds bigint; reserved_generations bigint; daily_starts bigint;
 wanted_rehearsals integer; wanted_seconds integer; wanted_generations integer;
 is_enabled boolean; due_at timestamptz;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'Studio request is too large or invalid.' using errcode='22023'; end if;
 if p_action='announce' then
  if p_actor is not null or p_id is null or coalesce(p_data->>'mode','youtube')<>'youtube' then raise exception 'Invalid worker identity.' using errcode='22023'; end if;
  insert into public.korlix_live_studio_workers(id,mode,ready_until,updated_at) values(p_id,'youtube',t+interval '35 seconds',t)
   on conflict(id) do update set ready_until=excluded.ready_until,updated_at=excluded.updated_at;
  return '{"ready":true}';
 end if;
 if p_action='retire' then
  if p_actor is not null or p_id is null then raise exception 'Invalid worker identity.' using errcode='22023'; end if;
  update public.korlix_live_studio_workers set ready_until=t,updated_at=t where id=p_id;
  return '{"retired":true}';
 end if;
 if p_action='worker_status' then
  return jsonb_build_object('youtubeReady',exists(select 1 from public.korlix_live_studio_workers where ready_until>t));
 end if;
 if p_action in ('claim','sweep') then
  -- The same owner-first order is used by queue/control/OAuth changes. Try locks
  -- ensure maintenance or a busy customer never blocks an unrelated customer.
  for expired in select id,owner_id from public.korlix_live_studio_shows
   where (p_actor is null or owner_id=p_actor) and
    ((state='queued' and coalesce(scheduled_at,queued_at,created_at)<t-interval '15 minutes') or
     (worker_token is not null and (lease_until<t or deadline_at<t))) order by owner_id,id
  loop
   if not pg_try_advisory_xact_lock(hashtextextended(expired.owner_id::text,9811)) then continue; end if;
   select * into s from public.korlix_live_studio_shows where id=expired.id for update skip locked;
   if not found then continue; end if;
   if s.state='queued' and coalesce(s.scheduled_at,s.queued_at,s.created_at)<t-interval '15 minutes' then
    update public.korlix_live_studio_runs set released_at=t where id=s.run_id and claimed_at is null;
    update public.korlix_live_studio_shows set state='failed',error='The scheduled worker was unavailable. Choose a new start time.',updated_at=t,version=version+1 where id=s.id;
   elsif s.worker_token is not null and (s.lease_until<t or s.deadline_at<t) then
    update public.korlix_live_studio_workers set run_id=null,updated_at=t where id=s.worker_id and run_id=s.run_id;
    update public.korlix_live_studio_shows set state=case when state='cancelled' then 'cancelled' else 'failed' end,
     error=coalesce(error,'The broadcast worker stopped. Review the show before starting a new run.'),worker_token=null,lease_until=null,worker_id=null,updated_at=t,version=version+1 where id=s.id;
   end if;
  end loop;
  if p_action='sweep' then return '{}'; end if;
  token:=(p_data->>'token')::uuid; worker:=(p_data->>'workerId')::uuid;
  if token is null or p_data->>'mode' is null or p_data->>'mode' not in ('rehearsal','youtube') then raise exception 'Invalid worker.' using errcode='22023'; end if;
  if p_data->>'mode'='youtube' and worker is null then raise exception 'A ready broadcast worker is required.' using errcode='42501'; end if;
  for candidate in select id,owner_id from public.korlix_live_studio_shows where state='queued' and mode=p_data->>'mode'
   and coalesce(scheduled_at,queued_at,created_at)<=t and (p_actor is null or owner_id=p_actor) order by coalesce(scheduled_at,queued_at,created_at),created_at,id
  loop
   if not pg_try_advisory_xact_lock(hashtextextended(candidate.owner_id::text,9811)) then continue; end if;
   select * into s from public.korlix_live_studio_shows where id=candidate.id and state='queued' for update skip locked;
   if not found then continue; end if;
   if exists(select 1 from public.korlix_live_studio_shows where owner_id=s.owner_id and worker_token is not null) then continue; end if;
   select * into r from public.korlix_live_studio_runs where id=s.run_id;
   select * into g from public.korlix_live_studio_grants where id=r.grant_id and owner_id=s.owner_id;
   if g.id is null or not g.enabled or g.period_start>t or g.period_end<=t or r.released_at is not null or r.claimed_at is not null
    or r.grant_period_start is distinct from g.period_start or r.grant_period_end is distinct from g.period_end
    or not korlix_live_private.account_available(s.owner_id) then
    update public.korlix_live_studio_shows set state='failed',error='Live Studio access expired or changed before this show started.',updated_at=t,version=version+1 where id=s.id;
    update public.korlix_live_studio_runs set released_at=t where id=s.run_id and claimed_at is null;
    continue;
   end if;
   if s.mode='youtube' then
    if not exists(select 1 from public.korlix_live_studio_connections where id=s.connection_id and owner_id=s.owner_id and state='connected'
     and revision=s.connection_revision and channel_id=s.channel_id) then
     update public.korlix_live_studio_shows set state='failed',error='Reconnect and confirm this channel before starting another show.',updated_at=t,version=version+1 where id=s.id;
     update public.korlix_live_studio_runs set released_at=t where id=s.run_id and claimed_at is null;
     continue;
    end if;
    if exists(select 1 from public.korlix_live_studio_shows where channel_id=s.channel_id and worker_token is not null) then continue; end if;
    -- One runtime slot is one worker UUID. Its heartbeat cannot free a running slot.
    select * into w from public.korlix_live_studio_workers where id=worker and mode='youtube' and ready_until>t for update skip locked;
    if not found then return '{}'; end if;
    -- Account deletion cascades shows/runs. Do not strand an otherwise idle slot.
    if w.run_id is not null and not exists(select 1 from public.korlix_live_studio_shows where run_id=w.run_id and worker_id=worker and worker_token is not null) then
     update public.korlix_live_studio_workers set run_id=null,updated_at=t where id=worker;
     w.run_id:=null;
    end if;
    if w.run_id is not null or exists(select 1 from public.korlix_live_studio_shows where worker_id=worker and worker_token is not null) then return '{}'; end if;
    update public.korlix_live_studio_workers set run_id=s.run_id,updated_at=t where id=worker;
   end if;
   update public.korlix_live_studio_runs set claimed_at=t,worker_id=case when s.mode='youtube' then worker else null end where id=s.run_id;
   update public.korlix_live_studio_shows set state='preparing',worker_token=token,worker_id=case when mode='youtube' then worker else null end,lease_until=t+interval '45 seconds',
    started_at=t,deadline_at=t+make_interval(secs=>case when mode='rehearsal' then 300 else (config->>'durationSeconds')::int+180 end),version=version+1,updated_at=t where id=s.id returning * into s;
   return to_jsonb(s);
  end loop;
  return '{}';
 end if;
 if p_actor is null then raise exception 'Sign in to use Live Studio.' using errcode='42501'; end if;
 -- All customer mutations, including allowance creation, acquire this before rows.
 if p_action not in ('list','workspace','get','events') then perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811)); end if;
 if p_action='grant_developer' then
  if not korlix_live_private.account_available(p_actor) then raise exception 'Live Studio access is unavailable.' using errcode='42501'; end if;
  insert into public.korlix_live_studio_grants(owner_id,label,enabled,period_start,period_end,max_daily_starts,rehearsal_limit,broadcast_seconds_limit,generation_limit)
   values(p_actor,'Developer pilot',true,t,t+interval '30 days',3,30,5400,5000) on conflict(owner_id) do nothing;
  return '{"recorded":true}';
 end if;
 if p_action='workspace' then
  select * into g from public.korlix_live_studio_grants where owner_id=p_actor;
  select count(*) into daily_starts from public.korlix_live_studio_runs where owner_id=p_actor and created_at>t-interval '24 hours';
  select coalesce(sum(rehearsal_reserved),0),coalesce(sum(broadcast_seconds_reserved),0),coalesce(sum(generations_reserved),0)
   into reserved_rehearsals,reserved_seconds,reserved_generations from public.korlix_live_studio_runs
   where owner_id=p_actor and grant_id=g.id and grant_period_start=g.period_start and grant_period_end=g.period_end and released_at is null;
  is_enabled:=coalesce(g.enabled and g.period_start<=t and g.period_end>t and korlix_live_private.account_available(p_actor),false);
  return jsonb_build_object('entitlement',jsonb_build_object('enabled',is_enabled,'label',coalesce(g.label,'Access not enabled'),'periodStart',g.period_start,'periodEnd',g.period_end,
   'maxDailyStarts',coalesce(g.max_daily_starts,0),'rehearsalLimit',coalesce(g.rehearsal_limit,0),'broadcastSecondsLimit',coalesce(g.broadcast_seconds_limit,0),'generationLimit',coalesce(g.generation_limit,0)),
   'usage',jsonb_build_object('dailyStarts',daily_starts,'dailyStartsRemaining',greatest(0,coalesce(g.max_daily_starts,0)-daily_starts),
    'rehearsalsUsed',reserved_rehearsals,'rehearsalsRemaining',greatest(0,coalesce(g.rehearsal_limit,0)-reserved_rehearsals),
    'broadcastSecondsReserved',reserved_seconds,'broadcastSecondsRemaining',greatest(0,coalesce(g.broadcast_seconds_limit,0)-reserved_seconds),
    'generationsReserved',reserved_generations,'generationsRemaining',greatest(0,coalesce(g.generation_limit,0)-reserved_generations)),
   'workerReady',exists(select 1 from public.korlix_live_studio_workers where ready_until>t));
 end if;
 if p_action='list' then
  return jsonb_build_object('shows',coalesce((select jsonb_agg(to_jsonb(q)) from
   (select * from public.korlix_live_studio_shows where owner_id=p_actor order by created_at desc limit 30) q),'[]'::jsonb));
 end if;
 if p_action='save' then
  select * into s from public.korlix_live_studio_shows where id=p_id for update;
  if found then
   if s.owner_id<>p_actor then raise exception 'Show not found.' using errcode='P0002'; end if;
   if s.config<>p_data->'config' then raise exception 'This save already has different settings. Save a new show.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if (select count(*) from public.korlix_live_studio_shows where owner_id=p_actor)>=30 then raise exception 'Remove an old show before saving another.' using errcode='54000'; end if;
  if p_id is null or p_data->'config' is null or jsonb_typeof(p_data->'config')<>'object' then raise exception 'Show settings required.' using errcode='22023'; end if;
  insert into public.korlix_live_studio_shows(id,owner_id,config) values(p_id,p_actor,p_data->'config') returning * into s;
  return to_jsonb(s);
 end if;
 -- Read-only operations never take locks needed by an encoder heartbeat.
 if p_action in ('get','events') then
  select * into s from public.korlix_live_studio_shows where id=p_id and owner_id=p_actor;
 else
  select * into s from public.korlix_live_studio_shows where id=p_id and owner_id=p_actor for update;
 end if;
 if not found then raise exception 'Show not found.' using errcode='P0002'; end if;
 if p_action='get' then return to_jsonb(s); end if;
 if p_action='events' then
  return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e)) from
   (select id,kind,data,created_at from public.korlix_live_studio_events where show_id=p_id and run_id=s.run_id order by created_at desc limit 250) e),'[]'::jsonb));
 end if;
 if p_action='delete' then
  if s.state in ('queued','preparing','live','paused') or s.worker_token is not null then raise exception 'End the show and wait for its worker to stop before removing it.' using errcode='40001'; end if;
  delete from public.korlix_live_studio_shows where id=p_id;return '{"deleted":true}';
 end if;
 if p_action='queue' then
  select * into existing from public.korlix_live_studio_events where id=(p_data->>'requestId')::uuid;
  if found then
   if existing.show_id<>p_id or existing.kind<>'queue' or existing.data<>p_data then raise exception 'This request has different settings.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if s.state in ('queued','preparing','live','paused') or s.worker_token is not null then raise exception 'This show is already running or scheduled.' using errcode='40001'; end if;
  if p_data->>'requestId' is null or p_data->>'mode' is null or p_data->>'mode' not in ('rehearsal','youtube') then raise exception 'Invalid show mode.' using errcode='22023'; end if;
  select * into g from public.korlix_live_studio_grants where owner_id=p_actor for update;
  if not found or not g.enabled or g.period_start>t or g.period_end<=t or not korlix_live_private.account_available(p_actor) then raise exception 'Live Studio access is not enabled for this account.' using errcode='42501'; end if;
  due_at:=coalesce((p_data->>'scheduledAt')::timestamptz,t);
  if due_at>=g.period_end or due_at>t+interval '7 days' or due_at<t-interval '1 minute' then raise exception 'Choose a start time within your current allowance period and the next seven days.' using errcode='22023'; end if;
  select count(*) into daily_starts from public.korlix_live_studio_runs where owner_id=p_actor and created_at>t-interval '24 hours';
  if daily_starts>=g.max_daily_starts then raise exception 'Your daily Live Studio start allowance was reached.' using errcode='54000'; end if;
  wanted_rehearsals:=case when p_data->>'mode'='rehearsal' then 1 else 0 end;
  wanted_seconds:=case when p_data->>'mode'='youtube' then (s.config->>'durationSeconds')::integer else 0 end;
  wanted_generations:=case when p_data->>'mode'='rehearsal' then 10 else 200 end;
  if wanted_seconds is null or (p_data->>'mode'='youtube' and wanted_seconds not in (900,1800)) then raise exception 'Choose a supported show duration.' using errcode='22023'; end if;
  select coalesce(sum(rehearsal_reserved),0),coalesce(sum(broadcast_seconds_reserved),0),coalesce(sum(generations_reserved),0)
   into reserved_rehearsals,reserved_seconds,reserved_generations from public.korlix_live_studio_runs
   where owner_id=p_actor and grant_id=g.id and grant_period_start=g.period_start and grant_period_end=g.period_end and released_at is null;
  if reserved_rehearsals+wanted_rehearsals>g.rehearsal_limit or reserved_seconds+wanted_seconds>g.broadcast_seconds_limit or reserved_generations+wanted_generations>g.generation_limit then raise exception 'This show exceeds your remaining Live Studio allowance.' using errcode='54000'; end if;
  if p_data->>'mode'='youtube' then
   if p_data->>'connectionId' is null or p_data->>'connectionRevision' is null then raise exception 'Confirm the connected YouTube channel before starting this show.' using errcode='22023'; end if;
   select id,revision,channel_id into connection_uuid,connection_revision_value,channel_value from public.korlix_live_studio_connections where owner_id=p_actor and state='connected' and id=(p_data->>'connectionId')::uuid and revision=(p_data->>'connectionRevision')::integer for update;
   if not found then raise exception 'The channel connection changed. Review and confirm the channel again.' using errcode='40001'; end if;
  end if;
  update public.korlix_live_studio_shows set state='queued',queued_at=t,mode=p_data->>'mode',scheduled_at=(p_data->>'scheduledAt')::timestamptz,
   run_id=(p_data->>'requestId')::uuid,started_at=null,deadline_at=null,worker_token=null,lease_until=null,worker_id=null,
   connection_id=case when p_data->>'mode'='youtube' then connection_uuid else null end,
   connection_revision=case when p_data->>'mode'='youtube' then connection_revision_value else null end,
   channel_id=case when p_data->>'mode'='youtube' then channel_value else null end,
   command='{"action":"play","seq":0}',progress='{}',error=null,watch_url=null,has_replay=replay_path is not null,updated_at=t,version=version+1
   where id=p_id returning * into s;
  insert into public.korlix_live_studio_events(id,show_id,run_id,kind,data) values(s.run_id,p_id,s.run_id,'queue',p_data);
  insert into public.korlix_live_studio_runs(id,owner_id,grant_id,grant_period_start,grant_period_end,show_id,mode,rehearsal_reserved,broadcast_seconds_reserved,generations_reserved,connection_id,connection_revision,channel_id)
   values(s.run_id,p_actor,g.id,g.period_start,g.period_end,p_id,s.mode,wanted_rehearsals,wanted_seconds,wanted_generations,s.connection_id,s.connection_revision,s.channel_id);
  return to_jsonb(s);
 end if;
 if p_action='control' then
  action:=p_data->>'action';
  if action is null or action not in ('pause','resume','skip','end','question') then raise exception 'Invalid studio control.' using errcode='22023'; end if;
  select * into existing from public.korlix_live_studio_events where id=(p_data->>'requestId')::uuid;
  if found then
   if existing.show_id<>p_id or existing.run_id<>s.run_id or existing.kind<>'control' or existing.data<>p_data then raise exception 'Refresh this request.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if s.state not in ('queued','preparing','live','paused') then raise exception 'This show is not running.' using errcode='40001'; end if;
  if s.state in ('queued','preparing') and action<>'end' then raise exception 'Wait for the show to start.' using errcode='40001'; end if;
  if action='question' and (length(p_data->>'text') not between 1 and 400 or p_data->>'text' is null) then raise exception 'Use a question of up to 400 characters.' using errcode='22023'; end if;
  if action<>'end' and (select count(*) from public.korlix_live_studio_events where show_id=p_id and run_id=s.run_id and kind='control')>=100 then raise exception 'The show control limit was reached. You can still end the show.' using errcode='54000'; end if;
  if action='end' and s.worker_token is null then update public.korlix_live_studio_runs set released_at=t where id=s.run_id and claimed_at is null; end if;
  update public.korlix_live_studio_shows set command=jsonb_build_object('action',action,'seq',coalesce((s.command->>'seq')::int,0)+1,'text',p_data->>'text'),
   state=case when action='end' then 'cancelled' when action='pause' then 'paused' when action='resume' then 'live' else state end,
   updated_at=t,version=version+1 where id=p_id returning * into s;
  insert into public.korlix_live_studio_events(id,show_id,run_id,kind,data) values((p_data->>'requestId')::uuid,p_id,s.run_id,'control',p_data);
  return to_jsonb(s);
 end if;
 if s.worker_token is null or s.worker_token is distinct from (p_data->>'token')::uuid or s.lease_until<t or s.deadline_at<t
  or s.state not in ('preparing','live','paused','cancelled') then raise exception 'The broadcast worker lease expired.' using errcode='40001'; end if;
 -- A fenced worker must observe an explicit stop even after access or channel
 -- revocation. Observation does not renew the lease or authorize provider work.
 if p_action='heartbeat' and s.state='cancelled' then return to_jsonb(s); end if;
 -- Cleanup remains possible after revocation. Spending and extending the lease do not.
 if p_action<>'finish' then
  select * into r from public.korlix_live_studio_runs where id=s.run_id;
  select * into g from public.korlix_live_studio_grants where id=r.grant_id and owner_id=p_actor;
  if g.id is null or not g.enabled or g.period_start>t or g.period_end<=t or r.grant_period_start is distinct from g.period_start or r.grant_period_end is distinct from g.period_end
   or not korlix_live_private.account_available(p_actor) then raise exception 'Live Studio access expired or was revoked.' using errcode='42501'; end if;
  if s.mode='youtube' and not exists(select 1 from public.korlix_live_studio_connections where id=s.connection_id and owner_id=p_actor and state='connected' and revision=s.connection_revision and channel_id=s.channel_id) then raise exception 'The channel connection changed. This show must stop.' using errcode='42501'; end if;
 end if;
 if p_action='heartbeat' then
  update public.korlix_live_studio_shows set lease_until=t+interval '45 seconds' where id=p_id returning * into s;
  return to_jsonb(s);
 end if;
 if p_action='event' then
  if s.state='cancelled' then raise exception 'The show was ended.' using errcode='40001'; end if;
  select * into existing from public.korlix_live_studio_events where id=(p_data->>'eventId')::uuid;
  if found then
   if existing.show_id<>p_id or existing.run_id<>s.run_id or existing.kind<>p_data->>'kind' or existing.data is distinct from p_data->'data' then raise exception 'This event has different settings.' using errcode='40001'; end if;
   return '{"recorded":true}';
  end if;
  if p_data->>'kind'='dispatch' then
   update public.korlix_live_studio_runs set generations_dispatched=generations_dispatched+1 where id=s.run_id and generations_dispatched<generations_reserved;
   if not found then raise exception 'The show generation limit was reached.' using errcode='54000'; end if;
  end if;
  insert into public.korlix_live_studio_events(id,show_id,run_id,kind,data) values((p_data->>'eventId')::uuid,p_id,s.run_id,p_data->>'kind',p_data->'data');
  return '{"recorded":true}';
 end if;
 if p_action='progress' then
  if s.state='cancelled' then return to_jsonb(s); end if;
  update public.korlix_live_studio_shows set progress=p_data->'progress',
   state=case when state='preparing' and p_data->>'started'='true' then 'live' else state end,
   watch_url=coalesce(p_data->>'watchUrl',watch_url),updated_at=t,version=version+1 where id=p_id returning * into s;
  return to_jsonb(s);
 end if;
 if p_action='finish' then
  update public.korlix_live_studio_workers set run_id=null,updated_at=t where id=s.worker_id and run_id=s.run_id;
  update public.korlix_live_studio_shows set state=case when state='cancelled' then state when p_data->>'error' is not null then 'failed' else 'completed' end,
   error=left(coalesce(p_data->>'error',error),300),replay_path=coalesce(p_data->>'replayPath',replay_path),has_replay=coalesce(p_data->>'replayPath',replay_path) is not null,
   worker_token=null,lease_until=null,worker_id=null,updated_at=t,version=version+1 where id=p_id returning * into s;
  return to_jsonb(s);
 end if;
 raise exception 'Unknown studio operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_live_studio_v2(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_v2(uuid,text,uuid,jsonb) to service_role;
-- Deploy overlap must not permit the old singleton API to bypass customer grants.
create or replace function public.korlix_live_studio_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language sql security invoker set search_path=public,pg_temp as $$
 select public.korlix_live_studio_v2(p_actor,p_action,p_id,p_data)
$$;
revoke all on function public.korlix_live_studio_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_v1(uuid,text,uuid,jsonb) to service_role;
