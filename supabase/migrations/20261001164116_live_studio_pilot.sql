-- Server-only pilot. Ownership is derived from verified auth in the API;
-- clients cannot execute the RPC, inspect worker leases, or write run state.
create table public.korlix_live_studio_shows (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 config jsonb not null, state text not null default 'draft' check(state in ('draft','queued','preparing','live','paused','completed','failed','cancelled')),
 mode text check(mode in ('rehearsal','youtube')), version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 scheduled_at timestamptz, started_at timestamptz, deadline_at timestamptz,
 run_id uuid, worker_token uuid, lease_until timestamptz,
 command jsonb not null default '{"action":"play","seq":0}', progress jsonb not null default '{}',
 error text, watch_url text, replay_path text, has_replay boolean not null default false,
 check(jsonb_typeof(config)='object' and octet_length(config::text)<=4000),
 check(octet_length(progress::text)<=12000)
);
create index korlix_live_studio_owner on public.korlix_live_studio_shows(owner_id,created_at desc);
create index korlix_live_studio_due on public.korlix_live_studio_shows(scheduled_at,created_at) where state='queued';
-- One rendering/broadcast job globally in the initial pilot, including schedules.
create unique index korlix_live_studio_single_run on public.korlix_live_studio_shows((true)) where state in ('queued','preparing','live','paused');
create table public.korlix_live_studio_events (
 id uuid primary key, show_id uuid not null references public.korlix_live_studio_shows(id) on delete cascade,
 run_id uuid, kind text not null, data jsonb not null default '{}', created_at timestamptz not null default now(),
 check(octet_length(data::text)<=18000)
);
create index korlix_live_studio_events_show on public.korlix_live_studio_events(show_id,created_at);
alter table public.korlix_live_studio_shows enable row level security;
alter table public.korlix_live_studio_events enable row level security;
revoke all on public.korlix_live_studio_shows,public.korlix_live_studio_events from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_live_studio_shows,public.korlix_live_studio_events to service_role;
create table public.korlix_live_studio_runs (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
create index korlix_live_studio_runs_owner on public.korlix_live_studio_runs(owner_id,created_at desc);
create table public.korlix_live_studio_workers (
 mode text primary key check(mode='youtube'),owner_id uuid not null references auth.users(id) on delete cascade,
 ready_until timestamptz not null
);
alter table public.korlix_live_studio_runs enable row level security;
alter table public.korlix_live_studio_workers enable row level security;
revoke all on public.korlix_live_studio_runs,public.korlix_live_studio_workers from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_live_studio_runs,public.korlix_live_studio_workers to service_role;

create function public.korlix_live_studio_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.korlix_live_studio_shows; existing public.korlix_live_studio_events;
 t timestamptz:=clock_timestamp(); token uuid; action text; v integer;
begin
 if octet_length(p_data::text)>20000 then raise exception 'Studio request is too large.' using errcode='22023'; end if;
 if p_action='announce' then
  if p_actor is null then raise exception 'Worker owner required.' using errcode='42501'; end if;
  insert into public.korlix_live_studio_workers(mode,owner_id,ready_until) values('youtube',p_actor,t+interval '35 seconds')
   on conflict(mode) do update set owner_id=excluded.owner_id,ready_until=excluded.ready_until;
  return '{"ready":true}';
 end if;
 if p_action='worker_status' then
  return jsonb_build_object('youtubeReady',exists(select 1 from public.korlix_live_studio_workers where owner_id=p_actor and ready_until>t));
 end if;
 if p_action in ('claim','sweep') then
  update public.korlix_live_studio_shows set state='failed',error='The scheduled worker was unavailable. Choose a new start time.',updated_at=t,version=version+1
   where state='queued' and coalesce(scheduled_at,created_at)<t-interval '15 minutes';
  update public.korlix_live_studio_shows set state='failed',error='The broadcast worker stopped. Review the show before starting a new run.',
   worker_token=null,lease_until=null,updated_at=t,version=version+1
   where state in ('preparing','live','paused') and (lease_until<t or deadline_at<t);
  if p_action='sweep' then return '{}'; end if;
  token:=(p_data->>'token')::uuid;
  if token is null or p_data->>'mode' not in ('rehearsal','youtube') then raise exception 'Invalid worker.' using errcode='22023'; end if;
  select * into s from public.korlix_live_studio_shows where state='queued' and mode=p_data->>'mode'
   and coalesce(scheduled_at,created_at)<=t and (p_actor is null or owner_id=p_actor)
   order by created_at for update skip locked limit 1;
  if not found then return '{}'; end if;
  update public.korlix_live_studio_shows set state='preparing',worker_token=token,lease_until=t+interval '45 seconds',
   started_at=t,deadline_at=t+make_interval(secs=>case when mode='rehearsal' then 300 else (config->>'durationSeconds')::int+180 end),
   version=version+1,updated_at=t where id=s.id returning * into s;
  return to_jsonb(s);
 end if;
 if p_actor is null then raise exception 'Sign in to use Live Studio.' using errcode='42501'; end if;
 if p_action='list' then
  return jsonb_build_object('shows',coalesce((select jsonb_agg(to_jsonb(q)) from
   (select * from public.korlix_live_studio_shows where owner_id=p_actor order by created_at desc limit 30) q),'[]'::jsonb));
 end if;
 if p_action='save' then
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
  select * into s from public.korlix_live_studio_shows where id=p_id for update;
  if found then
   if s.owner_id<>p_actor then raise exception 'Show not found.' using errcode='P0002'; end if;
   if s.config<>p_data->'config' then raise exception 'This save already has different settings. Save a new show.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if (select count(*) from public.korlix_live_studio_shows where owner_id=p_actor)>=30 then raise exception 'Remove an old show before saving another.' using errcode='54000'; end if;
  if p_data->'config' is null then raise exception 'Show settings required.' using errcode='22023'; end if;
  insert into public.korlix_live_studio_shows(id,owner_id,config) values(p_id,p_actor,p_data->'config') returning * into s;
  return to_jsonb(s);
 end if;
 select * into s from public.korlix_live_studio_shows where id=p_id and owner_id=p_actor for update;
 if not found then raise exception 'Show not found.' using errcode='P0002'; end if;
 if p_action='get' then return to_jsonb(s); end if;
 if p_action='events' then
  return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e)) from
   (select id,kind,data,created_at from public.korlix_live_studio_events where show_id=p_id and run_id=s.run_id order by created_at desc limit 250) e),'[]'::jsonb));
 end if;
 if p_action='delete' then
  if s.state in ('queued','preparing','live','paused') then raise exception 'End the show before removing it.' using errcode='40001'; end if;
  delete from public.korlix_live_studio_shows where id=p_id;return '{"deleted":true}';
 end if;
 if p_action='queue' then
  select * into existing from public.korlix_live_studio_events where id=(p_data->>'requestId')::uuid;
  if found then
   if existing.show_id<>p_id or existing.kind<>'queue' or existing.data<>p_data then raise exception 'This request has different settings.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if s.state in ('queued','preparing','live','paused') then raise exception 'This show is already running or scheduled.' using errcode='40001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
  if (select count(*) from public.korlix_live_studio_runs where owner_id=p_actor and created_at>t-interval '24 hours')>=3 then raise exception 'The pilot allows three starts in 24 hours.' using errcode='54000'; end if;
  if p_data->>'mode' not in ('rehearsal','youtube') then raise exception 'Invalid show mode.' using errcode='22023'; end if;
  update public.korlix_live_studio_shows set state='queued',mode=p_data->>'mode',scheduled_at=(p_data->>'scheduledAt')::timestamptz,
   run_id=(p_data->>'requestId')::uuid,started_at=null,deadline_at=null,worker_token=null,lease_until=null,
   command='{"action":"play","seq":0}',progress='{}',error=null,watch_url=null,has_replay=false,updated_at=t,version=version+1
   where id=p_id returning * into s;
  insert into public.korlix_live_studio_events(id,show_id,run_id,kind,data) values(s.run_id,p_id,s.run_id,'queue',p_data);
  insert into public.korlix_live_studio_runs(id,owner_id) values(s.run_id,p_actor);
  return to_jsonb(s);
 end if;
 if p_action='control' then
  action:=p_data->>'action';
  if action not in ('pause','resume','skip','end','question') then raise exception 'Invalid studio control.' using errcode='22023'; end if;
  select * into existing from public.korlix_live_studio_events where id=(p_data->>'requestId')::uuid;
  if found then
   if existing.show_id<>p_id or existing.run_id<>s.run_id or existing.kind<>'control' or existing.data<>p_data then raise exception 'Refresh this request.' using errcode='40001'; end if;
   return to_jsonb(s);
  end if;
  if s.state not in ('queued','preparing','live','paused') then raise exception 'This show is not running.' using errcode='40001'; end if;
  if s.state in ('queued','preparing') and action<>'end' then raise exception 'Wait for the show to start.' using errcode='40001'; end if;
  if action='question' and (length(p_data->>'text') not between 1 and 400 or p_data->>'text' is null) then raise exception 'Use a question of up to 400 characters.' using errcode='22023'; end if;
  if action<>'end' and (select count(*) from public.korlix_live_studio_events where show_id=p_id and run_id=s.run_id and kind='control')>=100 then raise exception 'The show control limit was reached. You can still end the show.' using errcode='54000'; end if;
  update public.korlix_live_studio_shows set command=jsonb_build_object('action',action,'seq',coalesce((s.command->>'seq')::int,0)+1,'text',p_data->>'text'),
   state=case when action='end' then 'cancelled' when action='pause' then 'paused' when action='resume' then 'live' else state end,
   updated_at=t,version=version+1 where id=p_id returning * into s;
  insert into public.korlix_live_studio_events(id,show_id,run_id,kind,data) values((p_data->>'requestId')::uuid,p_id,s.run_id,'control',p_data);
  return to_jsonb(s);
 end if;
 -- Fencing: an expired or superseded worker can never write or spend again.
 if s.worker_token is null or s.worker_token is distinct from (p_data->>'token')::uuid or s.lease_until<t or s.deadline_at<t
  or s.state not in ('preparing','live','paused','cancelled') then raise exception 'The broadcast worker lease expired.' using errcode='40001'; end if;
 if p_action='heartbeat' then
  update public.korlix_live_studio_shows set lease_until=t+interval '45 seconds' where id=p_id;
  return to_jsonb(s);
 end if;
 if p_action='event' then
  if s.state='cancelled' then raise exception 'The show was ended.' using errcode='40001'; end if;
  if p_data->>'kind'='dispatch' and (select count(*) from public.korlix_live_studio_events where show_id=p_id and run_id=s.run_id and kind='dispatch')>=200 then
   raise exception 'The show generation limit was reached.' using errcode='54000'; end if;
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
  update public.korlix_live_studio_shows set state=case when state='cancelled' then state when p_data->>'error' is not null then 'failed' else 'completed' end,
   error=left(p_data->>'error',300),replay_path=coalesce(p_data->>'replayPath',replay_path),has_replay=coalesce(p_data->>'replayPath',replay_path) is not null,
   worker_token=null,lease_until=null,updated_at=t,version=version+1 where id=p_id returning * into s;
  return to_jsonb(s);
 end if;
 raise exception 'Unknown studio operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_live_studio_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_v1(uuid,text,uuid,jsonb) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('korlix-live-studio','korlix-live-studio',false,52428800,array['video/mp4']) on conflict(id) do nothing;
