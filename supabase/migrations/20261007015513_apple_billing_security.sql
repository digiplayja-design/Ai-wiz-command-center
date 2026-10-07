-- Preserve Apple ownership and observation ordering independently of the
-- one-current-entitlement-per-user projection. No client role can access this.
create table if not exists public.korlix_apple_transaction_bindings (
  original_transaction_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text,
  last_signed_date bigint not null default 0 check(last_signed_date>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.korlix_apple_transaction_bindings enable row level security;
revoke all on public.korlix_apple_transaction_bindings from public,anon,authenticated;
grant select,insert,update on public.korlix_apple_transaction_bindings to service_role;
insert into public.korlix_apple_transaction_bindings(original_transaction_id,user_id,environment,last_signed_date)
select original_transaction_id,user_id,environment,
  case when raw_payload #>> '{transaction,signedDate}' ~ '^[0-9]{1,16}$'
    then (raw_payload #>> '{transaction,signedDate}')::bigint else 0 end
from public.apple_subscription_entitlements
on conflict(original_transaction_id) do nothing;

CREATE OR REPLACE FUNCTION public.korlix_apply_apple_subscription_entitlement(p_user_id uuid, p_product_id text, p_tier text, p_status text, p_environment text, p_original_transaction_id text, p_transaction_id text, p_purchase_date timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token text, p_ownership_type text, p_auto_renew_status boolean, p_signed_transaction_info text, p_signed_renewal_info text, p_last_notification_type text, p_raw_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_binding public.korlix_apple_transaction_bindings;
  v_current public.apple_subscription_entitlements;
  v_signed_date bigint;
  v_account_token text;
  v_profile_tier text;
  v_previous_tier text;
  v_effective_tier text;
  v_active boolean;
begin
  if p_user_id is null then
    raise exception 'user_id is required';
  end if;

  if p_product_id not in (
    'com.korlixdeveloper.korlixai.pro.monthly',
    'com.korlixdeveloper.korlixai.ultra.monthly'
  ) then
    raise exception 'unsupported Apple product id';
  end if;

  if p_tier not in ('pro', 'ultra') then
    raise exception 'unsupported Apple tier';
  end if;

  if coalesce(trim(p_original_transaction_id), '') = '' then
    raise exception 'original_transaction_id is required';
  end if;

  -- Serialize every entitlement transition for this account before checking
  -- ownership or recency. The durable original-transaction mapping is never
  -- replaced when this account later buys another subscription.
  select coalesce(up.tier, 'basic') into v_profile_tier
    from public.user_profiles up where up.id=p_user_id for update;
  if not found then raise exception 'Apple account profile is unavailable'; end if;
  v_account_token := nullif(lower(trim(p_app_account_token)), '');
  if v_account_token is not null and v_account_token<>p_user_id::text then
    raise exception 'Apple subscription is linked to a different Korlix account';
  end if;
  select * into v_binding from public.korlix_apple_transaction_bindings
    where original_transaction_id=p_original_transaction_id for update;
  if not found then
    if v_account_token is null then
      raise exception 'Apple purchase has no verified link to this Korlix account';
    end if;
    insert into public.korlix_apple_transaction_bindings(original_transaction_id,user_id,environment)
      values(p_original_transaction_id,p_user_id,p_environment)
      on conflict(original_transaction_id) do nothing;
    select * into v_binding from public.korlix_apple_transaction_bindings
      where original_transaction_id=p_original_transaction_id for update;
  end if;
  if v_binding.user_id<>p_user_id then
    raise exception 'Apple subscription is already linked to another Korlix account';
  end if;
  if v_binding.environment is not null and v_binding.environment is distinct from p_environment then
    raise exception 'Apple subscription environment changed';
  end if;
  if p_raw_payload #>> '{transaction,signedDate}' is null
      or not (p_raw_payload #>> '{transaction,signedDate}' ~ '^[0-9]{1,16}$') then
    raise exception 'Apple signed transaction timestamp is required';
  end if;
  v_signed_date := (p_raw_payload #>> '{transaction,signedDate}')::bigint;
  if v_signed_date<=0 or v_signed_date>(extract(epoch from clock_timestamp())*1000)::bigint+300000 then
    raise exception 'Apple signed transaction timestamp is invalid';
  end if;
  select * into v_current from public.apple_subscription_entitlements where user_id=p_user_id;
  if v_signed_date<=v_binding.last_signed_date or
      (v_current.purchase_date is not null and (p_purchase_date is null or p_purchase_date<v_current.purchase_date)) then
    -- A signed notification can be delivered again or out of order. Never
    -- overwrite accepted facts, but still expire the stored Apple grant by
    -- wall clock: an unchanged JWS cannot keep access alive after expires_at.
    v_active := coalesce(v_current.status in ('active','grace_period') and
      v_current.revoked_at is null and v_current.expires_at>now(),false);
    v_effective_tier := case when v_profile_tier='enterprise' then 'enterprise'
      when v_active then v_current.tier
      when v_current.previous_tier in ('basic','pro','ultra','enterprise') then v_current.previous_tier
      else 'basic' end;
    update public.user_profiles set tier=v_effective_tier where id=p_user_id;
    if exists(select 1 from public.korlix_web_billing_accounts where user_id=p_user_id) then
      v_effective_tier := public.korlix_web_billing_profile(p_user_id,true)->>'tier';
    end if;
    return jsonb_build_object('ok',true,'ignored',true,
      'active',v_active,
      'tier',v_effective_tier,'productId',v_current.product_id,'status',v_current.status,
      'expiresAt',v_current.expires_at,'originalTransactionId',v_current.original_transaction_id,
      'transactionId',v_current.transaction_id);
  end if;
  update public.korlix_apple_transaction_bindings set
    last_signed_date=v_signed_date, environment=coalesce(environment,p_environment),updated_at=now()
    where original_transaction_id=p_original_transaction_id;

  v_profile_tier := coalesce(v_profile_tier, 'basic');

  select ase.previous_tier
    into v_previous_tier
  from public.apple_subscription_entitlements ase
  where ase.user_id = p_user_id;

  v_previous_tier := coalesce(
    v_previous_tier,
    v_profile_tier,
    'basic'
  );

  v_active :=
    lower(coalesce(p_status, '')) in ('active', 'grace_period')
    and p_revoked_at is null
    and p_expires_at is not null
    and p_expires_at > now();

  insert into public.apple_subscription_entitlements (
    user_id,
    product_id,
    tier,
    status,
    environment,
    original_transaction_id,
    transaction_id,
    purchase_date,
    expires_at,
    revoked_at,
    app_account_token,
    ownership_type,
    auto_renew_status,
    previous_tier,
    signed_transaction_info,
    signed_renewal_info,
    last_notification_type,
    raw_payload,
    updated_at
  )
  values (
    p_user_id,
    p_product_id,
    p_tier,
    coalesce(p_status, 'unknown'),
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_purchase_date,
    p_expires_at,
    p_revoked_at,
    p_app_account_token,
    p_ownership_type,
    p_auto_renew_status,
    v_previous_tier,
    p_signed_transaction_info,
    p_signed_renewal_info,
    p_last_notification_type,
    coalesce(p_raw_payload, '{}'::jsonb),
    now()
  )
  on conflict (user_id) do update
  set
    product_id = excluded.product_id,
    tier = excluded.tier,
    status = excluded.status,
    environment = excluded.environment,
    original_transaction_id = excluded.original_transaction_id,
    transaction_id = excluded.transaction_id,
    purchase_date = excluded.purchase_date,
    expires_at = excluded.expires_at,
    revoked_at = excluded.revoked_at,
    app_account_token = excluded.app_account_token,
    ownership_type = excluded.ownership_type,
    auto_renew_status = excluded.auto_renew_status,
    signed_transaction_info = excluded.signed_transaction_info,
    signed_renewal_info = excluded.signed_renewal_info,
    last_notification_type = excluded.last_notification_type,
    raw_payload = excluded.raw_payload,
    updated_at = now();

  if v_profile_tier = 'enterprise' then
    v_effective_tier := 'enterprise';
  elsif v_active then
    v_effective_tier := p_tier;
  else
    v_effective_tier := case
      when v_previous_tier in ('basic', 'pro', 'ultra', 'enterprise')
        then v_previous_tier
      else 'basic'
    end;
  end if;

  update public.user_profiles
  set tier = v_effective_tier
  where id = p_user_id;

  -- Reconcile the independent web membership in this same transaction.
  if exists(select 1 from public.korlix_web_billing_accounts where user_id=p_user_id) then
    v_effective_tier := public.korlix_web_billing_profile(p_user_id, true)->>'tier';
  end if;

  return jsonb_build_object(
    'ok', true,
    'active', v_active,
    'tier', v_effective_tier,
    'productId', p_product_id,
    'status', coalesce(p_status, 'unknown'),
    'expiresAt', p_expires_at,
    'originalTransactionId', p_original_transaction_id,
    'transactionId', p_transaction_id
  );
end;
$function$;
revoke all on function public.korlix_apply_apple_subscription_entitlement(
  uuid,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,text,text,boolean,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.korlix_apply_apple_subscription_entitlement(
  uuid,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,text,text,boolean,text,text,text,jsonb
) to service_role;
