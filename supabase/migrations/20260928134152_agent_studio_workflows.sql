-- Agent Studio: private, reviewed, sequential AI work. No external action tools.
create table public.korlix_agent_workflows (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(length(title) between 1 and 120),
 objective text not null check(length(objective) between 1 and 6000),
 priority text not null default 'normal' check(priority in('normal','high','low')),
 use_memory boolean not null default false,
 steps jsonb not null check(jsonb_typeof(steps)='array' and jsonb_array_length(steps) between 1 and 8),
 state text not null default 'ready' check(state in('ready','running','review','paused','completed','cancelled','failed')),
 resume_state text, cursor integer not null default 0 check(cursor between 0 and 8),
 revision integer not null default 1, attempt_id uuid,
 events jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index korlix_agent_workflows_owner_updated on public.korlix_agent_workflows(owner_id,updated_at desc,id);
create table public.korlix_agent_workflow_attempts (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 workflow_id uuid not null references public.korlix_agent_workflows(id) on delete cascade,
 step_index integer not null, state text not null check(state in('running','review','failed','cancelled')),
 usage_id uuid references public.usage_counters(id) on delete set null,
 charged boolean not null default true, output text, agent_version integer,
 started_at timestamptz not null default now(), finished_at timestamptz
);
create index korlix_agent_workflow_attempts_owner on public.korlix_agent_workflow_attempts(owner_id,started_at desc);
create index korlix_agent_workflow_attempts_workflow on public.korlix_agent_workflow_attempts(workflow_id);
create index korlix_agent_workflow_attempts_usage on public.korlix_agent_workflow_attempts(usage_id);
alter table public.korlix_agent_workflows enable row level security;
alter table public.korlix_agent_workflow_attempts enable row level security;
revoke all on public.korlix_agent_workflows,public.korlix_agent_workflow_attempts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_agent_workflows,public.korlix_agent_workflow_attempts to service_role;

create function public.korlix_agent_workflow_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare w korlix_agent_workflows; a korlix_agent_workflow_attempts; s jsonb; ev jsonb; response jsonb; uid uuid; step_no integer; next_state text; event_name text; t record;
begin
 if p_actor is null then raise exception 'Sign in to use workflows.' using errcode='42501';end if;
 -- Serialize transitions across devices and workers for this account.
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':agent-workflow',0));
 if p_action='recover' then
  for t in select id,workflow_id from korlix_agent_workflow_attempts where owner_id=p_actor and state='running' and started_at<now()-interval '5 minutes' loop
   perform korlix_agent_workflow_v1(p_actor,'fail',t.workflow_id,jsonb_build_object('attempt_id',t.id));
  end loop;
  return jsonb_build_object('recovered',true);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(x),'[]'::jsonb) into response from (
   select id,title,priority,state,cursor,revision,created_at,updated_at,jsonb_array_length(steps) step_count
   from korlix_agent_workflows where owner_id=p_actor order by updated_at desc,id limit 200
  ) x;
  return jsonb_build_object('workflows',response);
 end if;
 if p_action='create' then
  select * into w from korlix_agent_workflows where owner_id=p_actor and id=p_id;
  if found then return to_jsonb(w)-'owner_id';end if;
  if (select count(*) from korlix_agent_workflows where owner_id=p_actor)>=200 then raise exception 'Archive a finished workflow by deleting it before creating more.' using errcode='54000';end if;
  if jsonb_typeof(p_data->'steps') is distinct from 'array' then raise exception 'Add workflow steps.';end if;
  for s in select value from jsonb_array_elements(p_data->'steps') loop
   if coalesce(length(s->>'agent_id'),0) not between 1 and 96 or coalesce(length(s->>'instruction'),0) not between 1 and 2000 or coalesce(length(s->>'title'),0) not between 1 and 100 then raise exception 'Each step needs an agent, title and instruction.';end if;
  end loop;
  insert into korlix_agent_workflows(id,owner_id,title,objective,priority,use_memory,steps,events)
   values(p_id,p_actor,p_data->>'title',p_data->>'objective',p_data->>'priority',coalesce((p_data->>'use_memory')::boolean,false),p_data->'steps',
    jsonb_build_array(jsonb_build_object('type','created','at',now()))) returning * into w;
  return to_jsonb(w)-'owner_id';
 end if;
 select * into w from korlix_agent_workflows where owner_id=p_actor and id=p_id for update;
 if not found then raise exception 'Workflow not found.' using errcode='P0002';end if;
 if p_action='get' then return to_jsonb(w)-'owner_id';end if;
 if p_action in('lookup','start') then
  select * into a from korlix_agent_workflow_attempts where owner_id=p_actor and id=(p_data->>'attempt_id')::uuid;
  if found then
   if a.workflow_id<>w.id then raise exception 'This run key belongs to another workflow.' using errcode='40001';end if;
   return (to_jsonb(w)-'owner_id')||jsonb_build_object('replayed',true);
  end if;
  if p_action='lookup' then raise exception 'Run not found.' using errcode='P0002';end if;
 end if;
 if p_action in('finish','fail') then
  select * into a from korlix_agent_workflow_attempts where owner_id=p_actor and workflow_id=w.id and id=(p_data->>'attempt_id')::uuid for update;
  if not found then raise exception 'Run not found.' using errcode='P0002';end if;
  if a.state<>'running' or w.state<>'running' or w.attempt_id is distinct from a.id then return to_jsonb(w)-'owner_id';end if;
  s:=w.steps->w.cursor;
  if p_action='finish' then
   if coalesce(length(p_data->>'output'),0) not between 1 and 18000 then raise exception 'Invalid agent output.';end if;
   s:=s||jsonb_build_object('status','review','output',p_data->>'output','agent_version',a.agent_version);
   update korlix_agent_workflow_attempts set state='review',output=p_data->>'output',finished_at=now() where id=a.id;
   next_state:='review';event_name:='result_ready';
  else
   if a.charged then update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-1),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=a.usage_id and user_id=p_actor;end if;
   update korlix_agent_workflow_attempts set state='failed',charged=false,finished_at=now() where id=a.id;
   s:=s||jsonb_build_object('status','failed');next_state:='failed';event_name:='run_failed';
  end if;
 else
  if w.revision is distinct from (p_data->>'revision')::integer then raise exception 'This workflow changed. Refresh before continuing.' using errcode='40001';end if;
  s:=w.steps->w.cursor;next_state:=w.state;
  if p_action='start' then
   if w.state not in('ready','failed') or w.cursor>=jsonb_array_length(w.steps) then raise exception 'Review the current result or resume this workflow before running.' using errcode='40001';end if;
   if exists(select 1 from jsonb_array_elements(w.steps) with ordinality as j(v,n) where n<=w.cursor and v->>'status'<>'approved') then raise exception 'Approve earlier steps first.' using errcode='40001';end if;
   if exists(select 1 from korlix_agent_workflow_attempts where owner_id=p_actor and state='running') then raise exception 'Another workflow step is still running.' using errcode='40001';end if;
   if (select count(*) from korlix_agent_workflow_attempts where owner_id=p_actor and started_at>now()-interval '1 hour')>=30 then raise exception 'Please wait before running more workflow steps.' using errcode='54000';end if;
   uid:=(p_data->>'usage_id')::uuid;
   update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now()
    where id=uid and user_id=p_actor and coalesce(credits_used,0)<(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;
   if not found then raise exception 'Your generation allowance is unavailable.' using errcode='54000';end if;
   insert into korlix_agent_workflow_attempts(id,owner_id,workflow_id,step_index,state,usage_id,agent_version)
    values((p_data->>'attempt_id')::uuid,p_actor,w.id,w.cursor,'running',uid,(p_data->>'agent_version')::integer) returning * into a;
   w.attempt_id:=a.id;s:=s||jsonb_build_object('status','running');next_state:='running';event_name:='run_started';
  elsif p_action='approve' then
   if w.state<>'review' then raise exception 'A completed result must be reviewed first.' using errcode='40001';end if;
   s:=s||jsonb_build_object('status','approved');event_name:='approved';
   next_state:=case when w.cursor+1=jsonb_array_length(w.steps) then 'completed' else 'ready' end;
  elsif p_action='revise' then
   if w.state<>'review' then raise exception 'Wait for a result to request changes.' using errcode='40001';end if;
   if coalesce(length(p_data->>'feedback'),0) not between 1 and 2000 then raise exception 'Describe the changes needed.';end if;
   s:=s||jsonb_build_object('status','pending','feedback',p_data->>'feedback');next_state:='ready';event_name:='changes_requested';
  elsif p_action='pause' then
   if w.state not in('ready','review','failed') then raise exception 'Pause between steps. Cancel a running workflow to stop it.' using errcode='40001';end if;
   w.resume_state:=w.state;next_state:='paused';event_name:='paused';
  elsif p_action='resume' then
   if w.state<>'paused' then raise exception 'This workflow is not paused.' using errcode='40001';end if;
   next_state:=w.resume_state;event_name:='resumed';
  elsif p_action='cancel' then
   if w.state in('completed','cancelled') then raise exception 'This workflow has already ended.' using errcode='40001';end if;
   if w.state='running' then
    select * into a from korlix_agent_workflow_attempts where id=w.attempt_id and owner_id=p_actor for update;
    if a.charged then update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-1),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=a.usage_id and user_id=p_actor;end if;
    update korlix_agent_workflow_attempts set state='cancelled',charged=false,finished_at=now() where id=a.id;
   end if;
   next_state:='cancelled';event_name:='cancelled';
  elsif p_action='delete' then
   if w.state not in('completed','cancelled') then raise exception 'Finish or cancel this workflow before deleting it.' using errcode='40001';end if;
   delete from korlix_agent_workflows where id=w.id and owner_id=p_actor;return jsonb_build_object('deleted',true);
  else raise exception 'Unknown workflow action.';end if;
 end if;
 ev:=w.events||jsonb_build_array(jsonb_build_object('type',event_name,'step',w.cursor,'at',now()));
 select coalesce(jsonb_agg(v order by n),'[]'::jsonb) into ev from jsonb_array_elements(ev) with ordinality as e(v,n) where n>jsonb_array_length(ev)-200;
 step_no:=w.cursor;
 update korlix_agent_workflows set steps=case when s is null then w.steps else jsonb_set(w.steps,array[step_no::text],s) end,
  state=next_state,resume_state=w.resume_state,attempt_id=w.attempt_id,cursor=case when p_action='approve' then w.cursor+1 else w.cursor end,
  events=ev,revision=w.revision+1,updated_at=now() where id=w.id and owner_id=p_actor returning * into w;
 return to_jsonb(w)-'owner_id';
end $$;
revoke all on function public.korlix_agent_workflow_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_agent_workflow_v1(uuid,text,uuid,jsonb) to service_role;
comment on table public.korlix_agent_workflows is 'Private reviewed agent workflows. API validates authenticated ownership; only service_role may access.';
