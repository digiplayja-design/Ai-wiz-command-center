begin;
create table public.korlix_workforce_orgs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 name text not null check(length(name) between 1 and 100), timezone text not null default 'America/New_York',
 policy jsonb not null default '{"require_selfie":false,"require_location":false,"hourly_updates":false,"interval_minutes":60,"grace_minutes":10,"retention_days":30,"worksite":"Main worksite","latitude":null,"longitude":null,"radius_m":200,"daily_goal":10,"output_unit":"tasks"}',
 version int not null default 1, created_at timestamptz not null default now()
);
create table public.korlix_workforce_members (
 org_id uuid not null references public.korlix_workforce_orgs(id), user_id uuid not null references auth.users(id),
 role text not null check(role in ('owner','manager','employee')), display_name text not null check(length(display_name) between 1 and 100),
 email text not null, team text not null default '', active boolean not null default true, policy_override jsonb,
 version int not null default 1, joined_at timestamptz not null default now(), primary key(org_id,user_id)
);
create index on public.korlix_workforce_members(user_id,active);
create table public.korlix_workforce_invites (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 email text not null, display_name text not null, role text not null check(role in ('manager','employee')),
 token_hash text not null unique check(length(token_hash)=64), expires_at timestamptz not null default now()+interval '7 days',
 accepted_at timestamptz, revoked_at timestamptz, created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.korlix_workforce_shifts (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id), user_id uuid not null,
 clock_in timestamptz not null default now(), clock_out timestamptz, state text not null default 'working' check(state in ('working','break','ended')),
 segment_start timestamptz not null default now(), worked_seconds int not null default 0 check(worked_seconds>=0), break_seconds int not null default 0 check(break_seconds>=0),
 policy_snapshot jsonb not null, version int not null default 1, review_status text not null default 'pending' check(review_status in ('pending','approved','needs_review')),
 approved_start timestamptz, approved_end timestamptz, approved_break_minutes int, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 foreign key(org_id,user_id) references public.korlix_workforce_members(org_id,user_id),
 check((state='ended')=(clock_out is not null)), check(clock_out is null or clock_out>=clock_in),
 check(approved_start is null or (approved_end>approved_start and approved_break_minutes>=0 and approved_break_minutes*60<extract(epoch from approved_end-approved_start)))
);
create unique index korlix_workforce_one_open_shift on public.korlix_workforce_shifts(user_id) where state<>'ended';
create index on public.korlix_workforce_shifts(org_id,clock_in);
create table public.korlix_workforce_events (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 user_id uuid not null references auth.users(id), shift_id uuid references public.korlix_workforce_shifts(id), action text not null,
 request_id uuid not null, recorded_at timestamptz not null default now(), client_time timestamptz,
 location jsonb, photo_path text, photo_expires_at timestamptz, exception_reason text, flags jsonb not null default '[]',
 unique(user_id,request_id)
);
create index on public.korlix_workforce_events(org_id,shift_id);
create table public.korlix_workforce_updates (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 user_id uuid not null references auth.users(id), shift_id uuid not null references public.korlix_workforce_shifts(id), request_id uuid not null,
 summary text not null check(length(summary) between 1 and 2000), blockers text not null default '' check(length(blockers)<=1000),
 project text not null default '' check(length(project)<=100), quantity int not null check(quantity between 0 and 100000),
 output_unit text not null check(length(output_unit) between 1 and 40), worked_seconds_at_submit int not null,
 created_at timestamptz not null default now(), unique(user_id,request_id)
);
create index on public.korlix_workforce_updates(org_id,created_at);
create table public.korlix_workforce_corrections (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 user_id uuid not null references auth.users(id), shift_id uuid references public.korlix_workforce_shifts(id),
 proposed_start timestamptz not null, proposed_end timestamptz not null, break_minutes int not null default 0,
 reason text not null check(length(reason) between 5 and 1000), status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz, review_note text, created_at timestamptz not null default now(),
 check(proposed_end>proposed_start and proposed_end-proposed_start<=interval '24 hours'),
 check(break_minutes>=0 and break_minutes*60<extract(epoch from proposed_end-proposed_start))
);
create table public.korlix_workforce_schedule (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 user_id uuid not null, starts_at timestamptz not null, ends_at timestamptz not null, worksite text not null, notes text not null default '',
 created_by uuid not null references auth.users(id), version int not null default 1, cancelled_at timestamptz,
 foreign key(org_id,user_id) references public.korlix_workforce_members(org_id,user_id), check(ends_at>starts_at and ends_at-starts_at<=interval '24 hours')
);
create table public.korlix_workforce_audit (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 actor_id uuid not null references auth.users(id), action text not null, details jsonb not null default '{}', recorded_at timestamptz not null default now()
);
create table public.korlix_workforce_photo_uploads (
 path text primary key, created_at timestamptz not null default now()
);
create index on public.korlix_workforce_photo_uploads(created_at);
-- Clients use authenticated backend endpoints. No browser role can query these tables or RPCs.
do $$ declare t text; begin
 foreach t in array array['orgs','members','invites','shifts','events','updates','corrections','schedule','audit','photo_uploads'] loop
  execute format('alter table public.korlix_workforce_%I enable row level security',t);
  execute format('revoke all on public.korlix_workforce_%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.korlix_workforce_%I to service_role',t);
 end loop;
end $$;

create function public.korlix_workforce_command_v1(p_actor uuid,p_email text,p_action text,p_org uuid default null,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 o public.korlix_workforce_orgs; m public.korlix_workforce_members; s public.korlix_workforce_shifts;
 inv public.korlix_workforce_invites; ev public.korlix_workforce_events; c public.korlix_workforce_corrections;
 pol jsonb; result jsonb; ent boolean; admin boolean; t timestamptz:=clock_timestamp();
 uid uuid; rid uuid; sid uuid; elapsed int; worked int; d1 date; d2 date; start_at timestamptz; end_at timestamptz;
begin
 if p_actor is null then raise exception 'WF: Sign in required'; end if;
 if p_action='workspaces' then
  return jsonb_build_object('can_create',exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise'),
   'workspaces',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'role',wm.role,'timezone',w.timezone,'active_plan',exists(select 1 from public.user_profiles where id=w.owner_id and lower(trim(tier))='enterprise')) order by w.name)
    from public.korlix_workforce_orgs w join public.korlix_workforce_members wm on wm.org_id=w.id where wm.user_id=p_actor and wm.active),'[]'::jsonb));
 end if;
 if p_action='create' then
  if not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'WF403: Enterprise is required to create a workspace'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,138));
  if (select count(*) from public.korlix_workforce_orgs where owner_id=p_actor)>=5 then raise exception 'WF: Workspace limit reached'; end if;
  if not exists(select 1 from pg_timezone_names where name=p->>'timezone') then raise exception 'WF: Choose a valid timezone'; end if;
  insert into public.korlix_workforce_orgs(owner_id,name,timezone) values(p_actor,p->>'name',p->>'timezone') returning * into o;
  insert into public.korlix_workforce_members(org_id,user_id,role,display_name,email) values(o.id,p_actor,'owner',p->>'display_name',lower(p_email));
  return to_jsonb(o);
 end if;
 if p_action='accept' then
  select * into inv from public.korlix_workforce_invites where token_hash=p->>'token_hash';
  if inv.org_id is not null then perform pg_advisory_xact_lock(hashtextextended(inv.org_id::text,139)); end if;
  select * into inv from public.korlix_workforce_invites where token_hash=p->>'token_hash' for update;
  if inv.id is null or inv.expires_at<t or inv.revoked_at is not null or inv.accepted_at is not null or lower(inv.email)<>lower(p_email) then raise exception 'WF403: Invitation is invalid, expired, used, or belongs to a different email'; end if;
  select * into o from public.korlix_workforce_orgs where id=inv.org_id;
  if not exists(select 1 from public.user_profiles where id=o.owner_id and lower(trim(tier))='enterprise') then raise exception 'WF403: This workspace needs an active Enterprise plan'; end if;
  if o.owner_id=p_actor then raise exception 'WF: You already own this workspace'; end if;
  if (select count(*) from public.korlix_workforce_members where org_id=o.id and active)>=500 then raise exception 'WF: Workspace member limit reached'; end if;
  insert into public.korlix_workforce_members(org_id,user_id,role,display_name,email) values(o.id,p_actor,inv.role,inv.display_name,lower(p_email))
   on conflict(org_id,user_id) do update set active=true, role=excluded.role, display_name=excluded.display_name,email=excluded.email,version=korlix_workforce_members.version+1;
  update public.korlix_workforce_invites set accepted_at=t where id=inv.id;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(o.id,p_actor,'invitation_accepted',jsonb_build_object('invite_id',inv.id));
  return jsonb_build_object('id',o.id,'name',o.name);
 end if;
 if p_action not in ('snapshot','audit','evidence') then perform pg_advisory_xact_lock(hashtextextended(p_org::text,139)); end if;
 select * into o from public.korlix_workforce_orgs where id=p_org;
 select * into m from public.korlix_workforce_members where org_id=p_org and user_id=p_actor and active;
 if o.id is null or m.user_id is null then raise exception 'WF403: Workspace access is unavailable'; end if;
 ent:=exists(select 1 from public.user_profiles where id=o.owner_id and lower(trim(tier))='enterprise');
 admin:=m.role in ('owner','manager');
 -- Read history and end an active shift even if the employer plan lapses. No new work starts.
 if not ent and p_action not in ('snapshot','clock_out','evidence','correction') then raise exception 'WF403: This workspace needs an active Enterprise plan'; end if;
 pol:=coalesce(m.policy_override,o.policy);
 if p_action='snapshot' then
  d1:=coalesce((p->>'from')::date,(t at time zone o.timezone)::date); d2:=coalesce((p->>'to')::date,d1);
  if d2<d1 or d2-d1>30 then raise exception 'WF: Choose a range of up to 31 days'; end if;
  start_at:=d1::timestamp at time zone o.timezone; end_at:=(d2+1)::timestamp at time zone o.timezone;
  return jsonb_build_object('organization',to_jsonb(o),'member',to_jsonb(m),'active_plan',ent,'policy',pol,'from',d1,'to',d2,'period_start',start_at,'period_end',end_at,'server_now',t,
   'members',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_name) from public.korlix_workforce_members x where org_id=p_org and (admin or user_id=p_actor)),'[]'::jsonb),
   'shifts',coalesce((select jsonb_agg(to_jsonb(x) order by x.clock_in desc) from public.korlix_workforce_shifts x where org_id=p_org and (admin or user_id=p_actor) and ((coalesce(approved_start,clock_in)<end_at and coalesce(approved_end,clock_out,t)>start_at) or state<>'ended')),'[]'::jsonb),
   'updates',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.korlix_workforce_updates x where org_id=p_org and (admin or user_id=p_actor) and ((created_at>=start_at and created_at<end_at) or shift_id in (select id from public.korlix_workforce_shifts where org_id=p_org and state<>'ended' and (admin or user_id=p_actor)))),'[]'::jsonb),
   'corrections',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.korlix_workforce_corrections x where org_id=p_org and (admin or user_id=p_actor) and (status='pending' or (created_at>=start_at and created_at<end_at))),'[]'::jsonb),
   'schedule',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from public.korlix_workforce_schedule x where org_id=p_org and (admin or user_id=p_actor) and cancelled_at is null and starts_at<end_at+interval '7 days' and ends_at>=start_at),'[]'::jsonb),
   'events',coalesce((select jsonb_agg((case when x.photo_expires_at<=t then to_jsonb(x)-'location' else to_jsonb(x) end)-'photo_path' || jsonb_build_object('has_photo',x.photo_path is not null and x.photo_expires_at>t) order by x.recorded_at desc) from public.korlix_workforce_events x where org_id=p_org and (admin or user_id=p_actor) and recorded_at>=start_at and recorded_at<end_at),'[]'::jsonb),
   'invites',case when m.role='owner' then coalesce((select jsonb_agg(to_jsonb(x)-'token_hash' order by x.created_at desc) from public.korlix_workforce_invites x where org_id=p_org and accepted_at is null and revoked_at is null and expires_at>t),'[]'::jsonb) else '[]'::jsonb end);
 elsif p_action='policy' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  if o.version<>(p->>'version')::int then raise exception 'WF409: Policy changed; refresh before saving'; end if;
  update public.korlix_workforce_orgs set policy=p->'policy',version=version+1 where id=p_org and version=(p->>'version')::int;
  if not found then raise exception 'WF409: Policy changed; refresh before saving'; end if;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'policy_changed',jsonb_build_object('before',o.policy,'after',p->'policy'));
  return jsonb_build_object('saved',true);
 elsif p_action='invite' then
  if m.role<>'owner' then raise exception 'WF403: Owner access required'; end if;
  if (select count(*) from public.korlix_workforce_invites where org_id=p_org and accepted_at is null and revoked_at is null and expires_at>t)>=500 then raise exception 'WF: Too many pending invitations'; end if;
  insert into public.korlix_workforce_invites(org_id,email,display_name,role,token_hash,created_by) values(p_org,lower(p->>'email'),p->>'display_name',p->>'role',p->>'token_hash',p_actor) returning to_jsonb(korlix_workforce_invites)-'token_hash' into result;
  return result;
 elsif p_action='revoke_invite' then
  if m.role<>'owner' then raise exception 'WF403: Owner access required'; end if;
  update public.korlix_workforce_invites set revoked_at=t where id=(p->>'id')::uuid and org_id=p_org and accepted_at is null;
  return jsonb_build_object('saved',true);
 elsif p_action='member' then
  if m.role<>'owner' then raise exception 'WF403: Owner access required'; end if;
  uid:=(p->>'user_id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,138));
  if uid=o.owner_id then raise exception 'WF: Owner membership cannot be changed here'; end if;
  if exists(select 1 from public.korlix_workforce_shifts where org_id=p_org and user_id=uid and state<>'ended') and not (p->>'active')::boolean then raise exception 'WF409: Close or correct the active shift before removing access'; end if;
  update public.korlix_workforce_members set role=p->>'role',active=(p->>'active')::boolean,team=p->>'team',policy_override=nullif(p->'policy_override','null'::jsonb),version=version+1 where org_id=p_org and user_id=uid and version=(p->>'version')::int;
  if not found then raise exception 'WF409: Member changed; refresh before saving'; end if;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'member_changed',p-'email');
  return jsonb_build_object('saved',true);
 elsif p_action in ('clock_in','start_break','end_break','clock_out') then
  -- Serialize across workspaces for this employee. A request ID cannot be reused for another action.
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,138));
  rid:=(p->>'request_id')::uuid;
  select * into ev from public.korlix_workforce_events where user_id=p_actor and request_id=rid;
  if ev.id is not null then
   if ev.org_id<>p_org or ev.action<>p_action then raise exception 'WF409: Request already used'; end if;
   return jsonb_build_object('event',jsonb_build_object('id',ev.id,'recorded_at',ev.recorded_at,'action',ev.action),'replayed',true);
  end if;
  select * into s from public.korlix_workforce_shifts where user_id=p_actor and state<>'ended' for update;
  if p_action='clock_in' then
   if s.id is not null then raise exception 'WF409: You already have an active shift'; end if;
   if (p ? 'policy_version' and (p->>'policy_version')::int<>o.version) or (p ? 'member_version' and (p->>'member_version')::int<>m.version) then raise exception 'WF409: Attendance policy changed; refresh before clocking in'; end if;
   if ((pol->>'require_selfie')::boolean and coalesce(p->>'photo_path','')='') or ((pol->>'require_location')::boolean and (p->'location' is null or p->'location'='null'::jsonb)) then
    if length(coalesce(p->>'exception_reason',''))<5 then raise exception 'WF: Required attendance evidence is missing'; end if;
   end if;
   insert into public.korlix_workforce_shifts(org_id,user_id,clock_in,segment_start,policy_snapshot,review_status) values(p_org,p_actor,t,t,pol,case when jsonb_array_length(p->'flags')>0 then 'needs_review' else 'pending' end) returning * into s;
  else
   if s.id is null or s.org_id<>p_org then raise exception 'WF409: No active shift in this workspace'; end if;
   if s.version<>(p->>'version')::int then raise exception 'WF409: Shift changed; refresh before trying again'; end if;
   if p_action='start_break' and s.state<>'working' or p_action='end_break' and s.state<>'break' then raise exception 'WF409: Refresh your shift before continuing'; end if;
   elapsed:=greatest(0,floor(extract(epoch from t-s.segment_start))::int);
   update public.korlix_workforce_shifts set
    worked_seconds=worked_seconds+case when state='working' then elapsed else 0 end,
    break_seconds=break_seconds+case when state='break' then elapsed else 0 end,
    state=case p_action when 'clock_out' then 'ended' when 'start_break' then 'break' else 'working' end,
    clock_out=case when p_action='clock_out' then t else null end, segment_start=t,version=version+1,
    review_status=case when jsonb_array_length(p->'flags')>0 then 'needs_review' else review_status end
    where id=s.id returning * into s;
  end if;
  pol:=s.policy_snapshot;
  insert into public.korlix_workforce_events(org_id,user_id,shift_id,action,request_id,recorded_at,client_time,location,photo_path,photo_expires_at,exception_reason,flags)
   values(p_org,p_actor,s.id,p_action,rid,t,(p->>'client_time')::timestamptz,nullif(p->'location','null'::jsonb),p->>'photo_path',t+make_interval(days=>coalesce((pol->>'retention_days')::int,30)),p->>'exception_reason',coalesce(p->'flags','[]')) returning * into ev;
  return jsonb_build_object('shift',to_jsonb(s),'event',jsonb_build_object('id',ev.id,'recorded_at',ev.recorded_at,'action',ev.action),'replayed',false);
 elsif p_action='update' then
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,138));
  rid:=(p->>'request_id')::uuid;
  select to_jsonb(x) into result from public.korlix_workforce_updates x where user_id=p_actor and request_id=rid;
  if result is not null then
   if result->>'org_id'<>p_org::text then raise exception 'WF409: Request already used'; end if;
   return result;
  end if;
  select * into s from public.korlix_workforce_shifts where id=(p->>'shift_id')::uuid and org_id=p_org and user_id=p_actor for update;
  if s.id is null or s.clock_out<t-interval '24 hours' then raise exception 'WF: Choose your current or recently ended shift'; end if;
  worked:=s.worked_seconds+case when s.state='working' then greatest(0,floor(extract(epoch from t-s.segment_start))::int) else 0 end;
  insert into public.korlix_workforce_updates(org_id,user_id,shift_id,request_id,summary,blockers,project,quantity,output_unit,worked_seconds_at_submit)
   values(p_org,p_actor,s.id,rid,p->>'summary',p->>'blockers',p->>'project',(p->>'quantity')::int,s.policy_snapshot->>'output_unit',worked) returning to_jsonb(korlix_workforce_updates) into result;
  return result;
 elsif p_action='correction' then
  sid:=(p->>'shift_id')::uuid;
  if sid is not null and not exists(select 1 from public.korlix_workforce_shifts where id=sid and org_id=p_org and user_id=p_actor) then raise exception 'WF403: This is not your shift'; end if;
  if (p->>'proposed_end')::timestamptz>t+interval '1 minute' then raise exception 'WF: Corrections cannot add future work'; end if;
  insert into public.korlix_workforce_corrections(org_id,user_id,shift_id,proposed_start,proposed_end,break_minutes,reason)
   values(p_org,p_actor,sid,(p->>'proposed_start')::timestamptz,(p->>'proposed_end')::timestamptz,(p->>'break_minutes')::int,p->>'reason') returning to_jsonb(korlix_workforce_corrections) into result;
  return result;
 elsif p_action='review_correction' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  select * into c from public.korlix_workforce_corrections where id=(p->>'id')::uuid and org_id=p_org for update;
  if c.id is null or c.status<>'pending' then raise exception 'WF409: Correction already reviewed or unavailable'; end if;
  if c.user_id=p_actor then raise exception 'WF403: Another manager must review your correction'; end if;
  perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,138));
  if p->>'decision'='approved' then
   if exists(select 1 from public.korlix_workforce_shifts where user_id=c.user_id and id is distinct from c.shift_id and coalesce(approved_start,clock_in)<c.proposed_end and coalesce(approved_end,clock_out,t)>c.proposed_start) then raise exception 'WF409: Corrected time overlaps another shift'; end if;
   if c.shift_id is null then
    insert into public.korlix_workforce_shifts(org_id,user_id,clock_in,clock_out,state,segment_start,policy_snapshot,approved_start,approved_end,approved_break_minutes,review_status,reviewed_by,reviewed_at)
     values(p_org,c.user_id,c.proposed_start,c.proposed_end,'ended',c.proposed_end,o.policy,c.proposed_start,c.proposed_end,c.break_minutes,'approved',p_actor,t) returning id into sid;
    update public.korlix_workforce_corrections set shift_id=sid where id=c.id;
   else
    update public.korlix_workforce_shifts set approved_start=c.proposed_start,approved_end=c.proposed_end,approved_break_minutes=c.break_minutes,
     worked_seconds=worked_seconds+case when state='working' then greatest(0,floor(extract(epoch from t-segment_start))::int) else 0 end,
     break_seconds=break_seconds+case when state='break' then greatest(0,floor(extract(epoch from t-segment_start))::int) else 0 end,segment_start=case when state='ended' then segment_start else t end,
     state='ended',clock_out=coalesce(clock_out,t),review_status='approved',reviewed_by=p_actor,reviewed_at=t,version=version+1 where id=c.shift_id;
   end if;
  end if;
  update public.korlix_workforce_corrections set status=p->>'decision',reviewed_by=p_actor,reviewed_at=t,review_note=p->>'review_note' where id=c.id;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'correction_reviewed',jsonb_build_object('correction',to_jsonb(c),'decision',p->>'decision','note',p->>'review_note'));
  return jsonb_build_object('saved',true);
 elsif p_action='approve_shift' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  update public.korlix_workforce_shifts set review_status='approved',reviewed_by=p_actor,reviewed_at=t,version=version+1 where id=(p->>'id')::uuid and org_id=p_org and state='ended' and version=(p->>'version')::int and user_id<>p_actor;
  if not found then raise exception 'WF409: Refresh this ended shift; a different manager must approve it'; end if;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'shift_approved',p);
  return jsonb_build_object('saved',true);
 elsif p_action='schedule' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  uid:=(p->>'user_id')::uuid;
  perform 1 from public.korlix_workforce_members where org_id=p_org and user_id=uid and active for update;
  if not found then raise exception 'WF: Choose an active team member'; end if;
  if exists(select 1 from public.korlix_workforce_schedule where org_id=p_org and user_id=uid and cancelled_at is null and starts_at<(p->>'ends_at')::timestamptz and ends_at>(p->>'starts_at')::timestamptz) then raise exception 'WF409: This schedule overlaps another shift'; end if;
  insert into public.korlix_workforce_schedule(org_id,user_id,starts_at,ends_at,worksite,notes,created_by) values(p_org,uid,(p->>'starts_at')::timestamptz,(p->>'ends_at')::timestamptz,p->>'worksite',p->>'notes',p_actor) returning to_jsonb(korlix_workforce_schedule) into result;
  return result;
 elsif p_action='cancel_schedule' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  update public.korlix_workforce_schedule set cancelled_at=t,version=version+1 where id=(p->>'id')::uuid and org_id=p_org and version=(p->>'version')::int;
  if not found then raise exception 'WF409: Schedule changed; refresh before saving'; end if;
  return jsonb_build_object('saved',true);
 elsif p_action='evidence' then
  select * into ev from public.korlix_workforce_events where id=(p->>'id')::uuid and org_id=p_org and (admin or user_id=p_actor);
  if ev.id is null or ev.photo_path is null or ev.photo_expires_at<=t then raise exception 'WF404: Photo unavailable or retention period expired'; end if;
  return jsonb_build_object('path',ev.photo_path);
 elsif p_action='audit' then
  if not admin then raise exception 'WF403: Manager access required'; end if;
  return jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.korlix_workforce_audit where org_id=p_org order by recorded_at desc limit 100) x),'[]'::jsonb));
 end if;
 raise exception 'WF: Unknown action';
end $$;
revoke all on function public.korlix_workforce_command_v1(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_workforce_command_v1(uuid,text,text,uuid,jsonb) to service_role;
-- Private, backend-mediated photo evidence. No direct client storage policies are added.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-workforce-evidence','korlix-workforce-evidence',false,524288,array['image/jpeg'])
 on conflict(id) do nothing;
do $$ begin
 if exists(select 1 from storage.buckets where id='korlix-workforce-evidence' and public) then
  raise exception 'Workforce attendance evidence requires a private bucket';
 end if;
end $$;
commit;
