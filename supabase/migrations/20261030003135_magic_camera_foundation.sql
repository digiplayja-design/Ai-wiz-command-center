-- Service-only state machine. No raw capture is ever readable by a client.
create table public.korlix_magic_jobs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 request_key uuid not null, fingerprint text not null, options jsonb not null,
 state text not null default 'uploading' check(state in ('uploading','queued','processing','ready','failed','deleted')),
 allowance text not null, created_at timestamptz not null default now(), finished_at timestamptz,
 source_purged boolean not null default false, output_purged boolean not null default false, cleanup_version integer not null default 0,
 deleted_at timestamptz, worker_token uuid, lease_until timestamptz not null default now()+interval '3 minutes',
 width integer, height integer, render_ms integer, error text,
 unique(owner_id,request_key)
);
create index korlix_magic_owner on public.korlix_magic_jobs(owner_id,created_at desc);
create index korlix_magic_queue on public.korlix_magic_jobs(state,created_at);
create table public.korlix_magic_purchases (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'), purchase_token text not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 product_id text not null check(product_id in ('magic_camera_starter','magic_camera_plus')),
 provider text not null default 'google' check(provider in ('google','apple')),
 state text not null,active boolean not null default false,expires_at timestamptz,
 acknowledged boolean not null default false,auto_renew boolean not null default false,
 test_purchase boolean not null default false,replaced_by_hash text,observed_at timestamptz not null default now()
);
create index korlix_magic_purchase_owner on public.korlix_magic_purchases(user_id);
create table public.korlix_magic_billing_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 account_id text not null unique check(account_id ~ '^[0-9a-f]{64}$'),sync_token uuid,sync_until timestamptz,
 next_sync_at timestamptz not null default now(),created_at timestamptz not null default now()
);
alter table public.korlix_magic_jobs enable row level security;
alter table public.korlix_magic_purchases enable row level security;
alter table public.korlix_magic_billing_accounts enable row level security;
revoke all on public.korlix_magic_jobs,public.korlix_magic_purchases,public.korlix_magic_billing_accounts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_magic_jobs,public.korlix_magic_purchases,public.korlix_magic_billing_accounts to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('korlix-magic-camera','korlix-magic-camera',false,67108864,array['image/jpeg','image/png']);
-- Restrictive policies also prevent unrelated broad policies from exposing this bucket.
create policy magic_private_select on storage.objects as restrictive for select to anon,authenticated using(bucket_id<>'korlix-magic-camera');
create policy magic_private_insert on storage.objects as restrictive for insert to anon,authenticated with check(bucket_id<>'korlix-magic-camera');
create policy magic_private_update on storage.objects as restrictive for update to anon,authenticated using(bucket_id<>'korlix-magic-camera') with check(bucket_id<>'korlix-magic-camera');
create policy magic_private_delete on storage.objects as restrictive for delete to anon,authenticated using(bucket_id<>'korlix-magic-camera');

create function public.korlix_magic_plan(p_actor uuid,p_standalone boolean default true) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr jsonb;n text;lim integer;daily integer;used integer;day_used integer;free_used integer;pending integer;paid text;included boolean;cy timestamptz:=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
begin
 pr:=public.korlix_web_billing_profile(p_actor);
 if pr is null or coalesce((pr->>'is_disabled')::boolean,false) then raise exception 'MAG403: Account is unavailable.';end if;
 included:=coalesce(pr->>'tier' in ('pro','ultra','enterprise'),false);
 select case when product_id='magic_camera_plus' then 'plus' else 'starter' end into paid from public.korlix_magic_purchases
  where user_id=p_actor and active and expires_at>now() and replaced_by_hash is null order by case product_id when 'magic_camera_plus' then 0 else 1 end limit 1;
 n:=case when pr->>'tier' in ('ultra','enterprise') then 'ultra' when pr->>'tier'='pro' then 'pro' when p_standalone and paid is not null then paid when p_standalone then 'free' else 'locked' end;
 lim:=case n when 'ultra' then 40 when 'pro' then 10 when 'plus' then 40 when 'starter' then 15 when 'free' then 2 else 0 end;
 daily:=case n when 'ultra' then 5 when 'pro' then 2 else null end;
 select count(*) filter(where state in ('ready','deleted') and allowance='free'),count(*) filter(where state in ('uploading','queued','processing') and allowance='free' and lease_until>now())
  into free_used,pending from public.korlix_magic_jobs where owner_id=p_actor;
 if n='free' then used:=free_used+pending;
 else select count(*) into used from public.korlix_magic_jobs where owner_id=p_actor and created_at>=cy and allowance<>'free'
   and (state in ('ready','deleted') or (state in ('uploading','queued','processing') and lease_until>now()));end if;
 select count(*) into day_used from public.korlix_magic_jobs where owner_id=p_actor and created_at>=(date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')
  and allowance<>'free' and (state in ('ready','deleted') or (state in ('uploading','queued','processing') and lease_until>now()));
 return jsonb_build_object('name',n,'included',included,'limit',lim,'used',used,'remaining',greatest(0,lim-used),
  'daily_limit',daily,'daily_remaining',case when daily is null then null else greatest(0,daily-day_used) end,
  'free_remaining',greatest(0,2-free_used-pending),'can_generate',used<lim and (daily is null or day_used<daily),
  'resets_at',case when n in ('free','locked') then null else cy+interval '1 month' end);
end $$;

create function public.korlix_magic_command(p_actor uuid,p_action text,p_id uuid default null,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare j public.korlix_magic_jobs;pl jsonb;result jsonb;dispatch boolean:=false;off integer;total integer;
begin
 if p_action='claim' then
  select * into j from public.korlix_magic_jobs where state='queued' and lease_until>now() order by created_at for update skip locked limit 1;
  if not found then return null;end if;
  update public.korlix_magic_jobs set state='processing',worker_token=gen_random_uuid(),lease_until=now()+interval '10 minutes' where id=j.id returning * into j;
  return to_jsonb(j);
 elsif p_action='sweep' then
  update public.korlix_magic_jobs set state='failed',finished_at=now(),cleanup_version=cleanup_version+1,source_purged=false,output_purged=false,error='This magic session expired. No credit was used.'
   where state in ('uploading','queued','processing') and lease_until<now();
  return coalesce((select jsonb_agg(to_jsonb(x)) from (select id,owner_id,state,source_purged,output_purged,cleanup_version from public.korlix_magic_jobs
   where state in ('ready','failed','deleted') and (not source_purged or (state in ('failed','deleted') and not output_purged)) limit 40)x),'[]');
 end if;
 if p_actor is null then raise exception 'MAG401: Sign in required.';end if;
 if p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>16000 then raise exception 'MAG400: Invalid request.';end if;
 perform pg_advisory_xact_lock(hashtextextended('magic-camera:'||p_actor::text,0));
 if p_action='list' then
  off:=coalesce((p->>'offset')::integer,0);if off<0 or off>1000000 then raise exception 'MAG400: Invalid gallery page.';end if;
  select count(*) into total from public.korlix_magic_jobs where owner_id=p_actor and state<>'deleted' and deleted_at is null;
  return jsonb_build_object('next_offset',case when total>off+100 then off+100 else null end,'plan',public.korlix_magic_plan(p_actor,coalesce((p->>'standalone')::boolean,false)),
   'jobs',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,state,options,created_at,finished_at,width,height,render_ms,error from public.korlix_magic_jobs
     where owner_id=p_actor and state<>'deleted' and deleted_at is null order by created_at desc,id limit 100 offset off)x),'[]'));
 elsif p_action='reserve' then
  select * into j from public.korlix_magic_jobs where owner_id=p_actor and request_key=(p->>'request_key')::uuid;
  if found then
   if j.fingerprint is distinct from p->>'fingerprint' then raise exception 'MAG409: This request key belongs to a different photo or look.';end if;
  else
   pl:=public.korlix_magic_plan(p_actor,coalesce((p->>'standalone')::boolean,false));
   if not (pl->>'can_generate')::boolean then raise exception 'MAG402: Your magic allowance is used or an upgrade is required. Saved images and reports remain available.';end if;
   if exists(select 1 from public.korlix_magic_jobs where owner_id=p_actor and state in ('uploading','queued','processing') and lease_until>now()) then raise exception 'MAG409: A photo is already becoming magic. Open your gallery to check it.';end if;
   if coalesce(p->>'fingerprint','') !~ '^[0-9a-f]{64}$' or jsonb_typeof(p->'options') is distinct from 'object' then raise exception 'MAG400: Invalid photo request.';end if;
   insert into public.korlix_magic_jobs(owner_id,request_key,fingerprint,options,allowance)
    values(p_actor,(p->>'request_key')::uuid,p->>'fingerprint',p->'options',pl->>'name') returning * into j;dispatch:=true;
  end if;
 else
  select * into j from public.korlix_magic_jobs where id=p_id and owner_id=p_actor for update;
  if not found then raise exception 'MAG404: Magic photo not found.';end if;
  if p_action='uploaded' then
   if j.state<>'uploading' or j.lease_until<now() then raise exception 'MAG409: Upload expired. Check your gallery.';end if;
   update public.korlix_magic_jobs set state='queued',lease_until=now()+interval '24 hours' where id=j.id returning * into j;
  elsif p_action in ('finish','fail') then
   if j.state='uploading' and p_action='fail' then
    update public.korlix_magic_jobs set state='failed',finished_at=now(),cleanup_version=cleanup_version+1,source_purged=false,output_purged=false,error='Upload did not finish. No credit was used.' where id=j.id returning * into j;
   elsif j.state='processing' and j.worker_token::text=p->>'worker_token' and j.lease_until>now() then
    update public.korlix_magic_jobs set state=case when p_action='finish' then 'ready' else 'failed' end,finished_at=now(),cleanup_version=cleanup_version+1,source_purged=false,output_purged=false,
     width=(p->>'width')::integer,height=(p->>'height')::integer,render_ms=(p->>'render_ms')::integer,
     error=case when p_action='fail' then 'This photo could not be transformed. No credit was used. Try a different prompt or photo.' end where id=j.id returning * into j;
   elsif p_action='fail' and j.state='failed' then
    -- A storage operation can settle after the sweeper expired and cleaned its job.
    update public.korlix_magic_jobs set cleanup_version=cleanup_version+1,source_purged=false,output_purged=false where id=j.id returning * into j;
   elsif j.state not in ('ready','deleted') then raise exception 'MAG409: This generation lease expired.';end if;
  elsif p_action='delete' then
   if j.state not in ('ready','failed','deleted') then raise exception 'MAG409: Wait for processing to finish before deleting.';end if;
   update public.korlix_magic_jobs set state=case when state='ready' then 'deleted' else state end,deleted_at=now(),cleanup_version=cleanup_version+1,source_purged=false,output_purged=false where id=j.id returning * into j;
  elsif p_action='purged' then
   if (p->>'cleanup_version')::integer is distinct from j.cleanup_version then raise exception 'MAG409: A newer cleanup is pending.';end if;
   update public.korlix_magic_jobs set source_purged=true,output_purged=case when state in ('failed','deleted') then true else output_purged end where id=j.id returning * into j;
  elsif p_action<>'get' then raise exception 'MAG400: Unsupported magic action.';
  end if;
 end if;
 return jsonb_build_object('job',to_jsonb(j),'dispatch',dispatch);
end $$;
revoke all on function public.korlix_magic_plan(uuid,boolean),public.korlix_magic_command(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_plan(uuid,boolean),public.korlix_magic_command(uuid,text,uuid,jsonb) to service_role;


create function public.korlix_magic_billing_command(p_actor uuid,p_action text,p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare g public.korlix_magic_billing_accounts; r public.korlix_magic_purchases;
 plan jsonb; hash text; blocked boolean;
begin
 if p_action='lookup' then
   select a.* into g from public.korlix_magic_billing_accounts a where
    a.account_id=p->>'account_id' or a.user_id=(select user_id from public.korlix_magic_purchases where token_hash=p->>'token_hash');
   return case when found then jsonb_build_object('user_id',g.user_id) else null end;
 end if;
 if p_action='due' then
   return coalesce((select jsonb_agg(x) from (select a.user_id from public.korlix_magic_billing_accounts a
    where a.next_sync_at<=now() and (a.sync_until is null or a.sync_until<now())
     and exists(select 1 from public.korlix_magic_purchases t where t.user_id=a.user_id and t.provider='google' and t.replaced_by_hash is null
      and t.state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'))
    order by a.next_sync_at limit 20) x),'[]'::jsonb);
 end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.'; end if;
 plan:=public.korlix_magic_plan(p_actor,true);
 -- Serializes preparation and callbacks even before a billing account exists.
 perform pg_advisory_xact_lock(hashtextextended('magic-billing:'||p_actor::text,0));
 select * into g from public.korlix_magic_billing_accounts where user_id=p_actor for update;
 if p_action in ('snapshot','prepare') then
   blocked:=exists(select 1 from public.korlix_magic_purchases where user_id=p_actor and replaced_by_hash is null
     and state in ('SUBSCRIPTION_STATE_PENDING','SUBSCRIPTION_STATE_ON_HOLD','SUBSCRIPTION_STATE_PAUSED'));
   if p_action='prepare' then
     if plan->>'name'<>'free' then raise exception 'BILL409: Magic Camera Full is already included in your account. No additional subscription is needed.'; end if;
     if blocked then raise exception 'BILL409: Manage or restore your existing Magic Camera subscription in Google Play.'; end if;
     if coalesce(p->>'account_id','') !~ '^[0-9a-f]{64}$' then raise exception 'BILL400: Invalid billing account.'; end if;
     if g.user_id is null then
       insert into public.korlix_magic_billing_accounts(user_id,account_id) values(p_actor,p->>'account_id') returning * into g;
     elsif g.account_id<>p->>'account_id' then raise exception 'BILL409: Billing account changed.'; end if;
   end if;
   return jsonb_build_object('tier',plan->>'name','plan',plan,'account_id',g.account_id,
    'webSubscriptionActive',false,'otherStoreSubscriptionActive',(plan->>'included')::boolean,
    'canPurchase',plan->>'name'='free' and not blocked,
    'entitlement',(select jsonb_build_object('product_id',product_id,'tier',case when product_id='magic_camera_plus' then 'plus' else 'starter' end,'status',state,'expires_at',expires_at,
      'active',active and expires_at>now(),'auto_renew_status',auto_renew,'environment',case when test_purchase then 'Test' else 'Production' end)
      from public.korlix_magic_purchases where user_id=p_actor and replaced_by_hash is null
      order by active desc, expires_at desc nulls last limit 1));
 end if;
 if g.user_id is null then raise exception 'BILL409: Restore using the KORLIX account that started this Magic Camera purchase.'; end if;
 if p_action='claim' then
   if g.sync_until>now() then raise exception 'BILL409: Subscription is updating. Please retry shortly.'; end if;
   update public.korlix_magic_billing_accounts set sync_token=gen_random_uuid(),sync_until=now()+interval '90 seconds',next_sync_at=now()+interval '1 minute'
    where user_id=p_actor returning * into g;
   return jsonb_build_object('sync_token',g.sync_token,'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from
    (select purchase_token,product_id from public.korlix_magic_purchases where user_id=p_actor and provider='google' and replaced_by_hash is null
      and state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED')
      order by observed_at desc limit 10) x),'[]'::jsonb));
 end if;
 if p_action='release' then
   update public.korlix_magic_billing_accounts set sync_token=null,sync_until=null,next_sync_at=now()+case when coalesce((p->>'success')::boolean,false)
    then interval '10 minutes' else interval '1 minute' end where user_id=p_actor and sync_token::text=p->>'sync_token';
   return jsonb_build_object('ok',true);
 end if;
 if g.sync_token is null or g.sync_token::text is distinct from p->>'sync_token' or g.sync_until<now() then
   raise exception 'BILL409: Subscription changed while verifying. Please retry.';
 end if;
 hash:=p->>'token_hash';
 if p_action='acknowledged' then
   update public.korlix_magic_purchases set acknowledged=true where user_id=p_actor and token_hash=hash;
   return jsonb_build_object('ok',true);
 end if;
 if p_action<>'apply' then raise exception 'BILL400: Unsupported billing action.'; end if;
 if coalesce(hash,'') !~ '^[0-9a-f]{64}$' or g.account_id is distinct from p->>'account_id'
    or coalesce(p->>'product_id','') not in ('magic_camera_starter','magic_camera_plus') or p->>'tier' is distinct from (case when p->>'product_id'='magic_camera_plus' then 'plus' else 'starter' end) then
   raise exception 'BILL409: Purchase does not match this Magic Camera account.';
 end if;
 select * into r from public.korlix_magic_purchases where token_hash=hash for update;
 if found and r.user_id<>p_actor then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if p->>'linked_hash' is not null then
   if p->>'linked_hash'=hash then raise exception 'BILL409: Invalid replacement purchase.'; end if;
   if exists(select 1 from public.korlix_magic_purchases where token_hash=p->>'linked_hash' and user_id<>p_actor) then
     raise exception 'BILL409: Linked purchase belongs to another account.';
   end if;
   if not exists(select 1 from public.korlix_magic_purchases where token_hash=p->>'linked_hash' and user_id=p_actor) then
     raise exception 'BILL409: Restore your previous Magic Camera purchase first.';
   end if;
 end if;
 insert into public.korlix_magic_purchases(token_hash,purchase_token,user_id,product_id,state,active,expires_at,acknowledged,auto_renew,test_purchase)
 values(hash,p->>'purchase_token',p_actor,p->>'product_id',p->>'state',(p->>'active')::boolean,
   (p->>'expires_at')::timestamptz,(p->>'acknowledged')::boolean,(p->>'auto_renew')::boolean,(p->>'test_purchase')::boolean)
 on conflict(token_hash) do update set state=excluded.state,active=excluded.active,expires_at=excluded.expires_at,
   acknowledged=excluded.acknowledged,auto_renew=excluded.auto_renew,observed_at=now()
   where korlix_magic_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if (p->>'active')::boolean and r.replaced_by_hash is null and p->>'linked_hash' is not null then
   update public.korlix_magic_purchases set replaced_by_hash=hash where token_hash=p->>'linked_hash' and user_id=p_actor;
 end if;
 plan:=public.korlix_magic_plan(p_actor,true);
 return jsonb_build_object('tier',plan->>'name','active',coalesce((p->>'active')::boolean,false) and r.replaced_by_hash is null);
end;
$$;
revoke all on function public.korlix_magic_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_billing_command(uuid,text,jsonb) to service_role;



create function public.korlix_magic_apple_command(p_actor uuid,p_action text,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr jsonb;existing public.korlix_magic_purchases;
begin
 if p_action='due' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select user_id,purchase_token from public.korlix_magic_purchases where provider='apple' and observed_at<now()-interval '10 minutes' and expires_at>now()-interval '1 day' order by observed_at limit 20)x),'[]');end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('magic-billing:'||p_actor::text,0));
 pr:=public.korlix_magic_plan(p_actor,true);
 if p_action='snapshot' then
  return jsonb_build_object('plan',pr,'purchases',coalesce((select jsonb_agg(jsonb_build_object('purchase_token',purchase_token)) from public.korlix_magic_purchases where user_id=p_actor and provider='apple'),'[]'),
   'entitlement',(select jsonb_build_object('product_id',product_id,'active',active and expires_at>now(),'expires_at',expires_at) from public.korlix_magic_purchases where user_id=p_actor and provider='apple' order by expires_at desc limit 1));
 end if;
 if p_action<>'apply' or p->>'account_id' is distinct from p_actor::text or coalesce(p->>'token_hash','') !~ '^[0-9a-f]{64}$' or coalesce(p->>'product_id','') not in ('magic_camera_starter','magic_camera_plus') then raise exception 'BILL409: Purchase does not match this Magic Camera account.';end if;
 select * into existing from public.korlix_magic_purchases where token_hash=p->>'token_hash' for update;
 if found and (existing.user_id<>p_actor or existing.provider<>'apple') then raise exception 'BILL409: Purchase belongs to another account.';end if;
 insert into public.korlix_magic_purchases(token_hash,purchase_token,user_id,product_id,state,active,expires_at,test_purchase,acknowledged,provider)
 values(p->>'token_hash',p->>'purchase_token',p_actor,p->>'product_id',p->>'state',(p->>'active')::boolean,(p->>'expires_at')::timestamptz,(p->>'test_purchase')::boolean,true,'apple')
 on conflict(token_hash) do update set product_id=excluded.product_id,state=excluded.state,active=excluded.active,expires_at=excluded.expires_at,observed_at=now() where korlix_magic_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase belongs to another account.';end if;
 return jsonb_build_object('active',(p->>'active')::boolean);
end $$;
revoke all on function public.korlix_magic_apple_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_apple_command(uuid,text,jsonb) to service_role;


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
