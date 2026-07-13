-- KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_SQL_BEGIN
-- Build 130: Apple auto-renewable subscription entitlements.
-- Run this migration in the production Supabase SQL Editor before deploying
-- the Build 130 backend.

create table if not exists public.apple_subscription_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  product_id text not null,
  tier text not null check (tier in ('pro', 'ultra')),
  status text not null default 'unknown',
  environment text,
  original_transaction_id text not null unique,
  transaction_id text,
  purchase_date timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  app_account_token text,
  ownership_type text,
  auto_renew_status boolean,
  previous_tier text not null default 'basic',
  signed_transaction_info text,
  signed_renewal_info text,
  last_notification_type text,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists apple_subscription_entitlements_expires_idx
  on public.apple_subscription_entitlements (expires_at);

create index if not exists apple_subscription_entitlements_transaction_idx
  on public.apple_subscription_entitlements (transaction_id);

alter table public.apple_subscription_entitlements enable row level security;

revoke all on table public.apple_subscription_entitlements
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.apple_subscription_entitlements
  to service_role;

create or replace function public.korlix_apply_apple_subscription_entitlement(
  p_user_id uuid,
  p_product_id text,
  p_tier text,
  p_status text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_purchase_date timestamptz,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_app_account_token text,
  p_ownership_type text,
  p_auto_renew_status boolean,
  p_signed_transaction_info text,
  p_signed_renewal_info text,
  p_last_notification_type text,
  p_raw_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
  v_existing_user uuid;
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

  select ase.user_id
    into v_existing_user
  from public.apple_subscription_entitlements ase
  where ase.original_transaction_id = p_original_transaction_id
  limit 1;

  if v_existing_user is not null and v_existing_user <> p_user_id then
    raise exception
      'Apple subscription is already linked to another Korlix account';
  end if;

  select coalesce(up.tier, 'basic')
    into v_profile_tier
  from public.user_profiles up
  where up.id = p_user_id;

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
$$;

revoke all on function public.korlix_apply_apple_subscription_entitlement(
  uuid, text, text, text, text, text, text, timestamptz, timestamptz,
  timestamptz, text, text, boolean, text, text, text, jsonb
) from public, anon, authenticated;

grant execute on function public.korlix_apply_apple_subscription_entitlement(
  uuid, text, text, text, text, text, text, timestamptz, timestamptz,
  timestamptz, text, text, boolean, text, text, text, jsonb
) to service_role;

-- KORLIX_APPLE_SUBSCRIPTIONS_BUILD130_SQL_END
