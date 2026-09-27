-- Private Music Studio jobs, usage reservations and versioned drafts.
create table public.korlix_music_jobs (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 payload jsonb not null check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=20000),
 payload_hash text not null, cycle text not null,
 state text not null check(state in ('submitting','submitted','processing','completed','partial','failed','uncertain')),
 task_id text, tracks jsonb not null default '[]' check(jsonb_typeof(tracks)='array' and octet_length(tracks::text)<=150000),
 quota_held boolean not null default true, accepted boolean not null default false,
 error text, favorite boolean not null default false, hidden boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), polled_at timestamptz
);
create index korlix_music_jobs_owner_created on public.korlix_music_jobs(owner_id,created_at desc,id desc) where not hidden;
create index korlix_music_jobs_usage on public.korlix_music_jobs(owner_id,cycle) where quota_held;
create table public.korlix_music_drafts (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 version integer not null default 1, data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=20000),
 request_key uuid not null, request_hash text not null, updated_at timestamptz not null default now()
);
alter table public.korlix_music_jobs enable row level security;
alter table public.korlix_music_drafts enable row level security;
revoke all on public.korlix_music_jobs,public.korlix_music_drafts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_music_jobs,public.korlix_music_drafts to service_role;
create function public.korlix_music_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare j public.korlix_music_jobs;d public.korlix_music_drafts;h text;cy text:=to_char(now() at time zone 'UTC','YYYY-MM');n integer;lim integer;cursor_time timestamptz;rows jsonb;
begin
 if p_actor is null then raise exception 'Sign in to use Music Studio.' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>180000 then raise exception 'Invalid Music Studio request.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,227));
 update public.korlix_music_jobs set state='uncertain',error='Submission could not be confirmed. Do not submit the same idea again until support checks this request.',updated_at=now()
  where owner_id=p_actor and state='submitting' and created_at<now()-interval '2 minutes';
 if p_action='usage' then
  select count(*)::integer into n from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held;
  return jsonb_build_object('cycle',cy,'usedThisCycle',(select count(*) from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held and accepted),
    'reservedThisCycle',(select count(*) from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held and not accepted),'allocated',n);
 end if;
 if p_action='list' then
  if p_id is not null then
   select created_at into cursor_time from public.korlix_music_jobs where owner_id=p_actor and id=p_id;
   if not found then raise exception 'Refresh your music library.' using errcode='P0002';end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)-'owner_id'-'payload_hash' order by x.created_at desc,x.id desc),'[]') into rows
   from (select * from public.korlix_music_jobs where owner_id=p_actor and not hidden and (coalesce(p_data->>'query','')='' or position(lower(p_data->>'query') in lower(payload::text||tracks::text))>0) and (p_data->'favorites' is distinct from 'true'::jsonb or favorite) and (p_id is null or (created_at,id)<(cursor_time,p_id)) order by created_at desc,id desc limit 31)x;
  return jsonb_build_object('jobs',rows);
 end if;
 if p_action='draft_get' then
  select * into d from public.korlix_music_drafts where owner_id=p_actor;
  return case when found then jsonb_build_object('version',d.version,'data',d.data,'updatedAt',d.updated_at) else jsonb_build_object('version',0,'data','{}'::jsonb) end;
 end if;
 if p_action='draft_save' then
  h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  select * into d from public.korlix_music_drafts where owner_id=p_actor;
  if found and d.request_key=p_id then
   if d.request_hash<>h then raise exception 'Use a new request after editing the draft.' using errcode='40001';end if;
  else
   if coalesce(d.version,0) is distinct from (p_data->>'version')::integer then raise exception 'Your saved draft changed elsewhere. Reload it before saving.' using errcode='40001';end if;
   insert into public.korlix_music_drafts(owner_id,version,data,request_key,request_hash) values(p_actor,1,p_data->'data',p_id,h)
    on conflict(owner_id) do update set version=korlix_music_drafts.version+1,data=excluded.data,request_key=excluded.request_key,request_hash=excluded.request_hash,updated_at=now() returning * into d;
  end if;
  return jsonb_build_object('version',d.version,'data',d.data,'updatedAt',d.updated_at);
 end if;
 if p_action='begin' then
  h:=encode(sha256(convert_to((p_data->'payload')::text,'UTF8')),'hex');
  select * into j from public.korlix_music_jobs where id=p_id and owner_id=p_actor;
  if found then
   if j.payload_hash<>h or j.hidden then raise exception 'Use a new request after changing your music idea.' using errcode='40001';end if;
   return jsonb_build_object('job',to_jsonb(j)-'owner_id'-'payload_hash','replayed',true);
  end if;
  lim:=(p_data->>'limit')::integer;
  if lim is null or lim<1 or lim>10000 then raise exception 'An active Music Production add-on is required.' using errcode='42501';end if;
  if (select count(*) from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held)>=lim then raise exception 'Your monthly music allowance is used or reserved. Check My tracks before creating another.' using errcode='54000';end if;
  if (select count(*) from public.korlix_music_jobs where owner_id=p_actor and state in ('submitting','submitted','processing'))>=3 then raise exception 'Three creations are already in progress. Check My tracks.' using errcode='54000';end if;
  if (select count(*) from public.korlix_music_jobs where owner_id=p_actor and not hidden)>=2000 then raise exception 'Your library is full. Download and remove older creations first.' using errcode='54000';end if;
  insert into public.korlix_music_jobs(id,owner_id,payload,payload_hash,cycle,state) values(p_id,p_actor,p_data->'payload',h,cy,'submitting') returning * into j;
  return jsonb_build_object('job',to_jsonb(j)-'owner_id'-'payload_hash','replayed',false);
 end if;
 select * into j from public.korlix_music_jobs where id=p_id and owner_id=p_actor and not hidden for update;
 if not found then raise exception 'Music creation not found.' using errcode='P0002';end if;
 if p_action='get' then return to_jsonb(j)-'owner_id'-'payload_hash';end if;
 if p_action='accepted' then
  if j.task_id is not null and j.task_id<>p_data->>'task_id' then raise exception 'Music task conflict.' using errcode='40001';end if;
  if j.state not in ('submitting','uncertain') then return to_jsonb(j)-'owner_id'-'payload_hash';end if;
  if coalesce(length(p_data->>'task_id'),0) not between 1 and 200 then raise exception 'Music task was not confirmed.';end if;
  update public.korlix_music_jobs set task_id=p_data->>'task_id',accepted=true,state='submitted',error=null,updated_at=now() where id=j.id returning * into j;
 elsif p_action='submission_error' then
  if j.state not in ('submitting','uncertain') or j.task_id is not null then return to_jsonb(j)-'owner_id'-'payload_hash';end if;
  update public.korlix_music_jobs set state=case when p_data->'definite'='true'::jsonb then 'failed' else 'uncertain' end,
   quota_held=case when p_data->'definite'='true'::jsonb then false else true end,error=left(p_data->>'error',400),updated_at=now() where id=j.id returning * into j;
 elsif p_action='poll_begin' then
  if j.task_id is null or j.state not in ('submitted','processing') or j.polled_at>now()-interval '15 seconds' then return jsonb_build_object('job',to_jsonb(j)-'owner_id'-'payload_hash','poll',false);end if;
  update public.korlix_music_jobs set polled_at=now() where id=j.id returning * into j;
  return jsonb_build_object('job',to_jsonb(j)-'owner_id'-'payload_hash','poll',true);
 elsif p_action='result' then
  if j.state not in ('submitted','processing') then return to_jsonb(j)-'owner_id'-'payload_hash';end if;
  if p_data->>'state' not in ('processing','completed','partial','failed') then raise exception 'Invalid music status.';end if;
  update public.korlix_music_jobs set state=p_data->>'state',tracks=p_data->'tracks',error=left(p_data->>'error',400),updated_at=now() where id=j.id returning * into j;
 elsif p_action='favorite' then
  if jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'Choose a favorite status.';end if;
  update public.korlix_music_jobs set favorite=(p_data->>'favorite')::boolean where id=j.id returning * into j;
 elsif p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before removing this creation.';end if;
  if j.state in ('submitting','submitted','processing','uncertain') then raise exception 'Wait until this creation has finished before removing it.';end if;
  update public.korlix_music_jobs set hidden=true,payload='{}',tracks='[]',error=null,task_id=null,favorite=false,updated_at=now() where id=j.id;
  return jsonb_build_object('removed',true);
 else raise exception 'Unknown Music Studio action.';
 end if;
 return to_jsonb(j)-'owner_id'-'payload_hash';
end $$;
revoke all on function public.korlix_music_v2(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_music_v2(uuid,text,uuid,jsonb) to service_role;
