begin;

-- Dedicated allowance for the companion app. No tokens or credentials are
-- stored here. Revoked bindings must survive provider-session deletion so an
-- unexpired JWT cannot be reclassified as a legacy hub login.
create table public.korlix_receipt_app_sessions (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 1 and 200),
  device_label text not null default '' check (length(device_label) <= 160),
  platform text not null default 'unknown' check (length(platform) <= 40),
  status text not null default 'active' check (status in ('active','revoked')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint receipt_app_revocation check ((status = 'revoked') = (revoked_at is not null))
);
create index korlix_receipt_app_sessions_owner on public.korlix_receipt_app_sessions(user_id);
create unique index korlix_receipt_app_active_device
  on public.korlix_receipt_app_sessions(user_id, device_id) where status = 'active';
alter table public.korlix_receipt_app_sessions enable row level security;
revoke all on public.korlix_receipt_app_sessions from public, anon, authenticated;
grant select, insert, update on public.korlix_receipt_app_sessions to service_role;
create policy receipt_app_server_only on public.korlix_receipt_app_sessions
  for all to service_role using (true) with check (true);

create function public.korlix_register_receipt_app_session(
  p_user_id uuid, p_session_id uuid, p_device_id text,
  p_device_label text default '', p_platform text default 'unknown'
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_profile public.user_profiles%rowtype;
  v_existing public.korlix_receipt_app_sessions%rowtype;
  v_limit integer;
  v_count integer;
begin
  if p_user_id is null or p_session_id is null or p_device_id is null
     or length(p_device_id) not between 1 and 200 then
    raise exception 'receipt_session_invalid' using errcode = '22023';
  end if;
  -- Serialize registration across all backend processes, including concurrent
  -- sign-ins on different devices. The hub's device_sessions stays untouched.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('receipt-wiz:' || p_user_id::text, 0));
  select * into v_profile from public.user_profiles where id = p_user_id;
  if not found or v_profile.is_disabled then
    raise exception 'receipt_account_disabled' using errcode = '42501';
  end if;
  if exists (select 1 from public.korlix_developer_access where user_id = p_user_id and enabled) then
    v_limit := 2147483647;
  elsif v_profile.max_devices_override > 0 then
    v_limit := v_profile.max_devices_override;
  elsif v_profile.tier in ('ultra','enterprise') then
    v_limit := 2;
  else
    v_limit := 1;
  end if;

  select * into v_existing from public.korlix_receipt_app_sessions where session_id = p_session_id;
  if found then
    if v_existing.user_id <> p_user_id or v_existing.device_id <> p_device_id or v_existing.status <> 'active' then
      raise exception 'receipt_session_binding_invalid' using errcode = '42501';
    end if;
    return to_jsonb(v_existing);
  end if;
  select count(*) into v_count from public.korlix_receipt_app_sessions
    where user_id = p_user_id and status = 'active' and device_id <> p_device_id;
  if v_count >= v_limit then
    raise exception 'receipt_device_limit' using errcode = '42501';
  end if;

  update public.korlix_receipt_app_sessions
    set status = 'revoked', revoked_at = now(), last_seen_at = now()
    where user_id = p_user_id and device_id = p_device_id and status = 'active';
  insert into public.korlix_receipt_app_sessions(session_id,user_id,device_id,device_label,platform)
    values(p_session_id,p_user_id,p_device_id,coalesce(p_device_label,''),coalesce(p_platform,'unknown'))
    returning * into v_existing;
  return to_jsonb(v_existing);
end;
$$;
revoke all on function public.korlix_register_receipt_app_session(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.korlix_register_receipt_app_session(uuid,uuid,text,text,text) to service_role;

comment on table public.korlix_receipt_app_sessions is
  'Server-owned Receipt Wiz login scope and separate per-plan device allowance. Retain revoked rows until account deletion. No auth tokens stored.';
commit;
