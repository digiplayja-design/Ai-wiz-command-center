-- Private App Studio projects, recoverable builds and immutable version snapshots.
create table public.korlix_app_projects (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null, brief jsonb not null check(octet_length(brief::text)<=16000),
 create_hash text not null, spec jsonb not null default '{}' check(octet_length(spec::text)<=70000),
 version integer not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index korlix_app_projects_owner on public.korlix_app_projects(owner_id,updated_at desc,id);
create table public.korlix_app_versions (
 id uuid primary key, project_id uuid not null references public.korlix_app_projects(id) on delete cascade,
 version integer not null, spec jsonb not null check(octet_length(spec::text)<=70000),
 label text not null, request_hash text not null, created_at timestamptz not null default now(), unique(project_id,version)
);
create table public.korlix_app_runs (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 project_id uuid references public.korlix_app_projects(id) on delete set null,
 state text not null default 'running' check(state in ('running','completed','failed')),
 input jsonb not null check(octet_length(input::text)<=85000), request_hash text not null,
 usage_id uuid not null references public.usage_counters(id), charged integer not null default 1 check(charged in(0,1)),
 error text, version integer, created_at timestamptz not null default now(), finished_at timestamptz
);
create unique index korlix_app_one_running on public.korlix_app_runs(owner_id) where state='running';
create index korlix_app_runs_owner on public.korlix_app_runs(owner_id,created_at desc);
create index korlix_app_runs_project on public.korlix_app_runs(project_id);
create index korlix_app_runs_usage on public.korlix_app_runs(usage_id);
alter table public.korlix_app_projects enable row level security;
alter table public.korlix_app_versions enable row level security;
alter table public.korlix_app_runs enable row level security;
revoke all on public.korlix_app_projects,public.korlix_app_versions,public.korlix_app_runs from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_app_projects,public.korlix_app_versions,public.korlix_app_runs to service_role;
create function public.korlix_app_studio_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare p public.korlix_app_projects;v public.korlix_app_versions;r public.korlix_app_runs;h text;uid uuid;nextspec jsonb;projectid uuid;
begin
 if p_actor is null then raise exception 'Sign in to use App Studio.' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>100000 then raise exception 'Invalid App Studio request.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,228));
 for r in update public.korlix_app_runs set state='failed',charged=0,input=jsonb_build_object('request',input->'request'),error='This build was interrupted. Your credit was returned. Start a new build.',finished_at=now()
  where owner_id=p_actor and state='running' and created_at<now()-interval '12 minutes' returning * loop
  update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=r.usage_id and user_id=p_actor;
 end loop;
 if p_action='list' then
  return jsonb_build_object('projects',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id'-'create_hash'-'spec' order by updated_at desc,id) from public.korlix_app_projects x where owner_id=p_actor),'[]'));
 elsif p_action='create' then
  h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  select * into p from public.korlix_app_projects where id=p_id and owner_id=p_actor;
  if found then
   if p.create_hash<>h then raise exception 'Use a new project request after changing the idea.' using errcode='40001';end if;
  else
   if (select count(*) from public.korlix_app_projects where owner_id=p_actor)>=50 then raise exception 'Your 50-project workspace is full. Export and remove an older project.' using errcode='54000';end if;
   insert into public.korlix_app_projects(id,owner_id,name,brief,spec,version,create_hash)
    values(p_id,p_actor,left(p_data->>'name',80),p_data->'brief',p_data->'spec',case when p_data->'spec'='{}'::jsonb then 0 else 1 end,h) returning * into p;
   if p.version=1 then insert into public.korlix_app_versions(id,project_id,version,spec,label,request_hash) values(p.id,p.id,1,p.spec,'Starter template',h);end if;
  end if;
  return to_jsonb(p)-'owner_id'-'create_hash';
 elsif p_action in('run_get','run_finish','run_fail') then
  select * into r from public.korlix_app_runs where id=p_id and owner_id=p_actor for update;
  if not found then raise exception 'Build not found.' using errcode='P0002';end if;
  if p_action='run_get' then return to_jsonb(r)-'owner_id'-'usage_id'-'request_hash';end if;
  if r.state<>'running' then return to_jsonb(r)-'owner_id'-'usage_id'-'request_hash';end if;
  if p_action='run_fail' then
   update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=r.usage_id and user_id=p_actor;
   update public.korlix_app_runs set state='failed',charged=0,input=jsonb_build_object('request',input->'request'),error=left(p_data->>'error',400),finished_at=now() where id=r.id returning * into r;
  else
   select * into p from public.korlix_app_projects where id=r.project_id and owner_id=p_actor for update;
   if not found or p.version is distinct from (r.input->>'baseVersion')::integer then raise exception 'The project changed while this build was running.' using errcode='40001';end if;
   update public.korlix_app_projects set spec=p_data->'spec',name=left(p_data->'spec'->>'name',80),version=version+1,updated_at=now() where id=p.id returning * into p;
   insert into public.korlix_app_versions(id,project_id,version,spec,label,request_hash) values(r.id,p.id,p.version,p.spec,left(r.input->>'message',140),r.request_hash);
   update public.korlix_app_runs set state='completed',input=jsonb_build_object('request',input->'request'),version=p.version,finished_at=now() where id=r.id returning * into r;
   delete from public.korlix_app_versions where project_id=p.id and version<p.version-29;
  end if;
  return to_jsonb(r)-'owner_id'-'usage_id'-'request_hash';
 elsif p_action='run_begin' then
  h:=encode(sha256(convert_to((p_data->'request')::text,'UTF8')),'hex');
  select * into r from public.korlix_app_runs where id=p_id and owner_id=p_actor;
  if found then
   if r.request_hash<>h or r.project_id is null then raise exception 'Use a new build request after editing your instructions.' using errcode='40001';end if;
   return (to_jsonb(r)-'owner_id'-'usage_id'-'request_hash')||jsonb_build_object('replayed',true);
  end if;
  select * into p from public.korlix_app_projects where id=(p_data->'request'->>'projectId')::uuid and owner_id=p_actor for update;
  if not found then raise exception 'Project not found.' using errcode='P0002';end if;
  if p.version is distinct from (p_data->'request'->>'version')::integer then raise exception 'Your project changed elsewhere. Reload before building.' using errcode='40001';end if;
  if exists(select 1 from public.korlix_app_runs where owner_id=p_actor and state='running') then raise exception 'A build is already running. Open your projects to follow it.' using errcode='40001';end if;
  if (select count(*) from public.korlix_app_runs where owner_id=p_actor and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before requesting more builds.' using errcode='54000';end if;
  uid:=(p_data->>'usage_id')::uuid;
  perform 1 from public.usage_counters where id=uid and user_id=p_actor for update;
  if not found then raise exception 'Usage could not be verified.' using errcode='40001';end if;
  if (p_data->>'credit_limit')::integer is null or (p_data->>'request_limit')::integer is null then raise exception 'Usage limits could not be verified.' using errcode='42501';end if;
  update public.usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now()
   where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer
    and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;
  if not found then raise exception 'Your daily generation allowance is used. Try again when it renews.' using errcode='54000';end if;
  insert into public.korlix_app_runs(id,owner_id,project_id,input,request_hash,usage_id) values(p_id,p_actor,p.id,
   jsonb_build_object('brief',p.brief,'baseSpec',p.spec,'baseVersion',p.version,'message',p_data->'request'->>'message','request',p_data->'request'),h,uid) returning * into r;
  return (to_jsonb(r)-'owner_id'-'usage_id'-'request_hash')||jsonb_build_object('replayed',false);
 end if;
 select * into p from public.korlix_app_projects where id=p_id and owner_id=p_actor for update;
 if not found then raise exception 'Project not found.' using errcode='P0002';end if;
 if p_action='get' then
  return jsonb_build_object('project',to_jsonb(p)-'owner_id'-'create_hash','versions',coalesce((select jsonb_agg(to_jsonb(x)-'spec'-'request_hash' order by version desc) from public.korlix_app_versions x where project_id=p.id),'[]'),
   'run',(select to_jsonb(x)-'owner_id'-'usage_id'-'request_hash'-'input'||jsonb_build_object('message',x.input->'request'->>'message') from public.korlix_app_runs x where project_id=p.id order by created_at desc,id desc limit 1));
 elsif p_action='version' then
  select * into v from public.korlix_app_versions where id=(p_data->>'version_id')::uuid and project_id=p.id;
  if not found then raise exception 'Version not found.' using errcode='P0002';end if;return to_jsonb(v)-'request_hash';
 end if;
 if p_action in('save','restore') then
  h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  select * into v from public.korlix_app_versions where id=(p_data->>'request_key')::uuid and project_id=p.id;
  if found then
   if v.request_hash<>h then raise exception 'Use a new request after editing.' using errcode='40001';end if;
   return to_jsonb(p)-'owner_id'-'create_hash';
  end if;
 end if;
 if exists(select 1 from public.korlix_app_runs where project_id=p.id and state='running') then raise exception 'Wait for the current build to finish before changing or removing this project.' using errcode='40001';end if;
 if p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before deleting the project.';end if;
  update public.korlix_app_runs set input='{}',error=null where project_id=p.id;
  delete from public.korlix_app_projects where id=p.id;return jsonb_build_object('removed',true);
 elsif p_action in('save','restore') then
  if p.version is distinct from (p_data->>'version')::integer then raise exception 'Your project changed elsewhere. Reload before saving.' using errcode='40001';end if;
  if p_action='restore' then
   select spec into nextspec from public.korlix_app_versions where id=(p_data->>'version_id')::uuid and project_id=p.id;
   if not found then raise exception 'Version not found.' using errcode='P0002';end if;
  else nextspec:=p_data->'spec';end if;
  update public.korlix_app_projects set spec=nextspec,name=left(nextspec->>'name',80),version=version+1,updated_at=now() where id=p.id returning * into p;
  insert into public.korlix_app_versions(id,project_id,version,spec,label,request_hash) values((p_data->>'request_key')::uuid,p.id,p.version,p.spec,case when p_action='restore' then 'Restored an earlier version' else 'Updated app styling' end,h);
  delete from public.korlix_app_versions where project_id=p.id and version<p.version-29;
  return to_jsonb(p)-'owner_id'-'create_hash';
 end if;
 raise exception 'Unknown App Studio operation.';
end $$;
revoke all on function public.korlix_app_studio_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_app_studio_v1(uuid,text,uuid,jsonb) to service_role;
