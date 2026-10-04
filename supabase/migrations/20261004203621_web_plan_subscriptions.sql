-- Main web subscriptions. Server-only billing records; no browser writes.
create table public.korlix_web_billing_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  base_tier text not null check (base_tier in ('basic','pro','ultra','enterprise')),
  last_applied_tier text not null check (last_applied_tier in ('basic','pro','ultra','enterprise')),
  generation uuid not null unique default gen_random_uuid(),
  livemode boolean not null,
  requested_tier text not null check (requested_tier in ('pro','ultra')),
  requested_price text not null,
  checkout_email text not null,
  checkout_expires timestamptz not null,
  checkout_id text unique,
  customer_id text unique,
  subscription_id text unique,
  state text not null default 'checkout',
  billed_tier text check (billed_tier in ('pro','ultra')),
  paid_tier text check (paid_tier in ('pro','ultra')),
  paid_until timestamptz,
  invoice_id text,
  cancel_at_period_end boolean not null default false,
  held boolean not null default false,
  hold_reason text,
  sync_token uuid,
  sync_until timestamptz,
  next_sync_at timestamptz not null default now(),
  observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index korlix_web_billing_due_idx on public.korlix_web_billing_accounts(next_sync_at);
create table public.korlix_web_billing_events (
  event_id text primary key,
  event_type text not null,
  livemode boolean not null,
  received_at timestamptz not null default now()
);
alter table public.korlix_web_billing_accounts enable row level security;
alter table public.korlix_web_billing_events enable row level security;
revoke all on public.korlix_web_billing_accounts, public.korlix_web_billing_events from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_web_billing_accounts, public.korlix_web_billing_events to service_role;

create function public.korlix_web_native_tier(p_user_id uuid)
returns text language sql stable security invoker set search_path=pg_catalog,public as $$
 select coalesce((select tier from (
   select a.tier from public.apple_subscription_entitlements a
    where a.user_id=p_user_id and a.status in ('active','grace_period')
      and a.revoked_at is null and a.expires_at>now()
   union all
   select s.tier from public.subscriptions s where s.user_id=p_user_id
    and s.status in ('active','trialing','grace_period') and s.current_period_end>now()
 ) x where tier in ('pro','ultra','enterprise')
 order by case tier when 'enterprise' then 3 when 'ultra' then 2 else 1 end desc limit 1),'basic');
$$;

create function public.korlix_web_billing_profile(p_user_id uuid,p_provider_update boolean default false)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr public.user_profiles; m public.korlix_web_billing_accounts; native_tier text; effective text; web_tier text;
begin
 select * into pr from public.user_profiles where id=p_user_id for update;
 if not found then raise exception 'BILL404: Account profile is unavailable.'; end if;
 select * into m from public.korlix_web_billing_accounts where user_id=p_user_id for update;
 if not found then return to_jsonb(pr); end if;
 native_tier:=public.korlix_web_native_tier(p_user_id);
 -- Preserve an explicit administrator profile change. Provider updates call
 -- this inside their transaction and cannot become a permanent manual grant.
 if not p_provider_update and pr.tier<>m.last_applied_tier and (native_tier='basic' or pr.tier<>native_tier) then
   m.base_tier:=pr.tier;
 end if;
 web_tier:=case when m.livemode and not m.held and m.state in ('active','past_due')
   and m.paid_until>now() then coalesce(m.paid_tier,'basic') else 'basic' end;
 select t into effective from unnest(array[m.base_tier,native_tier,web_tier]) t
 order by case t when 'enterprise' then 3 when 'ultra' then 2 when 'pro' then 1 else 0 end desc limit 1;
 if pr.tier<>effective then
   update public.user_profiles set tier=effective where id=p_user_id returning * into pr;
 end if;
 update public.korlix_web_billing_accounts set base_tier=m.base_tier,last_applied_tier=effective where user_id=p_user_id;
 return to_jsonb(pr);
end;
$$;

create function public.korlix_web_billing_command(p_actor uuid,p_action text,p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare m public.korlix_web_billing_accounts; pr jsonb; uid uuid; nt text; result jsonb;
begin
 if p_action='seen' then return jsonb_build_object('seen',exists(select 1 from public.korlix_web_billing_events where event_id=p->>'event_id')); end if;
 if p_action='record_event' then
   insert into public.korlix_web_billing_events(event_id,event_type,livemode)
   values(p->>'event_id',p->>'event_type',(p->>'livemode')::boolean) on conflict do nothing;
   return jsonb_build_object('ok',true);
 end if;
 if p_action='due' then
   return coalesce((select jsonb_agg(x) from (select user_id from public.korlix_web_billing_accounts
    where next_sync_at<=now() and (sync_until is null or sync_until<now())
     and state not in ('canceled','incomplete_expired','expired')
    order by next_sync_at limit 50) x),'[]'::jsonb);
 end if;
 if p_action='lookup' then
   select * into m from public.korlix_web_billing_accounts where
     (p->>'subscription_id' is not null and subscription_id=p->>'subscription_id') or
     (p->>'checkout_id' is not null and checkout_id=p->>'checkout_id') or
     (p->>'customer_id' is not null and customer_id=p->>'customer_id') or
     (p->>'generation' is not null and generation=(p->>'generation')::uuid);
   return case when found then to_jsonb(m) else null end;
 end if;
 uid:=p_actor;
 if uid is null then raise exception 'BILL401: Sign in required.'; end if;
 -- Consistent lock order across checkout, profile resolution and callbacks.
 perform 1 from public.user_profiles where id=uid for update;
 if not found then raise exception 'BILL404: Account profile is unavailable.'; end if;
 select * into m from public.korlix_web_billing_accounts where user_id=uid for update;
 if p_action='snapshot' then
   pr:=public.korlix_web_billing_profile(uid);
   select * into m from public.korlix_web_billing_accounts where user_id=uid;
   return jsonb_build_object('profile',jsonb_build_object('tier',pr->>'tier','is_disabled',pr->'is_disabled'),
    'native_tier',public.korlix_web_native_tier(uid),'membership',case when m.user_id is null then null else to_jsonb(m) end);
 end if;
 if p_action='checkout_start' then
   pr:=public.korlix_web_billing_profile(uid);
   if coalesce((pr->>'is_disabled')::boolean,false) then raise exception 'BILL403: Account is disabled.'; end if;
   nt:=public.korlix_web_native_tier(uid);
   if nt<>'basic' then raise exception 'BILL409: Manage your existing app-store subscription before starting another subscription.'; end if;
   select * into m from public.korlix_web_billing_accounts where user_id=uid;
   if m.held then raise exception 'BILL409: Contact support about the billing review before starting another subscription.'; end if;
   if m.subscription_id is not null and m.state not in ('canceled','incomplete_expired') then
    raise exception 'BILL409: A subscription already exists. Open Manage Billing.';
   end if;
   if pr->>'tier'<>'basic' then raise exception 'BILL409: Your account already has paid or custom access. Contact support before purchasing.'; end if;
   if coalesce(p->>'tier','') not in ('pro','ultra') or coalesce(p->>'price_id','') !~ '^price_[A-Za-z0-9_]+$' then
    raise exception 'BILL400: Choose an available plan.';
   end if;
   if m.user_id is not null and m.livemode is distinct from (p->>'livemode')::boolean then
    raise exception 'BILL409: Payment environment changed. Contact support.';
   end if;
   if m.state='checkout' then
    if m.requested_tier<>p->>'tier' then raise exception 'BILL409: Finish or cancel the open checkout before choosing another plan.'; end if;
    return to_jsonb(m);
   end if;
   insert into public.korlix_web_billing_accounts(user_id,base_tier,last_applied_tier,livemode,requested_tier,requested_price,checkout_email,checkout_expires)
   values(uid,pr->>'tier',pr->>'tier',(p->>'livemode')::boolean,p->>'tier',p->>'price_id',p->>'email',date_trunc('second',now()+interval '1 hour'))
   on conflict(user_id) do update set generation=gen_random_uuid(),requested_tier=excluded.requested_tier,
    requested_price=excluded.requested_price,checkout_email=excluded.checkout_email,checkout_expires=excluded.checkout_expires,
    checkout_id=null,subscription_id=null,state='checkout',billed_tier=null,paid_tier=null,paid_until=null,invoice_id=null,
    cancel_at_period_end=false,sync_token=null,sync_until=null,next_sync_at=now(),updated_at=now()
   returning * into m;
   return to_jsonb(m);
 end if;
 if m.user_id is null then return null; end if;
 if p_action='checkout_saved' then
   if m.generation::text is distinct from p->>'generation' or coalesce(p->>'checkout_id','') !~ '^cs_[A-Za-z0-9_]+$'
      or (m.checkout_id is not null and m.checkout_id<>p->>'checkout_id') then
    raise exception 'BILL409: Checkout changed. Refresh billing.';
   end if;
   update public.korlix_web_billing_accounts set checkout_id=p->>'checkout_id',next_sync_at=now(),updated_at=now() where user_id=uid returning * into m;
   return to_jsonb(m);
 end if;
 if p_action='claim' then
   if m.sync_until>now() then raise exception 'BILL409: Billing is updating. Please retry shortly.'; end if;
   update public.korlix_web_billing_accounts set sync_token=gen_random_uuid(),sync_until=now()+interval '90 seconds',next_sync_at=now()+interval '1 minute' where user_id=uid returning * into m;
   return to_jsonb(m);
 end if;
 if p_action='release' then
   update public.korlix_web_billing_accounts set sync_token=null,sync_until=null,next_sync_at=now()+interval '1 minute'
    where user_id=uid and sync_token=(p->>'sync_token')::uuid;
   return jsonb_build_object('ok',true);
 end if;
 if p_action in ('apply','empty') then
   if m.generation::text is distinct from p->>'generation' or m.sync_token is null
      or m.sync_token::text is distinct from p->>'sync_token' or m.sync_until<now() then
    raise exception 'BILL409: Billing changed while refreshing. Please retry.';
   end if;
   if p_action='empty' then
    update public.korlix_web_billing_accounts set state=case when p->>'checkout_status'='expired' then 'expired' else state end,
     sync_token=null,sync_until=null,next_sync_at=now()+interval '10 minutes',updated_at=now() where user_id=uid;
    return jsonb_build_object('ok',true);
   end if;
   if m.livemode is distinct from (p->>'livemode')::boolean
     or (m.subscription_id is not null and m.subscription_id<>p->>'subscription_id')
     or (m.customer_id is not null and m.customer_id<>p->>'customer_id')
     or coalesce(p->>'subscription_id','') !~ '^sub_[A-Za-z0-9_]+$'
     or coalesce(p->>'customer_id','') !~ '^cus_[A-Za-z0-9_]+$'
     or coalesce(p->>'tier','') not in ('pro','ultra')
     or coalesce(p->>'state','') not in ('active','past_due','incomplete','incomplete_expired','canceled','unpaid','paused','trialing')
     or (p->>'amount')::integer is distinct from (case p->>'tier' when 'pro' then 3499 else 12499 end)
     then raise exception 'BILL409: Payment does not match this account.'; end if;
   update public.korlix_web_billing_accounts set subscription_id=p->>'subscription_id',customer_id=p->>'customer_id',
    state=p->>'state',billed_tier=p->>'tier',
    paid_tier=case when (p->>'paid')::boolean then p->>'tier' else paid_tier end,
    paid_until=case when p->>'state' in ('canceled','incomplete_expired','unpaid','paused') then null
     when (p->>'paid')::boolean then (p->>'paid_until')::timestamptz else paid_until end,
    invoice_id=case when (p->>'paid')::boolean then p->>'invoice_id' else invoice_id end,
    cancel_at_period_end=coalesce((p->>'cancel_at_period_end')::boolean,false),
    observed_at=now(),sync_token=null,sync_until=null,next_sync_at=now()+interval '10 minutes',updated_at=now()
    where user_id=uid;
   pr:=public.korlix_web_billing_profile(uid,true);
   return jsonb_build_object('ok',true,'tier',pr->>'tier');
 end if;
 if p_action='hold' then
   if m.subscription_id is null or m.subscription_id is distinct from p->>'subscription_id' then return jsonb_build_object('ignored',true); end if;
   update public.korlix_web_billing_accounts set held=true,hold_reason=p->>'reason',updated_at=now() where user_id=uid;
   perform public.korlix_web_billing_profile(uid,true);
   return jsonb_build_object('ok',true);
 end if;
 raise exception 'BILL400: Unsupported billing action.';
end;
$$;
revoke all on function public.korlix_web_native_tier(uuid),public.korlix_web_billing_profile(uuid,boolean),public.korlix_web_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_web_native_tier(uuid),public.korlix_web_billing_profile(uuid,boolean),public.korlix_web_billing_command(uuid,text,jsonb) to service_role;

-- Preserve the inspected Apple implementation and its existing grants.
CREATE OR REPLACE FUNCTION public.korlix_apply_apple_subscription_entitlement(p_user_id uuid, p_product_id text, p_tier text, p_status text, p_environment text, p_original_transaction_id text, p_transaction_id text, p_purchase_date timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token text, p_ownership_type text, p_auto_renew_status boolean, p_signed_transaction_info text, p_signed_renewal_info text, p_last_notification_type text, p_raw_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'auth'
AS $function$
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
$function$
