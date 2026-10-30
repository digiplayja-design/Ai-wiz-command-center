begin;
-- Extend the verified companion session discriminator; existing rows and device allowances remain intact.
alter table public.korlix_receipt_app_sessions drop constraint korlix_receipt_app_sessions_client_app_check;
alter table public.korlix_receipt_app_sessions add constraint korlix_receipt_app_sessions_client_app_check check (client_app in ('receipt_wiz','korlix_messenger','auto_email','magic_camera'));

create or replace function public.korlix_register_companion_app_session(
  p_client_app text,
  p_user_id uuid, p_session_id uuid, p_device_id text,
  p_device_label text default '', p_platform text default 'unknown'
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_profile public.user_profiles%rowtype;
  v_existing public.korlix_receipt_app_sessions%rowtype;
  v_limit integer;
  v_count integer;
begin
  if p_client_app is null or p_client_app not in ('receipt_wiz','korlix_messenger','auto_email','magic_camera') then
    raise exception 'invalid_companion_app' using errcode = '22023';
  end if;
  if p_user_id is null or p_session_id is null or p_device_id is null
     or length(p_device_id) not between 1 and 200 then
    raise exception 'receipt_session_invalid' using errcode = '22023';
  end if;
  -- Serialize registration across all backend processes, including concurrent
  -- sign-ins on different devices. The hub's device_sessions stays untouched.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_client_app || ':' || p_user_id::text, 0));
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
    if v_existing.client_app <> p_client_app or v_existing.user_id <> p_user_id or v_existing.device_id <> p_device_id or v_existing.status <> 'active' then
      raise exception 'receipt_session_binding_invalid' using errcode = '42501';
    end if;
    return to_jsonb(v_existing);
  end if;
  select count(*) into v_count from public.korlix_receipt_app_sessions
    where user_id = p_user_id and client_app = p_client_app and status = 'active' and device_id <> p_device_id;
  if v_count >= v_limit then
    raise exception using message = case when p_client_app='auto_email' then 'auto_email_device_limit' when p_client_app='korlix_messenger' then 'messenger_device_limit' else 'receipt_device_limit' end, errcode = '42501';
  end if;

  update public.korlix_receipt_app_sessions
    set status = 'revoked', revoked_at = now(), last_seen_at = now()
    where user_id = p_user_id and client_app = p_client_app and device_id = p_device_id and status = 'active';
  insert into public.korlix_receipt_app_sessions(client_app,session_id,user_id,device_id,device_label,platform)
    values(p_client_app,p_session_id,p_user_id,p_device_id,coalesce(p_device_label,''),coalesce(p_platform,'unknown'))
    returning * into v_existing;
  return to_jsonb(v_existing);
end;
$$;
revoke all on function public.korlix_register_companion_app_session(text,uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.korlix_register_companion_app_session(text,uuid,uuid,text,text,text) to service_role;


create function public.korlix_register_magic_camera_app_session(
  p_user_id uuid, p_session_id uuid, p_device_id text,
  p_device_label text default '', p_platform text default 'unknown'
) returns jsonb language sql security invoker set search_path = '' as $$
  select public.korlix_register_companion_app_session('magic_camera', p_user_id, p_session_id, p_device_id, p_device_label, p_platform);
$$;
revoke all on function public.korlix_register_magic_camera_app_session(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.korlix_register_magic_camera_app_session(uuid,uuid,text,text,text) to service_role;
commit;
