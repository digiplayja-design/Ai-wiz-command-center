-- All receptionist records are private. The authenticated backend supplies the
-- actor and platform-admin decision; clients have no table or RPC privileges.
create table public.korlix_receptionist_settings (
 business_id uuid primary key references public.korlix_directory_businesses(id) on delete cascade,
 owner_id uuid not null references auth.users(id) on delete cascade,
 settings jsonb not null default '{}', version integer not null default 1,
 consent_at timestamptz, updated_at timestamptz not null default now()
);
create index korlix_receptionist_settings_owner on public.korlix_receptionist_settings(owner_id);
create table public.korlix_receptionist_lines (
 business_id uuid primary key references public.korlix_directory_businesses(id) on delete cascade,
 provider_id text not null unique, number text not null unique,
 connected_at timestamptz not null default now()
);
create table public.korlix_receptionist_calls (
 id uuid primary key, business_id uuid not null references public.korlix_directory_businesses(id) on delete cascade,
 owner_id uuid not null references auth.users(id) on delete cascade,
 provider_phone_id text not null, caller_number text not null default '',
 state text not null default 'active' check(state in('active','ended')),
 started_at timestamptz not null default now(), ended_at timestamptz,
 max_seconds integer not null check(max_seconds between 60 and 600), duration_seconds integer not null default 0,
 limits jsonb not null, snapshot jsonb not null,
 pending jsonb, booking jsonb, note jsonb, last_response text,
 turns integer not null default 0, input_tokens bigint not null default 0, output_tokens bigint not null default 0,
 lease uuid, lease_until timestamptz, end_reason text, handled_at timestamptz,
 constraint receptionist_duration check(duration_seconds between 0 and 600)
);
create index korlix_receptionist_calls_owner_date on public.korlix_receptionist_calls(owner_id,started_at desc);
create index korlix_receptionist_calls_business_date on public.korlix_receptionist_calls(business_id,started_at desc);
create index korlix_receptionist_calls_active on public.korlix_receptionist_calls(started_at) where state='active';
alter table public.korlix_receptionist_settings enable row level security;
alter table public.korlix_receptionist_lines enable row level security;
alter table public.korlix_receptionist_calls enable row level security;
revoke all on public.korlix_receptionist_settings,public.korlix_receptionist_lines,public.korlix_receptionist_calls from public,anon,authenticated;
grant all on public.korlix_receptionist_settings,public.korlix_receptionist_lines,public.korlix_receptionist_calls to service_role;

create function public.korlix_receptionist_meter(p_call uuid,p_ended boolean default false,p_seconds integer default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare c public.korlix_receptionist_calls%rowtype; seconds integer; result jsonb;
begin
 select * into c from public.korlix_receptionist_calls where id=p_call for update;
 if not found then raise exception 'REC404: Call not found.';end if;
 seconds:=greatest(c.duration_seconds,least(c.max_seconds,greatest(0,coalesce(p_seconds,ceil(extract(epoch from clock_timestamp()-c.started_at))::integer))));
 result:=public.korlix_live_convo_report_usage(c.id,c.owner_id,seconds,c.turns,c.input_tokens+c.output_tokens,
  c.input_tokens,c.output_tokens,0,0,0,0,(c.limits->>'monthlySeconds')::integer,(c.limits->>'monthlyTokens')::bigint,
  p_ended,case when p_ended then coalesce(c.end_reason,'receptionist_call_ended') else null end);
 if result->>'code'='session_not_found' then raise exception 'REC503: Call usage could not be recorded.';end if;
 update public.korlix_receptionist_calls set duration_seconds=seconds,
  state=case when p_ended then 'ended' else state end,
  ended_at=case when p_ended then coalesce(ended_at,clock_timestamp()) else ended_at end,
  pending=case when p_ended then null else pending end where id=c.id;
 return result;
end $$;

create function public.korlix_receptionist_command(p_actor uuid,p_admin boolean,p_action text,p_id uuid default null,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare b public.korlix_directory_businesses%rowtype;s public.korlix_receptionist_settings%rowtype;
 c public.korlix_receptionist_calls%rowtype;l public.korlix_receptionist_lines%rowtype;
 result jsonb;used integer;cap integer;seconds integer;eligible boolean;cfg jsonb;
begin
 if p_action='cleanup' then
  for c in select * from public.korlix_receptionist_calls where state='active' and started_at+make_interval(secs=>max_seconds+120)<now() order by started_at limit 100 for update skip locked loop
   update public.korlix_receptionist_calls set end_reason='duration_limit_or_missing_end_report' where id=c.id;
   perform public.korlix_receptionist_meter(c.id,true,c.max_seconds);
  end loop;
  -- Retain minimal duration totals for the month; remove caller content after 90 days.
  update public.korlix_receptionist_calls set caller_number='',note=null,booking=null,pending=null,last_response=null,snapshot='{}'
   where started_at<now()-interval '90 days' and (caller_number<>'' or note is not null or snapshot<>'{}');
  return '{"ok":true}';
 end if;
 if p_action='line_lookup' then
  select * into l from public.korlix_receptionist_lines where provider_id=p->>'provider_id';
  if not found then raise exception 'REC404: This phone line is not connected to a receptionist.';end if;
  return to_jsonb(l);
 end if;
 if p_action in('start','call_get','claim','finish','pending','confirm','check_lease','note','end','release') then
  if p_action='start' then
   select * into l from public.korlix_receptionist_lines where provider_id=p->>'provider_id';
   if not found then raise exception 'REC404: This phone line is not connected.';end if;
   select * into b from public.korlix_directory_businesses where id=l.business_id for update;
   select * into s from public.korlix_receptionist_settings where business_id=b.id;
   if b.state='hidden' or b.published is null or coalesce((s.settings->>'enabled')::boolean,false)=false or s.consent_at is null then raise exception 'REC409: The business receptionist is paused.';end if;
   -- Serialize call admission across all businesses belonging to this owner.
   perform 1 from public.user_profiles where id=b.owner_id and lower(trim(tier))='enterprise' and is_disabled is not true for update;
   if not found then raise exception 'REC402: AI Receptionist requires an active Enterprise account.';end if;
   select * into c from public.korlix_receptionist_calls where id=p_id;
   if found then
    if c.business_id<>b.id or c.provider_phone_id<>l.provider_id then raise exception 'REC403: Call identity does not match.';end if;
    return to_jsonb(c);
   end if;
   if exists(select 1 from public.korlix_receptionist_calls where owner_id=b.owner_id and state='active' and started_at+make_interval(secs=>max_seconds+120)>now()) then raise exception 'REC409: The receptionist is handling another call. Please try again shortly.';end if;
   select coalesce(sum(case when state='active' then max_seconds else duration_seconds end),0)::integer into used
    from public.korlix_receptionist_calls where business_id=b.id and started_at>=date_trunc('month',now());
   cap:=least(1200,greatest(1,(s.settings->>'monthly_minutes')::integer))*60;
   seconds:=least((s.settings->>'max_call_minutes')::integer*60,cap-used,coalesce((p->>'remaining_seconds')::integer,0));
   if seconds<60 then raise exception 'REC429: This business has reached its receptionist time limit.';end if;
   result:=public.korlix_live_convo_reserve_session(p_id,b.owner_id,p->'limits'->>'tier',
    (p->'limits'->>'monthlySessions')::integer,(p->'limits'->>'monthlySeconds')::integer,(p->'limits'->>'monthlyTokens')::bigint,seconds,100);
   if coalesce((result->>'allowed')::boolean,false)=false then raise exception 'REC429: The business voice allowance is unavailable.';end if;
   insert into public.korlix_receptionist_calls(id,business_id,owner_id,provider_phone_id,caller_number,max_seconds,limits,snapshot)
    values(p_id,b.id,b.owner_id,l.provider_id,left(coalesce(p->>'caller_number',''),40),seconds,p->'limits',
     jsonb_build_object('business',b.published,'settings',s.settings)) returning * into c;
   return to_jsonb(c);
  end if;
  select * into c from public.korlix_receptionist_calls where id=p_id for update;
  if not found then raise exception 'REC404: Call not found.';end if;
  if p_action='call_get' then return to_jsonb(c);end if;
  if p_action='end' then
   if c.state='ended' then return '{"ok":true}';end if;
   -- Keep an in-flight lease so completed model usage can still be accounted
   -- for after the caller hangs up. The ended state blocks further actions.
   update public.korlix_receptionist_calls set end_reason=left(coalesce(p->>'reason','completed'),120) where id=c.id;
   perform public.korlix_receptionist_meter(c.id,true,(p->>'seconds')::integer);
   return '{"ok":true}';
  end if;
  if p_action in('finish','release') then
   if c.lease is null or c.lease::text<>p->>'lease' or c.lease_until<clock_timestamp() then raise exception 'REC409: This answer has expired. Please try again.';end if;
   if p_action='release' then
    update public.korlix_receptionist_calls set lease=null,lease_until=null where id=c.id;
    return '{"ok":true}';
   end if;
   eligible:=c.state='active' and c.started_at+make_interval(secs=>c.max_seconds)>=clock_timestamp()
    and exists(select 1 from public.user_profiles where id=c.owner_id and lower(trim(tier))='enterprise' and is_disabled is not true)
    and exists(select 1 from public.korlix_receptionist_settings where business_id=c.business_id and settings->'enabled'='true'::jsonb)
    and exists(select 1 from public.korlix_directory_businesses where id=c.business_id and published is not null and state<>'hidden');
   update public.korlix_receptionist_calls set last_response=case when eligible then left(p->>'reply',2500) else last_response end,turns=turns+1,
    input_tokens=input_tokens+greatest(0,coalesce((p->>'input')::bigint,0)),output_tokens=output_tokens+greatest(0,coalesce((p->>'output')::bigint,0)),
    lease=null,lease_until=null where id=c.id;
   perform public.korlix_receptionist_meter(c.id,c.state='ended' or c.started_at+make_interval(secs=>c.max_seconds)<clock_timestamp(),case when c.state='ended' then c.duration_seconds else null end);
   return jsonb_build_object('ok',true,'deliver',eligible);
  end if;
  if c.state<>'active' or c.started_at+make_interval(secs=>c.max_seconds)<clock_timestamp() then raise exception 'REC409: This call has ended.';end if;
  if not exists(select 1 from public.user_profiles where id=c.owner_id and lower(trim(tier))='enterprise' and is_disabled is not true) then raise exception 'REC402: AI Receptionist requires Enterprise.';end if;
  select * into s from public.korlix_receptionist_settings where business_id=c.business_id;
  if coalesce((s.settings->>'enabled')::boolean,false)=false or not exists(select 1 from public.korlix_directory_businesses where id=c.business_id and published is not null and state<>'hidden') then raise exception 'REC409: This receptionist is paused.';end if;
  if p_action='claim' then
   if c.lease is not null and c.lease_until>clock_timestamp() then raise exception 'REC409: An answer is already being prepared.';end if;
   if c.turns>=100 then raise exception 'REC429: This call has reached its response limit.';end if;
   result:=public.korlix_receptionist_meter(c.id);
   if result->'allowed'='false'::jsonb then raise exception 'REC429: The business voice allowance has been reached.';end if;
   update public.korlix_receptionist_calls set lease=(p->>'lease')::uuid,lease_until=clock_timestamp()+interval '180 seconds' where id=c.id returning * into c;
   return to_jsonb(c);
  end if;
  if c.lease is null or c.lease::text<>p->>'lease' or c.lease_until<clock_timestamp() then raise exception 'REC409: This answer has expired. Please try again.';end if;
  if p_action='check_lease' then return to_jsonb(c);
  elsif p_action='pending' then
   if c.booking is not null then raise exception 'REC409: This call already has a confirmed booking.';end if;
   update public.korlix_receptionist_calls set pending=p->'pending' where id=c.id;
  elsif p_action='confirm' then
   if c.booking is not null then return c.booking;end if;
   if c.pending is null or c.last_response is distinct from c.pending->>'readback' or (c.pending->>'expires_at')::timestamptz<clock_timestamp() or p->'confirmed' is distinct from 'true'::jsonb then raise exception 'REC409: Read back and confirm the appointment before booking.';end if;
   if s.settings->'booking_enabled'<>'true'::jsonb or not (s.settings->'event_ids' ? (c.pending->>'event_id')) or not exists(select 1 from public.korlix_schedule_events where id=(c.pending->>'event_id')::uuid and owner_id=c.owner_id and state='published' and price_cents=0) then raise exception 'REC409: Phone booking is no longer available for that appointment.';end if;
   result:=public.korlix_schedule_public_v1('book',c.pending->>'slug',c.pending->'data');
   -- The management credential remains sealed in 2MEETU, never in the call inbox.
   result:=jsonb_build_object('id',result->'id','state',result->'state','starts_at',result->'starts_at','ends_at',result->'ends_at','guest_name',result->'guest_name','guest_email',result->'guest_email','event_title',c.pending->'event_title','timezone',c.pending->'timezone');
   update public.korlix_receptionist_calls set booking=result,pending=null where id=c.id;
   return result;
  elsif p_action='note' then
   update public.korlix_receptionist_calls set note=p->'note' where id=c.id;
  else raise exception 'REC400: Unsupported call action.';end if;
  return '{"ok":true}';
 end if;
 select * into b from public.korlix_directory_businesses where id=p_id for update;
 if not found then raise exception 'REC404: Business not found.';end if;
 if p_actor is null or (b.owner_id<>p_actor and not p_admin) then raise exception 'REC403: Only the business owner can manage this receptionist.';end if;
 select * into s from public.korlix_receptionist_settings where business_id=b.id;
 if p_action='pause' then
  update public.korlix_receptionist_settings set settings=jsonb_set(settings,'{enabled}','false'),version=version+1,updated_at=now() where business_id=b.id;
  return '{"ok":true}';
 end if;
 eligible:=exists(select 1 from public.user_profiles where id=b.owner_id and lower(trim(tier))='enterprise' and is_disabled is not true);
 if not eligible then raise exception 'REC402: AI Receptionist is available with Enterprise.';end if;
 if p_action='get' then
  return jsonb_build_object('settings',coalesce(s.settings,'{}'),'version',coalesce(s.version,0),'consent_at',s.consent_at,
   'published',b.published is not null and b.state<>'hidden','business_name',coalesce(b.published->>'name',b.draft->>'name'),
   'line',(select jsonb_build_object('number',number,'connected_at',connected_at) from public.korlix_receptionist_lines where business_id=b.id),
   'used_seconds',(select coalesce(sum(duration_seconds),0) from public.korlix_receptionist_calls where business_id=b.id and started_at>=date_trunc('month',now())),
   'calls',coalesce((select jsonb_agg(x) from(select id,started_at,ended_at,state,caller_number,duration_seconds,note,booking,end_reason,handled_at from public.korlix_receptionist_calls where business_id=b.id and started_at>=now()-interval '90 days' order by started_at desc limit 50)x),'[]'));
 elsif p_action='save' then
  if coalesce(s.version,0)<>(p->>'version')::integer then raise exception 'REC409: Settings changed. Refresh before saving.';end if;
  if jsonb_array_length(coalesce(p->'event_ids','[]'))>0 and exists(select 1 from jsonb_array_elements_text(p->'event_ids') x where not exists(select 1 from public.korlix_schedule_events e where e.id=x.value::uuid and e.owner_id=b.owner_id and e.state='published' and e.price_cents=0)) then raise exception 'REC409: Choose your own published appointment types without an online payment requirement.';end if;
  if p->'enabled'='true'::jsonb and (p->'processing_consent'<>'true'::jsonb or b.published is null or b.state='hidden') then raise exception 'REC409: Publish your Business Passport and accept call processing before enabling.';end if;
  cfg:=p-'version';
  insert into public.korlix_receptionist_settings(business_id,owner_id,settings,consent_at) values(b.id,b.owner_id,cfg,case when p->'processing_consent'='true'::jsonb then now() end)
   on conflict(business_id) do update set settings=excluded.settings,version=korlix_receptionist_settings.version+1,
   consent_at=case when excluded.consent_at is not null then coalesce(korlix_receptionist_settings.consent_at,excluded.consent_at) else null end,updated_at=now();
  return '{"ok":true}';
 elsif p_action='bind_line' then
  if not p_admin then raise exception 'REC403: Platform phone setup is required.';end if;
  if exists(select 1 from public.korlix_receptionist_calls where business_id=b.id and state='active') then raise exception 'REC409: Finish active calls before changing this line.';end if;
  insert into public.korlix_receptionist_lines(business_id,provider_id,number) values(b.id,p->>'provider_id',p->>'number');
  return '{"ok":true}';
 elsif p_action='handled' then
  update public.korlix_receptionist_calls set handled_at=now() where business_id=b.id and id=(p->>'call_id')::uuid;
  if not found then raise exception 'REC404: Call not found.';end if;
  return '{"ok":true}';
 end if;
 raise exception 'REC400: Unsupported receptionist action.';
end $$;
revoke all on function public.korlix_receptionist_meter(uuid,boolean,integer) from public,anon,authenticated;
revoke all on function public.korlix_receptionist_command(uuid,boolean,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_receptionist_meter(uuid,boolean,integer) to service_role;
grant execute on function public.korlix_receptionist_command(uuid,boolean,text,uuid,jsonb) to service_role;
