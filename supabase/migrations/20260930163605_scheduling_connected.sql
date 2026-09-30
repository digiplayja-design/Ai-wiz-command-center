-- Calendar connections, teams, payment holds and reviewed AI actions.
create table public.korlix_schedule_teams (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 name text not null check(length(trim(name)) between 1 and 100), revision int not null default 1,
 invite_hash text, invite_expires_at timestamptz, created_at timestamptz not null default now()
);
create index korlix_schedule_teams_owner_idx on public.korlix_schedule_teams(owner_id);
create table public.korlix_schedule_members (
 team_id uuid not null references public.korlix_schedule_teams(id), user_id uuid not null references public.korlix_schedule_profiles(owner_id),
 active boolean not null default true, joined_at timestamptz not null default now(), last_assigned_at timestamptz,
 primary key(team_id,user_id)
);
create index korlix_schedule_members_user_idx on public.korlix_schedule_members(user_id);
alter table public.korlix_schedule_events
 add column routing_mode text not null default 'single' check(routing_mode in ('single','round_robin','collective')),
 add column team_id uuid references public.korlix_schedule_teams(id),
 add column host_ids uuid[] not null default '{}',
 add column price_cents integer not null default 0 check(price_cents=0 or price_cents between 50 and 1000000),
 add column currency text not null default 'usd' check(currency='usd'),
 add column refund_policy text not null default 'Contact your host to request a refund.' check(length(refund_policy) between 1 and 1000),
 add constraint korlix_schedule_events_routing_check check(routing_mode='single' or (team_id is not null and cardinality(host_ids) between 1 and 20 and kind='one_to_one'));
create index korlix_schedule_events_team_idx on public.korlix_schedule_events(team_id);
alter table public.korlix_schedule_bookings drop constraint korlix_schedule_bookings_state_check;
alter table public.korlix_schedule_bookings add constraint korlix_schedule_bookings_state_check check(state in ('confirmed','canceled','completed','no_show','awaiting_payment','payment_failed'));
alter table public.korlix_schedule_bookings add column hold_expires_at timestamptz;
create table public.korlix_schedule_booking_hosts (
 booking_id uuid not null references public.korlix_schedule_bookings(id), host_id uuid not null references public.korlix_schedule_profiles(owner_id),
 primary key(booking_id,host_id)
);
create index korlix_schedule_booking_hosts_host_idx on public.korlix_schedule_booking_hosts(host_id);
insert into public.korlix_schedule_booking_hosts(booking_id,host_id) select id,owner_id from public.korlix_schedule_bookings;
create table public.korlix_schedule_connections (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 provider text not null check(provider in ('google','microsoft','stripe')), remote_id text not null, label text not null,
 sealed_grant text, config_hash text not null, state text not null default 'connected' check(state in ('connected','disconnected','reconnect_required')),
 calendars jsonb not null default '[]', busy_ids text[] not null default '{}', write_id text,
 enabled boolean not null default false, charges_enabled boolean not null default false, livemode boolean,
 revision integer not null default 1, lease_id uuid, lease_until timestamptz, last_sync_at timestamptz, last_error text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(owner_id,provider,remote_id)
);
create index korlix_schedule_connections_owner_idx on public.korlix_schedule_connections(owner_id);
create table public.korlix_schedule_oauth (
 id uuid primary key, owner_id uuid not null references public.korlix_schedule_profiles(owner_id), provider text not null check(provider in ('google','microsoft','stripe')),
 ticket_hash text not null unique, state_hash text not null unique, browser_hash text, sealed_secrets text not null, sealed_grant text, identity jsonb,
 config_hash text not null, status text not null default 'pending' check(status in ('pending','launched','exchanging','ready','finished','failed')),
 expires_at timestamptz not null default now()+interval '10 minutes', created_at timestamptz not null default now()
);
create index korlix_schedule_oauth_owner_idx on public.korlix_schedule_oauth(owner_id);
create table public.korlix_schedule_calendar_windows (
 id uuid primary key default gen_random_uuid(), connection_id uuid not null references public.korlix_schedule_connections(id), revision int not null,
 starts_at timestamptz not null, ends_at timestamptz not null, checked_at timestamptz not null default now(), busy jsonb not null,
 check(ends_at>starts_at and ends_at<=starts_at+interval '17 days')
);
create index korlix_schedule_calendar_windows_lookup_idx on public.korlix_schedule_calendar_windows(connection_id,checked_at desc);
create table public.korlix_schedule_calendar_links (
 id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.korlix_schedule_bookings(id), host_id uuid not null references public.korlix_schedule_profiles(owner_id),
 connection_id uuid not null references public.korlix_schedule_connections(id), calendar_id text not null, provider_event_id text,
 generation integer not null default 0, provider_deleted boolean not null default false, desired_revision int not null, synced_revision int, removed boolean not null default false,
 state text not null default 'pending' check(state in ('pending','sending','synced','failed','uncertain')),
 create_wire jsonb, creation_attempted boolean not null default false, lease_id uuid, lease_until timestamptz,
 attempts integer not null default 0, first_attempt_at timestamptz, next_attempt_at timestamptz not null default now(), last_error text,
 unique(booking_id,host_id,connection_id,calendar_id)
);
create index korlix_schedule_calendar_links_host_idx on public.korlix_schedule_calendar_links(host_id);
create index korlix_schedule_calendar_links_connection_idx on public.korlix_schedule_calendar_links(connection_id);
create index korlix_schedule_calendar_links_queue_idx on public.korlix_schedule_calendar_links(next_attempt_at) where state in ('pending','sending');
create table public.korlix_schedule_payments (
 booking_id uuid primary key references public.korlix_schedule_bookings(id), connection_id uuid not null references public.korlix_schedule_connections(id),
 account_id text not null, livemode boolean not null, amount_cents integer not null, currency text not null check(currency='usd'),
 checkout_closed boolean not null default false, checkout_id text unique, checkout_url text, checkout_wire text, checkout_expires_at timestamptz not null,
 payment_intent_id text, payment_state text not null default 'unpaid' check(payment_state in ('unpaid','paid','paid_unfulfilled','refunded','disputed')),
 refund_state text not null default 'none' check(refund_state in ('none','required','sending','pending','succeeded','failed','uncertain')),
 refund_id text, refund_requested_at timestamptz, refund_reason text, refund_attempts int not null default 0,
 lease_id uuid, lease_until timestamptz, next_check_at timestamptz not null default now(), checked_at timestamptz,
 created_at timestamptz not null default now()
);
create index korlix_schedule_payments_due_idx on public.korlix_schedule_payments(next_check_at) where payment_state='unpaid' or refund_state in ('required','sending','pending');
create index korlix_schedule_payments_connection_idx on public.korlix_schedule_payments(connection_id);
create index korlix_schedule_payments_intent_idx on public.korlix_schedule_payments(payment_intent_id);
create table public.korlix_schedule_payment_receipts (
 provider_event_id text primary key, account_id text not null, kind text not null, received_at timestamptz not null default now()
);
create table public.korlix_schedule_ai_plans (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 request_id uuid not null, prompt text not null check(length(prompt)<=3000), plan jsonb,
 state text not null default 'generating' check(state in ('generating','review','applied','failed','expired')),
 profile_revision int not null, result jsonb, expires_at timestamptz not null default now()+interval '15 minutes', created_at timestamptz not null default now(), unique(owner_id,request_id)
);
create index korlix_schedule_ai_plans_owner_idx on public.korlix_schedule_ai_plans(owner_id,created_at);

create function public.korlix_schedule_live_booking_v2(b public.korlix_schedule_bookings) returns boolean
language sql stable security invoker set search_path=public,pg_temp as $$
 select b.state in ('confirmed','completed','no_show') or (b.state='awaiting_payment' and b.hold_expires_at>now());
$$;
create function public.korlix_schedule_event_hosts_v2(e public.korlix_schedule_events) returns uuid[]
language sql stable security invoker set search_path=public,pg_temp as $$
 select case when e.routing_mode='single' then array[e.owner_id] else coalesce((select array_agg(m.user_id order by m.user_id) from public.korlix_schedule_members m join public.korlix_schedule_teams t on t.id=m.team_id where t.id=e.team_id and t.owner_id=e.owner_id and m.active and m.user_id=any(e.host_ids) and public.korlix_schedule_active_v1(m.user_id)),'{}') end;
$$;
create function public.korlix_schedule_lock_hosts_v2(p_event uuid,p_booking uuid default null) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare e public.korlix_schedule_events; locked_hosts uuid[]; latest_hosts uuid[];
begin
 select * into e from public.korlix_schedule_events where id=p_event;
 locked_hosts:=array(select unnest(e.host_ids||array[e.owner_id]) union select host_id from public.korlix_schedule_booking_hosts where booking_id=p_booking);
 -- All reservations, including collective hosts, use one deterministic lock order.
 perform 1 from public.user_profiles where id=any(locked_hosts) order by id for update;
 select * into e from public.korlix_schedule_events where id=p_event;
 latest_hosts:=array(select unnest(e.host_ids||array[e.owner_id]) union select host_id from public.korlix_schedule_booking_hosts where booking_id=p_booking);
 if not latest_hosts<@locked_hosts then raise exception using errcode='40001',message='Host assignments changed. Refresh before booking.';end if;
end;
$$;
create function public.korlix_schedule_calendar_available_v2(p_host uuid,p_start timestamptz,p_end timestamptz) returns boolean
language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare c public.korlix_schedule_connections; w public.korlix_schedule_calendar_windows; busy_item jsonb; s timestamptz; f timestamptz;
begin
 for c in select * from public.korlix_schedule_connections where owner_id=p_host and provider in ('google','microsoft') and enabled and cardinality(busy_ids)>0 loop
  if c.state<>'connected' then return false; end if;
  select * into w from public.korlix_schedule_calendar_windows where connection_id=c.id and revision=c.revision and starts_at<=p_start and ends_at>=p_end and checked_at>now()-interval '60 seconds' order by checked_at desc limit 1;
  if w.id is null then return false; end if;
  for busy_item in select value from jsonb_array_elements(w.busy) loop
   if busy_item ? 'start_date' then s:=(busy_item->>'start_date')::date::timestamp at time zone (busy_item->>'timezone'); f:=(busy_item->>'end_date')::date::timestamp at time zone (busy_item->>'timezone');
   else s:=(busy_item->>'starts_at')::timestamptz; f:=(busy_item->>'ends_at')::timestamptz; end if;
   if s<p_end and f>p_start and not exists(
    select 1 from public.korlix_schedule_calendar_links l join public.korlix_schedule_bookings b on b.id=l.booking_id
    where l.connection_id=c.id and l.calendar_id=busy_item->>'calendar_id' and l.provider_event_id=busy_item->>'remote_id'
     and public.korlix_schedule_live_booking_v2(b) and b.starts_at=s and b.ends_at=f) then return false; end if;
  end loop;
 end loop;
 return true;
end;
$$;
create function public.korlix_schedule_host_free_v2(p_host uuid,e public.korlix_schedule_events,p_start timestamptz,p_end timestamptz,p_exclude uuid default null) returns boolean
language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare p public.korlix_schedule_profiles; d date; windows jsonb; w jsonb; fits boolean:=false; daily int;
begin
 if not public.korlix_schedule_active_v1(p_host) then return false; end if;
 select * into p from public.korlix_schedule_profiles where owner_id=p_host; if p.owner_id is null then return false; end if;
 d:=(p_start at time zone p.timezone)::date;
 select x->'windows' into windows from jsonb_array_elements(p.overrides)x where x->>'date'=d::text;
 if windows is null then select x->'windows' into windows from jsonb_array_elements(p.weekly)x where (x->>'day')::int=extract(dow from d)::int; end if;
 for w in select value from jsonb_array_elements(coalesce(windows,'[]')) loop
  if not exists(select 1 from generate_series(p_start,p_end-interval '5 minutes',interval '5 minutes') t where (t at time zone p.timezone)::date<>d or extract(epoch from (t at time zone p.timezone)::time)/60<(w->>0)::int or extract(epoch from (t at time zone p.timezone)::time)/60>=(w->>1)::int) then fits:=true;exit;end if;
 end loop;
 if not fits then return false; end if;
 if exists(select 1 from public.korlix_schedule_blocks where owner_id=p_host and starts_at<p_end+make_interval(mins=>e.buffer_after) and ends_at>p_start-make_interval(mins=>e.buffer_before)) then return false; end if;
 if exists(select 1 from public.korlix_schedule_booking_hosts h join public.korlix_schedule_bookings b on b.id=h.booking_id where h.host_id=p_host and b.id is distinct from p_exclude and public.korlix_schedule_live_booking_v2(b)
   and b.busy_start<p_end+make_interval(mins=>e.buffer_after) and b.busy_end>p_start-make_interval(mins=>e.buffer_before)
   and not(e.kind='group' and b.event_id=e.id and b.starts_at=p_start and b.ends_at=p_end)) then return false; end if;
 select count(distinct (b.event_id,b.starts_at)) into daily from public.korlix_schedule_booking_hosts h join public.korlix_schedule_bookings b on b.id=h.booking_id where h.host_id=p_host and b.id is distinct from p_exclude and public.korlix_schedule_live_booking_v2(b) and (b.starts_at at time zone p.timezone)::date=d;
 if daily>=e.daily_limit and not exists(select 1 from public.korlix_schedule_booking_hosts h join public.korlix_schedule_bookings b on b.id=h.booking_id where h.host_id=p_host and b.id is distinct from p_exclude and e.kind='group' and b.event_id=e.id and b.starts_at=p_start and public.korlix_schedule_live_booking_v2(b)) then return false; end if;
 return public.korlix_schedule_calendar_available_v2(p_host,p_start-make_interval(mins=>e.buffer_before),p_end+make_interval(mins=>e.buffer_after));
end;
$$;
create function public.korlix_schedule_allocate_v2(e public.korlix_schedule_events,p_start timestamptz,p_end timestamptz,p_exclude uuid default null) returns uuid[]
language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare hosts uuid[]; eligible uuid[];
begin
 hosts:=public.korlix_schedule_event_hosts_v2(e);
 if cardinality(hosts)=0 or (e.routing_mode='collective' and cardinality(hosts)<>cardinality(e.host_ids)) then return '{}'; end if;
 select array_agg(h order by coalesce(m.last_assigned_at,'-infinity'::timestamptz),h) into eligible from unnest(hosts)h left join public.korlix_schedule_members m on m.team_id=e.team_id and m.user_id=h where public.korlix_schedule_host_free_v2(h,e,p_start,p_end,p_exclude);
 if e.routing_mode='round_robin' then return coalesce(eligible[1:1],'{}');end if;
 if cardinality(eligible)=cardinality(hosts) then return eligible;end if;
 return '{}';
end;
$$;

create or replace function public.korlix_schedule_event_public_v1(e public.korlix_schedule_events) returns jsonb
language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('slug',e.slug,'title',e.title,'description',e.description,'kind',e.kind,
 'duration_minutes',e.duration_minutes,'location_kind',e.location_kind,'questions',e.questions,'color',e.color,
 'cancel_notice_minutes',e.cancel_notice_minutes,'capacity',e.capacity,'horizon_days',e.horizon_days,
 'payment_live',(select c.livemode from public.korlix_schedule_connections c where c.owner_id=e.owner_id and c.provider='stripe' and c.enabled and c.state='connected' limit 1),'routing_mode',e.routing_mode,'price_cents',e.price_cents,'currency',e.currency,'refund_policy',e.refund_policy,
 'calendar_sync',exists(select 1 from public.korlix_schedule_connections c where c.owner_id=any(public.korlix_schedule_event_hosts_v2(e)) and c.enabled and c.provider in ('google','microsoft')),
 'host_name',case when e.routing_mode='single' then p.display_name else (select name from public.korlix_schedule_teams where id=e.team_id) end,'host_timezone',p.timezone,'revision',e.revision) from public.korlix_schedule_profiles p where p.owner_id=e.owner_id;
$$;

create or replace function public.korlix_schedule_booking_public_v1(b public.korlix_schedule_bookings) returns jsonb
language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('id',b.id,'event_id',b.event_id,'guest_name',b.guest_name,'guest_email',b.guest_email,
 'guest_timezone',b.guest_timezone,'answers',b.answers,'starts_at',b.starts_at,'ends_at',b.ends_at,
 'cancel_until',b.cancel_until,'state',b.state,'snapshot',case when exists(select 1 from public.korlix_schedule_payments pay where pay.booking_id=b.id and pay.payment_state not in ('paid','refunded')) then b.snapshot-'location_detail' else b.snapshot end,'revision',b.revision,'created_at',b.created_at,
 'hosts',coalesce((select jsonb_agg(p.display_name order by p.display_name) from public.korlix_schedule_booking_hosts h join public.korlix_schedule_profiles p on p.owner_id=h.host_id where h.booking_id=b.id),'[]'),
 'hold_expires_at',b.hold_expires_at,'payment',(select jsonb_build_object('amount_cents',pay.amount_cents,'livemode',pay.livemode,'currency',pay.currency,'state',pay.payment_state,'refund_state',pay.refund_state,'checkout_url',pay.checkout_url,'checkout_expires_at',pay.checkout_expires_at) from public.korlix_schedule_payments pay where pay.booking_id=b.id),
 'calendar_updates',coalesce((select jsonb_agg(jsonb_build_object('state',l.state,'last_error',l.last_error)) from public.korlix_schedule_calendar_links l where l.booking_id=b.id),'[]'),
 'event_slug',(select slug from public.korlix_schedule_events where id=b.event_id),
 'notifications',coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'state',state,'due_at',due_at)) from public.korlix_schedule_notifications where booking_id=b.id and booking_revision=b.revision and recipient_role='guest'),'[]'));
$$;

create or replace function public.korlix_schedule_slots_v1(p_event uuid,p_from date,p_days integer default 7,p_exclude uuid default null)
returns jsonb language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare e public.korlix_schedule_events; p public.korlix_schedule_profiles; d date; w jsonb; windows jsonb;
 s timestamptz; fin timestamptz; local_start timestamp; local_end timestamp; minutes integer; end_minutes numeric;
 seats integer; daily integer; day_start timestamptz; result jsonb:='[]';
begin
 select * into e from public.korlix_schedule_events where id=p_event and state='published';
 if not found or not public.korlix_schedule_active_v1(e.owner_id) then raise exception using errcode='P0002',message='This booking page is unavailable.'; end if;
 select * into p from public.korlix_schedule_profiles where owner_id=e.owner_id;
 if p_days not between 1 and 14 or p_from<(now() at time zone p.timezone)::date-1 or p_from>(now() at time zone p.timezone)::date+366 then raise exception 'Choose a date within the booking window.'; end if;
 for d in select p_from+i from generate_series(0,p_days-1)i loop
  day_start:=d::timestamp at time zone p.timezone;
  select count(distinct (event_id,starts_at)) into daily from public.korlix_schedule_bookings
   where owner_id=e.owner_id and state<>'canceled' and id is distinct from p_exclude
   and (starts_at at time zone p.timezone)::date=d;
  select x->'windows' into windows from jsonb_array_elements(p.overrides)x where x->>'date'=d::text;
  if windows is null then select x->'windows' into windows from jsonb_array_elements(p.weekly)x where (x->>'day')::int=extract(dow from d)::int; end if;
  for w in select value from jsonb_array_elements(coalesce(windows,'[]')) loop
   -- Walk real instants: nonexistent DST times disappear; repeated times keep unique UTC IDs.
   for s in select t from generate_series(day_start,((d+1)::timestamp at time zone p.timezone)-interval '5 minutes',interval '5 minutes')t loop
    local_start:=s at time zone p.timezone; minutes:=extract(hour from local_start)::int*60+extract(minute from local_start)::int;
    if local_start::date<>d or minutes<(w->>0)::int or minutes>=(w->>1)::int or (minutes-(w->>0)::int)%e.interval_minutes<>0 then continue; end if;
    fin:=s+make_interval(mins=>e.duration_minutes);local_end:=fin at time zone p.timezone;
    end_minutes:=extract(epoch from local_end::time)/60;
    if local_end::date=d+1 and local_end::time='00:00'::time then end_minutes:=1440;
    elsif local_end::date<>d then continue; end if;
    if end_minutes>(w->>1)::int or end_minutes<(w->>0)::int or s<now()+make_interval(mins=>e.notice_minutes)
     or s>now()+make_interval(days=>e.horizon_days) then continue; end if;
    -- On a clock transition, every real instant must stay inside this availability window.
    if local_end-local_start<>make_interval(mins=>e.duration_minutes) and exists(
     select 1 from generate_series(s,fin-interval '5 minutes',interval '5 minutes') probe
     where (probe at time zone p.timezone)::date<>d
      or extract(epoch from (probe at time zone p.timezone)::time)/60<(w->>0)::int
      or extract(epoch from (probe at time zone p.timezone)::time)/60>=(w->>1)::int) then continue; end if;
    if e.price_cents>0 and s<now()+interval '55 minutes' then continue; end if;
    if cardinality(public.korlix_schedule_allocate_v2(e,s,fin,p_exclude))=0 then continue; end if;
    select count(*) into seats from public.korlix_schedule_bookings b where e.kind='group' and event_id=e.id and starts_at=s and ends_at=fin and public.korlix_schedule_live_booking_v2(b) and id is distinct from p_exclude;
    if seats>=e.capacity then continue; end if;
    result:=result||jsonb_build_array(jsonb_build_object('starts_at',s,'ends_at',fin,'seats_left',e.capacity-seats));
   end loop;
  end loop;
 end loop;
 return result;
end;
$$;

create or replace function public.korlix_schedule_owner_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare p public.korlix_schedule_profiles; e public.korlix_schedule_events; b public.korlix_schedule_bookings; v_item jsonb; v_question jsonb;
begin
 if p_action='booking_state' then perform public.korlix_schedule_lock_hosts_v2(event_id,id) from public.korlix_schedule_bookings where id=p_id and (owner_id=p_actor or exists(select 1 from public.korlix_schedule_booking_hosts where booking_id=p_id and host_id=p_actor));end if;
 if not public.korlix_schedule_active_v1(p_actor) then raise exception using errcode='42501',message='An active, verified KORLIX account is required.'; end if;
 -- Consistent lock order serializes every mutation of a host's schedule across all event types.
 perform 1 from public.user_profiles where id=p_actor for update;
 select * into p from public.korlix_schedule_profiles where owner_id=p_actor;
 if p_action='dashboard' then
  return jsonb_build_object('profile',case when p.owner_id is null then null else to_jsonb(p)-'owner_id' end,
   'events',coalesce((select jsonb_agg(to_jsonb(t)-'owner_id' order by t.created_at desc) from public.korlix_schedule_events t where owner_id=p_actor),'[]'),
   'bookings',coalesce((select jsonb_agg(public.korlix_schedule_booking_public_v1(t)||jsonb_build_object('is_organizer',t.owner_id=p_actor) order by t.starts_at) from (select * from public.korlix_schedule_bookings where (owner_id=p_actor or exists(select 1 from public.korlix_schedule_booking_hosts h where h.booking_id=korlix_schedule_bookings.id and h.host_id=p_actor)) and ends_at>=now()-interval '90 days' order by starts_at limit 500)t),'[]'),
   'blocks',coalesce((select jsonb_agg(to_jsonb(t)-'owner_id' order by t.starts_at) from public.korlix_schedule_blocks t where owner_id=p_actor and ends_at>now()-interval '1 day'),'[]'),
   'audit',coalesce((select jsonb_agg(to_jsonb(t)-'owner_id' order by t.created_at desc) from (select * from public.korlix_schedule_audit where owner_id=p_actor order by created_at desc limit 30)t),'[]'),
   'booking_limit',500,'history_days',90);
 elsif p_action='save_profile' then
  if coalesce(p.revision,0)<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='Your availability changed. Refresh before saving.'; end if;
  if not exists(select 1 from pg_timezone_names where name=p_data->>'timezone') then raise exception 'Choose a valid time zone.'; end if;
  if jsonb_typeof(p_data->'weekly') is distinct from 'array' or jsonb_array_length(p_data->'weekly')<>7
   or jsonb_typeof(p_data->'overrides') is distinct from 'array' or jsonb_array_length(p_data->'overrides')>60 then raise exception 'Review your weekly hours and date overrides.'; end if;
  for v_item in select value from jsonb_array_elements(p_data->'weekly') loop
   if jsonb_typeof(v_item->'day') is distinct from 'number' or (v_item->>'day')!~'^[0-6]$' or not public.korlix_schedule_windows_valid_v1(v_item->'windows') then raise exception 'Review your weekly hours.'; end if;
  end loop;
  if (select count(distinct x->>'day') from jsonb_array_elements(p_data->'weekly')x)<>7 then raise exception 'Each weekday must appear once.'; end if;
  for v_item in select value from jsonb_array_elements(p_data->'overrides') loop
   if (v_item->>'date') is null or (v_item->>'date')!~'^\d{4}-\d{2}-\d{2}$' or not public.korlix_schedule_windows_valid_v1(v_item->'windows') then raise exception 'Review your date overrides.'; end if;
   perform (v_item->>'date')::date;
  end loop;
  if (select count(distinct x->>'date') from jsonb_array_elements(p_data->'overrides')x)<>jsonb_array_length(p_data->'overrides') then raise exception 'Each override date must appear once.'; end if;
  insert into public.korlix_schedule_profiles(owner_id,display_name,timezone,weekly,overrides)
   values(p_actor,p_data->>'display_name',p_data->>'timezone',p_data->'weekly',p_data->'overrides')
   on conflict(owner_id) do update set display_name=excluded.display_name,timezone=excluded.timezone,weekly=excluded.weekly,overrides=excluded.overrides,revision=korlix_schedule_profiles.revision+1,updated_at=now() returning * into p;
  insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'availability_saved');
  return to_jsonb(p)-'owner_id';
 end if;
 if p.owner_id is null then raise exception 'Save your host name and availability first.'; end if;
 if p_action='notifications' then
  if p.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='Your email settings changed. Refresh before saving.'; end if;
  if p_data->>'confirmed' is distinct from 'true' or jsonb_typeof(p_data->'enabled') is distinct from 'boolean'
   or coalesce(p_data->>'verified_email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Confirm your booking email settings.'; end if;
  update public.korlix_schedule_profiles set notifications_enabled=(p_data->>'enabled')::boolean,notification_email=p_data->>'verified_email',reminder_minutes=(p_data->>'reminder_minutes')::int,revision=revision+1,updated_at=now() where owner_id=p_actor;
  if p_data->>'enabled'='false' then update public.korlix_schedule_notifications set state='skipped' where owner_id=p_actor and state='pending'; end if;
  insert into public.korlix_schedule_audit(owner_id,action) values(p_actor,case when p_data->>'enabled'='true' then 'booking_emails_enabled' else 'booking_emails_disabled' end);
  return jsonb_build_object('saved',true);
 end if;
 if p_action='save_event' then
  select * into e from public.korlix_schedule_events where id=p_id and owner_id=p_actor;
  if p_id is not null and not found then raise exception using errcode='P0002',message='Event type not found.'; end if;
  if coalesce(e.revision,0)<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This event type changed. Refresh before saving.'; end if;
  if p_id is null and (select count(*) from public.korlix_schedule_events where owner_id=p_actor)>=200 then raise exception 'The 200 event type limit has been reached.'; end if;
  if jsonb_typeof(p_data->'questions') is distinct from 'array' or jsonb_array_length(p_data->'questions')>6 then raise exception 'Use at most six booking questions.'; end if;
  for v_question in select value from jsonb_array_elements(p_data->'questions') loop
   if (v_question->>'id') is null or (v_question->>'id')!~'^[a-z][a-z0-9_]{0,30}$' or length(coalesce(v_question->>'label','')) not between 1 and 200
    or coalesce(v_question->>'kind','') not in ('text','choice') or jsonb_typeof(v_question->'required') is distinct from 'boolean' then raise exception 'Review the booking questions.'; end if;
   if v_question->>'kind'='choice' and (jsonb_typeof(v_question->'options') is distinct from 'array' or jsonb_array_length(v_question->'options') not between 2 and 12) then raise exception 'Choices need 2 to 12 options.'; end if;
  end loop;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_data->'questions')x)<>jsonb_array_length(p_data->'questions') then raise exception 'Question identifiers must be unique.'; end if;
  if coalesce(p_data->>'routing_mode','single')<>'single' and (p_data->>'kind'<>'one_to_one' or not exists(select 1 from public.korlix_schedule_teams where id=(p_data->>'team_id')::uuid and owner_id=p_actor)) then raise exception 'Choose your own team and a one-to-one event.';end if;
  if coalesce(p_data->>'routing_mode','single')<>'single' and (jsonb_array_length(p_data->'host_ids') not between 1 and 20 or exists(select 1 from jsonb_array_elements_text(p_data->'host_ids')h where not exists(select 1 from public.korlix_schedule_members where team_id=(p_data->>'team_id')::uuid and user_id=h::uuid and active))) then raise exception 'Choose active team members.';end if;
  if coalesce((p_data->>'price_cents')::int,0)>0 and not exists(select 1 from public.korlix_schedule_connections where owner_id=p_actor and provider='stripe' and state='connected' and enabled and charges_enabled) then raise exception 'Connect a Stripe account that can accept payments first.';end if;
  if p_id is null then insert into public.korlix_schedule_events(owner_id,slug,title,duration_minutes) values(p_actor,p_data->>'slug',p_data->>'title',(p_data->>'duration_minutes')::int) returning * into e; end if;
  update public.korlix_schedule_events set title=p_data->>'title',description=p_data->>'description',kind=p_data->>'kind',duration_minutes=(p_data->>'duration_minutes')::int,
   interval_minutes=(p_data->>'interval_minutes')::int,buffer_before=(p_data->>'buffer_before')::int,buffer_after=(p_data->>'buffer_after')::int,
   notice_minutes=(p_data->>'notice_minutes')::int,horizon_days=(p_data->>'horizon_days')::int,daily_limit=(p_data->>'daily_limit')::int,
   capacity=(p_data->>'capacity')::int,cancel_notice_minutes=(p_data->>'cancel_notice_minutes')::int,location_kind=p_data->>'location_kind',location_detail=p_data->>'location_detail',
   routing_mode=coalesce(p_data->>'routing_mode','single'),team_id=(p_data->>'team_id')::uuid,host_ids=coalesce(array(select jsonb_array_elements_text(p_data->'host_ids')::uuid),'{}'),price_cents=coalesce((p_data->>'price_cents')::int,0),refund_policy=coalesce(p_data->>'refund_policy','Contact your host to request a refund.'),
   questions=p_data->'questions',color=p_data->>'color',revision=case when p_id is null then 1 else revision+1 end,updated_at=now() where id=e.id returning * into e;
  insert into public.korlix_schedule_audit(owner_id,event_id,action)values(p_actor,e.id,'event_saved');
  return to_jsonb(e)-'owner_id';
 elsif p_action='event_state' then
  select * into e from public.korlix_schedule_events where id=p_id and owner_id=p_actor;
  if not found then raise exception using errcode='P0002',message='Event type not found.'; end if;
  if e.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This event type changed. Refresh before updating.'; end if;
  if p_data->>'confirmed' is distinct from 'true' or coalesce(p_data->>'state','') not in ('published','paused','archived') then raise exception 'Confirm this event change.'; end if;
  if p_data->>'state'='published' and not exists(select 1 from jsonb_array_elements(p.weekly)x where jsonb_array_length(x->'windows')>0) and not exists(select 1 from jsonb_array_elements(p.overrides)x where jsonb_array_length(x->'windows')>0) then raise exception 'Add some availability before publishing.'; end if;
  if p_data->>'state'='published' and e.price_cents>0 and not exists(select 1 from public.korlix_schedule_connections where owner_id=p_actor and provider='stripe' and state='connected' and enabled and charges_enabled) then raise exception 'Reconnect your payment account before publishing.';end if;
  update public.korlix_schedule_events set state=p_data->>'state',revision=revision+1,updated_at=now() where id=e.id returning * into e;
  insert into public.korlix_schedule_audit(owner_id,event_id,action)values(p_actor,e.id,'event_'||e.state);
  return to_jsonb(e)-'owner_id';
 elsif p_action='add_block' then
  if (select count(*) from public.korlix_schedule_blocks where owner_id=p_actor)>=500 then raise exception 'Remove an older time block before adding another.'; end if;
  insert into public.korlix_schedule_blocks(owner_id,starts_at,ends_at,label) values(p_actor,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,p_data->>'label');
  insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'time_block_added');
  return jsonb_build_object('saved',true);
 elsif p_action='remove_block' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm this time block removal.'; end if;
  delete from public.korlix_schedule_blocks where id=p_id and owner_id=p_actor;
  return jsonb_build_object('removed',true);
 elsif p_action in ('booking_state','booking_get') then
  select * into b from public.korlix_schedule_bookings where id=p_id and (owner_id=p_actor or exists(select 1 from public.korlix_schedule_booking_hosts where booking_id=p_id and host_id=p_actor));
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  if p_action='booking_get' then return public.korlix_schedule_booking_public_v1(b); end if;
  if b.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This booking changed. Refresh before updating.'; end if;
  if p_data->>'confirmed' is distinct from 'true' or coalesce(p_data->>'state','') not in ('canceled','completed','no_show') then raise exception 'Confirm the booking status change.'; end if;
  if b.state in ('canceled','payment_failed') or (b.state='awaiting_payment' and p_data->>'state'<>'canceled') or (p_data->>'state' in ('completed','no_show') and b.starts_at>now()) then raise exception 'This status is unavailable for this booking.'; end if;
  update public.korlix_schedule_bookings set state=p_data->>'state',revision=revision+1,updated_at=now() where id=b.id returning * into b;
  perform public.korlix_schedule_calendar_enqueue_v2(b.id);
  if b.state='canceled' then perform public.korlix_schedule_enqueue_v1(b,'cancellation');
  else update public.korlix_schedule_notifications set state='skipped' where booking_id=b.id and state='pending'; end if;
  insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action) values(p_actor,b.event_id,b.id,'host_'||b.state);
  return public.korlix_schedule_booking_public_v1(b);
 end if;
 raise exception 'Unsupported scheduling action.';
end;
$$;

create or replace function public.korlix_schedule_public_v1(p_action text,p_slug text default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare e public.korlix_schedule_events; p public.korlix_schedule_profiles; b public.korlix_schedule_bookings;
 c public.korlix_schedule_contexts; s timestamptz; slots jsonb; v_question jsonb; answer text; snapshot jsonb; assigned uuid[]; pay_connection public.korlix_schedule_connections;
begin
 if p_action in ('manage','cancel','reschedule','manage_slots') then
  select * into b from public.korlix_schedule_bookings where id=(p_data->>'booking_id')::uuid and manage_hash=p_data->>'manage_hash' and ends_at>now()-interval '30 days';
  if not found then raise exception using errcode='P0002',message='This private booking link is unavailable.'; end if;
  if p_action='manage' then return public.korlix_schedule_booking_public_v1(b); end if;
  perform public.korlix_schedule_lock_hosts_v2(b.event_id,b.id);
  select * into b from public.korlix_schedule_bookings where id=b.id;
  if b.state not in ('confirmed','awaiting_payment') or (b.state='awaiting_payment' and p_action<>'cancel') or (b.state='confirmed' and b.cancel_until<=now()) then raise exception using errcode='40001',message='Online changes are closed. Contact your host.'; end if;
  select * into e from public.korlix_schedule_events where id=b.event_id;
  select * into p from public.korlix_schedule_profiles where owner_id=b.owner_id;
  if p_action in ('manage_slots','reschedule') and (e.duration_minutes<>(b.snapshot->>'duration_minutes')::int
   or e.location_kind<>b.snapshot->>'location_kind' or e.location_detail<>b.snapshot->>'location_detail'
   or e.title<>b.snapshot->>'title' or e.questions<>b.snapshot->'questions' or e.price_cents<>coalesce((b.snapshot->>'price_cents')::int,0)) then
   raise exception using errcode='40001',message='The host changed this meeting type. Contact your host before rescheduling.';
  end if;
  if p_action='manage_slots' then return jsonb_build_object('slots',public.korlix_schedule_slots_v1(e.id,(p_data->>'date')::date,7,b.id),'event',public.korlix_schedule_event_public_v1(e)); end if;
  if b.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This booking changed. Reload your booking.'; end if;
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm this booking change.'; end if;
  if p_action='cancel' then
   update public.korlix_schedule_bookings set state='canceled',revision=revision+1,updated_at=now() where id=b.id returning * into b;
  else
   s:=(p_data->>'starts_at')::timestamptz;
   slots:=public.korlix_schedule_slots_v1(e.id,(s at time zone p.timezone)::date,1,b.id);
   if not exists(select 1 from jsonb_array_elements(slots)x where (x->>'starts_at')::timestamptz=s) then raise exception using errcode='40001',message='That time is no longer available. Choose another.'; end if;
   -- Reschedule requires re-review when an event's duration or location changed.
   if e.revision<>coalesce((p_data->>'event_revision')::int,-1) then raise exception using errcode='40001',message='The meeting details changed. Reload and review them before rescheduling.'; end if;
   assigned:=public.korlix_schedule_allocate_v2(e,s,s+make_interval(mins=>e.duration_minutes),b.id);
   if cardinality(assigned)=0 then raise exception 'No team member is available at that time.';end if;
   update public.korlix_schedule_bookings set starts_at=s,ends_at=s+make_interval(mins=>e.duration_minutes),busy_start=s-make_interval(mins=>e.buffer_before),busy_end=s+make_interval(mins=>e.duration_minutes+e.buffer_after),
    cancel_until=s-make_interval(mins=>e.cancel_notice_minutes),snapshot=public.korlix_schedule_event_public_v1(e)||jsonb_build_object('location_detail',e.location_detail),revision=revision+1,updated_at=now() where id=b.id returning * into b;
   delete from public.korlix_schedule_booking_hosts where booking_id=b.id;
   insert into public.korlix_schedule_booking_hosts select b.id,unnest(assigned);
   update public.korlix_schedule_members set last_assigned_at=now() where team_id=e.team_id and user_id=any(assigned);
  end if;
  insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action)values(b.owner_id,b.event_id,b.id,'guest_'||p_action);
  perform public.korlix_schedule_calendar_enqueue_v2(b.id);
  perform public.korlix_schedule_enqueue_v1(b,case when p_action='cancel' then 'cancellation' else 'reschedule' end);
  return public.korlix_schedule_booking_public_v1(b);
 end if;
 if p_action='book' then
  select * into b from public.korlix_schedule_bookings where request_id=(p_data->>'request_id')::uuid;
  if found then
   if b.request_hash<>p_data->>'request_hash' or b.manage_hash<>p_data->>'manage_hash' then raise exception using errcode='40001',message='This booking request changed. Start a new booking.'; end if;
   return public.korlix_schedule_booking_public_v1(b);
  end if;
 end if;
 select * into e from public.korlix_schedule_events where slug=p_slug and state='published';
 if not found or not public.korlix_schedule_active_v1(e.owner_id) then raise exception using errcode='P0002',message='This booking page is unavailable.'; end if;
 -- Lock the host, then re-read the event so a concurrent unpublish/edit cannot be bypassed.
 perform public.korlix_schedule_lock_hosts_v2(e.id);
 select * into e from public.korlix_schedule_events where id=e.id and state='published';
 if not found or not public.korlix_schedule_active_v1(e.owner_id) then raise exception using errcode='P0002',message='This booking page is unavailable.'; end if;
 select * into p from public.korlix_schedule_profiles where owner_id=e.owner_id;
 if p_action='book' then
  select * into b from public.korlix_schedule_bookings where request_id=(p_data->>'request_id')::uuid;
  if found then
   if b.request_hash<>p_data->>'request_hash' or b.manage_hash<>p_data->>'manage_hash' then raise exception using errcode='40001',message='This booking request changed. Start a new booking.'; end if;
   return public.korlix_schedule_booking_public_v1(b);
  end if;
 end if;
 if p_action='context' then
  delete from public.korlix_schedule_contexts where event_id=e.id and expires_at<now();
  if (select count(*) from public.korlix_schedule_contexts where event_id=e.id)>2000 then raise exception using errcode='54000',message='This booking page is busy. Try again shortly.'; end if;
  insert into public.korlix_schedule_contexts(token_hash,browser_hash,event_id,event_revision,profile_revision) values(p_data->>'token_hash',p_data->>'browser_hash',e.id,e.revision,p.revision);
  return jsonb_build_object('event',public.korlix_schedule_event_public_v1(e),'today',(now() at time zone p.timezone)::date,'email_enabled',p.notifications_enabled);
 end if;
 select * into c from public.korlix_schedule_contexts where token_hash=p_data->>'token_hash' and browser_hash=p_data->>'browser_hash' and event_id=e.id and expires_at>now();
 if not found then raise exception using errcode='40001',message='Your booking session expired. Reload this page.'; end if;
 if c.event_revision<>e.revision or c.profile_revision<>p.revision then raise exception using errcode='40001',message='The host updated this page. Reload and review the latest details.'; end if;
 if p_action='slots' then return jsonb_build_object('slots',public.korlix_schedule_slots_v1(e.id,(p_data->>'date')::date,7)); end if;
 if p_action<>'book' then raise exception 'Unsupported booking action.'; end if;
 if p_data->>'confirmed' is distinct from 'true' or length(trim(coalesce(p_data->>'guest_name',''))) not between 1 and 100
  or coalesce(p_data->>'guest_email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  or not exists(select 1 from pg_timezone_names where name=p_data->>'guest_timezone') then raise exception 'Review your name, email, time zone and booking confirmation.'; end if;
 if jsonb_typeof(p_data->'answers') is distinct from 'object' or length((p_data->'answers')::text)>6500 then raise exception 'Review your answers.'; end if;
 if exists(select 1 from jsonb_object_keys(p_data->'answers')k where not exists(select 1 from jsonb_array_elements(e.questions)q where q->>'id'=k)) then raise exception 'The booking questions changed. Reload this page.'; end if;
 for v_question in select value from jsonb_array_elements(e.questions) loop
  answer:=trim(coalesce(p_data->'answers'->>(v_question->>'id'),''));
  if length(answer)>1000 or (v_question->>'required'='true' and answer='') or (answer<>'' and v_question->>'kind'='choice' and not (v_question->'options' ? answer)) then raise exception 'Complete the requested booking questions.'; end if;
 end loop;
 s:=(p_data->>'starts_at')::timestamptz;
 slots:=public.korlix_schedule_slots_v1(e.id,(s at time zone p.timezone)::date,1);
 if not exists(select 1 from jsonb_array_elements(slots)x where (x->>'starts_at')::timestamptz=s) then raise exception using errcode='40001',message='That time is no longer available. Choose another.'; end if;
 if exists(select 1 from public.korlix_schedule_bookings where event_id=e.id and starts_at=s and public.korlix_schedule_live_booking_v2(korlix_schedule_bookings) and lower(guest_email)=lower(p_data->>'guest_email')) then raise exception using errcode='40001',message='This email already has a booking at that time. Use the existing private booking link.'; end if;
 if (select count(*) from public.korlix_schedule_bookings where owner_id=e.owner_id and created_at>now()-interval '1 day')>=1000 then raise exception using errcode='54000',message='This host has reached the daily booking limit.'; end if;
 assigned:=public.korlix_schedule_allocate_v2(e,s,s+make_interval(mins=>e.duration_minutes));
 if cardinality(assigned)=0 then raise exception 'No host is available at that time.';end if;
 if e.price_cents>0 then
  select * into pay_connection from public.korlix_schedule_connections where owner_id=e.owner_id and provider='stripe' and state='connected' and enabled and charges_enabled;
  if pay_connection.id is null or coalesce(p_data->>'payments_ready','false')<>'true' then raise exception 'Payments are unavailable for this booking. Contact the host.';end if;
 end if;
 snapshot:=public.korlix_schedule_event_public_v1(e)||jsonb_build_object('location_detail',e.location_detail);
 insert into public.korlix_schedule_bookings(owner_id,event_id,request_id,request_hash,manage_hash,sealed_manage_token,guest_name,guest_email,guest_timezone,answers,starts_at,ends_at,busy_start,busy_end,cancel_until,snapshot)
 values(e.owner_id,e.id,(p_data->>'request_id')::uuid,p_data->>'request_hash',p_data->>'manage_hash',p_data->>'sealed_manage_token',trim(p_data->>'guest_name'),lower(trim(p_data->>'guest_email')),p_data->>'guest_timezone',p_data->'answers',s,s+make_interval(mins=>e.duration_minutes),s-make_interval(mins=>e.buffer_before),s+make_interval(mins=>e.duration_minutes+e.buffer_after),s-make_interval(mins=>e.cancel_notice_minutes),snapshot) returning * into b;
 insert into public.korlix_schedule_booking_hosts select b.id,unnest(assigned);
 update public.korlix_schedule_members set last_assigned_at=now() where team_id=e.team_id and user_id=any(assigned);
 if e.price_cents>0 then
  update public.korlix_schedule_bookings set state='awaiting_payment',hold_expires_at=now()+interval '50 minutes' where id=b.id returning * into b;
  insert into public.korlix_schedule_payments(booking_id,connection_id,account_id,livemode,amount_cents,currency,checkout_expires_at)values(b.id,pay_connection.id,pay_connection.remote_id,pay_connection.livemode,e.price_cents,e.currency,date_trunc('second',now()+interval '40 minutes'));
 end if;
 perform public.korlix_schedule_calendar_enqueue_v2(b.id);
 insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action)values(e.owner_id,e.id,b.id,case when b.state='confirmed' then 'booking_confirmed' else 'payment_hold_created' end);
 perform public.korlix_schedule_enqueue_v1(b,'confirmation');
 return public.korlix_schedule_booking_public_v1(b);
end;
$$;

create or replace function public.korlix_schedule_enqueue_v1(b public.korlix_schedule_bookings,p_kind text) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare p public.korlix_schedule_profiles; recipient text; target text;
begin
 if b.state not in ('confirmed','canceled') then return;end if;
 update public.korlix_schedule_notifications set state='skipped' where booking_id=b.id and booking_revision<>b.revision and state='pending';
 select * into p from public.korlix_schedule_profiles where owner_id=b.owner_id;
 if not p.notifications_enabled or b.sealed_manage_token is null then return; end if;
 foreach recipient in array array['host','guest'] loop
  target:=case when recipient='host' then p.notification_email else b.guest_email end;
  if target is null then continue; end if;
  insert into public.korlix_schedule_notifications(owner_id,booking_id,booking_revision,kind,recipient_role,payload,due_at)
   values(b.owner_id,b.id,b.revision,p_kind,recipient,jsonb_build_object('to',target,'booking',public.korlix_schedule_booking_public_v1(b)),now()) on conflict do nothing;
 end loop;
 if p.reminder_minutes>0 and b.state='confirmed' and b.starts_at-make_interval(mins=>p.reminder_minutes)>now() then
  insert into public.korlix_schedule_notifications(owner_id,booking_id,booking_revision,kind,recipient_role,payload,due_at)
   values(b.owner_id,b.id,b.revision,'reminder','guest',jsonb_build_object('to',b.guest_email,'booking',public.korlix_schedule_booking_public_v1(b)),b.starts_at-make_interval(mins=>p.reminder_minutes)) on conflict do nothing;
 end if;
end;
$$;

create function public.korlix_schedule_team_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare t public.korlix_schedule_teams; target uuid;
begin
 if not public.korlix_schedule_active_v1(p_actor) or not exists(select 1 from public.korlix_schedule_profiles where owner_id=p_actor) then raise exception using errcode='42501',message='Save your verified host profile first.';end if;
 if p_action='list' then return coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'revision',q.revision,'is_owner',q.owner_id=p_actor,'members',(select jsonb_agg(jsonb_build_object('user_id',m.user_id,'is_owner',m.user_id=q.owner_id,'name',p.display_name,'timezone',p.timezone,'active',m.active) order by p.display_name) from public.korlix_schedule_members m join public.korlix_schedule_profiles p on p.owner_id=m.user_id where m.team_id=q.id))) from public.korlix_schedule_teams q where q.owner_id=p_actor or exists(select 1 from public.korlix_schedule_members where team_id=q.id and user_id=p_actor and active)),'[]');end if;
 if p_action='create' then
  perform 1 from public.user_profiles where id=p_actor for update;
  if (select count(*) from public.korlix_schedule_teams where owner_id=p_actor)>=10 then raise exception 'The ten-team limit has been reached.';end if;
  insert into public.korlix_schedule_teams(owner_id,name) values(p_actor,p_data->>'name') returning * into t;
  insert into public.korlix_schedule_members(team_id,user_id)values(t.id,p_actor);
  return to_jsonb(t)-'owner_id'-'invite_hash';
 end if;
 if p_action in ('preview_join','join') then select * into t from public.korlix_schedule_teams where invite_hash=p_data->>'invite_hash' and invite_expires_at>now();
 else select * into t from public.korlix_schedule_teams where id=p_id and (owner_id=p_actor or p_action='leave' and exists(select 1 from public.korlix_schedule_members where team_id=p_id and user_id=p_actor and active));end if;
 if t.id is null then raise exception using errcode='P0002',message='This team or invitation is unavailable.';end if;
 if p_action='preview_join' then return jsonb_build_object('id',t.id,'name',t.name,'owner_name',(select display_name from public.korlix_schedule_profiles where owner_id=t.owner_id));end if;
 target:=case when p_action='remove' then (p_data->>'user_id')::uuid else p_actor end;
 perform 1 from public.user_profiles where id in (p_actor,t.owner_id,target) order by id for update;
 select * into t from public.korlix_schedule_teams where id=t.id for update;
 if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm this team action.';end if;
 if p_action='join' then
  if t.invite_hash is distinct from p_data->>'invite_hash' or t.invite_expires_at<=now() then raise exception 'This invitation expired.';end if;
  if (select count(*) from public.korlix_schedule_members where team_id=t.id and active)>=20 and not exists(select 1 from public.korlix_schedule_members where team_id=t.id and user_id=p_actor and active) then raise exception 'This team already has twenty active hosts.';end if;
  insert into public.korlix_schedule_members(team_id,user_id)values(t.id,p_actor)on conflict(team_id,user_id)do update set active=true,joined_at=now();
 elsif p_action='invite' then
  if t.revision<>(p_data->>'revision')::int then raise exception using errcode='40001',message='The team changed. Refresh first.';end if;
  update public.korlix_schedule_teams set invite_hash=p_data->>'invite_hash',invite_expires_at=now()+interval '7 days',revision=revision+1 where id=t.id;
 elsif p_action in ('leave','remove') then
  if target=t.owner_id then raise exception 'The team owner cannot be removed.';end if;
  update public.korlix_schedule_members set active=false where team_id=t.id and user_id=target;
  update public.korlix_schedule_teams set revision=revision+1 where id=t.id;
 else raise exception 'Unsupported team action.';end if;
 insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'team_'||p_action);
 return jsonb_build_object('saved',true);
end;
$$;

create function public.korlix_schedule_connections_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare c public.korlix_schedule_connections; a public.korlix_schedule_oauth; ids text[];
begin
 if not public.korlix_schedule_active_v1(p_actor) or not exists(select 1 from public.korlix_schedule_profiles where owner_id=p_actor) then raise exception using errcode='42501',message='Save your verified host profile first.';end if;
 if p_action='list' then return jsonb_build_object('connections',coalesce((select jsonb_agg(to_jsonb(q)-'owner_id'-'sealed_grant'-'config_hash'-'lease_id'-'lease_until' order by q.created_at) from public.korlix_schedule_connections q where owner_id=p_actor),'[]'),'pending',coalesce((select jsonb_agg(jsonb_build_object('id',id,'provider',provider,'status',status,'identity',identity,'expires_at',expires_at)) from public.korlix_schedule_oauth where owner_id=p_actor and expires_at>now() and status in ('pending','launched','exchanging','ready')),'[]'));end if;
 perform 1 from public.user_profiles where id=p_actor for update;
 if p_action='start' then
  if (select count(*) from public.korlix_schedule_oauth where owner_id=p_actor and created_at>now()-interval '1 hour')>=20 then raise exception using errcode='54000',message='Too many connection attempts. Try again later.';end if;
  update public.korlix_schedule_oauth set status='failed',sealed_secrets='',sealed_grant=null where owner_id=p_actor and provider=p_data->>'provider' and status in ('pending','launched','exchanging','ready');
  insert into public.korlix_schedule_oauth(id,owner_id,provider,ticket_hash,state_hash,sealed_secrets,config_hash)values(p_id,p_actor,p_data->>'provider',p_data->>'ticket_hash',p_data->>'state_hash',p_data->>'sealed_secrets',p_data->>'config_hash');
  return jsonb_build_object('started',true);
 elsif p_action in ('ready','finish') then
  select * into a from public.korlix_schedule_oauth where id=p_id and owner_id=p_actor and expires_at>now() and status='ready' for update;
  if a.id is null then raise exception 'This connection attempt expired. Start again.';end if;
  if p_action='ready' then return to_jsonb(a);end if;
  if p_data->>'confirmed' is distinct from 'true' or a.config_hash<>p_data->>'config_hash' then raise exception 'Review the connected account again.';end if;
  if a.provider='stripe' then
   perform pg_advisory_xact_lock(hashtextextended('schedule-stripe:'||(a.identity->>'id'),0));
   if exists(select 1 from public.korlix_schedule_connections where provider='stripe' and remote_id=a.identity->>'id' and owner_id<>p_actor) then raise exception 'This merchant account is linked to another KORLIX host.';end if;
   update public.korlix_schedule_connections set enabled=false,revision=revision+1 where owner_id=p_actor and provider='stripe';
  end if;
  if (select count(*) from public.korlix_schedule_connections where owner_id=p_actor and provider<>'stripe' and state<>'disconnected')>=5 and not exists(select 1 from public.korlix_schedule_connections where owner_id=p_actor and provider=a.provider and remote_id=a.identity->>'id') then raise exception 'Disconnect an account before adding more than five calendar accounts.';end if;
  insert into public.korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,charges_enabled,livemode,enabled)
   values(p_actor,a.provider,a.identity->>'id',a.identity->>'label',p_data->>'sealed_grant',a.config_hash,coalesce((a.identity->>'charges_enabled')::boolean,false),(a.identity->>'livemode')::boolean,a.provider='stripe')
   on conflict(owner_id,provider,remote_id)do update set sealed_grant=excluded.sealed_grant,config_hash=excluded.config_hash,state='connected',charges_enabled=excluded.charges_enabled,livemode=excluded.livemode,label=excluded.label,enabled=case when excluded.provider='stripe' then true else korlix_schedule_connections.enabled end,revision=korlix_schedule_connections.revision+1,last_error=null,updated_at=now() returning * into c;
  update public.korlix_schedule_oauth set status='finished',sealed_secrets='',sealed_grant=null where id=a.id;
  insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,a.provider||'_connected');
  return jsonb_build_object('id',c.id,'saved',true);
 end if;
 select * into c from public.korlix_schedule_connections where id=p_id and owner_id=p_actor for update;
 if c.id is null then raise exception using errcode='P0002',message='Connection not found.';end if;
 if p_action='private' then return to_jsonb(c);end if;
 if p_action='calendar_list' then
  if c.revision<>(p_data->>'revision')::int then raise exception using errcode='40001',message='The connection changed. Refresh again.';end if;
  update public.korlix_schedule_connections set calendars=p_data->'calendars' where id=c.id;
 elsif p_action='settings' then
  if p_data->>'confirmed' is distinct from 'true' or c.revision<>(p_data->>'revision')::int or c.provider='stripe' then raise exception using errcode='40001',message='Review the latest calendar settings.';end if;
  ids:=array(select distinct jsonb_array_elements_text(p_data->'busy_ids'));
  if cardinality(ids) not between 1 and 5 or exists(select 1 from unnest(ids)x where not exists(select 1 from jsonb_array_elements(c.calendars)y where y->>'id'=x)) then raise exception 'Choose one to five calendars from this account.';end if;
  if nullif(p_data->>'write_id','') is not null and not exists(select 1 from jsonb_array_elements(c.calendars)y where y->>'id'=p_data->>'write_id' and y->>'writable'='true') then raise exception 'Choose a calendar you can edit.';end if;
  if nullif(p_data->>'write_id','') is not null then update public.korlix_schedule_connections set write_id=null,revision=revision+1 where owner_id=p_actor and id<>c.id and write_id is not null;end if;
  update public.korlix_schedule_connections set busy_ids=ids,write_id=nullif(p_data->>'write_id',''),enabled=true,revision=revision+1,lease_until=null,last_error=null where id=c.id;
 elsif p_action='disconnect' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm disconnection.';end if;
  if c.provider='stripe' and exists(select 1 from public.korlix_schedule_payments p join public.korlix_schedule_bookings b on b.id=p.booking_id where p.connection_id=c.id and (b.state='awaiting_payment' and b.hold_expires_at>now() or p.payment_state='unpaid' and p.checkout_wire is not null and not p.checkout_closed or p.refund_state in ('required','sending','pending'))) then raise exception 'Complete open payments and refunds before disconnecting.';end if;
  update public.korlix_schedule_connections set state='disconnected',sealed_grant=null,enabled=false,revision=revision+1,write_id=null,busy_ids='{}' where id=c.id;
  update public.korlix_schedule_calendar_links set state='failed',last_error='Calendar disconnected. Existing external entries must be managed in the calendar.' where connection_id=c.id and state='pending';
 else raise exception 'Unsupported connection action.';end if;
 insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'connection_'||p_action);
 return jsonb_build_object('saved',true);
end;
$$;

create function public.korlix_schedule_oauth_v2(p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_schedule_oauth;
begin
 if p_action='launch' then
  select * into a from public.korlix_schedule_oauth where ticket_hash=p_data->>'ticket_hash' and provider=p_data->>'provider' and status='pending' and expires_at>now() for update;
  if a.id is null or not public.korlix_schedule_active_v1(a.owner_id) then raise exception 'This connection link expired. Return to KORLIX and start again.';end if;
  update public.korlix_schedule_oauth set browser_hash=p_data->>'browser_hash',status='launched' where id=a.id;
 elsif p_action='claim' then
  select * into a from public.korlix_schedule_oauth where state_hash=p_data->>'state_hash' and browser_hash=p_data->>'browser_hash' and provider=p_data->>'provider' and status='launched' and expires_at>now() for update;
  if a.id is null or not public.korlix_schedule_active_v1(a.owner_id) then raise exception 'This connection callback is expired or belongs to another browser.';end if;
  update public.korlix_schedule_oauth set status='exchanging' where id=a.id;
 elsif p_action='complete' then
  select * into a from public.korlix_schedule_oauth where id=p_id and status='exchanging' and expires_at>now() for update;
  if a.id is null or not public.korlix_schedule_active_v1(a.owner_id) or a.config_hash<>p_data->>'config_hash' then raise exception 'This connection attempt is no longer active.';end if;
  update public.korlix_schedule_oauth set sealed_grant=p_data->>'sealed_grant',identity=p_data->'identity',status='ready' where id=a.id;
  return jsonb_build_object('ready',true);
 else raise exception 'Unsupported authorization action.';end if;
 return to_jsonb(a);
end;
$$;

create function public.korlix_schedule_subjects_v2(p_actor uuid default null,p_slug text default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare e public.korlix_schedule_events; b public.korlix_schedule_bookings; c public.korlix_schedule_contexts; hosts uuid[];
begin
 if p_data ? 'request_id' then
  select * into b from public.korlix_schedule_bookings where request_id=(p_data->>'request_id')::uuid and manage_hash=p_data->>'manage_hash' and request_hash=p_data->>'request_hash';
  if b.id is not null then return jsonb_build_object('replay',true,'connections','[]'::jsonb);end if;
 end if;
 if p_data ? 'booking_id' then
  select * into b from public.korlix_schedule_bookings where id=(p_data->>'booking_id')::uuid and ((p_actor is not null and (owner_id=p_actor or exists(select 1 from public.korlix_schedule_booking_hosts h where h.booking_id=korlix_schedule_bookings.id and h.host_id=p_actor))) or (manage_hash=p_data->>'manage_hash' and ends_at>now()-interval '30 days'));
  if b.id is null then raise exception using errcode='P0002',message='Booking not found.';end if;
  select * into e from public.korlix_schedule_events where id=b.event_id;
 elsif p_actor is not null then
  select * into e from public.korlix_schedule_events where id=(p_data->>'event_id')::uuid and owner_id=p_actor;
 else
  select * into e from public.korlix_schedule_events where slug=p_slug and state='published';
  select * into c from public.korlix_schedule_contexts where token_hash=p_data->>'token_hash' and browser_hash=p_data->>'browser_hash' and event_id=e.id and expires_at>now();
  if c.token_hash is null or c.event_revision<>e.revision or c.profile_revision<>(select revision from public.korlix_schedule_profiles where owner_id=e.owner_id) then raise exception using errcode='40001',message='Reload this booking page to review current availability.';end if;
 end if;
 if e.id is null or not public.korlix_schedule_active_v1(e.owner_id) or p_actor is not null and not public.korlix_schedule_active_v1(p_actor) then raise exception using errcode='P0002',message='This schedule is unavailable.';end if;
 hosts:=array(select distinct unnest(public.korlix_schedule_event_hosts_v2(e)) union select host_id from public.korlix_schedule_booking_hosts where booking_id=b.id);
 return jsonb_build_object('event',to_jsonb(e),'connections',coalesce((select jsonb_agg(to_jsonb(q)) from public.korlix_schedule_connections q where owner_id=any(hosts) and provider in ('google','microsoft') and enabled and cardinality(busy_ids)>0),'[]'));
end;
$$;

create function public.korlix_schedule_calendar_sync_v2(p_action text,p_id uuid,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare c public.korlix_schedule_connections; f timestamptz; t timestamptz; x jsonb;
begin
 select * into c from public.korlix_schedule_connections where id=p_id for update;
 if c.id is null or c.provider='stripe' or c.state<>'connected' or not public.korlix_schedule_active_v1(c.owner_id) then raise exception 'Reconnect the calendar before checking availability.';end if;
 if p_action='claim' then
  if c.lease_until>now() then raise exception using errcode='40001',message='This calendar is being checked. Try again shortly.';end if;
  update public.korlix_schedule_connections set lease_id=gen_random_uuid(),lease_until=now()+interval '3 minutes' where id=c.id returning * into c;
  return to_jsonb(c);
 end if;
 if c.lease_id is distinct from (p_data->>'lease_id')::uuid or c.lease_until<=now() or c.revision<>(p_data->>'revision')::int then raise exception using errcode='40001',message='Calendar settings changed. Check availability again.';end if;
 if p_action='release' then update public.korlix_schedule_connections set lease_until=null where id=c.id;return jsonb_build_object('released',true);end if;
 if p_action='token' then update public.korlix_schedule_connections set sealed_grant=p_data->>'sealed_grant' where id=c.id;return jsonb_build_object('saved',true);end if;
 if p_action='cache' then
  f:=(p_data->>'from')::timestamptz;t:=(p_data->>'to')::timestamptz;
  if not isfinite(f) or not isfinite(t) or t<=f or t>f+interval '17 days' or jsonb_typeof(p_data->'busy') is distinct from 'array' or jsonb_array_length(p_data->'busy')>10000 then raise exception 'Invalid calendar window.';end if;
  for x in select value from jsonb_array_elements(p_data->'busy') loop
   if not (x->>'calendar_id'=any(c.busy_ids)) then raise exception 'Calendar selection changed.';end if;
   if x ? 'start_date' then
    if not exists(select 1 from pg_timezone_names where name=x->>'timezone') or (x->>'end_date')::date<=(x->>'start_date')::date then raise exception 'Invalid all-day calendar event.';end if;
   elsif not isfinite((x->>'starts_at')::timestamptz) or not isfinite((x->>'ends_at')::timestamptz) or (x->>'ends_at')::timestamptz<=(x->>'starts_at')::timestamptz then raise exception 'Invalid calendar event.';end if;
  end loop;
  delete from public.korlix_schedule_calendar_windows where connection_id=c.id and checked_at<now()-interval '5 minutes';
  insert into public.korlix_schedule_calendar_windows(connection_id,revision,starts_at,ends_at,busy)values(c.id,c.revision,f,t,p_data->'busy');
  delete from public.korlix_schedule_calendar_windows where id in(select id from public.korlix_schedule_calendar_windows where connection_id=c.id order by checked_at desc offset 30);
  update public.korlix_schedule_connections set last_sync_at=now(),last_error=null where id=c.id;
  return jsonb_build_object('checked',true);
 end if;
 raise exception 'Unsupported calendar synchronization action.';
end;
$$;

create function public.korlix_schedule_calendar_enqueue_v2(p_booking uuid) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare b public.korlix_schedule_bookings;
begin
 select * into b from public.korlix_schedule_bookings where id=p_booking;
 if b.state in ('awaiting_payment','completed','no_show') then return;end if;
 update public.korlix_schedule_calendar_links l set desired_revision=b.revision,removed=b.state<>'confirmed' or not exists(select 1 from public.korlix_schedule_booking_hosts h join public.korlix_schedule_connections c on c.owner_id=h.host_id where h.booking_id=b.id and h.host_id=l.host_id and c.id=l.connection_id and c.write_id=l.calendar_id and c.enabled and c.state='connected'),state=case when l.state='sending' then 'sending' else 'pending' end,attempts=case when l.state='sending' then l.attempts else 0 end,next_attempt_at=now(),last_error=null where l.booking_id=b.id;
 if b.state<>'confirmed' then return;end if;
 insert into public.korlix_schedule_calendar_links(booking_id,host_id,connection_id,calendar_id,desired_revision)
 select b.id,h.host_id,c.id,c.write_id,b.revision from public.korlix_schedule_booking_hosts h join public.korlix_schedule_connections c on c.owner_id=h.host_id where h.booking_id=b.id and c.enabled and c.state='connected' and c.provider in ('google','microsoft') and c.write_id is not null
 on conflict(booking_id,host_id,connection_id,calendar_id)do nothing;
end;
$$;
create function public.korlix_schedule_calendar_queue_v2(p_action text,p_id uuid default null,p_lease uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare l public.korlix_schedule_calendar_links; b public.korlix_schedule_bookings; c public.korlix_schedule_connections;
begin
 if p_action='claim' then
  select * into l from public.korlix_schedule_calendar_links q where (state='pending' or state='sending' and lease_until<now()) and next_attempt_at<=now() order by next_attempt_at limit 1 for update skip locked;
  if l.id is null then return null;end if;
  select * into c from public.korlix_schedule_connections where id=l.connection_id;
  if c.state<>'connected' or not public.korlix_schedule_active_v1(l.host_id) then update public.korlix_schedule_calendar_links set state='failed',last_error='Calendar access is unavailable. Reconnect to resume future updates.' where id=l.id;return null;end if;
  if l.creation_attempted and l.provider_event_id is null and l.first_attempt_at<now()-interval '15 minutes' then update public.korlix_schedule_calendar_links set state='uncertain',last_error='Creation could not be confirmed. Check the external calendar before making changes.' where id=l.id;return null;end if;
  if l.provider_deleted and not l.removed then
   update public.korlix_schedule_calendar_links set generation=generation+1,provider_deleted=false,provider_event_id=null,create_wire=null,creation_attempted=false,first_attempt_at=null where id=l.id returning * into l;
  end if;
  update public.korlix_schedule_calendar_links set state='sending',lease_id=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()) where id=l.id returning * into l;
  select * into b from public.korlix_schedule_bookings where id=l.booking_id;
  return to_jsonb(l)||jsonb_build_object('booking',public.korlix_schedule_booking_public_v1(b),'connection',to_jsonb(c));
 end if;
 select * into l from public.korlix_schedule_calendar_links where id=p_id and lease_id=p_lease and state='sending' and lease_until>now() for update;
 if l.id is null then return null;end if;
 if p_action='prepare' then
  select * into b from public.korlix_schedule_bookings where id=l.booking_id;
  if not l.creation_attempted and (l.removed or b.state in ('canceled','payment_failed')) then update public.korlix_schedule_calendar_links set state='synced',synced_revision=desired_revision,lease_until=null where id=l.id;return null;end if;
  if l.create_wire is null then update public.korlix_schedule_calendar_links set create_wire=p_data->'wire',creation_attempted=true where id=l.id returning * into l;end if;
  return to_jsonb(l)||jsonb_build_object('booking',public.korlix_schedule_booking_public_v1(b));
 elsif p_action='created' then
  update public.korlix_schedule_calendar_links set provider_event_id=p_data->>'event_id' where id=l.id;return jsonb_build_object('saved',true);
 elsif p_action='finish' then
  if p_data->>'state'='synced' then
   update public.korlix_schedule_calendar_links set provider_deleted=coalesce((p_data->>'deleted')::boolean,false),provider_event_id=coalesce(p_data->>'event_id',provider_event_id),synced_revision=(p_data->>'revision')::int,state=case when desired_revision=(p_data->>'revision')::int then 'synced' else 'pending' end,lease_until=null,next_attempt_at=now(),last_error=null where id=l.id;
  else
   update public.korlix_schedule_calendar_links set state=case when l.attempts>=5 then 'uncertain' else 'pending' end,provider_event_id=coalesce(p_data->>'event_id',provider_event_id),lease_until=null,next_attempt_at=now()+make_interval(secs=>least(900,30*power(2,l.attempts)::int)),last_error='Calendar update not confirmed. It will retry while it is safe to do so.' where id=l.id;
  end if;
  return jsonb_build_object('saved',true);
 end if;
 raise exception 'Unsupported calendar queue action.';
end;
$$;

create function public.korlix_schedule_payment_v2(p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare pay public.korlix_schedule_payments; b public.korlix_schedule_bookings; e public.korlix_schedule_events; assigned uuid[]; c public.korlix_schedule_connections; actor uuid;
begin
 if p_action='event_received' then
  insert into public.korlix_schedule_payment_receipts(provider_event_id,account_id,kind)values(p_data->>'event_id',p_data->>'account_id',p_data->>'kind')on conflict do nothing;return jsonb_build_object('recorded',true);
 end if;
 if p_action='due' then return coalesce((select jsonb_agg(to_jsonb(q)) from (select p.booking_id from public.korlix_schedule_payments p join public.korlix_schedule_bookings booked on booked.id=p.booking_id where p.next_check_at<=now() and (p.payment_state='unpaid' or p.refund_state in ('required','sending','pending')) and (p.refund_state in ('required','sending','pending') or booked.state='awaiting_payment' or p.checkout_id is not null and p.created_at>now()-interval '2 days') order by p.next_check_at limit 10)q),'[]');end if;
 if p_action='lookup' then
  select * into pay from public.korlix_schedule_payments where account_id=p_data->>'account_id' and (checkout_id=p_data->>'checkout_id' or payment_intent_id=p_data->>'payment_intent_id');
  return case when pay.booking_id is null then null else jsonb_build_object('booking_id',pay.booking_id) end;
 end if;
 select * into b from public.korlix_schedule_bookings where id=p_id;
 if b.id is null then raise exception using errcode='P0002',message='Payment booking not found.';end if;
 perform public.korlix_schedule_lock_hosts_v2(b.event_id,b.id);
 select * into b from public.korlix_schedule_bookings where id=p_id for update;
 select * into pay from public.korlix_schedule_payments where booking_id=b.id for update;
 if pay.booking_id is null then raise exception 'This booking does not require payment.';end if;
 select * into c from public.korlix_schedule_connections where id=pay.connection_id;
 if p_action='private' then return to_jsonb(pay)||jsonb_build_object('booking',to_jsonb(b),'connection',to_jsonb(c));end if;
 if p_action='checkout_wire' then
  if pay.checkout_wire is null then update public.korlix_schedule_payments set checkout_wire=p_data->>'wire' where booking_id=b.id returning * into pay;end if;
  return to_jsonb(pay.checkout_wire);
 elsif p_action='checkout_saved' then
  if pay.checkout_id is not null and pay.checkout_id<>p_data->>'checkout_id' then raise exception 'Another checkout is already linked to this booking.';end if;
  update public.korlix_schedule_payments set checkout_id=p_data->>'checkout_id',checkout_url=p_data->>'checkout_url' where booking_id=b.id;
 elsif p_action='observe' then
  if pay.account_id<>p_data->>'account_id' or pay.checkout_id is distinct from p_data->>'checkout_id' or pay.livemode is distinct from (p_data->>'livemode')::boolean or pay.amount_cents is distinct from (p_data->>'amount_cents')::int or pay.currency is distinct from p_data->>'currency' then raise exception 'Payment verification did not match this booking.';end if;
  update public.korlix_schedule_payments set checkout_closed=checkout_closed or coalesce((p_data->>'expired')::boolean,false) or coalesce((p_data->>'paid')::boolean,false),checked_at=now(),next_check_at=now()+interval '2 minutes' where booking_id=b.id;
  if p_data->>'paid'='true' then
   if pay.payment_state<>'unpaid' then return public.korlix_schedule_booking_public_v1(b);end if;
   if coalesce(p_data->>'payment_intent_id','') !~ '^pi_[A-Za-z0-9]+$' then raise exception 'Payment reference is missing.';end if;
   select * into e from public.korlix_schedule_events where id=b.event_id;
   select array_agg(host_id order by host_id) into assigned from public.korlix_schedule_booking_hosts where booking_id=b.id;
   if b.state='awaiting_payment' and b.hold_expires_at>now() and b.starts_at>now() and public.korlix_schedule_active_v1(b.owner_id) and c.state='connected' and p_data->>'calendars_checked'='true'
    and e.revision=(b.snapshot->>'revision')::int and e.state='published' and assigned<@public.korlix_schedule_event_hosts_v2(e) and cardinality(assigned)>0 and not exists(select 1 from unnest(assigned)h where not public.korlix_schedule_host_free_v2(h,e,b.starts_at,b.ends_at,b.id)) then
    update public.korlix_schedule_bookings set state='confirmed',hold_expires_at=null,revision=revision+1 where id=b.id returning * into b;
    update public.korlix_schedule_payments set payment_state='paid',payment_intent_id=p_data->>'payment_intent_id' where booking_id=b.id;
    perform public.korlix_schedule_calendar_enqueue_v2(b.id);perform public.korlix_schedule_enqueue_v1(b,'confirmation');
    insert into public.korlix_schedule_audit(owner_id,booking_id,event_id,action)values(b.owner_id,b.id,b.event_id,'payment_confirmed');
   elsif p_data->>'calendars_checked'<>'true' and b.state='awaiting_payment' and b.hold_expires_at>now() then
    -- A temporary provider outage is retried while the original hold remains active.
    return public.korlix_schedule_booking_public_v1(b);
   else
    update public.korlix_schedule_bookings set state='payment_failed',hold_expires_at=null,revision=revision+1 where id=b.id returning * into b;
    update public.korlix_schedule_payments set payment_state='paid_unfulfilled',payment_intent_id=p_data->>'payment_intent_id',refund_state='required',refund_requested_at=now(),refund_reason='Appointment could not be confirmed',next_check_at=now() where booking_id=b.id;
    insert into public.korlix_schedule_audit(owner_id,booking_id,event_id,action)values(b.owner_id,b.id,b.event_id,'payment_refund_required');
   end if;
  elsif p_data->>'expired'='true' or b.hold_expires_at<=now() then
   if b.state='awaiting_payment' then update public.korlix_schedule_bookings set state='payment_failed',hold_expires_at=null,revision=revision+1 where id=b.id returning * into b;end if;
  end if;
 elsif p_action='refund_request' then
  actor:=(p_data->>'actor')::uuid;
  if actor<>b.owner_id or not public.korlix_schedule_active_v1(actor) then raise exception using errcode='42501',message='Only the booking organizer can refund this payment.';end if;
  if p_data->>'confirmed' is distinct from 'true' or b.revision<>(p_data->>'revision')::int or pay.payment_state<>'paid' or c.state<>'connected' then raise exception 'Review the current booking and payment before refunding.';end if;
  if pay.refund_state='none' then
   update public.korlix_schedule_payments set refund_state='required',refund_requested_at=now(),refund_reason='Requested by booking organizer',next_check_at=now() where booking_id=b.id;
   if b.state<>'canceled' then update public.korlix_schedule_bookings set state='canceled',revision=revision+1 where id=b.id returning * into b;perform public.korlix_schedule_calendar_enqueue_v2(b.id);perform public.korlix_schedule_enqueue_v1(b,'cancellation');end if;
   insert into public.korlix_schedule_audit(owner_id,booking_id,event_id,action)values(actor,b.id,b.event_id,'full_refund_requested');
  end if;
 elsif p_action='refund_claim' then
  if pay.refund_state not in ('required','sending','pending') or pay.lease_until>now() then return null;end if;
  if pay.refund_requested_at<now()-interval '20 hours' and pay.refund_id is null then update public.korlix_schedule_payments set refund_state='uncertain' where booking_id=b.id;return null;end if;
  update public.korlix_schedule_payments set refund_state='sending',lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes',refund_attempts=refund_attempts+1,next_check_at=now()+interval '5 minutes' where booking_id=b.id returning * into pay;
  return to_jsonb(pay)||jsonb_build_object('connection',to_jsonb(c));
 elsif p_action='refund_finish' then
  if pay.lease_id is distinct from (p_data->>'lease_id')::uuid or pay.lease_until<=now() then return null;end if;
  if coalesce(p_data->>'state','') not in ('pending','succeeded','failed','uncertain') then raise exception 'Invalid refund result.';end if;
  update public.korlix_schedule_payments set refund_state=p_data->>'state',refund_id=coalesce(p_data->>'refund_id',refund_id),payment_state=case when p_data->>'state'='succeeded' then 'refunded' else payment_state end,lease_until=null where booking_id=b.id;
 elsif p_action='refund_observed' then
  if pay.account_id<>p_data->>'account_id' or pay.payment_intent_id<>p_data->>'payment_intent_id' or (p_data->>'refunded_cents')::int<>pay.amount_cents then raise exception 'Refund verification did not match.';end if;
  update public.korlix_schedule_payments set refund_state='succeeded',payment_state='refunded' where booking_id=b.id;
 else raise exception 'Unsupported payment action.';end if;
 return public.korlix_schedule_booking_public_v1(b);
end;
$$;

create function public.korlix_schedule_ai_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_schedule_ai_plans; p public.korlix_schedule_profiles; b public.korlix_schedule_bookings; e public.korlix_schedule_events; v_result jsonb;
begin
 if not public.korlix_schedule_active_v1(p_actor) then raise exception using errcode='42501',message='Sign in with an active account.';end if;
 -- Take multi-host locks before the actor/profile lock, consistently with bookings.
 if p_action='apply' then
  select * into a from public.korlix_schedule_ai_plans where id=p_id and owner_id=p_actor;
  if a.plan->>'action' in ('reschedule','cancel') then
   select * into b from public.korlix_schedule_bookings where id=(a.plan->>'booking_id')::uuid and (owner_id=p_actor or exists(select 1 from public.korlix_schedule_booking_hosts where booking_id=(a.plan->>'booking_id')::uuid and host_id=p_actor));
   if b.id is null then raise exception using errcode='P0002',message='Booking unavailable.';end if;
   perform public.korlix_schedule_lock_hosts_v2(b.event_id,b.id);
  end if;
 end if;
 perform 1 from public.user_profiles where id=p_actor for update;
 select * into p from public.korlix_schedule_profiles where owner_id=p_actor;
 if p.owner_id is null then raise exception 'Save your host profile first.';end if;
 if p_action='start' then
  select * into a from public.korlix_schedule_ai_plans where owner_id=p_actor and request_id=(p_data->>'request_id')::uuid;
  if a.id is not null then
   if a.prompt is distinct from p_data->>'prompt' then raise exception using errcode='40001',message='This AI request changed. Start a new proposal.';end if;
   return to_jsonb(a)-'owner_id'-'prompt';
  end if;
  if (select count(*) from public.korlix_schedule_ai_plans where owner_id=p_actor and created_at>now()-interval '1 day')>=10 then raise exception using errcode='54000',message='Your ten daily scheduling AI requests have been used. Try again tomorrow.';end if;
  insert into public.korlix_schedule_ai_plans(id,owner_id,request_id,prompt,profile_revision)values(p_id,p_actor,(p_data->>'request_id')::uuid,p_data->>'prompt',p.revision)returning * into a;
  return to_jsonb(a)-'owner_id'-'prompt';
 end if;
 select * into a from public.korlix_schedule_ai_plans where id=p_id and owner_id=p_actor for update;
 if a.id is null then raise exception using errcode='P0002',message='Scheduling proposal not found.';end if;
 if p_action='get' then return to_jsonb(a)-'owner_id'-'prompt';end if;
 if p_action='failed' then update public.korlix_schedule_ai_plans set state='failed' where id=a.id and state='generating';return null;end if;
 if p_action='ready' then
  if a.state<>'generating' or a.expires_at<=now() then raise exception 'This proposal expired. Ask KORLIX again.';end if;
  update public.korlix_schedule_ai_plans set state='review',plan=p_data->'plan' where id=a.id returning * into a;
  return to_jsonb(a)-'owner_id'-'prompt';
 end if;
 if p_action<>'apply' then raise exception 'Unsupported scheduling AI action.';end if;
 if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and approve this scheduling change.';end if;
 if a.state='applied' then return to_jsonb(a)-'owner_id'-'prompt';end if;
 if a.state<>'review' or a.expires_at<=now() or a.profile_revision<>p.revision then raise exception using errcode='40001',message='This proposal is stale. Ask KORLIX for a new proposal.';end if;
 case a.plan->>'action'
 when 'draft' then v_result:=public.korlix_schedule_owner_v1(p_actor,'save_event',null,a.plan->'data');
 when 'availability' then v_result:=public.korlix_schedule_owner_v1(p_actor,'save_profile',null,a.plan->'data');
 when 'cancel' then v_result:=public.korlix_schedule_owner_v1(p_actor,'booking_state',b.id,jsonb_build_object('state','canceled','confirmed',true,'revision',a.plan->'booking_revision'));
 when 'reschedule' then
  select * into e from public.korlix_schedule_events where id=b.event_id;
  v_result:=public.korlix_schedule_public_v1('reschedule',null,jsonb_build_object('booking_id',b.id,'manage_hash',b.manage_hash,'confirmed',true,'revision',a.plan->'booking_revision','event_revision',a.plan->'event_revision','starts_at',a.plan->'starts_at'));
 else raise exception 'This proposal provides information and does not change your schedule.';
 end case;
 update public.korlix_schedule_ai_plans set state='applied',result=v_result where id=a.id returning * into a;
 return to_jsonb(a)-'owner_id'-'prompt';
end;
$$;

do $$ declare t text; f record; begin
 foreach t in array array['korlix_schedule_teams','korlix_schedule_members','korlix_schedule_booking_hosts','korlix_schedule_connections','korlix_schedule_oauth','korlix_schedule_calendar_windows','korlix_schedule_calendar_links','korlix_schedule_payments','korlix_schedule_payment_receipts','korlix_schedule_ai_plans'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and (proname like 'korlix_schedule_%_v2' or proname like 'korlix_schedule_%_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
