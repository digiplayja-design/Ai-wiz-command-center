begin;
alter table public.korlix_workforce_orgs add column business_profile jsonb not null default '{"industry":"general","work_mode":"hybrid","description":""}' check(jsonb_typeof(business_profile)='object');
alter table public.korlix_workforce_members add column member_kind text not null default 'employee' check(member_kind in ('employee','contractor','freelancer','volunteer','partner')), add column job_title text not null default '' check(length(job_title)<=100), add column worksite text not null default '' check(length(worksite)<=100);
alter table public.korlix_workforce_invites add column member_kind text not null default 'employee' check(member_kind in ('employee','contractor','freelancer','volunteer','partner')), add column job_title text not null default '' check(length(job_title)<=100), add column worksite text not null default '' check(length(worksite)<=100);
create table public.korlix_workforce_tasks (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.korlix_workforce_orgs(id),
 created_by uuid not null, assignee_id uuid not null, request_id uuid not null, request_payload jsonb not null,
 title text not null check(length(title) between 1 and 160), details text not null default '' check(length(details)<=2000),
 priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 status text not null default 'todo' check(status in ('todo','in_progress','blocked','done','cancelled')),
 project text not null default '' check(length(project)<=100), worksite text not null default '' check(length(worksite)<=100),
 due_at timestamptz, progress_note text not null default '' check(length(progress_note)<=1000), version int not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), completed_at timestamptz,
 foreign key(org_id,created_by) references public.korlix_workforce_members(org_id,user_id),
 foreign key(org_id,assignee_id) references public.korlix_workforce_members(org_id,user_id), unique(org_id,created_by,request_id)
);
create index korlix_workforce_tasks_assignee on public.korlix_workforce_tasks(org_id,assignee_id,updated_at desc);
create index korlix_workforce_tasks_creator on public.korlix_workforce_tasks(org_id,created_by);
create index korlix_workforce_tasks_board on public.korlix_workforce_tasks(org_id,status,due_at);
alter table public.korlix_workforce_tasks enable row level security;
revoke all on public.korlix_workforce_tasks from public,anon,authenticated;
grant all on public.korlix_workforce_tasks to service_role;
-- The existing attendance RPC remains unchanged for backwards-compatible rollback.
create function public.korlix_workforce_workspace_v2(p_actor uuid,p_email text,p_action text,p_org uuid default null,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare r jsonb; o public.korlix_workforce_orgs; m public.korlix_workforce_members; inv public.korlix_workforce_invites;
 task public.korlix_workforce_tasks; admin boolean; uid uuid; t timestamptz:=clock_timestamp(); rows jsonb;
begin
 if p_actor is null then raise exception 'WF403: Sign in required'; end if;
 if p_action='create' then
  r:=public.korlix_workforce_command_v1(p_actor,p_email,p_action,p_org,p);
  update public.korlix_workforce_orgs set business_profile=coalesce(p->'profile',business_profile),policy=coalesce(p->'initial_policy',policy) where id=(r->>'id')::uuid returning to_jsonb(korlix_workforce_orgs) into r;
  return r;
 elsif p_action='invite' then
  r:=public.korlix_workforce_command_v1(p_actor,p_email,p_action,p_org,p);
  update public.korlix_workforce_invites set member_kind=coalesce(p->>'member_kind','employee'),job_title=coalesce(p->>'job_title',''),worksite=coalesce(p->>'worksite','') where id=(r->>'id')::uuid returning to_jsonb(korlix_workforce_invites)-'token_hash' into r;
  return r;
 elsif p_action='accept' then
  r:=public.korlix_workforce_command_v1(p_actor,p_email,p_action,p_org,p);
  select * into inv from public.korlix_workforce_invites where token_hash=p->>'token_hash';
  update public.korlix_workforce_members set member_kind=inv.member_kind,job_title=inv.job_title,worksite=inv.worksite where org_id=(r->>'id')::uuid and user_id=p_actor;
  return r;
 elsif p_action='snapshot' then
  r:=public.korlix_workforce_command_v1(p_actor,p_email,p_action,p_org,p);
  admin:=r->'member'->>'role' in ('owner','manager');
  select coalesce(jsonb_agg(to_jsonb(x)-'request_payload' order by x.updated_at desc,x.id),'[]'::jsonb) into rows from
   (select * from public.korlix_workforce_tasks where org_id=p_org and (admin or assignee_id=p_actor) order by updated_at desc,id limit 501) x;
  return r||jsonb_build_object('tasks',coalesce((select jsonb_agg(value) from jsonb_array_elements(rows) with ordinality x(value,n) where n<=500),'[]'::jsonb),'tasks_truncated',jsonb_array_length(rows)>500);
 end if;
 if p_action not in ('business','team_profile','task_create','task_edit','task_status') then
  -- Draft saves can pin the reviewed membership and workspace versions. Never trust a model-supplied role.
  if p ? 'expected_member_version' then
   perform pg_advisory_xact_lock(hashtextextended(p_org::text,139));
   if not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=p_actor and active and version=(p->>'expected_member_version')::int) then raise exception 'WF409: Your workspace access changed; reopen this draft'; end if;
  end if;
  return public.korlix_workforce_command_v1(p_actor,p_email,p_action,p_org,p);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text,139));
 select * into o from public.korlix_workforce_orgs where id=p_org;
 select * into m from public.korlix_workforce_members where org_id=p_org and user_id=p_actor and active;
 if o.id is null or m.user_id is null then raise exception 'WF403: Workspace access is unavailable'; end if;
 if not exists(select 1 from public.user_profiles where id=o.owner_id and lower(trim(tier))='enterprise') then raise exception 'WF403: This workspace needs an active Enterprise plan'; end if;
 if p ? 'expected_member_version' and m.version<>(p->>'expected_member_version')::int then raise exception 'WF409: Your workspace access changed; reopen this draft'; end if;
 admin:=m.role in ('owner','manager');
 if p_action='business' then
  if m.role<>'owner' then raise exception 'WF403: Owner access required'; end if;
  if o.version<>(p->>'version')::int then raise exception 'WF409: Workspace changed; refresh before saving'; end if;
  update public.korlix_workforce_orgs set name=p->>'name',business_profile=p->'profile',version=version+1 where id=p_org returning to_jsonb(korlix_workforce_orgs) into r;
 elsif p_action='team_profile' then
  if m.role<>'owner' then raise exception 'WF403: Owner access required'; end if;
  update public.korlix_workforce_members set member_kind=p->>'member_kind',job_title=p->>'job_title',worksite=p->>'worksite',version=version+1 where org_id=p_org and user_id=(p->>'user_id')::uuid and version=(p->>'version')::int returning to_jsonb(korlix_workforce_members) into r;
  if not found then raise exception 'WF409: Member changed; refresh before saving'; end if;
 else
  if p_action in ('task_create','task_edit') then
   uid:=(p->>'assignee_id')::uuid;
   if not admin and (p_action='task_edit' or uid<>p_actor) then raise exception 'WF403: Managers assign team tasks; members can create their own tasks'; end if;
   if not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=uid and active) then raise exception 'WF: Choose an active member of this workspace'; end if;
  end if;
  if p_action='task_create' then
   select * into task from public.korlix_workforce_tasks where org_id=p_org and created_by=p_actor and request_id=(p->>'request_id')::uuid;
   if task.id is not null then
    if task.request_payload<>(p-'expected_member_version') then raise exception 'WF409: Task request changed; refresh before trying again'; end if;
    return to_jsonb(task)-'request_payload';
   end if;
   if (select count(*) from public.korlix_workforce_tasks where org_id=p_org)>=5000 then raise exception 'WF: Workspace task limit reached'; end if;
   insert into public.korlix_workforce_tasks(org_id,created_by,assignee_id,request_id,request_payload,title,details,priority,project,worksite,due_at)
    values(p_org,p_actor,uid,(p->>'request_id')::uuid,p-'expected_member_version',p->>'title',coalesce(p->>'details',''),p->>'priority',coalesce(p->>'project',''),coalesce(p->>'worksite',''),nullif(p->>'due_at','')::timestamptz) returning * into task;
  else
   select * into task from public.korlix_workforce_tasks where org_id=p_org and id=(p->>'id')::uuid and (admin or assignee_id=p_actor) for update;
   if task.id is null then raise exception 'WF403: Task access is unavailable'; end if;
   if task.version<>(p->>'version')::int then raise exception 'WF409: Task changed; refresh before saving'; end if;
   if p_action='task_edit' then
    update public.korlix_workforce_tasks set assignee_id=uid,title=p->>'title',details=p->>'details',priority=p->>'priority',project=p->>'project',worksite=p->>'worksite',due_at=nullif(p->>'due_at','')::timestamptz,version=version+1,updated_at=t where id=task.id returning * into task;
   else
    if task.status='cancelled' and not admin then raise exception 'WF403: A manager must reopen cancelled work'; end if;
    if p->>'status'='cancelled' and not admin then raise exception 'WF403: A manager must cancel assigned work'; end if;
    update public.korlix_workforce_tasks set status=p->>'status',progress_note=p->>'progress_note',completed_at=case when p->>'status'='done' then coalesce(completed_at,t) else null end,version=version+1,updated_at=t where id=task.id returning * into task;
   end if;
  end if;
  r:=to_jsonb(task)-'request_payload';
 end if;
 insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,p_action,jsonb_build_object('id',coalesce(r->>'id',r->>'user_id'),'version',r->'version'));
 return r;
end; $$;
revoke all on function public.korlix_workforce_workspace_v2(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_workforce_workspace_v2(uuid,text,text,uuid,jsonb) to service_role;
comment on function public.korlix_workforce_workspace_v2(uuid,text,text,uuid,jsonb) is 'Service-only Workforce commands with verified actor, current membership, plan and tenant checks. Browser roles have no direct grants.';
commit;
