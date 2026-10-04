-- Contract Radar monitoring: service-owned actors, opt-in, no AI jobs or credits.
create table public.korlix_radar_monitor_settings (
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default false, timezone text not null default 'America/New_York',
 digest_time time not null default '09:00', deadline_days jsonb not null default '[7,3,1]',
 version int not null default 1, last_run_day date, last_checked_at timestamptz, last_error text,
 lease_token uuid, lease_until timestamptz, next_attempt_at timestamptz,
 updated_at timestamptz not null default now()
);
create index korlix_radar_monitor_due on public.korlix_radar_monitor_settings(next_attempt_at,lease_until) where enabled;
create table public.korlix_radar_searches (
 id uuid primary key,user_id uuid not null references public.korlix_radar_monitor_settings(user_id) on delete cascade,
 name text not null check(length(name) between 1 and 80),query text not null default '' check(length(query)<=160),
 naics text not null default '' check(naics='' or naics ~ '^\d{2,6}$'),state text not null default '' check(state='' or state ~ '^[A-Z]{2}$'),
 enabled boolean not null default true,last_checked_at timestamptz,last_error text,
 result jsonb not null default '{}' check(octet_length(result::text)<=500000),
 created_at timestamptz not null default now(),check(query<>'' or naics<>'')
);
create index korlix_radar_searches_owner on public.korlix_radar_searches(user_id,created_at);
create table public.korlix_radar_alerts (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.korlix_radar_monitor_settings(user_id) on delete cascade,
 event_key text not null check(length(event_key)<=300),kind text not null check(kind in('deadline','amendment','digest','search')),
 title text not null check(length(title)<=240),message text not null check(length(message)<=4000),
 source_url text not null default '' check(length(source_url)<=2000),data jsonb not null default '{}' check(octet_length(data::text)<=500000),
 created_at timestamptz not null default now(),read_at timestamptz,unique(user_id,event_key)
);
create index korlix_radar_alerts_owner on public.korlix_radar_alerts(user_id,created_at desc);
create table public.korlix_radar_watches (
 opportunity_id uuid primary key references public.korlix_radar_opportunities(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 revision text not null check(length(revision)<=64), snapshot jsonb not null check(octet_length(snapshot::text)<=12000),
 checked_at timestamptz not null default now()
);
create index korlix_radar_watches_owner on public.korlix_radar_watches(user_id,checked_at);
create table public.korlix_radar_request_limits (
 user_id uuid not null references auth.users(id) on delete cascade,day date not null default current_date,
 count int not null default 0 check(count>=0),automatic_count int not null default 0 check(automatic_count>=0),primary key(user_id,day)
);
alter table public.korlix_radar_monitor_settings enable row level security;
alter table public.korlix_radar_searches enable row level security;
alter table public.korlix_radar_alerts enable row level security;
alter table public.korlix_radar_watches enable row level security;
alter table public.korlix_radar_request_limits enable row level security;
revoke all on public.korlix_radar_monitor_settings,public.korlix_radar_searches,public.korlix_radar_alerts,public.korlix_radar_watches,public.korlix_radar_request_limits from public,anon,authenticated;
grant all on public.korlix_radar_monitor_settings,public.korlix_radar_searches,public.korlix_radar_alerts,public.korlix_radar_watches,public.korlix_radar_request_limits to service_role;

create function public.korlix_radar_monitor_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.korlix_radar_monitor_settings; x public.korlix_radar_searches; a public.korlix_radar_alerts;
 o public.korlix_radar_opportunities; w public.korlix_radar_watches; v jsonb; result jsonb; local_day date; days_left int; n int;
begin
 if p_action='claim' then
  select * into s from korlix_radar_monitor_settings ms where enabled
   and coalesce(lease_until,'-infinity')<now() and coalesce(next_attempt_at,'-infinity')<=now()
   and (now() at time zone timezone)::time>=digest_time
   and last_run_day is distinct from (now() at time zone timezone)::date
   order by coalesce(last_checked_at,'-infinity'),user_id for update skip locked limit 1;
  if not found then return null;end if;
  update korlix_radar_monitor_settings set lease_token=gen_random_uuid(),lease_until=now()+interval '10 minutes' where user_id=s.user_id returning * into s;
  return jsonb_build_object('settings',to_jsonb(s),'local_day',(now() at time zone s.timezone)::date,
   'searches',coalesce((select jsonb_agg(to_jsonb(z)) from korlix_radar_searches z where user_id=s.user_id and enabled),'[]'),
   'opportunities',coalesce((select jsonb_agg(to_jsonb(z)) from(select op.*,wa.revision as watch_revision,wa.snapshot as watch_snapshot from korlix_radar_opportunities op left join korlix_radar_watches wa on wa.opportunity_id=op.id where op.user_id=s.user_id and op.stage not in('won','closed') order by coalesce(wa.checked_at,'-infinity'),op.id limit 100)z),'[]'));
 end if;
 if p_actor is null then raise exception 'Sign in to use Contract Radar.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,222));
 if p_action='state' then
  return jsonb_build_object('settings',(select to_jsonb(z)-'lease_token'-'lease_until'-'next_attempt_at'-'user_id' from korlix_radar_monitor_settings z where user_id=p_actor),
   'searches',coalesce((select jsonb_agg(to_jsonb(z)-'user_id' order by created_at) from korlix_radar_searches z where user_id=p_actor),'[]'),
   'alerts',coalesce((select jsonb_agg(to_jsonb(z)-'user_id'-'event_key') from(select * from korlix_radar_alerts where user_id=p_actor and coalesce(data->>'hidden','false')<>'true' order by created_at desc limit 100)z),'[]'));
 elsif p_action='save_settings' then
  select * into s from korlix_radar_monitor_settings where user_id=p_actor for update;
  if coalesce(s.version,0)<>(p_data->>'version')::int then raise exception 'Monitoring settings changed. Refresh and try again.' using errcode='40001';end if;
  if not exists(select 1 from pg_timezone_names where name=p_data->>'timezone') then raise exception 'Choose a valid time zone.';end if;
  if p_data->>'digest_time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Choose a valid digest time.';end if;
  if jsonb_typeof(p_data->'deadline_days')<>'array' or jsonb_array_length(p_data->'deadline_days')>5 then raise exception 'Choose up to five deadline reminders.';end if;
  for v in select * from jsonb_array_elements(p_data->'deadline_days') loop
   if v::text !~ '^(0|1|3|7|14|30)$' then raise exception 'Choose supported deadline reminders.';end if;
  end loop;
  insert into korlix_radar_monitor_settings(user_id,enabled,timezone,digest_time,deadline_days)
   values(p_actor,(p_data->>'enabled')::boolean,p_data->>'timezone',(p_data->>'digest_time')::time,p_data->'deadline_days')
   on conflict(user_id) do update set enabled=excluded.enabled,timezone=excluded.timezone,digest_time=excluded.digest_time,deadline_days=excluded.deadline_days,
    version=korlix_radar_monitor_settings.version+1,lease_token=null,lease_until=null,next_attempt_at=null,updated_at=now();
  return public.korlix_radar_monitor_v1(p_actor,'state');
 elsif p_action='search_save' then
  insert into korlix_radar_monitor_settings(user_id) values(p_actor) on conflict do nothing;
  select * into x from korlix_radar_searches where id=p_id and user_id=p_actor;
  if found then
   if x.name<>p_data->>'name' or x.query<>p_data->>'query' or x.naics<>p_data->>'naics' or x.state<>p_data->>'state' or x.enabled<>(p_data->>'enabled')::boolean then raise exception 'Use a new request for changed search details.' using errcode='40001';end if;
   return to_jsonb(x)-'user_id';end if;
  select * into x from korlix_radar_searches where user_id=p_actor and lower(query)=lower(p_data->>'query') and naics=p_data->>'naics' and state=p_data->>'state' and enabled=(p_data->>'enabled')::boolean;
  if found then return to_jsonb(x)-'user_id';end if;
  if(select count(*) from korlix_radar_searches where user_id=p_actor)>=5 then raise exception 'Keep up to five saved searches. Remove one first.' using errcode='54000';end if;
  insert into korlix_radar_searches(id,user_id,name,query,naics,state,enabled) values(p_id,p_actor,p_data->>'name',p_data->>'query',p_data->>'naics',p_data->>'state',(p_data->>'enabled')::boolean) returning * into x;
  update korlix_radar_monitor_settings set version=version+1,lease_token=null,lease_until=null where user_id=p_actor;
  return to_jsonb(x)-'user_id';
 elsif p_action='search_delete' then
  delete from korlix_radar_searches where id=p_id and user_id=p_actor;
  if not found then raise exception 'This saved search was not found.' using errcode='P0002';end if;
  update korlix_radar_monitor_settings set version=version+1,lease_token=null,lease_until=null where user_id=p_actor;return '{}';
 elsif p_action='read' then
  update korlix_radar_alerts set read_at=coalesce(read_at,now()) where id=p_id and user_id=p_actor returning * into a;
  if not found then raise exception 'This alert was not found.' using errcode='P0002';end if;return to_jsonb(a)-'user_id'-'event_key';
 elsif p_action='read_all' then
  update korlix_radar_alerts set read_at=coalesce(read_at,now()) where user_id=p_actor;return '{}';
 elsif p_action='clear_alerts' then
  -- Keep event keys for deduplication; hide cleared history from API.
  update korlix_radar_alerts set read_at=coalesce(read_at,now()),data=data||'{"hidden":true}'::jsonb where user_id=p_actor;return '{}';
 elsif p_action='clear' then
  delete from korlix_radar_monitor_settings where user_id=p_actor;delete from korlix_radar_watches where user_id=p_actor;return '{}';
 elsif p_action='reserve_worker' then
  if (p_data->>'count')::int not in(1,2) then raise exception 'Invalid feed reservation.';end if;
  insert into korlix_radar_request_limits(user_id,day,automatic_count) values(p_actor,(now() at time zone 'UTC')::date,(p_data->>'count')::int)
   on conflict(user_id,day) do update set automatic_count=korlix_radar_request_limits.automatic_count+excluded.automatic_count returning automatic_count into n;
  if n>20 then raise exception 'Automatic SAM.gov checks reached the daily limit. Deadline reminders remain active.' using errcode='54000';end if;return '{}';
 elsif p_action='reserve_request' then
  delete from korlix_radar_request_limits where day<(now() at time zone 'UTC')::date-7;
  insert into korlix_radar_request_limits(user_id,day,count) values(p_actor,(now() at time zone 'UTC')::date,1)
   on conflict(user_id,day) do update set count=korlix_radar_request_limits.count+1 returning count into n;
  if n>40 then raise exception 'Direct search reached its daily limit. Try again tomorrow.' using errcode='54000';end if;return '{}';
 elsif p_action in('finish','failed') then
  select * into s from korlix_radar_monitor_settings where user_id=p_actor for update;
  if not found or not s.enabled or s.lease_token is distinct from (p_data->>'lease_token')::uuid or s.version<>(p_data->>'version')::int or s.lease_until<now() then return jsonb_build_object('stale',true);end if;
  if p_action='failed' then
   update korlix_radar_monitor_settings set lease_token=null,lease_until=null,next_attempt_at=now()+interval '1 hour',last_error='Monitoring was interrupted. It will retry automatically.',last_checked_at=now() where user_id=p_actor;return '{}';
  end if;
  local_day=(p_data->>'local_day')::date;
  delete from korlix_radar_request_limits where user_id=p_actor and day<(now() at time zone 'UTC')::date-7;
  for v in select * from jsonb_array_elements(coalesce(p_data->'searches','[]')) loop
   update korlix_radar_searches set result=coalesce(v->'result','{}'),last_error=v->>'error',last_checked_at=now() where id=(v->>'id')::uuid and user_id=p_actor and enabled;
  end loop;
  for v in select * from jsonb_array_elements(coalesce(p_data->'watches','[]')) loop
   select * into o from korlix_radar_opportunities where id=(v->>'id')::uuid and user_id=p_actor and stage not in('won','closed');if not found then continue;end if;
   select * into w from korlix_radar_watches where opportunity_id=o.id and user_id=p_actor;
   if coalesce(w.revision,o.data->>'revision') is not null and coalesce(w.revision,o.data->>'revision')<>v->'snapshot'->>'revision' then
    insert into korlix_radar_alerts(user_id,event_key,kind,title,message,source_url,data)
     values(p_actor,'amendment:'||o.id||':'||(v->'snapshot'->>'revision'),'amendment','Notice changed: '||left(o.data->>'title',210),
     'SAM.gov notice details changed. Recheck the official notice and amendments before bidding.',o.data->>'sourceUrl',jsonb_build_object('opportunity_id',o.id,'previous',coalesce(w.snapshot,o.data),'current',v->'snapshot')) on conflict do nothing;
   end if;
   insert into korlix_radar_watches(opportunity_id,user_id,revision,snapshot) values(o.id,p_actor,v->'snapshot'->>'revision',v->'snapshot')
    on conflict(opportunity_id) do update set revision=excluded.revision,snapshot=excluded.snapshot,checked_at=now();
  end loop;
  for o in select * from korlix_radar_opportunities where user_id=p_actor and stage not in('won','closed','submitted') loop
   select * into w from korlix_radar_watches where opportunity_id=o.id and user_id=p_actor;
   v=case when w.opportunity_id is not null then w.snapshot else o.data end;
   if v->>'deadline' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(v->>'active','true')<>'false' then
    days_left=(v->>'deadline')::date-local_day;
    if s.deadline_days @> to_jsonb(days_left) then
     insert into korlix_radar_alerts(user_id,event_key,kind,title,message,source_url,data)
      values(p_actor,'deadline:'||o.id||':'||(v->>'deadline')||':'||days_left,'deadline',left(o.data->>'title',200),
      case when days_left=0 then 'Deadline is today' else 'Deadline in '||days_left||' day(s)' end||' ('||(v->>'deadline')||'). Confirm the exact closing time on the official notice.',coalesce(o.data->>'sourceUrl',''),jsonb_build_object('opportunity_id',o.id,'deadline',v->>'deadline','days_left',days_left)) on conflict do nothing;
    end if;
   end if;
  end loop;
  insert into korlix_radar_alerts(user_id,event_key,kind,title,message,data)
   values(p_actor,'digest:'||local_day,'digest','Your daily Contract Radar update',left(p_data->>'message',4000),coalesce(p_data->'digest','{}')) on conflict do nothing;
  update korlix_radar_monitor_settings set last_run_day=local_day,last_checked_at=now(),last_error=p_data->>'error',lease_token=null,lease_until=null,next_attempt_at=null where user_id=p_actor;
  delete from korlix_radar_alerts where user_id=p_actor and created_at<now()-interval '180 days';
  return '{}';
 end if;
 raise exception 'Unknown radar monitoring operation.';
end $$;
revoke all on function public.korlix_radar_monitor_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_radar_monitor_v1(uuid,text,uuid,jsonb) to service_role;

-- Keep "Clear radar" atomic across legacy records and autonomous monitoring.
alter function public.korlix_radar_v1(uuid,text,uuid,jsonb) rename to korlix_radar_core_v1;
create function public.korlix_radar_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare result jsonb;
begin
 result=public.korlix_radar_core_v1(p_actor,p_action,p_id,p_data);
 if p_action='clear' then perform public.korlix_radar_monitor_v1(p_actor,'clear');end if;
 return result;
end $$;
revoke all on function public.korlix_radar_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_radar_v1(uuid,text,uuid,jsonb) to service_role;
