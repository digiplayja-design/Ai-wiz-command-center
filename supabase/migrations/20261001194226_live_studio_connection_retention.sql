-- Data lifecycle for customer YouTube authorizations. Applied migrations are immutable.
alter table public.korlix_live_studio_connections
 alter column channel_id drop not null, alter column channel_title drop not null,
 add column last_verified_at timestamptz,
 add column next_check_at timestamptz not null default now(),
 add column maintenance_lease uuid,
 add column maintenance_until timestamptz,
 add column maintenance_failures integer not null default 0 check(maintenance_failures between 0 and 24),
 add constraint korlix_live_studio_connected_identity check(state<>'connected' or (channel_id is not null and channel_title is not null));
update public.korlix_live_studio_connections set last_verified_at=connected_at,next_check_at=least(connected_at+interval '1 day',now()) where state='connected';
create index korlix_live_studio_maintenance_due on public.korlix_live_studio_connections(next_check_at) where state='connected';
alter table public.korlix_live_studio_shows add column channel_fence text,add column api_data_purged_at timestamptz;
alter table public.korlix_live_studio_runs add column api_data_purged_at timestamptz;
create index korlix_live_studio_runs_connection on public.korlix_live_studio_runs(owner_id,connection_id) where mode='youtube';
create index korlix_live_studio_runs_retention on public.korlix_live_studio_runs(created_at) where mode='youtube' and api_data_purged_at is null;
-- Raw channel IDs can be erased immediately, while an irreversible, temporary
-- execution fence keeps a second encoder off that channel until cleanup/expiry.
update public.korlix_live_studio_shows set channel_fence=encode(sha256(convert_to(channel_id,'UTF8')),'hex') where worker_token is not null and channel_id is not null;
drop index public.korlix_live_studio_channel_execution;
create unique index korlix_live_studio_channel_execution on public.korlix_live_studio_shows(channel_fence) where worker_token is not null and channel_fence is not null;

create function korlix_live_private.youtube_show_guard()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if TG_OP='UPDATE' and OLD.api_data_purged_at is not null and NEW.run_id is not distinct from OLD.run_id then
  NEW.channel_id:=null;NEW.watch_url:=null;NEW.progress:='{}';NEW.api_data_purged_at:=OLD.api_data_purged_at;
  NEW.error:=OLD.error;NEW.replay_path:=OLD.replay_path;NEW.has_replay:=OLD.has_replay;
 end if;
 if NEW.worker_token is null or NEW.mode is distinct from 'youtube' then NEW.channel_fence:=null;
 elsif NEW.channel_id is not null then NEW.channel_fence:=encode(sha256(convert_to(NEW.channel_id,'UTF8')),'hex');
 end if;
 return NEW;
end $$;
revoke all on function korlix_live_private.youtube_show_guard() from public,anon,authenticated;
grant execute on function korlix_live_private.youtube_show_guard() to service_role;
create trigger korlix_live_studio_youtube_show_guard before insert or update on public.korlix_live_studio_shows for each row execute function korlix_live_private.youtube_show_guard();

create function korlix_live_private.youtube_event_guard()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.korlix_live_studio_runs where id=NEW.run_id and api_data_purged_at is not null) then
  raise exception 'YouTube data for this run was removed.' using errcode='40001';
 end if;
 return NEW;
end $$;
revoke all on function korlix_live_private.youtube_event_guard() from public,anon,authenticated;
grant execute on function korlix_live_private.youtube_event_guard() to service_role;
create trigger korlix_live_studio_youtube_event_guard before insert or update on public.korlix_live_studio_events for each row execute function korlix_live_private.youtube_event_guard();

-- p_before expires historical run data independently of channel metadata refresh.
-- Internal IDs, paid-call receipts and usage reservations remain for accounting.
create function korlix_live_private.purge_youtube_data(p_actor uuid,p_connection uuid default null,p_before timestamptz default null)
returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare r public.korlix_live_studio_runs; t timestamptz:=clock_timestamp(); n integer:=0;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
 for r in select * from public.korlix_live_studio_runs where owner_id=p_actor and mode='youtube'
  and (p_connection is null or connection_id=p_connection) and (p_before is null or created_at<=p_before)
  and (api_data_purged_at is null or channel_id is not null) order by id for update
 loop
  update public.korlix_live_studio_shows set
   state=case when state in ('queued','preparing','live','paused') then 'cancelled' else state end,
   command=case when state in ('queued','preparing','live','paused') then jsonb_build_object('action','end','seq',coalesce((command->>'seq')::int,0)+1) else command end,
   error=case when worker_token is not null or state in ('queued','preparing','live','paused') then 'YouTube connection data was removed. A stop was requested for this show; check YouTube Studio if the broadcast is still visible.' else null end,
   channel_id=null,watch_url=null,progress='{}',api_data_purged_at=t,updated_at=t,version=version+1
   where owner_id=p_actor and run_id=r.id;
  -- Queue request fields and provider accounting are generated by KORLIX, not YouTube.
  -- Preserve them verbatim so idempotency and cost audit receipts remain valid.
  delete from public.korlix_live_studio_events where run_id=r.id and kind not in ('queue','dispatch','receipt');
  update public.korlix_live_studio_runs set channel_id=null,api_data_purged_at=t,
   released_at=case when claimed_at is null then coalesce(released_at,t) else released_at end where id=r.id;
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function korlix_live_private.purge_youtube_data(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function korlix_live_private.purge_youtube_data(uuid,uuid,timestamptz) to service_role;

create function korlix_live_private.purge_youtube_connection(p_actor uuid,p_connection uuid,p_state text default 'reconnect_required',p_attempts boolean default true)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare t timestamptz:=clock_timestamp();
begin
 if p_state not in ('reconnect_required','disconnected') then raise exception 'Invalid disconnected state.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
 perform korlix_live_private.purge_youtube_data(p_actor,p_connection);
 update public.korlix_live_studio_connections set state=p_state,channel_id=null,channel_title=null,sealed_grant=null,
  revision=revision+1,refresh_lease=null,refresh_until=null,maintenance_lease=null,maintenance_until=null,
  last_verified_at=null,updated_at=t where id=p_connection and owner_id=p_actor;
 if p_attempts then
  update public.korlix_live_studio_oauth set state=case when state='confirmed' then state else 'failed' end,
   channel_id=null,channel_title=null,sealed_secrets=null,sealed_grant=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor;
 end if;
end $$;
revoke all on function korlix_live_private.purge_youtube_connection(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function korlix_live_private.purge_youtube_connection(uuid,uuid,text,boolean) to service_role;

create function public.korlix_live_studio_maintenance_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare c public.korlix_live_studio_connections; candidate record; target record;
 t timestamptz:=clock_timestamp(); touched integer:=0; failures integer;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>40000 then raise exception 'Invalid maintenance request.' using errcode='22023'; end if;
 if p_action='retention_sweep' then
  -- At most 100 owners per tick; stale metadata remains eligible until purged.
  for target in select owner_id from (
   select owner_id from public.korlix_live_studio_connections where
    (state='connected' and (last_verified_at is null or last_verified_at<=t-interval '28 days' or not korlix_live_private.account_available(owner_id)))
    or (state<>'connected' and (channel_id is not null or channel_title is not null or sealed_grant is not null))
   union select owner_id from public.korlix_live_studio_oauth where created_at<t-interval '1 day' or
    (expires_at<=t and (channel_id is not null or sealed_grant is not null or sealed_secrets is not null or ticket_hash is not null or state_hash is not null or browser_hash is not null))
   union select owner_id from public.korlix_live_studio_runs where mode='youtube' and created_at<=t-interval '28 days' and api_data_purged_at is null
  ) q order by owner_id limit 100
  loop
   if not pg_try_advisory_xact_lock(hashtextextended(target.owner_id::text,9811)) then continue; end if;
   for c in select * from public.korlix_live_studio_connections where owner_id=target.owner_id and
    ((state='connected' and (last_verified_at is null or last_verified_at<=t-interval '28 days' or not korlix_live_private.account_available(owner_id)))
     or (state<>'connected' and (channel_id is not null or channel_title is not null or sealed_grant is not null)))
   loop
    perform korlix_live_private.purge_youtube_connection(c.owner_id,c.id,case when c.state='disconnected' then 'disconnected' else 'reconnect_required' end,true);
   end loop;
   perform korlix_live_private.purge_youtube_data(target.owner_id,null,t-interval '28 days');
   update public.korlix_live_studio_oauth set state=case when state='confirmed' then state else 'failed' end,
    channel_id=null,channel_title=null,sealed_secrets=null,sealed_grant=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=target.owner_id and expires_at<=t;
   -- Retain expired attempt rows for a day so cleanup cannot reset the 10/hour cap.
   delete from public.korlix_live_studio_oauth where owner_id=target.owner_id and created_at<t-interval '1 day';
   touched:=touched+1;
  end loop;
  return jsonb_build_object('ownersProcessed',touched);
 elsif p_action='maintenance_claim' then
  if p_actor is not null or p_id is not null or p_data->>'lease' is null or coalesce(p_data->>'config_hash','')!~'^[a-f0-9]{64}$' then raise exception 'Invalid maintenance worker.' using errcode='22023'; end if;
  for candidate in select id,owner_id from public.korlix_live_studio_connections where state='connected'
   and config_hash=p_data->>'config_hash' and next_check_at<=t and last_verified_at>t-interval '28 days'
   and coalesce(maintenance_until,'-infinity'::timestamptz)<=t and coalesce(refresh_until,'-infinity'::timestamptz)<=t
   order by next_check_at,id limit 100
  loop
   if not pg_try_advisory_xact_lock(hashtextextended(candidate.owner_id::text,9811)) then continue; end if;
   -- Owner lock excludes a simultaneous encoder claim; a stopped encoder keeps its fence.
   if exists(select 1 from public.korlix_live_studio_shows where owner_id=candidate.owner_id and worker_token is not null) then continue; end if;
   if not korlix_live_private.account_available(candidate.owner_id) then continue; end if;
   select * into c from public.korlix_live_studio_connections where id=candidate.id and state='connected'
    and config_hash=p_data->>'config_hash' and next_check_at<=t and last_verified_at>t-interval '28 days'
    and coalesce(maintenance_until,'-infinity'::timestamptz)<=t and coalesce(refresh_until,'-infinity'::timestamptz)<=t for update skip locked;
   if not found then continue; end if;
   update public.korlix_live_studio_connections set maintenance_lease=(p_data->>'lease')::uuid,maintenance_until=t+interval '60 seconds' where id=c.id returning * into c;
   return to_jsonb(c);
  end loop;
  return '{}';
 elsif p_action in ('maintenance_store','maintenance_fail') then
  if p_actor is null or p_id is null then raise exception 'Maintenance owner required.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
  select * into c from public.korlix_live_studio_connections where id=p_id and owner_id=p_actor for update;
  if not found or c.state<>'connected' or c.revision is distinct from (p_data->>'revision')::integer or c.config_hash is distinct from p_data->>'config_hash'
   or c.maintenance_lease is null or c.maintenance_lease is distinct from (p_data->>'lease')::uuid or c.maintenance_until<=t
   or (not (p_action='maintenance_fail' and coalesce(p_data->>'revoked','false')='true') and
    (c.last_verified_at is null or c.last_verified_at<=t-interval '28 days' or not korlix_live_private.account_available(p_actor)))
   or exists(select 1 from public.korlix_live_studio_shows where owner_id=p_actor and worker_token is not null)
  then raise exception 'The connection maintenance lease expired or access changed.' using errcode='40001'; end if;
  if p_action='maintenance_store' then
   if c.channel_id is distinct from p_data->>'channel_id' or p_data->>'channel_title' is null or length(p_data->>'channel_title')>150 or coalesce(length(p_data->>'sealed_grant'),0)=0 then raise exception 'The refreshed channel could not be verified.' using errcode='22023'; end if;
   update public.korlix_live_studio_connections set sealed_grant=p_data->>'sealed_grant',channel_title=p_data->>'channel_title',last_verified_at=t,
    next_check_at=t+interval '1 day',maintenance_failures=0,maintenance_lease=null,maintenance_until=null,updated_at=t where id=p_id;
  elsif p_data->>'revoked'='true' then
   perform korlix_live_private.purge_youtube_connection(p_actor,p_id,'reconnect_required',true);
  else
   failures:=least(c.maintenance_failures+1,24);
   update public.korlix_live_studio_connections set sealed_grant=coalesce(nullif(p_data->>'sealed_grant',''),sealed_grant),
    maintenance_failures=failures,next_check_at=t+make_interval(hours=>least(24,power(2,least(failures-1,5))::integer)),
    maintenance_lease=null,maintenance_until=null,updated_at=t where id=p_id;
  end if;
  return '{"ok":true}';
 end if;
 raise exception 'Unknown connection maintenance operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_live_studio_maintenance_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_maintenance_v1(uuid,text,uuid,jsonb) to service_role;

create or replace function public.korlix_live_studio_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
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
    if exists(select 1 from public.korlix_live_studio_connections where id=s.connection_id and (maintenance_until>t or refresh_until>t)) then continue; end if;
    if not exists(select 1 from public.korlix_live_studio_connections where id=s.connection_id and owner_id=s.owner_id and state='connected' and last_verified_at>t-interval '28 days'
     and revision=s.connection_revision and channel_id=s.channel_id) then
     update public.korlix_live_studio_shows set state='failed',error='Reconnect and confirm this channel before starting another show.',updated_at=t,version=version+1 where id=s.id;
     update public.korlix_live_studio_runs set released_at=t where id=s.run_id and claimed_at is null;
     continue;
    end if;
    if exists(select 1 from public.korlix_live_studio_shows where channel_fence=encode(sha256(convert_to(s.channel_id,'UTF8')),'hex') and worker_token is not null) then continue; end if;
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
   select id,revision,channel_id into connection_uuid,connection_revision_value,channel_value from public.korlix_live_studio_connections where owner_id=p_actor and state='connected' and last_verified_at>t-interval '28 days' and id=(p_data->>'connectionId')::uuid and revision=(p_data->>'connectionRevision')::integer for update;
   if not found then raise exception 'The channel connection changed. Review and confirm the channel again.' using errcode='40001'; end if;
  end if;
  update public.korlix_live_studio_shows set state='queued',queued_at=t,api_data_purged_at=null,mode=p_data->>'mode',scheduled_at=(p_data->>'scheduledAt')::timestamptz,
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
  if s.mode='youtube' and not exists(select 1 from public.korlix_live_studio_connections where id=s.connection_id and owner_id=p_actor and state='connected' and last_verified_at>t-interval '28 days' and revision=s.connection_revision and channel_id=s.channel_id) then raise exception 'The channel connection changed. This show must stop.' using errcode='42501'; end if;
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

create or replace function public.korlix_live_studio_connections_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_live_studio_oauth; c public.korlix_live_studio_connections; s public.korlix_live_studio_shows;
 t timestamptz:=clock_timestamp(); result jsonb; selected_owner uuid; old_connection record;
begin
 if octet_length(p_data::text)>40000 then raise exception 'Connection request is too large.' using errcode='22023'; end if;
 if p_action in ('maintenance_claim','maintenance_store','maintenance_fail','retention_sweep') then return public.korlix_live_studio_maintenance_v1(p_actor,p_action,p_id,p_data); end if;
 -- Public callback operations authenticate exclusively with single-use hashed secrets.
 if p_action='launch' then
  select * into a from public.korlix_live_studio_oauth where ticket_hash=p_data->>'ticket_hash' and state='created' and expires_at>t for update;
  if not found or coalesce(p_data->>'browser_hash','')!~'^[a-f0-9]{64}$' then raise exception 'This connection link expired. Start again.' using errcode='40001'; end if;
  update public.korlix_live_studio_oauth set state='launched',ticket_hash=null,browser_hash=p_data->>'browser_hash' where id=a.id;
  return to_jsonb(a);
 elsif p_action='claim' then
  select * into a from public.korlix_live_studio_oauth where state_hash=p_data->>'state_hash' and browser_hash=p_data->>'browser_hash' and state='launched' and expires_at>t for update;
  if not found then raise exception 'This connection request expired or belongs to another browser. Start again.' using errcode='40001'; end if;
  update public.korlix_live_studio_oauth set state='exchanging',state_hash=null,browser_hash=null,sealed_secrets=null where id=a.id;
  return to_jsonb(a);
 elsif p_action in ('complete','fail') then
  if p_actor is not null then perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811)); end if;
  select * into a from public.korlix_live_studio_oauth where id=p_id and expires_at>t
   and ((state='exchanging' and (p_actor is null or owner_id=p_actor)) or (p_action='fail' and state='ready' and owner_id=p_actor)) for update;
  if not found then raise exception 'This connection request expired. Start again.' using errcode='40001'; end if;
  if p_action='fail' then
   update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,channel_id=null,channel_title=null,ticket_hash=null,state_hash=null,browser_hash=null where id=p_id;return '{}';
  end if;
  if a.config_hash is distinct from p_data->>'config_hash' or coalesce(p_data->>'channel_id','')!~'^UC[A-Za-z0-9_-]{22}$'
   or coalesce(length(p_data->>'sealed_grant'),0)=0 or p_data->>'channel_title' is null then raise exception 'The channel connection could not be verified.' using errcode='22023'; end if;
  update public.korlix_live_studio_oauth set state='ready',sealed_grant=p_data->>'sealed_grant',channel_id=p_data->>'channel_id',channel_title=p_data->>'channel_title',
   sealed_secrets=null,ticket_hash=null,state_hash=null,browser_hash=null where id=p_id;
  return '{"ready":true}';
 end if;
 if p_actor is null then raise exception 'Sign in to manage YouTube connections.' using errcode='42501'; end if;
 -- Same lock order as the show RPC: owner lock, show row, then connection row.
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,9811));
 if p_action='list' then
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,channel_id=null,channel_title=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and expires_at<t and state<>'confirmed';
  delete from public.korlix_live_studio_oauth where owner_id=p_actor and created_at<t-interval '1 day';
  select * into c from public.korlix_live_studio_connections where owner_id=p_actor and state<>'disconnected';
  if c.state='connected' and (c.last_verified_at is null or c.last_verified_at<=t-interval '28 days' or not korlix_live_private.account_available(p_actor)) then
   perform korlix_live_private.purge_youtube_connection(p_actor,c.id,'reconnect_required',true);
   select * into c from public.korlix_live_studio_connections where id=c.id;
  end if;
  perform korlix_live_private.purge_youtube_data(p_actor,null,t-interval '28 days');
  return jsonb_build_object('connection',case when c.id is null then null else to_jsonb(c)-'sealed_grant'-'refresh_lease'-'refresh_until' end,
   'pending',coalesce((select jsonb_agg(jsonb_build_object('id',id,'channel_id',channel_id,'channel_title',channel_title,'expires_at',expires_at,'config_hash',config_hash))
   from public.korlix_live_studio_oauth where owner_id=p_actor and state='ready' and expires_at>t),'[]'::jsonb));
 elsif p_action='start' then
  if (select count(*) from public.korlix_live_studio_oauth where owner_id=p_actor and created_at>t-interval '1 hour')>=10 then raise exception 'Too many connection attempts. Try again later.' using errcode='54000'; end if;
  -- A new attempt invalidates older unfinished attempts, preventing stale callbacks from being confirmed.
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,channel_id=null,channel_title=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and state in ('created','launched','exchanging','ready');
  if coalesce(p_data->>'ticket_hash','')!~'^[a-f0-9]{64}$' or coalesce(p_data->>'state_hash','')!~'^[a-f0-9]{64}$' or coalesce(length(p_data->>'sealed_secrets'),0)=0 then raise exception 'Connection secrets required.' using errcode='22023'; end if;
  insert into public.korlix_live_studio_oauth(id,owner_id,ticket_hash,state_hash,sealed_secrets,config_hash,created_at,expires_at)
   values(p_id,p_actor,p_data->>'ticket_hash',p_data->>'state_hash',p_data->>'sealed_secrets',p_data->>'config_hash',t,t+interval '10 minutes');
  return '{"created":true}';
 elsif p_action in ('ready','confirm') then
  select * into a from public.korlix_live_studio_oauth where owner_id=p_actor and id=p_id and state in ('ready','confirmed') and expires_at>t for update;
  if not found then raise exception 'Channel confirmation not found or expired. Connect again.' using errcode='P0002'; end if;
  if p_action='ready' then return to_jsonb(a); end if;
  if a.config_hash is distinct from p_data->>'config_hash' then raise exception 'Connection settings changed. Start again.' using errcode='40001'; end if;
  if a.state='confirmed' then return '{"connected":true}'; end if;
  -- Serialize assignments of the same external channel across different owners.
  perform pg_advisory_xact_lock(hashtextextended(a.channel_id,9813));
  if exists(select 1 from public.korlix_live_studio_connections where channel_id=a.channel_id and owner_id<>p_actor and state<>'disconnected') then
   raise exception 'This channel is already connected to another KORLIX account.' using errcode='40001';
  end if;
  -- Retain leases for claimed shows until their process stops; release only unclaimed reservations.
  update public.korlix_live_studio_runs set released_at=t where owner_id=p_actor and claimed_at is null and released_at is null and id in
   (select run_id from public.korlix_live_studio_shows where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused'));
  update public.korlix_live_studio_shows set state='cancelled',error='YouTube connection changed. Start a new show after the worker stops.',
   command=jsonb_build_object('action','end','seq',coalesce((command->>'seq')::int,0)+1),version=version+1,updated_at=t
   where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused');
  for old_connection in select id from public.korlix_live_studio_connections where owner_id=p_actor and state<>'disconnected' loop
   perform korlix_live_private.purge_youtube_connection(p_actor,old_connection.id,'disconnected',false);
  end loop;
  insert into public.korlix_live_studio_connections(id,owner_id,channel_id,channel_title,state,sealed_grant,config_hash,connected_at,updated_at,last_verified_at,next_check_at)
   values(a.id,p_actor,a.channel_id,a.channel_title,'connected',a.sealed_grant,a.config_hash,t,t,t,t+interval '1 day');
  update public.korlix_live_studio_oauth set state='confirmed',sealed_grant=null,sealed_secrets=null,channel_id=null,channel_title=null,ticket_hash=null,state_hash=null,browser_hash=null where id=p_id;
  return '{"connected":true}';
 elsif p_action='disconnect' then
  update public.korlix_live_studio_oauth set channel_id=null,channel_title=null,sealed_grant=null,sealed_secrets=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor;
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,channel_id=null,channel_title=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and state in ('created','launched','exchanging','ready');
  update public.korlix_live_studio_runs set released_at=t where owner_id=p_actor and claimed_at is null and released_at is null and id in
   (select run_id from public.korlix_live_studio_shows where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused'));
  update public.korlix_live_studio_shows set state='cancelled',error='YouTube was disconnected. A stop was requested for this show.',
   command=jsonb_build_object('action','end','seq',coalesce((command->>'seq')::int,0)+1),version=version+1,updated_at=t
   where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused');
  select * into c from public.korlix_live_studio_connections where owner_id=p_actor and state<>'disconnected' for update;
  perform korlix_live_private.purge_youtube_data(p_actor);
  for old_connection in select id from public.korlix_live_studio_connections where owner_id=p_actor and
   (state<>'disconnected' or channel_id is not null or channel_title is not null or sealed_grant is not null) loop
   perform korlix_live_private.purge_youtube_connection(p_actor,old_connection.id,'disconnected',true);
  end loop;
  if c.id is null then return '{}'; end if;
  -- Only trusted backend receives the previous encrypted grant, for best-effort provider revocation.
  return to_jsonb(c);
 end if;
 if p_action like 'token_%' then
  select * into s from public.korlix_live_studio_shows where id=(p_data->>'show_id')::uuid and owner_id=p_actor for update;
  if not found or s.mode<>'youtube' or s.worker_token is null or s.worker_token is distinct from (p_data->>'worker_token')::uuid
   or s.state not in ('preparing','live','paused') or s.lease_until is null or s.lease_until<=t or s.deadline_at is null or s.deadline_at<=t
   or s.connection_id is distinct from p_id or s.connection_revision is distinct from (p_data->>'revision')::int or s.channel_id is distinct from p_data->>'channel_id'
  then raise exception 'The show no longer has access to this YouTube connection.' using errcode='40001'; end if;
  if p_action<>'token_fail' and (not korlix_live_private.account_available(p_actor) or not exists(
   select 1 from public.korlix_live_studio_runs r join public.korlix_live_studio_grants g on g.id=r.grant_id and g.owner_id=p_actor
   where r.id=s.run_id and r.owner_id=p_actor and r.claimed_at is not null and r.released_at is null
    and g.enabled and g.period_start<=t and g.period_end>t
    and r.grant_period_start=g.period_start and r.grant_period_end=g.period_end
  )) then raise exception 'Live Studio access expired or was revoked.' using errcode='42501'; end if;
  select * into c from public.korlix_live_studio_connections where id=p_id and owner_id=p_actor for update;
  if not found or c.state<>'connected' or (p_action<>'token_fail' and (c.last_verified_at is null or c.last_verified_at<=t-interval '28 days')) or c.revision is distinct from s.connection_revision or c.channel_id is distinct from s.channel_id
   or c.config_hash is distinct from p_data->>'config_hash' then raise exception 'Reconnect YouTube before starting another show.' using errcode='40001'; end if;
  if p_action='token_claim' then
   if c.refresh_until>t or c.maintenance_until>t or p_data->>'lease' is null then raise exception 'YouTube token access is busy. Try again shortly.' using errcode='40001'; end if;
   update public.korlix_live_studio_connections set refresh_lease=(p_data->>'lease')::uuid,refresh_until=t+interval '25 seconds' where id=p_id;
   return to_jsonb(c);
  end if;
  if c.refresh_lease is null or c.refresh_lease is distinct from (p_data->>'lease')::uuid or c.refresh_until<=t then raise exception 'The YouTube token lease expired.' using errcode='40001'; end if;
  if p_action='token_store' then
   if coalesce(length(p_data->>'sealed_grant'),0)=0 then raise exception 'Encrypted grant required.' using errcode='22023'; end if;
   update public.korlix_live_studio_connections set sealed_grant=p_data->>'sealed_grant',updated_at=t where id=p_id;
  elsif p_action='token_check' then null;
  elsif p_action='token_release' then
   update public.korlix_live_studio_connections set refresh_lease=null,refresh_until=null where id=p_id;
  elsif p_action='token_fail' then
   update public.korlix_live_studio_shows set state='cancelled',error='YouTube access expired. Reconnect your channel.',
    command=jsonb_build_object('action','end','seq',coalesce((command->>'seq')::int,0)+1),version=version+1,updated_at=t where id=s.id;
   perform korlix_live_private.purge_youtube_connection(p_actor,p_id,'reconnect_required',true);
  else raise exception 'Unknown connection operation.' using errcode='22023'; end if;
  return '{"ok":true}';
 end if;
 raise exception 'Unknown connection operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_live_studio_connections_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_connections_v1(uuid,text,uuid,jsonb) to service_role;
