-- Customer-owned YouTube grants stay encrypted and service-only. OAuth attempts are
-- launch-ticket, browser-cookie, state and PKCE bound, then confirmed by the owner.
create table public.korlix_live_studio_connections (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 channel_id text not null check(channel_id ~ '^UC[A-Za-z0-9_-]{22}$'), channel_title text not null check(length(channel_title)<=150),
 state text not null check(state in ('connected','reconnect_required','disconnected')), revision integer not null default 1 check(revision>0),
 sealed_grant text, config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
 refresh_lease uuid, refresh_until timestamptz,
 connected_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(sealed_grant is null or octet_length(sealed_grant)<=30000),
 check(state<>'connected' or sealed_grant is not null)
);
create unique index korlix_live_studio_connection_owner on public.korlix_live_studio_connections(owner_id) where state<>'disconnected';
create unique index korlix_live_studio_connection_channel on public.korlix_live_studio_connections(channel_id) where state<>'disconnected';
create index korlix_live_studio_connection_history on public.korlix_live_studio_connections(owner_id,updated_at desc);
create table public.korlix_live_studio_oauth (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'created' check(state in ('created','launched','exchanging','ready','confirmed','failed')),
 ticket_hash text unique, state_hash text unique, browser_hash text,
 sealed_secrets text, sealed_grant text, channel_id text, channel_title text,
 config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes',
 check(ticket_hash is null or ticket_hash ~ '^[a-f0-9]{64}$'),
 check(state_hash is null or state_hash ~ '^[a-f0-9]{64}$'),
 check(browser_hash is null or browser_hash ~ '^[a-f0-9]{64}$'),
 check(sealed_secrets is null or octet_length(sealed_secrets)<=4000),
 check(sealed_grant is null or octet_length(sealed_grant)<=30000),
 check(channel_id is null or channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
 check(channel_title is null or length(channel_title)<=150)
);
create index korlix_live_studio_oauth_owner on public.korlix_live_studio_oauth(owner_id,created_at desc);
create index korlix_live_studio_oauth_expiry on public.korlix_live_studio_oauth(expires_at);
alter table public.korlix_live_studio_connections enable row level security;
alter table public.korlix_live_studio_oauth enable row level security;
revoke all on public.korlix_live_studio_connections,public.korlix_live_studio_oauth from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_live_studio_connections,public.korlix_live_studio_oauth to service_role;

create function public.korlix_live_studio_connections_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_live_studio_oauth; c public.korlix_live_studio_connections; s public.korlix_live_studio_shows;
 t timestamptz:=clock_timestamp(); result jsonb; selected_owner uuid;
begin
 if octet_length(p_data::text)>40000 then raise exception 'Connection request is too large.' using errcode='22023'; end if;
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
  select * into a from public.korlix_live_studio_oauth where id=p_id and state='exchanging' and expires_at>t for update;
  if not found then raise exception 'This connection request expired. Start again.' using errcode='40001'; end if;
  if p_action='fail' then
   update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null where id=p_id;return '{}';
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
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and expires_at<t and state<>'confirmed';
  delete from public.korlix_live_studio_oauth where owner_id=p_actor and created_at<t-interval '1 day';
  select * into c from public.korlix_live_studio_connections where owner_id=p_actor and state<>'disconnected';
  return jsonb_build_object('connection',case when c.id is null then null else to_jsonb(c)-'sealed_grant'-'refresh_lease'-'refresh_until' end,
   'pending',coalesce((select jsonb_agg(jsonb_build_object('id',id,'channel_id',channel_id,'channel_title',channel_title,'expires_at',expires_at,'config_hash',config_hash))
   from public.korlix_live_studio_oauth where owner_id=p_actor and state='ready' and expires_at>t),'[]'::jsonb));
 elsif p_action='start' then
  if (select count(*) from public.korlix_live_studio_oauth where owner_id=p_actor and created_at>t-interval '1 hour')>=10 then raise exception 'Too many connection attempts. Try again later.' using errcode='54000'; end if;
  -- A new attempt invalidates older unfinished attempts, preventing stale callbacks from being confirmed.
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and state in ('created','launched','exchanging','ready');
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
  update public.korlix_live_studio_connections set state='disconnected',sealed_grant=null,revision=revision+1,refresh_lease=null,refresh_until=null,updated_at=t where owner_id=p_actor and state<>'disconnected';
  insert into public.korlix_live_studio_connections(id,owner_id,channel_id,channel_title,state,sealed_grant,config_hash,connected_at,updated_at)
   values(a.id,p_actor,a.channel_id,a.channel_title,'connected',a.sealed_grant,a.config_hash,t,t);
  update public.korlix_live_studio_oauth set state='confirmed',sealed_grant=null,sealed_secrets=null where id=p_id;
  return '{"connected":true}';
 elsif p_action='disconnect' then
  update public.korlix_live_studio_oauth set state='failed',sealed_secrets=null,sealed_grant=null,ticket_hash=null,state_hash=null,browser_hash=null where owner_id=p_actor and state in ('created','launched','exchanging','ready');
  update public.korlix_live_studio_runs set released_at=t where owner_id=p_actor and claimed_at is null and released_at is null and id in
   (select run_id from public.korlix_live_studio_shows where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused'));
  update public.korlix_live_studio_shows set state='cancelled',error='YouTube was disconnected. This show has been stopped.',
   command=jsonb_build_object('action','end','seq',coalesce((command->>'seq')::int,0)+1),version=version+1,updated_at=t
   where owner_id=p_actor and mode='youtube' and state in ('queued','preparing','live','paused');
  select * into c from public.korlix_live_studio_connections where owner_id=p_actor and state<>'disconnected' for update;
  if not found then return '{}'; end if;
  update public.korlix_live_studio_connections set state='disconnected',sealed_grant=null,revision=revision+1,refresh_lease=null,refresh_until=null,updated_at=t where id=c.id;
  -- Only trusted backend receives the previous encrypted grant, for best-effort provider revocation.
  return to_jsonb(c);
 end if;
 if p_action like 'token_%' then
  select * into s from public.korlix_live_studio_shows where id=(p_data->>'show_id')::uuid and owner_id=p_actor for update;
  if not found or s.mode<>'youtube' or s.worker_token is null or s.worker_token is distinct from (p_data->>'worker_token')::uuid
   or s.state not in ('preparing','live','paused') or s.lease_until is null or s.lease_until<=t or s.deadline_at is null or s.deadline_at<=t
   or s.connection_id is distinct from p_id or s.connection_revision is distinct from (p_data->>'revision')::int or s.channel_id is distinct from p_data->>'channel_id'
  then raise exception 'The show no longer has access to this YouTube connection.' using errcode='40001'; end if;
  if not korlix_live_private.account_available(p_actor) or not exists(
   select 1 from public.korlix_live_studio_runs r join public.korlix_live_studio_grants g on g.id=r.grant_id and g.owner_id=p_actor
   where r.id=s.run_id and r.owner_id=p_actor and r.claimed_at is not null and r.released_at is null
    and g.enabled and g.period_start<=t and g.period_end>t
    and r.grant_period_start=g.period_start and r.grant_period_end=g.period_end
  ) then raise exception 'Live Studio access expired or was revoked.' using errcode='42501'; end if;
  select * into c from public.korlix_live_studio_connections where id=p_id and owner_id=p_actor for update;
  if not found or c.state<>'connected' or c.revision is distinct from s.connection_revision or c.channel_id is distinct from s.channel_id
   or c.config_hash is distinct from p_data->>'config_hash' then raise exception 'Reconnect YouTube before starting another show.' using errcode='40001'; end if;
  if p_action='token_claim' then
   if c.refresh_until>t or p_data->>'lease' is null then raise exception 'YouTube token access is busy. Try again shortly.' using errcode='40001'; end if;
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
   update public.korlix_live_studio_connections set state='reconnect_required',sealed_grant=null,revision=revision+1,refresh_lease=null,refresh_until=null,updated_at=t where id=p_id;
  else raise exception 'Unknown connection operation.' using errcode='22023'; end if;
  return '{"ok":true}';
 end if;
 raise exception 'Unknown connection operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_live_studio_connections_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_live_studio_connections_v1(uuid,text,uuid,jsonb) to service_role;
