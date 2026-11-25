begin;

create table public.korlix_fax_lines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  is_company boolean not null default false,
  preference text not null check (preference = 'toll_free' or preference ~ '^[2-9][0-9]{2}$'),
  state text not null default 'requested' check (state in ('requested','ordering','active')),
  phone text unique check (phone ~ '^\+1[2-9][0-9]{9}$'),
  order_id text,
  created_at timestamptz not null default now(),
  check (state = 'requested' or phone is not null)
);
create unique index korlix_fax_one_company on public.korlix_fax_lines(is_company) where is_company;

create table public.korlix_fax_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  request_id uuid,
  carrier_id uuid,
  sender text not null,
  recipient text not null,
  name text not null,
  object_path text,
  status text not null check (status in ('preparing','submitting','checking','queued','sending','delivered','received','failed')),
  pages integer check (pages >= 0),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id,request_id),
  unique (direction,carrier_id)
);
create index korlix_fax_history on public.korlix_fax_documents(user_id,direction,created_at desc,id desc);

create table public.korlix_fax_sessions (
  token_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  expires_at timestamptz not null,
  unique (user_id,device_id)
);
create index korlix_fax_sessions_expiry on public.korlix_fax_sessions(expires_at);

alter table public.korlix_fax_lines enable row level security;
alter table public.korlix_fax_documents enable row level security;
alter table public.korlix_fax_sessions enable row level security;
revoke all on public.korlix_fax_lines,public.korlix_fax_documents,public.korlix_fax_sessions from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_fax_lines,public.korlix_fax_documents,public.korlix_fax_sessions to service_role;

-- Called after password verification. Only a fax-specific token is given to the browser.
create function public.korlix_fax_open_session(p_user uuid,p_device uuid,p_hash text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  profile public.user_profiles%rowtype;
  allowed_devices integer;
begin
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or p_device is null then return false; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fax:' || p_user::text,0));
  select * into profile from public.user_profiles where id=p_user and not is_disabled;
  if not found then return false; end if;
  select case when exists (select 1 from public.korlix_developer_access where user_id=p_user and enabled)
    then 2147483647 when profile.max_devices_override > 0 then profile.max_devices_override
    when profile.tier in ('ultra','enterprise') then 2 else 1 end into allowed_devices;
  delete from public.korlix_fax_sessions where user_id=p_user and expires_at <= now();
  if (select count(*) from public.korlix_fax_sessions where user_id=p_user and device_id<>p_device) >= allowed_devices then return false; end if;
  insert into public.korlix_fax_sessions (token_hash,user_id,device_id,expires_at)
    values(p_hash,p_user,p_device,now()+interval '12 hours')
    on conflict(user_id,device_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at;
  return true;
end;
$$;
create function public.korlix_fax_identity(p_hash text)
returns table(user_id uuid,operator boolean) language sql stable security invoker set search_path = '' as $$
  select s.user_id,exists(select 1 from public.korlix_fax_lines l where l.user_id=s.user_id and l.is_company)
  from public.korlix_fax_sessions s
  join public.user_profiles p on p.id=s.user_id
  where s.token_hash=p_hash and s.expires_at>now() and not p.is_disabled;
$$;
revoke all on function public.korlix_fax_open_session(uuid,uuid,text),public.korlix_fax_identity(text) from public,anon,authenticated;
grant execute on function public.korlix_fax_open_session(uuid,uuid,text),public.korlix_fax_identity(text) to service_role;

-- Client storage policies for other apps may be broad. All fax reads and writes go through the service.
create policy korlix_fax_files_service_only on storage.objects
  as restrictive for all to public
  using (bucket_id <> 'korlix-fax-documents') with check (bucket_id <> 'korlix-fax-documents');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('korlix-fax-documents','korlix-fax-documents',false,52428800,array['application/pdf']);
insert into public.korlix_fax_lines(user_id,is_company,preference)
select id,true,'toll_free' from auth.users where lower(email)='support@korlixdeveloper.com' and email_confirmed_at is not null and deleted_at is null;
commit;
