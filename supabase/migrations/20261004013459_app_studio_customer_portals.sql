-- Fixed-workflow customer portals. Project code is never executed by the hosted runtime.
-- Narrow auth reads let the SECURITY INVOKER service RPC enforce current sessions,
-- verified invitation email and banned/deleted account checks without a definer function.
grant usage on schema auth to service_role;
grant select(id,email,email_confirmed_at,banned_until) on auth.users to service_role;
grant select(id,user_id,not_after) on auth.sessions to service_role;
create table public.korlix_app_portals (
 id uuid primary key references public.korlix_app_projects(id) on delete cascade,
 owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 80), description text not null default '' check(length(description)<=1800),
 accent text not null check(accent ~ '^#[0-9a-fA-F]{6}$'), theme text not null check(theme in('light','dark')),
 payment_url text not null default '' check(length(payment_url)<=2048), published boolean not null default false,
 version integer not null default 1, project_version integer not null,
 spec jsonb not null check(octet_length(spec::text)<=70000),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index korlix_app_portals_owner on public.korlix_app_portals(owner_id);
create table public.korlix_app_portal_members (
 portal_id uuid not null references public.korlix_app_portals(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in('staff','customer')), email text not null, joined_at timestamptz not null default now(),
 primary key(portal_id,user_id)
);
create index korlix_app_portal_members_user on public.korlix_app_portal_members(user_id);
create table public.korlix_app_portal_invites (
 id uuid primary key,portal_id uuid not null references public.korlix_app_portals(id) on delete cascade,
 email text not null check(length(email)<=254),role text not null check(role in('staff','customer')),
 code_hash text unique not null check(code_hash ~ '^[a-f0-9]{64}$'),expires_at timestamptz not null,
 created_at timestamptz not null default now(),used_at timestamptz,revoked_at timestamptz
);
create index korlix_app_portal_invites_portal on public.korlix_app_portal_invites(portal_id);
create table public.korlix_app_portal_sessions (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 portal_id uuid not null references public.korlix_app_portals(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 auth_session_id uuid not null,kind text not null check(kind in('launch','session')),
 expires_at timestamptz not null,created_at timestamptz not null default now()
);
create index korlix_app_portal_sessions_user on public.korlix_app_portal_sessions(user_id);
create index korlix_app_portal_sessions_portal on public.korlix_app_portal_sessions(portal_id);
create index korlix_app_portal_sessions_expiry on public.korlix_app_portal_sessions(expires_at);
create table public.korlix_app_portal_requests (
 id uuid primary key,portal_id uuid not null references public.korlix_app_portals(id) on delete cascade,
 customer_id uuid references auth.users(id) on delete set null, customer_email text not null,
 title text not null check(length(title) between 1 and 160),description text not null check(length(description) between 1 and 6000),
 status text not null default 'open' check(status in('open','in_progress','waiting','completed','cancelled')),
 version integer not null default 1,request_hash text not null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index korlix_app_portal_requests_portal on public.korlix_app_portal_requests(portal_id,updated_at desc,id);
create index korlix_app_portal_requests_customer on public.korlix_app_portal_requests(customer_id);
create table public.korlix_app_portal_messages (
 id uuid primary key,request_id uuid not null references public.korlix_app_portal_requests(id) on delete cascade,
 author_id uuid references auth.users(id) on delete set null,author_role text not null,body text not null check(length(body) between 1 and 6000),
 request_hash text not null,created_at timestamptz not null default now()
);
create index korlix_app_portal_messages_request on public.korlix_app_portal_messages(request_id,created_at,id);
create index korlix_app_portal_messages_author on public.korlix_app_portal_messages(author_id);
create table public.korlix_app_portal_files (
 id uuid primary key,portal_id uuid not null references public.korlix_app_portals(id) on delete cascade,
 request_id uuid not null references public.korlix_app_portal_requests(id) on delete cascade,
 author_id uuid references auth.users(id) on delete set null,
 name text not null check(length(name) between 1 and 120),mime text not null check(mime in('image/jpeg','application/pdf')),
 bytes integer not null check(bytes between 1 and 5242880),sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),path text unique not null,
 state text not null default 'pending' check(state in('pending','ready')), created_at timestamptz not null default now()
);
create index korlix_app_portal_files_portal on public.korlix_app_portal_files(portal_id);
create index korlix_app_portal_files_request on public.korlix_app_portal_files(request_id);
create index korlix_app_portal_files_author on public.korlix_app_portal_files(author_id);
-- Deliberately no foreign key: cleanup must survive project/account cascades.
create table public.korlix_app_portal_gc(path text primary key,created_at timestamptz not null default now());
create function public.korlix_app_portal_file_gc() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin insert into public.korlix_app_portal_gc(path) values(old.path) on conflict do nothing;return old;end;$$;
create trigger korlix_app_portal_file_delete before delete on public.korlix_app_portal_files for each row execute function public.korlix_app_portal_file_gc();
revoke all on function public.korlix_app_portal_file_gc() from public,anon,authenticated;
grant execute on function public.korlix_app_portal_file_gc() to service_role;
alter table public.korlix_app_portals enable row level security;
alter table public.korlix_app_portal_members enable row level security;
alter table public.korlix_app_portal_invites enable row level security;
alter table public.korlix_app_portal_sessions enable row level security;
alter table public.korlix_app_portal_requests enable row level security;
alter table public.korlix_app_portal_messages enable row level security;
alter table public.korlix_app_portal_files enable row level security;
alter table public.korlix_app_portal_gc enable row level security;
revoke all on public.korlix_app_portals,public.korlix_app_portal_members,public.korlix_app_portal_invites,public.korlix_app_portal_sessions,public.korlix_app_portal_requests,public.korlix_app_portal_messages,public.korlix_app_portal_files,public.korlix_app_portal_gc from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_app_portals,public.korlix_app_portal_members,public.korlix_app_portal_invites,public.korlix_app_portal_sessions,public.korlix_app_portal_requests,public.korlix_app_portal_messages,public.korlix_app_portal_files,public.korlix_app_portal_gc to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('korlix-app-portals','korlix-app-portals',false,5242880,array['image/jpeg','application/pdf']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy korlix_app_portals_server_only on storage.objects as restrictive for all to anon,authenticated using(bucket_id<>'korlix-app-portals') with check(bucket_id<>'korlix-app-portals');
create function public.korlix_app_portal_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare p public.korlix_app_portals;pr public.korlix_app_projects;m public.korlix_app_portal_members;i public.korlix_app_portal_invites;
 s public.korlix_app_portal_sessions;r public.korlix_app_portal_requests;msg public.korlix_app_portal_messages;f public.korlix_app_portal_files;
 actor uuid:=p_actor;email_address text;access_role text;h text;pid uuid;data jsonb;uid uuid;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>100000 then raise exception 'Invalid customer portal request.';end if;
 if p_action='cleanup' then
  delete from public.korlix_app_portal_sessions where expires_at<now();
  delete from public.korlix_app_portal_invites where expires_at<now()-interval '30 days';
  delete from public.korlix_app_portal_files where state='pending' and created_at<now()-interval '10 minutes';
  return coalesce((select jsonb_agg(path) from (select path from public.korlix_app_portal_gc where created_at<now()-interval '2 minutes' order by created_at limit 100) x),'[]');
 elsif p_action='cleanup_done' then
  delete from public.korlix_app_portal_gc where path in(select jsonb_array_elements_text(p_data->'paths'));return '{}';
 end if;
 if p_data?'session_hash' or p_action='exchange' then
  select * into s from public.korlix_app_portal_sessions where token_hash=p_data->>'session_hash' and portal_id=p_id and expires_at>now() for update;
  if not found or s.kind<>(case when p_action='exchange' then 'launch' else 'session' end) then raise exception 'Open this portal from KORLIX again.' using errcode='42501';end if;
  if not exists(select 1 from auth.sessions a where a.id=s.auth_session_id and a.user_id=s.user_id and (a.not_after is null or a.not_after>now())) then raise exception 'Your KORLIX session has ended. Sign in again.' using errcode='42501';end if;
  actor:=s.user_id;
 end if;
 if actor is null then raise exception 'Sign in to use customer portals.' using errcode='42501';end if;
 select lower(trim(email)) into email_address from auth.users where id=actor and email_confirmed_at is not null and (banned_until is null or banned_until<now());
 if not found or coalesce(email_address,'')='' then raise exception 'Use a verified KORLIX account to open customer portals.' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('portals',coalesce((select jsonb_agg(to_jsonb(x) order by updated_at desc) from (select z.id,z.id as project_id,z.name,z.description,z.accent,z.theme,z.published,z.version,z.project_version,z.payment_url,z.updated_at,case when z.owner_id=actor then 'owner' else mm.role end as role from public.korlix_app_portals z left join public.korlix_app_portal_members mm on mm.portal_id=z.id and mm.user_id=actor where z.owner_id=actor or mm.user_id=actor) x),'[]'));
 elsif p_action in('manage','save') then
  perform pg_advisory_xact_lock(hashtextextended(actor::text,228));
  select * into pr from public.korlix_app_projects where id=p_id and owner_id=actor for update;
  if not found then raise exception 'Project not found.' using errcode='P0002';end if;
  select * into p from public.korlix_app_portals where id=p_id for update;
  if p_action='save' then
   if pr.version=0 or pr.version is distinct from (p_data->>'project_version')::integer then raise exception 'Your app design changed. Reload before publishing.' using errcode='40001';end if;
   if coalesce(p.version,0) is distinct from (p_data->>'version')::integer then raise exception 'Your portal changed. Reload before saving.' using errcode='40001';end if;
   if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before changing publication.';end if;
   insert into public.korlix_app_portals(id,owner_id,name,description,accent,theme,payment_url,published,project_version,spec)
    values(pr.id,actor,p_data->>'name',p_data->>'description',pr.spec->>'accent',pr.spec->>'theme',p_data->>'payment_url',(p_data->>'published')::boolean,pr.version,pr.spec)
    on conflict(id) do update set name=excluded.name,description=excluded.description,accent=excluded.accent,theme=excluded.theme,payment_url=excluded.payment_url,published=excluded.published,project_version=excluded.project_version,spec=excluded.spec,version=korlix_app_portals.version+1,updated_at=now() returning * into p;
   -- A new publication requires all runtimes to relaunch against the frozen version.
   delete from public.korlix_app_portal_sessions where portal_id=p.id;
  end if;
  if p.id is null then return jsonb_build_object('portal',null,'members','[]'::jsonb,'invites','[]'::jsonb);end if;
  return jsonb_build_object('portal',to_jsonb(p)-'owner_id'-'spec'||jsonb_build_object('role','owner','project_id',p.id),
   'members',coalesce((select jsonb_agg(to_jsonb(x)-'portal_id' order by joined_at) from public.korlix_app_portal_members x where portal_id=p.id),'[]'),
   'invites',coalesce((select jsonb_agg(to_jsonb(x)-'portal_id'-'code_hash' order by created_at desc) from public.korlix_app_portal_invites x where portal_id=p.id),'[]'));
 elsif p_action='join' then
  select * into i from public.korlix_app_portal_invites where code_hash=p_data->>'code_hash';
  if not found or i.email<>email_address or i.expires_at<=now() or i.used_at is not null or i.revoked_at is not null then raise exception 'This invitation is unavailable or belongs to a different verified email.' using errcode='P0002';end if;
  pid:=i.portal_id;
 else pid:=p_id;end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,229));
 select * into p from public.korlix_app_portals where id=pid for update;
 if not found then raise exception 'Portal not found.' using errcode='P0002';end if;
 access_role:=case when p.owner_id=actor then 'owner' else (select role from public.korlix_app_portal_members where portal_id=p.id and user_id=actor) end;
 if p_action='join' then
  select * into i from public.korlix_app_portal_invites where id=i.id for update;
  if not found or i.email<>email_address or i.expires_at<=now() or i.used_at is not null or i.revoked_at is not null or (p_data?'portal_id' and (p_data->>'portal_id')::uuid<>p.id) then raise exception 'This invitation is unavailable or belongs to a different portal.' using errcode='P0002';end if;
  if not p.published then raise exception 'This portal is currently unavailable.' using errcode='P0002';end if;
  if p.owner_id<>actor then
   if (select count(*) from public.korlix_app_portal_members where portal_id=p.id)>=500 and access_role is null then raise exception 'This portal has reached its member limit.' using errcode='54000';end if;
   insert into public.korlix_app_portal_members(portal_id,user_id,role,email) values(p.id,actor,i.role,email_address) on conflict(portal_id,user_id) do update set role=excluded.role,email=excluded.email;
   access_role:=i.role;
  end if;
  update public.korlix_app_portal_invites set used_at=now() where id=i.id;
  update public.korlix_app_portal_invites set revoked_at=now() where portal_id=p.id and email=email_address and id<>i.id and used_at is null;
  delete from public.korlix_app_portal_sessions where portal_id=p.id and user_id=actor;
  return jsonb_build_object('portal',to_jsonb(p)-'owner_id'-'spec'||jsonb_build_object('role',access_role,'project_id',p.id));
 end if;
 if access_role is null then raise exception 'Portal not found.' using errcode='P0002';end if;
 if p_action in('invite','invite_revoke','member_remove') then
  if access_role<>'owner' then raise exception 'Only the portal owner can manage access.' using errcode='42501';end if;
  if p_action='invite' then
   if (select count(*) from public.korlix_app_portal_invites where portal_id=p.id and expires_at>now() and used_at is null and revoked_at is null)>=50 then raise exception 'Revoke an unused invitation before creating another.' using errcode='54000';end if;
   update public.korlix_app_portal_invites set revoked_at=now() where portal_id=p.id and email=p_data->>'email' and used_at is null;
   insert into public.korlix_app_portal_invites(id,portal_id,email,role,code_hash,expires_at) values((p_data->>'id')::uuid,p.id,p_data->>'email',p_data->>'role',p_data->>'code_hash',now()+make_interval(days=>least(30,greatest(1,(p_data->>'expires_days')::integer)))) returning * into i;
   return jsonb_build_object('invite',to_jsonb(i)-'code_hash'-'portal_id');
  elsif p_action='invite_revoke' then
   update public.korlix_app_portal_invites set revoked_at=now() where id=(p_data->>'invite_id')::uuid and portal_id=p.id;
  else
   uid:=(p_data->>'user_id')::uuid;
   update public.korlix_app_portal_invites set revoked_at=now() where portal_id=p.id and email=(select email from public.korlix_app_portal_members where portal_id=p.id and user_id=uid) and used_at is null;
   delete from public.korlix_app_portal_members where portal_id=p.id and user_id=uid;
   delete from public.korlix_app_portal_sessions where portal_id=p.id and user_id=uid;
  end if;return '{}';
 end if;
 if p_action='get' then return jsonb_build_object('portal',to_jsonb(p)-'owner_id'-'spec'||jsonb_build_object('role',access_role,'project_id',p.id));end if;
 if not p.published then raise exception 'This portal is currently unpublished.' using errcode='P0002';end if;
 if p_action='launch' then
  if not exists(select 1 from auth.sessions a where a.id=(p_data->>'auth_session_id')::uuid and a.user_id=actor and (a.not_after is null or a.not_after>now())) then raise exception 'Sign in to KORLIX again before opening the portal.' using errcode='42501';end if;
  delete from public.korlix_app_portal_sessions where user_id=actor and (expires_at<now() or (portal_id=p.id and kind='launch'));
  if (select count(*) from public.korlix_app_portal_sessions where user_id=actor)>=30 then raise exception 'Close older portal sessions or wait before opening more.' using errcode='54000';end if;
  insert into public.korlix_app_portal_sessions(token_hash,portal_id,user_id,auth_session_id,kind,expires_at) values(p_data->>'token_hash',p.id,actor,(p_data->>'auth_session_id')::uuid,'launch',now()+interval '60 seconds');return '{}';
 elsif p_action='exchange' then
  delete from public.korlix_app_portal_sessions where token_hash=s.token_hash;
  insert into public.korlix_app_portal_sessions(token_hash,portal_id,user_id,auth_session_id,kind,expires_at) values(p_data->>'token_hash',p.id,actor,s.auth_session_id,'session',now()+interval '1 hour');
  return jsonb_build_object('portal',to_jsonb(p)-'owner_id'-'spec'||jsonb_build_object('role',access_role,'project_id',p.id),'expires_in',3600);
 elsif p_action='logout' then delete from public.korlix_app_portal_sessions where token_hash=s.token_hash;return '{}';
 elsif p_action='requests' then
  return jsonb_build_object('portal',to_jsonb(p)-'owner_id'-'spec'||jsonb_build_object('role',access_role,'project_id',p.id),'requests',coalesce((select jsonb_agg(to_jsonb(x)-'request_hash'-'portal_id' order by updated_at desc,id) from public.korlix_app_portal_requests x where portal_id=p.id and (access_role<>'customer' or customer_id=actor)),'[]'));
 elsif p_action='request_create' then
  h:=encode(sha256(convert_to((p_data-'session_hash')::text,'UTF8')),'hex');
  select * into r from public.korlix_app_portal_requests where id=(p_data->>'id')::uuid and portal_id=p.id and customer_id=actor;
  if found then if r.request_hash<>h then raise exception 'Use a new request after editing.' using errcode='40001';end if;return to_jsonb(r)-'request_hash'-'portal_id';end if;
  if (select count(*) from public.korlix_app_portal_requests where portal_id=p.id)>=1000 then raise exception 'This portal has reached its request limit. Ask the owner to remove older requests.' using errcode='54000';end if;
  if (select count(*) from public.korlix_app_portal_requests where portal_id=p.id and customer_id=actor and created_at>now()-interval '1 hour')>=20 then raise exception 'Please wait before submitting more requests.' using errcode='54000';end if;
  insert into public.korlix_app_portal_requests(id,portal_id,customer_id,customer_email,title,description,request_hash) values((p_data->>'id')::uuid,p.id,actor,email_address,p_data->>'title',p_data->>'description',h) returning * into r;
  return to_jsonb(r)-'request_hash'-'portal_id';
 end if;
 if p_action in('file_get','file_delete','file_finish') then
  select * into f from public.korlix_app_portal_files where id=(p_data->>'file_id')::uuid and portal_id=p.id;
  if not found then raise exception 'File not found.' using errcode='P0002';end if;
  uid:=f.request_id;
 else uid:=(p_data->>'request_id')::uuid;end if;
 select * into r from public.korlix_app_portal_requests where id=uid and portal_id=p.id and (access_role<>'customer' or customer_id=actor) for update;
 if not found then raise exception 'Request not found.' using errcode='P0002';end if;
 if p_action='request_get' then
  return jsonb_build_object('request',to_jsonb(r)-'request_hash'-'portal_id','messages',coalesce((select jsonb_agg(to_jsonb(x)-'request_hash' order by created_at,id) from public.korlix_app_portal_messages x where request_id=r.id),'[]'),'files',coalesce((select jsonb_agg(to_jsonb(x)-'path'-'sha256'-'portal_id' order by created_at,id) from public.korlix_app_portal_files x where request_id=r.id and state='ready'),'[]'));
 elsif p_action='request_status' then
  if access_role='customer' then raise exception 'Only staff can change the request status.' using errcode='42501';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'This request changed. Reload before updating.' using errcode='40001';end if;
  update public.korlix_app_portal_requests set status=p_data->>'status',version=version+1,updated_at=now() where id=r.id returning * into r;return to_jsonb(r)-'request_hash'-'portal_id';
 elsif p_action='request_delete' then
  if access_role='customer' then raise exception 'Only staff can remove requests.' using errcode='42501';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'This request changed. Reload before removing.' using errcode='40001';end if;
  delete from public.korlix_app_portal_requests where id=r.id;return '{}';
 elsif p_action='message' then
  h:=encode(sha256(convert_to((p_data-'session_hash')::text,'UTF8')),'hex');
  select * into msg from public.korlix_app_portal_messages where id=(p_data->>'id')::uuid and request_id=r.id and author_id=actor;
  if found then if msg.request_hash<>h then raise exception 'Use a new reply after editing.' using errcode='40001';end if;return '{}';end if;
  if (select count(*) from public.korlix_app_portal_messages where request_id=r.id)>=200 then raise exception 'This conversation has reached its reply limit.' using errcode='54000';end if;
  insert into public.korlix_app_portal_messages(id,request_id,author_id,author_role,body,request_hash) values((p_data->>'id')::uuid,r.id,actor,access_role,p_data->>'body',h);
  update public.korlix_app_portal_requests set updated_at=now() where id=r.id;return '{}';
 elsif p_action='file_begin' then
  if (select count(*) from public.korlix_app_portal_files where request_id=r.id)>=10 then raise exception 'Each request can hold up to ten files.' using errcode='54000';end if;
  if coalesce((select sum(bytes) from public.korlix_app_portal_files where portal_id=p.id),0)+(p_data->>'bytes')::integer>104857600 then raise exception 'This portal has reached its 100 MB file limit. Remove older attachments first.' using errcode='54000';end if;
  insert into public.korlix_app_portal_files(id,portal_id,request_id,author_id,name,mime,bytes,sha256,path) values((p_data->>'file_id')::uuid,p.id,r.id,actor,p_data->>'name',p_data->>'mime',(p_data->>'bytes')::integer,p_data->>'sha256',p.id::text||'/'||r.id::text||'/'||(p_data->>'file_id')) returning * into f;return to_jsonb(f);
 elsif p_action='file_finish' then
  if f.author_id is distinct from actor then raise exception 'File not found.' using errcode='P0002';end if;
  update public.korlix_app_portal_files set state='ready' where id=f.id;return '{}';
 elsif p_action='file_get' then
  if f.state<>'ready' then raise exception 'This file is still uploading.' using errcode='40001';end if;return to_jsonb(f);
 elsif p_action='file_delete' then
  if access_role='customer' and f.author_id is distinct from actor then raise exception 'Only staff can remove this attachment.' using errcode='42501';end if;
  delete from public.korlix_app_portal_files where id=f.id;return '{}';
 end if;
 raise exception 'Unsupported customer portal action.';
end;$$;
revoke all on function public.korlix_app_portal_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_app_portal_v1(uuid,text,uuid,jsonb) to service_role;
