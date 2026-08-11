begin;

create extension if not exists pgcrypto;

-- ============================================================
-- KORLIX AI GAS BUILD 132
-- Server-owned catalog, verified-purchase ledger, balance,
-- revocation, and atomic consumption functions.
--
-- This migration does not configure Apple, Google Play, or web
-- provider product IDs. Those mappings are added only after the
-- provider products exist and are separately verified.
-- ============================================================

create table if not exists public.korlix_ai_gas_products (
  sku text primary key,
  display_name text not null,
  seconds integer not null check (seconds > 0),
  base_usd_cents integer not null check (base_usd_cents > 0),
  active boolean not null default true,
  apple_product_id text,
  google_product_id text,
  web_price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint korlix_ai_gas_products_sku_check
    check (sku in (
      'korlix_ai_gas_1h',
      'korlix_ai_gas_2h',
      'korlix_ai_gas_3h',
      'korlix_ai_gas_5h'
    ))
);

create unique index if not exists
  korlix_ai_gas_products_apple_product_id_uidx
on public.korlix_ai_gas_products (apple_product_id)
where apple_product_id is not null;

create unique index if not exists
  korlix_ai_gas_products_google_product_id_uidx
on public.korlix_ai_gas_products (google_product_id)
where google_product_id is not null;

create unique index if not exists
  korlix_ai_gas_products_web_price_id_uidx
on public.korlix_ai_gas_products (web_price_id)
where web_price_id is not null;

insert into public.korlix_ai_gas_products (
  sku,
  display_name,
  seconds,
  base_usd_cents,
  active
)
values
  ('korlix_ai_gas_1h', '1 Hour AI GAS', 3600, 3000, true),
  ('korlix_ai_gas_2h', '2 Hours AI GAS', 7200, 5500, true),
  ('korlix_ai_gas_3h', '3 Hours AI GAS', 10800, 8000, true),
  ('korlix_ai_gas_5h', '5 Hours AI GAS', 18000, 12500, true)
on conflict (sku) do update
set
  display_name = excluded.display_name,
  seconds = excluded.seconds,
  base_usd_cents = excluded.base_usd_cents,
  active = excluded.active,
  updated_at = now();

create table if not exists public.korlix_ai_gas_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (
    provider in ('apple', 'google', 'web')
  ),
  provider_transaction_id text not null,
  provider_original_transaction_id text,
  sku text not null references public.korlix_ai_gas_products(sku),
  seconds_granted integer not null check (seconds_granted > 0),
  base_usd_cents integer not null check (base_usd_cents > 0),
  status text not null default 'verified' check (
    status in ('verified', 'refunded', 'revoked')
  ),
  receipt_or_token_hash text,
  purchased_at timestamptz not null,
  verified_at timestamptz not null default now(),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_transaction_id)
);

create index if not exists
  korlix_ai_gas_purchases_user_created_idx
on public.korlix_ai_gas_purchases (
  user_id,
  created_at desc
);

create index if not exists
  korlix_ai_gas_purchases_original_transaction_idx
on public.korlix_ai_gas_purchases (
  provider,
  provider_original_transaction_id
)
where provider_original_transaction_id is not null;

create table if not exists public.korlix_ai_gas_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta_seconds integer not null check (delta_seconds <> 0),
  reason text not null check (
    reason in (
      'verified_purchase',
      'live_convo_usage',
      'refund',
      'revocation',
      'admin_adjustment'
    )
  ),
  purchase_id uuid references public.korlix_ai_gas_purchases(id)
    on delete restrict,
  live_convo_session_id text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists
  korlix_ai_gas_ledger_user_created_idx
on public.korlix_ai_gas_ledger (
  user_id,
  created_at desc
);

create index if not exists
  korlix_ai_gas_ledger_purchase_idx
on public.korlix_ai_gas_ledger (purchase_id)
where purchase_id is not null;

create or replace function public.korlix_ai_gas_set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists
  korlix_ai_gas_products_set_updated_at
on public.korlix_ai_gas_products;

create trigger korlix_ai_gas_products_set_updated_at
before update on public.korlix_ai_gas_products
for each row
execute function public.korlix_ai_gas_set_updated_at();

drop trigger if exists
  korlix_ai_gas_purchases_set_updated_at
on public.korlix_ai_gas_purchases;

create trigger korlix_ai_gas_purchases_set_updated_at
before update on public.korlix_ai_gas_purchases
for each row
execute function public.korlix_ai_gas_set_updated_at();

create or replace function public.korlix_ai_gas_get_catalog()
returns table (
  sku text,
  display_name text,
  seconds integer,
  base_usd_cents integer,
  apple_product_id text,
  google_product_id text,
  web_price_id text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.sku,
    p.display_name,
    p.seconds,
    p.base_usd_cents,
    p.apple_product_id,
    p.google_product_id,
    p.web_price_id
  from public.korlix_ai_gas_products p
  where p.active = true
  order by p.seconds asc;
$$;

create or replace function public.korlix_ai_gas_get_balance(
  p_user_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(l.delta_seconds), 0)::bigint
  from public.korlix_ai_gas_ledger l
  where l.user_id = p_user_id;
$$;

create or replace function public.korlix_ai_gas_grant_verified_purchase(
  p_user_id uuid,
  p_provider text,
  p_provider_transaction_id text,
  p_provider_original_transaction_id text,
  p_sku text,
  p_receipt_or_token_hash text,
  p_purchased_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_transaction_id text :=
    btrim(coalesce(p_provider_transaction_id, ''));
  v_product public.korlix_ai_gas_products%rowtype;
  v_existing public.korlix_ai_gas_purchases%rowtype;
  v_purchase_id uuid;
  v_inserted boolean := false;
  v_balance bigint;
  v_metadata jsonb :=
    coalesce(p_metadata, '{}'::jsonb)
      - 'receipt'
      - 'purchaseToken'
      - 'purchase_token'
      - 'signedPayload'
      - 'signed_payload';
begin
  if p_user_id is null then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_user_id_required';
  end if;

  if v_provider not in ('apple', 'google', 'web') then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_provider_invalid';
  end if;

  if v_transaction_id = '' then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_transaction_id_required';
  end if;

  perform 1
  from auth.users
  where id = p_user_id;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_user_not_found';
  end if;

  select *
  into v_product
  from public.korlix_ai_gas_products
  where sku = p_sku
    and active = true;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_product_invalid';
  end if;

  insert into public.korlix_ai_gas_purchases (
    user_id,
    provider,
    provider_transaction_id,
    provider_original_transaction_id,
    sku,
    seconds_granted,
    base_usd_cents,
    status,
    receipt_or_token_hash,
    purchased_at,
    metadata
  )
  values (
    p_user_id,
    v_provider,
    v_transaction_id,
    nullif(btrim(coalesce(
      p_provider_original_transaction_id,
      ''
    )), ''),
    v_product.sku,
    v_product.seconds,
    v_product.base_usd_cents,
    'verified',
    nullif(btrim(coalesce(
      p_receipt_or_token_hash,
      ''
    )), ''),
    coalesce(p_purchased_at, now()),
    v_metadata
  )
  on conflict (provider, provider_transaction_id)
  do nothing
  returning id
  into v_purchase_id;

  if v_purchase_id is null then
    select *
    into v_existing
    from public.korlix_ai_gas_purchases
    where provider = v_provider
      and provider_transaction_id = v_transaction_id;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'ai_gas_purchase_conflict_unresolved';
    end if;

    if v_existing.user_id <> p_user_id
       or v_existing.sku <> p_sku then
      raise exception using
        errcode = 'P0001',
        message = 'ai_gas_purchase_replay_conflict';
    end if;

    v_purchase_id := v_existing.id;
  else
    insert into public.korlix_ai_gas_ledger (
      user_id,
      delta_seconds,
      reason,
      purchase_id,
      idempotency_key,
      metadata
    )
    values (
      p_user_id,
      v_product.seconds,
      'verified_purchase',
      v_purchase_id,
      'purchase:' || v_provider || ':' || v_transaction_id,
      jsonb_build_object(
        'provider',
        v_provider,
        'sku',
        v_product.sku
      )
    )
    on conflict (user_id, idempotency_key)
    do nothing;

    v_inserted := true;
  end if;

  v_balance :=
    public.korlix_ai_gas_get_balance(p_user_id);

  return jsonb_build_object(
    'purchaseId',
    v_purchase_id,
    'sku',
    v_product.sku,
    'seconds',
    v_product.seconds,
    'balanceSeconds',
    v_balance,
    'granted',
    v_inserted,
    'idempotent',
    not v_inserted
  );
end;
$$;

create or replace function public.korlix_ai_gas_reverse_verified_purchase(
  p_provider text,
  p_provider_transaction_id text,
  p_reason text default 'revoked',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_transaction_id text :=
    btrim(coalesce(p_provider_transaction_id, ''));
  v_reason text := lower(btrim(coalesce(p_reason, '')));
  v_purchase public.korlix_ai_gas_purchases%rowtype;
  v_balance bigint;
  v_reverse_seconds bigint;
  v_new_balance bigint;
  v_metadata jsonb :=
    coalesce(p_metadata, '{}'::jsonb)
      - 'receipt'
      - 'purchaseToken'
      - 'purchase_token'
      - 'signedPayload'
      - 'signed_payload';
begin
  if v_provider not in ('apple', 'google', 'web') then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_provider_invalid';
  end if;

  if v_transaction_id = '' then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_transaction_id_required';
  end if;

  if v_reason not in ('refunded', 'revoked') then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_reversal_reason_invalid';
  end if;

  select *
  into v_purchase
  from public.korlix_ai_gas_purchases
  where provider = v_provider
    and provider_transaction_id = v_transaction_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'ai_gas_purchase_not_found';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('korlix_ai_gas:' || v_purchase.user_id::text)
  );

  v_balance :=
    public.korlix_ai_gas_get_balance(v_purchase.user_id);

  v_reverse_seconds :=
    least(
      v_purchase.seconds_granted::bigint,
      greatest(v_balance, 0::bigint)
    );

  update public.korlix_ai_gas_purchases
  set
    status = v_reason,
    revoked_at = coalesce(revoked_at, now()),
    metadata =
      metadata
      || v_metadata
      || jsonb_build_object('reversalReason', v_reason)
  where id = v_purchase.id;

  if v_reverse_seconds > 0 then
    insert into public.korlix_ai_gas_ledger (
      user_id,
      delta_seconds,
      reason,
      purchase_id,
      idempotency_key,
      metadata
    )
    values (
      v_purchase.user_id,
      (-v_reverse_seconds)::integer,
      case
        when v_reason = 'refunded' then 'refund'
        else 'revocation'
      end,
      v_purchase.id,
      'reverse:'
        || v_provider
        || ':'
        || v_transaction_id
        || ':'
        || v_reason,
      jsonb_build_object(
        'provider',
        v_provider,
        'transactionId',
        v_transaction_id
      )
    )
    on conflict (user_id, idempotency_key)
    do nothing;
  end if;

  v_new_balance :=
    public.korlix_ai_gas_get_balance(v_purchase.user_id);

  return jsonb_build_object(
    'purchaseId',
    v_purchase.id,
    'status',
    v_reason,
    'reversedSeconds',
    v_reverse_seconds,
    'unrecoveredSeconds',
    greatest(
      v_purchase.seconds_granted::bigint - v_reverse_seconds,
      0::bigint
    ),
    'balanceSeconds',
    v_new_balance
  );
end;
$$;

create or replace function public.korlix_ai_gas_consume(
  p_user_id uuid,
  p_seconds integer,
  p_idempotency_key text,
  p_live_convo_session_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_existing public.korlix_ai_gas_ledger%rowtype;
  v_balance bigint;
  v_new_balance bigint;
  v_metadata jsonb :=
    coalesce(p_metadata, '{}'::jsonb)
      - 'receipt'
      - 'purchaseToken'
      - 'purchase_token';
begin
  if p_user_id is null then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_user_id_required';
  end if;

  if p_seconds is null or p_seconds <= 0 then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_seconds_invalid';
  end if;

  if v_key = '' then
    raise exception using
      errcode = '22023',
      message = 'ai_gas_idempotency_key_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('korlix_ai_gas:' || p_user_id::text)
  );

  select *
  into v_existing
  from public.korlix_ai_gas_ledger
  where user_id = p_user_id
    and idempotency_key = v_key;

  if found then
    if v_existing.delta_seconds <> -p_seconds then
      raise exception using
        errcode = 'P0001',
        message = 'ai_gas_idempotency_conflict';
    end if;

    return jsonb_build_object(
      'consumedSeconds',
      abs(v_existing.delta_seconds),
      'balanceSeconds',
      public.korlix_ai_gas_get_balance(p_user_id),
      'idempotent',
      true
    );
  end if;

  v_balance :=
    public.korlix_ai_gas_get_balance(p_user_id);

  if v_balance < p_seconds then
    raise exception using
      errcode = 'P0001',
      message = 'ai_gas_insufficient_balance';
  end if;

  insert into public.korlix_ai_gas_ledger (
    user_id,
    delta_seconds,
    reason,
    live_convo_session_id,
    idempotency_key,
    metadata
  )
  values (
    p_user_id,
    -p_seconds,
    'live_convo_usage',
    nullif(btrim(coalesce(
      p_live_convo_session_id,
      ''
    )), ''),
    v_key,
    v_metadata
  );

  v_new_balance :=
    public.korlix_ai_gas_get_balance(p_user_id);

  return jsonb_build_object(
    'consumedSeconds',
    p_seconds,
    'balanceSeconds',
    v_new_balance,
    'idempotent',
    false
  );
end;
$$;

alter table public.korlix_ai_gas_products
  enable row level security;

alter table public.korlix_ai_gas_purchases
  enable row level security;

alter table public.korlix_ai_gas_ledger
  enable row level security;

revoke all
on public.korlix_ai_gas_products
from public, anon, authenticated;

revoke all
on public.korlix_ai_gas_purchases
from public, anon, authenticated;

revoke all
on public.korlix_ai_gas_ledger
from public, anon, authenticated;

grant select, insert, update, delete
on public.korlix_ai_gas_products
to service_role;

grant select, insert, update, delete
on public.korlix_ai_gas_purchases
to service_role;

grant select, insert, update, delete
on public.korlix_ai_gas_ledger
to service_role;

revoke all
on function public.korlix_ai_gas_set_updated_at()
from public, anon, authenticated;

revoke all
on function public.korlix_ai_gas_get_catalog()
from public, anon, authenticated;

revoke all
on function public.korlix_ai_gas_get_balance(uuid)
from public, anon, authenticated;

revoke all
on function public.korlix_ai_gas_grant_verified_purchase(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
)
from public, anon, authenticated;

revoke all
on function public.korlix_ai_gas_reverse_verified_purchase(
  text,
  text,
  text,
  jsonb
)
from public, anon, authenticated;

revoke all
on function public.korlix_ai_gas_consume(
  uuid,
  integer,
  text,
  text,
  jsonb
)
from public, anon, authenticated;

grant execute
on function public.korlix_ai_gas_set_updated_at()
to service_role;

grant execute
on function public.korlix_ai_gas_get_catalog()
to service_role;

grant execute
on function public.korlix_ai_gas_get_balance(uuid)
to service_role;

grant execute
on function public.korlix_ai_gas_grant_verified_purchase(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
)
to service_role;

grant execute
on function public.korlix_ai_gas_reverse_verified_purchase(
  text,
  text,
  text,
  jsonb
)
to service_role;

grant execute
on function public.korlix_ai_gas_consume(
  uuid,
  integer,
  text,
  text,
  jsonb
)
to service_role;

comment on table public.korlix_ai_gas_products is
  'Server-owned KORLIX AI GAS product catalog.';

comment on table public.korlix_ai_gas_purchases is
  'Verified provider transactions. Raw receipts and tokens are not stored.';

comment on table public.korlix_ai_gas_ledger is
  'Append-only AI GAS second-credit ledger.';

comment on function public.korlix_ai_gas_grant_verified_purchase(
  uuid,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
) is
  'Idempotently grants AI GAS only after server-side provider verification.';

comment on function public.korlix_ai_gas_consume(
  uuid,
  integer,
  text,
  text,
  jsonb
) is
  'Atomically consumes purchased AI GAS through a service-role caller.';

commit;
