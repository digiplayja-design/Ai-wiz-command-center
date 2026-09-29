-- Private free-play tables. No wallet, wagers, purchases or cash-out paths.
create table public.korlix_domino_tables (
 id uuid primary key, host uuid not null references public.korlix_social_profiles(id) on delete cascade,
 name text not null check(char_length(name) between 1 and 60), capacity int not null check(capacity in (2,4)),
 revision int not null default 0 check(revision>=0),
 state jsonb not null default '{"phase":"waiting","ready":{},"round":0}'::jsonb check(jsonb_typeof(state)='object' and octet_length(state::text)<60000),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '4 hours'
);
create index korlix_domino_tables_host on public.korlix_domino_tables(host);
create index korlix_domino_tables_expiry on public.korlix_domino_tables(expires_at);
create table public.korlix_domino_members (
 table_id uuid not null references public.korlix_domino_tables(id) on delete cascade,
 profile_id uuid not null references public.korlix_social_profiles(id) on delete cascade,
 status text not null check(status in ('invited','joined','left')), seat int check(seat between 0 and 3),
 last_seen timestamptz, media_seen timestamptz, media_session uuid, device uuid,
 microphone boolean not null default false, camera boolean not null default false,
 primary key(table_id,profile_id), check((status='joined')=(seat is not null))
);
create unique index korlix_domino_seats on public.korlix_domino_members(table_id,seat) where status='joined';
create index korlix_domino_members_profile on public.korlix_domino_members(profile_id,status,table_id);
create table public.korlix_domino_signals (
 id uuid primary key, seq bigint generated always as identity unique,
 table_id uuid not null references public.korlix_domino_tables(id) on delete cascade,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 recipient uuid not null references public.korlix_social_profiles(id) on delete cascade,
 from_session uuid not null,to_session uuid not null,
 kind text not null check(kind in ('offer','answer','candidate')),payload jsonb not null check(octet_length(payload::text)<150000),
 created_at timestamptz not null default now(),check(sender<>recipient)
);
create index korlix_domino_signals_inbox on public.korlix_domino_signals(table_id,recipient,to_session,seq);
create index korlix_domino_signals_sender on public.korlix_domino_signals(sender);
create index korlix_domino_signals_expiry on public.korlix_domino_signals(created_at);
create unique index korlix_domino_descriptions on public.korlix_domino_signals(table_id,from_session,to_session,kind) where kind in ('offer','answer');
alter table public.korlix_domino_tables enable row level security;
alter table public.korlix_domino_members enable row level security;
alter table public.korlix_domino_signals enable row level security;
revoke all on public.korlix_domino_tables,public.korlix_domino_members,public.korlix_domino_signals from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_domino_tables,public.korlix_domino_members,public.korlix_domino_signals to service_role;
revoke all on sequence public.korlix_domino_signals_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_domino_signals_seq_seq to service_role;

-- Only the authenticated backend can call this invoker RPC. p_actor is never
-- taken from a browser's body. The Node engine alone supplies commit state.
create function public.korlix_domino_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; t korlix_domino_tables; m korlix_domino_members; other korlix_domino_members;
 target uuid;room_id uuid;session_id uuid;items jsonb;signals jsonb:='[]';players jsonb;next_seat int;signal_payload jsonb;signal_kind text;signal_id uuid;changed int;
begin
 select * into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'Create an active Social profile to play.' using errcode='42501';end if;
 if p_action='list' then
  perform korlix_social_limit(p_actor,'domino-list',30,60);
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select jsonb_build_object('id',r.id,'name',r.name,'capacity',r.capacity,'host',korlix_social_card(p),'status',d.status,'phase',r.state->>'phase','expiresAt',r.expires_at,
    'seated',(select count(*) from korlix_domino_members u where u.table_id=r.id and u.status='joined')) card
   from korlix_domino_members d join korlix_domino_tables r on r.id=d.table_id join korlix_social_profiles p on p.id=r.host
   where d.profile_id=me.id and d.status in ('invited','joined') and r.expires_at>now() and r.state->>'phase'<>'closed' and not p.suspended and not korlix_social_blocked(me.id,p.id)
   order by r.created_at desc limit 30
  )x;return jsonb_build_object('items',items,'me',me.id);
 end if;
 room_id:=(p_data->>'id')::uuid;
 if room_id is null then raise exception 'Choose a table.';end if;
 if p_action='create' then
  perform pg_advisory_xact_lock(hashtextextended('domino-create:'||me.id::text,0));
  select * into t from korlix_domino_tables where id=room_id;
  if t.id is not null then
   if t.host<>me.id then raise exception 'This table ID is already in use.' using errcode='42501';end if;
  else
   if coalesce(p_data->>'capacity','') not in ('2','4') or char_length(trim(coalesce(p_data->>'name',''))) not between 1 and 60 then raise exception 'Choose a table name and two or four seats.';end if;
   if (select count(*) from korlix_domino_tables where host=me.id and expires_at>now() and state->>'phase'<>'closed')>=3 then raise exception 'Close an existing table before creating another.' using errcode='54000';end if;
   perform korlix_social_limit(p_actor,'domino-create',12,3600);
   insert into korlix_domino_tables(id,host,name,capacity)values(room_id,me.id,trim(p_data->>'name'),(p_data->>'capacity')::int) returning * into t;
   insert into korlix_domino_members(table_id,profile_id,status,seat,last_seen)values(t.id,me.id,'joined',0,now());
   delete from korlix_domino_tables where id in(select id from korlix_domino_tables where expires_at<now()-interval '7 days' limit 30);
  end if;
 end if;
 -- Lock this table only for the short transaction. Video media never traverses Postgres.
 select * into t from korlix_domino_tables where id=room_id for update;
 select * into m from korlix_domino_members where table_id=room_id and profile_id=me.id;
 if t.id is null or m.profile_id is null or m.status='left' then raise exception 'This private table is unavailable. Ask its host for an invitation.' using errcode='42501';end if;
 if t.expires_at<=now() or exists(select 1 from korlix_domino_members d join korlix_social_profiles p on p.id=d.profile_id where d.table_id=t.id and d.status='joined' and (p.suspended or korlix_social_blocked(me.id,d.profile_id))) then
  update korlix_domino_tables set state=jsonb_build_object('phase','closed','last','This table is no longer available.'),revision=revision+1 where id=t.id returning * into t;
  update korlix_domino_members set media_session=null,camera=false,microphone=false where table_id=t.id;
 end if;
 if p_action='decline' then
  if m.status<>'invited' then raise exception 'Only a pending invitation can be declined.';end if;
  update korlix_domino_members set status='left' where table_id=t.id and profile_id=me.id;return jsonb_build_object('ok',true);
 end if;
 if p_action='leave' then
  if m.status='joined' and (t.host=me.id or t.state->>'phase'<>'waiting') then
   update korlix_domino_tables set state=jsonb_build_object('phase','closed','last',me.name||' left the table.'),revision=revision+1 where id=t.id;
   update korlix_domino_members set media_session=null,camera=false,microphone=false where table_id=t.id;
   delete from korlix_domino_signals where table_id=t.id;
  else
   update korlix_domino_tables set revision=revision+1,state=jsonb_set(state,'{ready}',coalesce(state->'ready','{}')-me.id::text) where id=t.id;
  end if;
  update korlix_domino_members set status='left',seat=null,media_session=null,microphone=false,camera=false where table_id=t.id and profile_id=me.id;
  return jsonb_build_object('ok',true);
 end if;
 if t.state->>'phase'='closed' then
  return jsonb_build_object('id',t.id,'host',t.host,'capacity',t.capacity,'name',t.name,'revision',t.revision,'state',t.state,'me',me.id,'players','[]'::jsonb);
 end if;
 if p_action='join' then
  if m.status='invited' then
   if not exists(select 1 from korlix_social_connections c where c.state='accepted' and least(c.requester,c.recipient)=least(me.id,t.host) and greatest(c.requester,c.recipient)=greatest(me.id,t.host)) then raise exception 'Reconnect with the host before joining this table.' using errcode='42501';end if;
   if t.state->>'phase'<>'waiting' then raise exception 'This round has already started.' using errcode='40001';end if;
   select s into next_seat from generate_series(0,t.capacity-1)s where not exists(select 1 from korlix_domino_members d where d.table_id=t.id and d.status='joined' and d.seat=s) order by s limit 1;
   if next_seat is null then raise exception 'This table is full.' using errcode='40001';end if;
   update korlix_domino_members set status='joined',seat=next_seat,last_seen=now() where table_id=t.id and profile_id=me.id returning * into m;
   update korlix_domino_tables set revision=revision+1 where id=t.id returning * into t;
  end if;
 elsif m.status<>'joined' then raise exception 'Accept the table invitation before playing.' using errcode='42501';
 end if;
 if p_action='invite' then
  if me.id<>t.host or t.state->>'phase'<>'waiting' then raise exception 'Only the host can invite players before dealing.' using errcode='42501';end if;
  target:=(p_data->>'peer')::uuid;
  if target=me.id or not exists(select 1 from korlix_social_connections c join korlix_social_profiles p on p.id=target where c.state='accepted' and least(c.requester,c.recipient)=least(me.id,target) and greatest(c.requester,c.recipient)=greatest(me.id,target) and not p.suspended) then raise exception 'Invite an accepted Social connection.' using errcode='42501';end if;
  if exists(select 1 from korlix_domino_members d where d.table_id=t.id and d.status='joined' and korlix_social_blocked(d.profile_id,target)) then raise exception 'This connection cannot join this table.' using errcode='42501';end if;
  if (select count(*) from korlix_domino_members where table_id=t.id and status<>'left')>=12 then raise exception 'This table already has enough invitations.' using errcode='54000';end if;
  perform korlix_social_limit(p_actor,'domino-invite',40,3600);
  insert into korlix_domino_members(table_id,profile_id,status)values(t.id,target,'invited')on conflict(table_id,profile_id)do update set status='invited' where korlix_domino_members.status='left';
  get diagnostics changed=row_count;
  if changed>0 then
   insert into korlix_social_messages(id,sender,recipient,body)values(gen_random_uuid(),me.id,target,'Join my free-play domino table: '||t.name||'. Open KORLIX Social → Dominoes to accept. Live video is optional.');
  end if;
 elsif p_action='commit' then
  if t.revision is distinct from (p_data->>'revision')::int then raise exception 'The table changed. Refresh before playing.' using errcode='40001';end if;
  if jsonb_typeof(p_data->'state') is distinct from 'object' then raise exception 'Invalid game state.';end if;
  update korlix_domino_tables set state=p_data->'state',revision=revision+1 where id=t.id returning * into t;
 elsif p_action='media' then
  session_id:=(p_data->>'session')::uuid;
  if session_id is null or jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'Choose your camera and microphone settings.';end if;
  if p_data->'enabled'='true'::jsonb then
   if p_data->'start' is distinct from 'true'::jsonb and (m.media_session is distinct from session_id or m.device is distinct from nullif(p_data->>'device','')::uuid) then raise exception 'Your video session changed. Join video again.' using errcode='40001';end if;
   if nullif(p_data->>'device','') is null or jsonb_typeof(p_data->'camera') is distinct from 'boolean' or jsonb_typeof(p_data->'microphone') is distinct from 'boolean' then raise exception 'Choose your camera and microphone settings.';end if;
   update korlix_domino_members set media_session=session_id,device=(p_data->>'device')::uuid,media_seen=now(),camera=(p_data->>'camera')::boolean,microphone=(p_data->>'microphone')::boolean where table_id=t.id and profile_id=me.id;
  else
   update korlix_domino_members set media_session=null,media_seen=null,camera=false,microphone=false where table_id=t.id and profile_id=me.id and media_session=session_id;
  end if;
 elsif p_action='signal' then
  target:=(p_data->>'peer')::uuid;session_id:=(p_data->>'session')::uuid;signal_id:=(p_data->>'signalId')::uuid;signal_payload:=p_data->'payload';signal_kind:=p_data->>'kind';
  select * into other from korlix_domino_members where table_id=t.id and profile_id=target and status='joined';
  if target=me.id or other.profile_id is null or m.media_session is distinct from session_id or other.media_session is distinct from (p_data->>'targetSession')::uuid or m.media_seen<now()-interval '60 seconds' or other.media_seen<now()-interval '60 seconds' or m.media_session is null or other.media_session is null then raise exception 'Video session changed. Reconnect video at the table.' using errcode='40001';end if;
  if signal_id is null or signal_kind not in ('offer','answer','candidate') or jsonb_typeof(signal_payload) is distinct from 'object' then raise exception 'Invalid video signal.';end if;
  if signal_kind in ('offer','answer') and (jsonb_typeof(signal_payload->'sdp') is distinct from 'string' or char_length(signal_payload->>'sdp') not between 1 and 100000) then raise exception 'Invalid video description.';end if;
  if signal_kind='candidate' and (jsonb_typeof(signal_payload->'candidate') is distinct from 'string' or char_length(signal_payload->>'candidate') not between 1 and 4000) then raise exception 'Invalid video candidate.';end if;
  perform korlix_social_limit(p_actor,'domino-signal',240,60);
  if exists(select 1 from korlix_domino_signals where id=signal_id and (sender<>me.id or table_id<>t.id or from_session<>session_id or to_session<>other.media_session or kind<>signal_kind or korlix_domino_signals.payload<>signal_payload)) then raise exception 'Signal ID is already in use.' using errcode='42501';end if;
  insert into korlix_domino_signals(id,table_id,sender,recipient,from_session,to_session,kind,payload)values(signal_id,t.id,me.id,target,session_id,other.media_session,signal_kind,signal_payload)on conflict do nothing;
  return jsonb_build_object('ok',true);
 elsif p_action='sync' then
  update korlix_domino_members set last_seen=now(),media_seen=case when media_session=nullif(p_data->>'session','')::uuid and device=nullif(p_data->>'device','')::uuid then now() else media_seen end where table_id=t.id and profile_id=me.id returning * into m;
  if m.media_session=nullif(p_data->>'session','')::uuid and m.device=nullif(p_data->>'device','')::uuid then
   select coalesce(jsonb_agg(x.item order by x.seq),'[]') into signals from (
    select s.seq,jsonb_build_object('seq',s.seq,'sender',s.sender,'session',s.from_session,'targetSession',s.to_session,'kind',s.kind,'payload',s.payload) item
    from korlix_domino_signals s join korlix_domino_members d on d.table_id=s.table_id and d.profile_id=s.sender and d.status='joined' and d.media_session=s.from_session
    where s.table_id=t.id and s.recipient=me.id and s.to_session=m.media_session and s.seq>greatest(0,coalesce((p_data->>'after')::bigint,0)) and s.created_at>now()-interval '2 minutes' order by s.seq limit 150
   )x;
  end if;
  delete from korlix_domino_signals where table_id=t.id and created_at<now()-interval '2 minutes';
 elsif p_action not in ('create','join','snapshot') then raise exception 'Unknown table operation.';end if;
 select coalesce(jsonb_agg(x.card order by x.seat),'[]') into players from (
  select d.seat,korlix_social_card(p)||jsonb_build_object('state',d.status,'seat',d.seat,'online',coalesce(d.last_seen>now()-interval '90 seconds',false),'mediaSession',case when d.media_seen>now()-interval '60 seconds' then d.media_session else null end,'camera',d.camera,'microphone',d.microphone) card
  from korlix_domino_members d join korlix_social_profiles p on p.id=d.profile_id where d.table_id=t.id and d.status in ('joined','invited')
 )x;
 return jsonb_build_object('id',t.id,'host',t.host,'capacity',t.capacity,'name',t.name,'revision',t.revision,'state',t.state,'me',me.id,'players',players,'signals',signals,'expiresAt',t.expires_at);
end $$;
revoke all on function public.korlix_domino_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_domino_v1(uuid,text,jsonb) to service_role;
