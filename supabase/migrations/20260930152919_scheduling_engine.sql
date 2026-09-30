-- Native scheduling. Only the authenticated backend may execute these commands.
create table public.korlix_schedule_profiles (
 owner_id uuid primary key references auth.users(id),
 display_name text not null check(length(trim(display_name)) between 1 and 100),
 timezone text not null,
 weekly jsonb not null default '[]',
 overrides jsonb not null default '[]',
 notifications_enabled boolean not null default false,
 notification_email text,
 reminder_minutes integer not null default 60 check(reminder_minutes in (0,15,30,60,1440)),
 revision integer not null default 1,
 updated_at timestamptz not null default now()
);
create table public.korlix_schedule_events (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 slug text not null unique check(slug ~ '^[a-z0-9][a-z0-9-]{5,79}$'),
 title text not null check(length(trim(title)) between 1 and 120),
 description text not null default '' check(length(description)<=2000),
 kind text not null default 'one_to_one' check(kind in ('one_to_one','group')),
 duration_minutes integer not null check(duration_minutes between 5 and 480 and duration_minutes%5=0),
 interval_minutes integer not null default 30 check(interval_minutes between 5 and 120 and interval_minutes%5=0),
 buffer_before integer not null default 0 check(buffer_before between 0 and 120),
 buffer_after integer not null default 0 check(buffer_after between 0 and 120),
 notice_minutes integer not null default 240 check(notice_minutes between 0 and 10080),
 horizon_days integer not null default 60 check(horizon_days between 1 and 365),
 daily_limit integer not null default 8 check(daily_limit between 1 and 100),
 capacity integer not null default 1 check(capacity between 1 and 100),
 cancel_notice_minutes integer not null default 60 check(cancel_notice_minutes between 0 and 10080),
 location_kind text not null default 'custom' check(location_kind in ('video','phone','in_person','custom')),
 location_detail text not null default '' check(length(location_detail)<=500),
 questions jsonb not null default '[]',
 color text not null default '#72D6EB' check(color ~ '^#[a-fA-F0-9]{6}$'),
 state text not null default 'draft' check(state in ('draft','published','paused','archived')),
 revision integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(kind<>'one_to_one' or capacity=1)
);
create index korlix_schedule_events_owner_idx on public.korlix_schedule_events(owner_id);
create table public.korlix_schedule_blocks (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 label text not null default 'Unavailable' check(length(label) between 1 and 120),
 check(isfinite(starts_at) and isfinite(ends_at) and ends_at>starts_at and ends_at<=starts_at+interval '366 days')
);
create index korlix_schedule_blocks_owner_time_idx on public.korlix_schedule_blocks(owner_id,starts_at,ends_at);
create table public.korlix_schedule_bookings (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 event_id uuid not null references public.korlix_schedule_events(id),
 request_id uuid not null unique,
 request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
 manage_hash text not null check(manage_hash ~ '^[a-f0-9]{64}$'),
 sealed_manage_token text,
 guest_name text not null check(length(trim(guest_name)) between 1 and 100),
 guest_email text not null check(length(guest_email) between 3 and 254),
 guest_timezone text not null,
 answers jsonb not null default '{}',
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 busy_start timestamptz not null,
 busy_end timestamptz not null,
 cancel_until timestamptz not null,
 state text not null default 'confirmed' check(state in ('confirmed','canceled','completed','no_show')),
 snapshot jsonb not null,
 revision integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(isfinite(starts_at) and isfinite(ends_at) and ends_at>starts_at and ends_at<=starts_at+interval '8 hours'),
 check(busy_start<=starts_at and busy_end>=ends_at)
);
create index korlix_schedule_bookings_owner_time_idx on public.korlix_schedule_bookings(owner_id,starts_at,ends_at);
create index korlix_schedule_bookings_event_idx on public.korlix_schedule_bookings(event_id,starts_at) where state<>'canceled';
create table public.korlix_schedule_contexts (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 browser_hash text not null check(browser_hash ~ '^[a-f0-9]{64}$'),
 event_id uuid not null references public.korlix_schedule_events(id),
 event_revision integer not null,
 profile_revision integer not null,
 expires_at timestamptz not null default now()+interval '20 minutes',
 created_at timestamptz not null default now()
);
create index korlix_schedule_contexts_event_expiry_idx on public.korlix_schedule_contexts(event_id,expires_at);
create table public.korlix_schedule_audit (
 id bigint generated always as identity primary key,
 owner_id uuid not null references auth.users(id),
 event_id uuid references public.korlix_schedule_events(id),
 booking_id uuid references public.korlix_schedule_bookings(id),
 action text not null,
 created_at timestamptz not null default now()
);
create index korlix_schedule_audit_owner_idx on public.korlix_schedule_audit(owner_id,created_at);
create index korlix_schedule_audit_event_idx on public.korlix_schedule_audit(event_id);
create index korlix_schedule_audit_booking_idx on public.korlix_schedule_audit(booking_id);
create table public.korlix_schedule_notifications (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 booking_id uuid not null references public.korlix_schedule_bookings(id),
 booking_revision integer not null,
 kind text not null check(kind in ('confirmation','reschedule','cancellation','reminder')),
 recipient_role text not null check(recipient_role in ('host','guest')),
 payload jsonb not null,
 wire text,
 due_at timestamptz not null,
 state text not null default 'pending' check(state in ('pending','sending','accepted','failed','uncertain','skipped')),
 lease_id uuid,
 lease_until timestamptz,
 attempts integer not null default 0,
 first_attempt_at timestamptz,
 provider_id text,
 accepted_at timestamptz,
 created_at timestamptz not null default now(),
 unique(booking_id,booking_revision,kind,recipient_role)
);
create index korlix_schedule_notifications_due_idx on public.korlix_schedule_notifications(due_at) where state in ('pending','sending');
create index korlix_schedule_notifications_owner_idx on public.korlix_schedule_notifications(owner_id,first_attempt_at);

create function public.korlix_schedule_active_v1(p_actor uuid) returns boolean
language sql stable security invoker set search_path=public,pg_temp as $$
 -- The backend verifies identity/email on every host route. Public bookings use
 -- the already-published page and the authoritative current disabled flag.
 select exists(select 1 from public.user_profiles p where p.id=p_actor and p.is_disabled is not true);
$$;
create function public.korlix_schedule_windows_valid_v1(p_windows jsonb) returns boolean
language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare w jsonb; last_end integer:=0;
begin
 if jsonb_typeof(p_windows) is distinct from 'array' or jsonb_array_length(p_windows)>8 then return false; end if;
 for w in select value from jsonb_array_elements(p_windows) loop
  if jsonb_typeof(w) is distinct from 'array' or jsonb_array_length(w)<>2
   or jsonb_typeof(w->0) is distinct from 'number' or jsonb_typeof(w->1) is distinct from 'number'
   or (w->>0)!~'^[0-9]{1,4}$' or (w->>1)!~'^[0-9]{1,4}$' then return false; end if;
  if (w->>0)::int<last_end or (w->>0)::int%5<>0 or (w->>1)::int%5<>0
   or (w->>1)::int<= (w->>0)::int or (w->>1)::int>1440 then return false; end if;
  last_end:=(w->>1)::int;
 end loop;
 return true;
end;
$$;
create function public.korlix_schedule_event_public_v1(e public.korlix_schedule_events) returns jsonb
language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('slug',e.slug,'title',e.title,'description',e.description,'kind',e.kind,
 'duration_minutes',e.duration_minutes,'location_kind',e.location_kind,'questions',e.questions,'color',e.color,
 'cancel_notice_minutes',e.cancel_notice_minutes,'capacity',e.capacity,'horizon_days',e.horizon_days,
 'host_name',p.display_name,'host_timezone',p.timezone,'revision',e.revision) from public.korlix_schedule_profiles p where p.owner_id=e.owner_id;
$$;
create function public.korlix_schedule_booking_public_v1(b public.korlix_schedule_bookings) returns jsonb
language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('id',b.id,'event_id',b.event_id,'guest_name',b.guest_name,'guest_email',b.guest_email,
 'guest_timezone',b.guest_timezone,'answers',b.answers,'starts_at',b.starts_at,'ends_at',b.ends_at,
 'cancel_until',b.cancel_until,'state',b.state,'snapshot',b.snapshot,'revision',b.revision,'created_at',b.created_at,
 'event_slug',(select slug from public.korlix_schedule_events where id=b.event_id),
 'notifications',coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'state',state,'due_at',due_at)) from public.korlix_schedule_notifications where booking_id=b.id and booking_revision=b.revision and recipient_role='guest'),'[]'));
$$;

create function public.korlix_schedule_enqueue_v1(b public.korlix_schedule_bookings,p_kind text) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
declare p public.korlix_schedule_profiles; recipient text; target text;
begin
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

-- The same function is used for display and final booking validation under the host lock.
create function public.korlix_schedule_slots_v1(p_event uuid,p_from date,p_days integer default 7,p_exclude uuid default null)
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
    if exists(select 1 from public.korlix_schedule_blocks where owner_id=e.owner_id and starts_at<fin+make_interval(mins=>e.buffer_after) and ends_at>s-make_interval(mins=>e.buffer_before)) then continue; end if;
    if exists(select 1 from public.korlix_schedule_bookings b where b.owner_id=e.owner_id and b.state<>'canceled' and b.id is distinct from p_exclude
     and b.busy_start<fin+make_interval(mins=>e.buffer_after) and b.busy_end>s-make_interval(mins=>e.buffer_before)
     and not(e.kind='group' and b.event_id=e.id and b.starts_at=s and b.ends_at=fin)) then continue; end if;
    select count(*) into seats from public.korlix_schedule_bookings where event_id=e.id and starts_at=s and ends_at=fin and state<>'canceled' and id is distinct from p_exclude;
    if seats>=e.capacity or (daily>=e.daily_limit and seats=0) then continue; end if;
    result:=result||jsonb_build_array(jsonb_build_object('starts_at',s,'ends_at',fin,'seats_left',e.capacity-seats));
   end loop;
  end loop;
 end loop;
 return result;
end;
$$;

create function public.korlix_schedule_owner_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare p public.korlix_schedule_profiles; e public.korlix_schedule_events; b public.korlix_schedule_bookings; v_item jsonb; v_question jsonb;
begin
 if not public.korlix_schedule_active_v1(p_actor) then raise exception using errcode='42501',message='An active, verified KORLIX account is required.'; end if;
 -- Consistent lock order serializes every mutation of a host's schedule across all event types.
 perform 1 from public.user_profiles where id=p_actor for update;
 select * into p from public.korlix_schedule_profiles where owner_id=p_actor;
 if p_action='dashboard' then
  return jsonb_build_object('profile',case when p.owner_id is null then null else to_jsonb(p)-'owner_id' end,
   'events',coalesce((select jsonb_agg(to_jsonb(t)-'owner_id' order by t.created_at desc) from public.korlix_schedule_events t where owner_id=p_actor),'[]'),
   'bookings',coalesce((select jsonb_agg(public.korlix_schedule_booking_public_v1(t) order by t.starts_at) from (select * from public.korlix_schedule_bookings where owner_id=p_actor and ends_at>=now()-interval '90 days' order by starts_at limit 500)t),'[]'),
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
  if p_id is null then insert into public.korlix_schedule_events(owner_id,slug,title,duration_minutes) values(p_actor,p_data->>'slug',p_data->>'title',(p_data->>'duration_minutes')::int) returning * into e; end if;
  update public.korlix_schedule_events set title=p_data->>'title',description=p_data->>'description',kind=p_data->>'kind',duration_minutes=(p_data->>'duration_minutes')::int,
   interval_minutes=(p_data->>'interval_minutes')::int,buffer_before=(p_data->>'buffer_before')::int,buffer_after=(p_data->>'buffer_after')::int,
   notice_minutes=(p_data->>'notice_minutes')::int,horizon_days=(p_data->>'horizon_days')::int,daily_limit=(p_data->>'daily_limit')::int,
   capacity=(p_data->>'capacity')::int,cancel_notice_minutes=(p_data->>'cancel_notice_minutes')::int,location_kind=p_data->>'location_kind',location_detail=p_data->>'location_detail',
   questions=p_data->'questions',color=p_data->>'color',revision=case when p_id is null then 1 else revision+1 end,updated_at=now() where id=e.id returning * into e;
  insert into public.korlix_schedule_audit(owner_id,event_id,action)values(p_actor,e.id,'event_saved');
  return to_jsonb(e)-'owner_id';
 elsif p_action='event_state' then
  select * into e from public.korlix_schedule_events where id=p_id and owner_id=p_actor;
  if not found then raise exception using errcode='P0002',message='Event type not found.'; end if;
  if e.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This event type changed. Refresh before updating.'; end if;
  if p_data->>'confirmed' is distinct from 'true' or coalesce(p_data->>'state','') not in ('published','paused','archived') then raise exception 'Confirm this event change.'; end if;
  if p_data->>'state'='published' and not exists(select 1 from jsonb_array_elements(p.weekly)x where jsonb_array_length(x->'windows')>0) and not exists(select 1 from jsonb_array_elements(p.overrides)x where jsonb_array_length(x->'windows')>0) then raise exception 'Add some availability before publishing.'; end if;
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
  select * into b from public.korlix_schedule_bookings where id=p_id and owner_id=p_actor;
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  if p_action='booking_get' then return public.korlix_schedule_booking_public_v1(b); end if;
  if b.revision<>coalesce((p_data->>'revision')::int,-1) then raise exception using errcode='40001',message='This booking changed. Refresh before updating.'; end if;
  if p_data->>'confirmed' is distinct from 'true' or coalesce(p_data->>'state','') not in ('canceled','completed','no_show') then raise exception 'Confirm the booking status change.'; end if;
  if b.state='canceled' or (p_data->>'state' in ('completed','no_show') and b.starts_at>now()) then raise exception 'This status is unavailable for this booking.'; end if;
  update public.korlix_schedule_bookings set state=p_data->>'state',revision=revision+1,updated_at=now() where id=b.id returning * into b;
  if b.state='canceled' then perform public.korlix_schedule_enqueue_v1(b,'cancellation');
  else update public.korlix_schedule_notifications set state='skipped' where booking_id=b.id and state='pending'; end if;
  insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action) values(p_actor,b.event_id,b.id,'host_'||b.state);
  return public.korlix_schedule_booking_public_v1(b);
 end if;
 raise exception 'Unsupported scheduling action.';
end;
$$;

create function public.korlix_schedule_public_v1(p_action text,p_slug text default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare e public.korlix_schedule_events; p public.korlix_schedule_profiles; b public.korlix_schedule_bookings;
 c public.korlix_schedule_contexts; s timestamptz; slots jsonb; v_question jsonb; answer text; snapshot jsonb;
begin
 if p_action in ('manage','cancel','reschedule','manage_slots') then
  select * into b from public.korlix_schedule_bookings where id=(p_data->>'booking_id')::uuid and manage_hash=p_data->>'manage_hash' and ends_at>now()-interval '30 days';
  if not found then raise exception using errcode='P0002',message='This private booking link is unavailable.'; end if;
  if p_action='manage' then return public.korlix_schedule_booking_public_v1(b); end if;
  perform 1 from public.user_profiles where id=b.owner_id for update;
  select * into b from public.korlix_schedule_bookings where id=b.id;
  if b.state<>'confirmed' or b.cancel_until<=now() then raise exception using errcode='40001',message='Online changes are closed. Contact your host.'; end if;
  select * into e from public.korlix_schedule_events where id=b.event_id;
  select * into p from public.korlix_schedule_profiles where owner_id=b.owner_id;
  if p_action in ('manage_slots','reschedule') and (e.duration_minutes<>(b.snapshot->>'duration_minutes')::int
   or e.location_kind<>b.snapshot->>'location_kind' or e.location_detail<>b.snapshot->>'location_detail'
   or e.title<>b.snapshot->>'title' or e.questions<>b.snapshot->'questions') then
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
   update public.korlix_schedule_bookings set starts_at=s,ends_at=s+make_interval(mins=>e.duration_minutes),busy_start=s-make_interval(mins=>e.buffer_before),busy_end=s+make_interval(mins=>e.duration_minutes+e.buffer_after),
    cancel_until=s-make_interval(mins=>e.cancel_notice_minutes),snapshot=public.korlix_schedule_event_public_v1(e)||jsonb_build_object('location_detail',e.location_detail),revision=revision+1,updated_at=now() where id=b.id returning * into b;
  end if;
  insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action)values(b.owner_id,b.event_id,b.id,'guest_'||p_action);
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
 perform 1 from public.user_profiles where id=e.owner_id for update;
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
 if exists(select 1 from public.korlix_schedule_bookings where event_id=e.id and starts_at=s and state<>'canceled' and lower(guest_email)=lower(p_data->>'guest_email')) then raise exception using errcode='40001',message='This email already has a booking at that time. Use the existing private booking link.'; end if;
 if (select count(*) from public.korlix_schedule_bookings where owner_id=e.owner_id and created_at>now()-interval '1 day')>=1000 then raise exception using errcode='54000',message='This host has reached the daily booking limit.'; end if;
 snapshot:=public.korlix_schedule_event_public_v1(e)||jsonb_build_object('location_detail',e.location_detail);
 insert into public.korlix_schedule_bookings(owner_id,event_id,request_id,request_hash,manage_hash,sealed_manage_token,guest_name,guest_email,guest_timezone,answers,starts_at,ends_at,busy_start,busy_end,cancel_until,snapshot)
 values(e.owner_id,e.id,(p_data->>'request_id')::uuid,p_data->>'request_hash',p_data->>'manage_hash',p_data->>'sealed_manage_token',trim(p_data->>'guest_name'),lower(trim(p_data->>'guest_email')),p_data->>'guest_timezone',p_data->'answers',s,s+make_interval(mins=>e.duration_minutes),s-make_interval(mins=>e.buffer_before),s+make_interval(mins=>e.duration_minutes+e.buffer_after),s-make_interval(mins=>e.cancel_notice_minutes),snapshot) returning * into b;
  insert into public.korlix_schedule_audit(owner_id,event_id,booking_id,action)values(e.owner_id,e.id,b.id,'booking_confirmed');
 perform public.korlix_schedule_enqueue_v1(b,'confirmation');
 return public.korlix_schedule_booking_public_v1(b);
end;
$$;

create function public.korlix_schedule_queue_v1(p_action text,p_id uuid default null,p_lease uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare n public.korlix_schedule_notifications; b public.korlix_schedule_bookings; p public.korlix_schedule_profiles;
begin
 if p_action='claim' then
  -- Serialize quota accounting across workers; row leases survive process restarts.
  perform pg_advisory_xact_lock(817462039);
  update public.korlix_schedule_notifications set state='uncertain',lease_until=null
   where state in ('pending','sending') and first_attempt_at<now()-interval '20 hours';
  update public.korlix_schedule_notifications n1 set state='skipped',lease_until=null
   where (n1.state='pending' or (n1.state='sending' and n1.lease_until<now())) and not exists(
    select 1 from public.korlix_schedule_bookings b1 join public.korlix_schedule_profiles p1 on p1.owner_id=b1.owner_id
    where b1.id=n1.booking_id and b1.revision=n1.booking_revision and p1.notifications_enabled
     and public.korlix_schedule_active_v1(b1.owner_id)
     and (n1.kind='cancellation' and b1.state='canceled' or n1.kind<>'cancellation' and b1.state='confirmed' and b1.starts_at>now()));
  select * into n from public.korlix_schedule_notifications q
   where (q.state='pending' or (q.state='sending' and q.lease_until<now())) and q.due_at<=now()
    and (q.first_attempt_at is not null or (
      (select count(*) from public.korlix_schedule_notifications where first_attempt_at>now()-interval '1 day')<1000
      and (select count(*) from public.korlix_schedule_notifications where owner_id=q.owner_id and first_attempt_at>now()-interval '1 day')<100
      and (q.recipient_role='host' or (select count(*) from public.korlix_schedule_notifications where payload->>'to'=q.payload->>'to' and first_attempt_at>now()-interval '1 day')<20)))
   order by q.due_at,q.created_at limit 1 for update skip locked;
  if n.id is null then return null; end if;
  update public.korlix_schedule_notifications set state='sending',lease_id=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()) where id=n.id returning * into n;
  select * into b from public.korlix_schedule_bookings where id=n.booking_id;
  select * into p from public.korlix_schedule_profiles where owner_id=n.owner_id;
  return to_jsonb(n)||jsonb_build_object('sealed_manage_token',b.sealed_manage_token,'request_id',b.request_id,'host_email',p.notification_email);
 end if;
 select * into n from public.korlix_schedule_notifications where id=p_id and lease_id=p_lease and state='sending' and lease_until>now() for update;
 if n.id is null then return null; end if;
 if p_action='prepare' then
  select * into b from public.korlix_schedule_bookings where id=n.booking_id;
  select * into p from public.korlix_schedule_profiles where owner_id=n.owner_id;
  if not p.notifications_enabled or not public.korlix_schedule_active_v1(n.owner_id) or b.revision<>n.booking_revision
   or (n.kind='cancellation' and b.state<>'canceled') or (n.kind<>'cancellation' and (b.state<>'confirmed' or b.starts_at<=now())) then
   update public.korlix_schedule_notifications set state='skipped',lease_until=null where id=n.id;return null;
  end if;
  if n.wire is null then update public.korlix_schedule_notifications set wire=p_data->>'wire' where id=n.id returning * into n;end if;
  return to_jsonb(n.wire);
 elsif p_action='finish' then
  if p_data->>'state' not in ('pending','accepted','failed','skipped') then raise exception 'Invalid delivery state.';end if;
  update public.korlix_schedule_notifications set state=case when p_data->>'state'='pending' and (n.attempts>=5 or n.first_attempt_at<now()-interval '19 hours') then 'uncertain' else p_data->>'state' end,
   due_at=case when p_data->>'state'='pending' then now()+make_interval(secs=>least(3600,60*power(3,n.attempts)::int)) else due_at end,
   provider_id=p_data->>'provider_id',accepted_at=case when p_data->>'state'='accepted' then now() else accepted_at end,lease_until=null where id=n.id;
  return jsonb_build_object('saved',true);
 end if;
 raise exception 'Unknown queue action.';
end;
$$;

do $$ declare t text; f record; begin
 foreach t in array array['korlix_schedule_profiles','korlix_schedule_events','korlix_schedule_blocks','korlix_schedule_bookings','korlix_schedule_contexts','korlix_schedule_audit','korlix_schedule_notifications'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
 revoke update,delete on public.korlix_schedule_audit from service_role;
 revoke all on sequence public.korlix_schedule_audit_id_seq from public,anon,authenticated,service_role;
 grant usage,select on sequence public.korlix_schedule_audit_id_seq to service_role;
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname like 'korlix_schedule_%_v1' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
