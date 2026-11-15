-- Esha-only store membership and consultation allowance. Apply as a Supabase migration.
-- No core Korlix profile, subscription, credit, or model-policy table is modified.
create table public.korlix_esha_billing_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.korlix_esha_purchases (
  purchase_key text primary key check (purchase_key ~ '^[a-f0-9]{64}$'),
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  provider text not null check (provider in ('apple','google')),
  provider_token text not null check (length(provider_token) between 5 and 4096),
  product_id text not null,
  period_key text not null check (period_key ~ '^[a-f0-9]{64}$'),
  period_started_at timestamptz not null,
  expires_at timestamptz not null,
  active boolean not null,
  revoked boolean not null default false,
  trial boolean not null default false,
  auto_renewing boolean not null default false,
  test_purchase boolean not null default false,
  provider_updated_at timestamptz not null,
  observed_at timestamptz not null,
  superseded_by text check (superseded_by is null or superseded_by ~ '^[a-f0-9]{64}$'),
  next_sync_at timestamptz not null default now(),
  check ((provider='apple' and product_id='com.korlixdeveloper.esha.monthly') or
    (provider='google' and product_id='esha_monthly')),
  check (expires_at >= period_started_at)
);
create index korlix_esha_purchases_user on public.korlix_esha_purchases(user_id);
create index korlix_esha_purchases_sync on public.korlix_esha_purchases(next_sync_at);
create table public.korlix_esha_voided_periods (
  period_key text primary key check (period_key ~ '^[a-f0-9]{64}$'),
  -- Refund notifications can arrive before a signed-in client first restores.
  -- Keep hash-only tombstones independently of purchase/account row creation.
  purchase_key text not null check (purchase_key ~ '^[a-f0-9]{64}$'),
  user_id uuid references public.korlix_esha_billing_accounts(user_id) on delete set null,
  verified_at timestamptz not null default now()
);
create index korlix_esha_voided_purchase on public.korlix_esha_voided_periods(purchase_key);
create table public.korlix_esha_consultation_grants (
  period_key text primary key check (period_key ~ '^[a-f0-9]{64}$'),
  purchase_key text not null references public.korlix_esha_purchases(purchase_key) on delete cascade,
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  quantity integer not null check (quantity between 1 and 999999),
  used integer not null default 0 check (used >= 0),
  reserved integer not null default 0 check (reserved >= 0),
  trial boolean not null,
  revoked boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (used + reserved <= quantity)
);
create index korlix_esha_grants_user on public.korlix_esha_consultation_grants(user_id);
create index korlix_esha_grants_purchase on public.korlix_esha_consultation_grants(purchase_key);
create table public.korlix_esha_consultation_requests (
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  request_id uuid not null,
  input_hash text not null check (input_hash ~ '^[a-f0-9]{64}$'),
  period_key text not null references public.korlix_esha_consultation_grants(period_key),
  state text not null check (state in ('reserved','committed','failed')),
  result jsonb,
  created_at timestamptz not null default now(),
  deadline timestamptz not null default now()+interval '10 minutes',
  finished_at timestamptz,
  primary key (user_id,request_id),
  check (state<>'committed' or result is not null)
);
create index korlix_esha_requests_pending on public.korlix_esha_consultation_requests(user_id,deadline) where state='reserved';
alter table public.korlix_esha_billing_accounts enable row level security;
alter table public.korlix_esha_purchases enable row level security;
alter table public.korlix_esha_voided_periods enable row level security;
alter table public.korlix_esha_consultation_grants enable row level security;
alter table public.korlix_esha_consultation_requests enable row level security;
revoke all on public.korlix_esha_billing_accounts,public.korlix_esha_purchases,public.korlix_esha_voided_periods,
  public.korlix_esha_consultation_grants,public.korlix_esha_consultation_requests from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_esha_billing_accounts,public.korlix_esha_purchases,public.korlix_esha_voided_periods,
  public.korlix_esha_consultation_grants,public.korlix_esha_consultation_requests to service_role;

create function public.korlix_esha_billing_command(p_actor uuid,p_action text,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  t timestamptz:=clock_timestamp();
  old public.korlix_esha_purchases;
  linked public.korlix_esha_purchases;
  chosen public.korlix_esha_purchases;
  g public.korlix_esha_consultation_grants;
  r public.korlix_esha_consultation_requests;
  quantity integer; fresh boolean; membership_active boolean;
  incoming_observed timestamptz; incoming_updated timestamptz; incoming_start timestamptz; incoming_expiry timestamptz;
  accepted boolean;
begin
  -- Serialize a confirmed refund with first restore, including before a purchase
  -- row exists. All apply/refund paths take this lock before an account row lock.
  if p_action in ('apply','record_void') and coalesce(p->>'purchase_key','')~'^[a-f0-9]{64}$' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('esha:'||(p->>'purchase_key'),0));
  end if;
  if p_action='due' then
    return coalesce((select jsonb_agg(to_jsonb(x)) from
      (select * from public.korlix_esha_purchases where next_sync_at<=t and expires_at>t-interval '60 days'
        order by next_sync_at limit 50)x),'[]');
  end if;
  if p_action='lookup' then
    return (select to_jsonb(x) from public.korlix_esha_purchases x where purchase_key=p->>'purchase_key');
  end if;
  if p_action='record_void' then
    if coalesce(p->>'purchase_key','')!~'^[a-f0-9]{64}$' or coalesce(p->>'period_key','')!~'^[a-f0-9]{64}$' then
      raise exception 'ESHA400:invalid_refund:Invalid confirmed refunded order.';
    end if;
    select * into old from public.korlix_esha_purchases where purchase_key=p->>'purchase_key';
    if found then
      -- The same account lock orders this confirmed refund against reserve and
      -- commit. A second store lookup must not be needed to remove paid access.
      perform 1 from public.korlix_esha_billing_accounts where user_id=old.user_id for update;
      select * into old from public.korlix_esha_purchases where purchase_key=p->>'purchase_key' for update;
    end if;
    insert into public.korlix_esha_voided_periods(period_key,purchase_key)
      values(p->>'period_key',p->>'purchase_key') on conflict do nothing;
    if exists(select 1 from public.korlix_esha_voided_periods where period_key=p->>'period_key' and purchase_key<>p->>'purchase_key') then
      raise exception 'ESHA409:period_ownership_mismatch:This refunded order belongs to a different purchase.';
    end if;
    if old.purchase_key is not null then
      update public.korlix_esha_voided_periods set user_id=old.user_id
        where period_key=p->>'period_key' and user_id is null;
      update public.korlix_esha_purchases set active=false,revoked=true,next_sync_at=t
        where purchase_key=old.purchase_key and period_key=p->>'period_key';
      update public.korlix_esha_consultation_grants set revoked=true
        where purchase_key=old.purchase_key and period_key=p->>'period_key';
    end if;
    return jsonb_build_object('recorded',true);
  end if;
  if p_actor is null then raise exception 'ESHA401:authentication_required:Sign in to use Esha.'; end if;
  insert into public.korlix_esha_billing_accounts(user_id) values(p_actor) on conflict do nothing;
  perform 1 from public.korlix_esha_billing_accounts where user_id=p_actor for update;

  -- A crashed/timed-out provider request cannot reserve a consultation forever.
  -- The server provider timeout is 180 seconds; this lease is ten minutes.
  for r in select * from public.korlix_esha_consultation_requests
    where user_id=p_actor and state='reserved' and deadline<=t for update loop
    update public.korlix_esha_consultation_grants set reserved=reserved-1 where period_key=r.period_key;
    update public.korlix_esha_consultation_requests set state='failed',finished_at=t
      where user_id=p_actor and request_id=r.request_id;
  end loop;

  if p_action='apply' then
    if coalesce(p->>'provider','') not in ('apple','google') or
      coalesce(p->>'purchase_key','')!~'^[a-f0-9]{64}$' or coalesce(p->>'period_key','')!~'^[a-f0-9]{64}$' or
      length(coalesce(p->>'provider_token','')) not between 5 and 4096 or
      (p->>'provider'='apple' and p->>'product_id' is distinct from 'com.korlixdeveloper.esha.monthly') or
      (p->>'provider'='google' and p->>'product_id' is distinct from 'esha_monthly') or
      jsonb_typeof(p->'active') is distinct from 'boolean' or jsonb_typeof(p->'revoked') is distinct from 'boolean' or
      jsonb_typeof(p->'trial') is distinct from 'boolean' or jsonb_typeof(p->'test_purchase') is distinct from 'boolean' or
      jsonb_typeof(p->'auto_renewing') is distinct from 'boolean' or
      ((p->>'revoked')::boolean and (p->>'active')::boolean) then
      raise exception 'ESHA400:invalid_purchase:Invalid verified Esha purchase.';
    end if;
    incoming_observed:=(p->>'observed_at')::timestamptz;
    incoming_updated:=(p->>'provider_updated_at')::timestamptz;
    incoming_start:=(p->>'period_started_at')::timestamptz;
    incoming_expiry:=(p->>'expires_at')::timestamptz;
    quantity:=(p->>'allowance')::integer;
    if incoming_observed is null or incoming_updated is null or incoming_start is null or incoming_expiry is null or
      incoming_observed>t+interval '5 minutes' or incoming_updated>t+interval '5 minutes' or
      incoming_start>t+interval '5 minutes' or incoming_expiry<incoming_start or
      (quantity is not null and quantity not between 1 and 999999) then
      raise exception 'ESHA400:invalid_purchase:Invalid verified purchase dates or allowance.';
    end if;
    -- INSERT/unique key + row lock binds a token once, including concurrent restores by two accounts.
    insert into public.korlix_esha_purchases(purchase_key,user_id,provider,provider_token,product_id,period_key,
      period_started_at,expires_at,active,revoked,trial,auto_renewing,test_purchase,provider_updated_at,observed_at)
      values(p->>'purchase_key',p_actor,p->>'provider',p->>'provider_token',p->>'product_id',p->>'period_key',
        incoming_start,incoming_expiry,false,false,(p->>'trial')::boolean,(p->>'auto_renewing')::boolean,
        (p->>'test_purchase')::boolean,'epoch','epoch') on conflict do nothing;
    select * into old from public.korlix_esha_purchases where purchase_key=p->>'purchase_key' for update;
    if old.user_id<>p_actor or old.provider<>p->>'provider' or old.product_id<>p->>'product_id' or
      old.provider_token<>p->>'provider_token' or old.test_purchase<>(p->>'test_purchase')::boolean then
      raise exception 'ESHA409:purchase_ownership_mismatch:This store purchase is already linked to another account or product.';
    end if;
    -- Play replacement tokens never revive their superseded predecessor, even
    -- when an older in-flight API lookup completes after the replacement.
    if old.superseded_by is not null then p:=p||jsonb_build_object('active',false,'revoked',true); end if;
    -- A confirmed Google void belongs to an order forever; a later ACTIVE response
    -- for the same token/order must not undo a refund-without-revoke from Play.
    if p->>'provider'='google' and coalesce((p->>'voided')::boolean,false) then
      insert into public.korlix_esha_voided_periods(period_key,purchase_key,user_id)
        values(p->>'period_key',old.purchase_key,p_actor) on conflict do nothing;
    end if;
    if exists(select 1 from public.korlix_esha_voided_periods where period_key=p->>'period_key') then
      update public.korlix_esha_voided_periods set user_id=p_actor where period_key=p->>'period_key' and purchase_key=old.purchase_key and user_id is null;
      if not exists(select 1 from public.korlix_esha_voided_periods where period_key=p->>'period_key' and user_id=p_actor and purchase_key=old.purchase_key) then
        raise exception 'ESHA409:period_ownership_mismatch:This refunded period belongs to another purchase.';
      end if;
      p:=p||jsonb_build_object('active',false,'revoked',true);
    end if;
    accepted:=incoming_observed>=old.observed_at and incoming_start>=old.period_started_at and
      (old.provider<>'apple' or incoming_updated>=old.provider_updated_at) and
      not (old.revoked and (p->>'active')::boolean and old.period_key=p->>'period_key' and incoming_updated<=old.provider_updated_at);
    if accepted then
      if p->>'linked_purchase_key' is not null then
        select * into linked from public.korlix_esha_purchases where purchase_key=p->>'linked_purchase_key' for update;
        if found and linked.user_id<>p_actor then
          raise exception 'ESHA409:purchase_ownership_mismatch:The previous subscription belongs to another account.';
        end if;
        if found and linked.purchase_key<>old.purchase_key then
          update public.korlix_esha_purchases set active=false,revoked=true,superseded_by=old.purchase_key,
            observed_at=greatest(observed_at,incoming_observed),provider_updated_at=greatest(provider_updated_at,incoming_updated),next_sync_at=t+interval '1 day'
            where purchase_key=linked.purchase_key;
          update public.korlix_esha_consultation_grants set revoked=true where purchase_key=linked.purchase_key;
        end if;
      end if;
      update public.korlix_esha_purchases set period_key=p->>'period_key',period_started_at=incoming_start,
        expires_at=incoming_expiry,active=(p->>'active')::boolean,revoked=(p->>'revoked')::boolean,
        trial=(p->>'trial')::boolean,auto_renewing=(p->>'auto_renewing')::boolean,
        provider_updated_at=incoming_updated,observed_at=incoming_observed,
        next_sync_at=t+case when (p->>'active')::boolean then interval '10 minutes' else interval '1 day' end
        where purchase_key=old.purchase_key;
      -- Only the current verified billing period is usable; renewal does not roll unused consultations over.
      update public.korlix_esha_consultation_grants set revoked=true where purchase_key=old.purchase_key and
        (period_key<>p->>'period_key' or not (p->>'active')::boolean or (p->>'revoked')::boolean);
      if (p->>'active')::boolean and not (p->>'revoked')::boolean and incoming_expiry>t and quantity is not null then
        insert into public.korlix_esha_consultation_grants(period_key,purchase_key,user_id,quantity,trial,expires_at)
          values(p->>'period_key',old.purchase_key,p_actor,quantity,(p->>'trial')::boolean,incoming_expiry)
          on conflict do nothing;
        select * into g from public.korlix_esha_consultation_grants where period_key=p->>'period_key' for update;
        if g.user_id<>p_actor or g.purchase_key<>old.purchase_key or g.trial<>(p->>'trial')::boolean then
          raise exception 'ESHA409:period_ownership_mismatch:This billing period belongs to a different purchase.';
        end if;
        -- Quantity is immutable for a period. Restores/config changes cannot refill used consultations.
        update public.korlix_esha_consultation_grants set revoked=false,expires_at=incoming_expiry
          where period_key=g.period_key;
      end if;
    end if;
  elsif p_action='retry_later' then
    update public.korlix_esha_purchases set next_sync_at=t+interval '5 minutes'
      where user_id=p_actor and purchase_key=p->>'purchase_key';
  elsif p_action='purchases' then
    return coalesce((select jsonb_agg(to_jsonb(x)) from
      (select * from public.korlix_esha_purchases where user_id=p_actor order by observed_at desc limit 100)x),'[]');
  elsif p_action='reserve' then
    if coalesce(p->>'request_id','')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' or
      coalesce(p->>'input_hash','')!~'^[a-f0-9]{64}$' then
      raise exception 'ESHA400:invalid_request:Send a valid consultation request ID.';
    end if;
    select * into r from public.korlix_esha_consultation_requests
      where user_id=p_actor and request_id=(p->>'request_id')::uuid for update;
    if found then
      if r.input_hash<>p->>'input_hash' then raise exception 'ESHA409:idempotency_mismatch:This request ID has already been used for different content.'; end if;
      if r.state='committed' then return jsonb_build_object('replay',true,'result',r.result); end if;
      if r.state='failed' then raise exception 'ESHA409:request_finished:This request has ended. Start a new consultation request.'; end if;
      raise exception 'ESHA409:request_in_progress:This consultation is still running. Retry this same request shortly.';
    end if;
    if exists(select 1 from public.korlix_esha_consultation_requests where user_id=p_actor and state='reserved') then
      raise exception 'ESHA409:request_in_progress:Wait for your current Esha consultation to finish.';
    end if;
    -- Choose one membership. Duplicate subscriptions across stores never stack allowances.
    select x.* into chosen from public.korlix_esha_purchases x where x.user_id=p_actor and x.active and not x.revoked and x.expires_at>t
      order by x.trial,x.expires_at desc,x.observed_at desc limit 1;
    if not found then raise exception 'ESHA402:membership_required:An active Esha membership is required.'; end if;
    if chosen.observed_at<t-interval '15 minutes' then
      raise exception 'ESHA503:verification_stale:Restore your membership so Esha can verify your access.';
    end if;
    select * into g from public.korlix_esha_consultation_grants where period_key=chosen.period_key and user_id=p_actor and not revoked and expires_at>t for update;
    if not found then raise exception 'ESHA503:allowance_unconfigured:Your Esha consultation allowance is being set up.'; end if;
    if g.quantity<=g.used+g.reserved then raise exception 'ESHA402:allowance_exhausted:You have used the consultations included in this Esha billing period.'; end if;
    update public.korlix_esha_consultation_grants set reserved=reserved+1 where period_key=g.period_key;
    insert into public.korlix_esha_consultation_requests(user_id,request_id,input_hash,period_key,state)
      values(p_actor,(p->>'request_id')::uuid,p->>'input_hash',g.period_key,'reserved');
    return jsonb_build_object('replay',false,'requestId',p->>'request_id');
  elsif p_action in ('commit','release') then
    select * into r from public.korlix_esha_consultation_requests where user_id=p_actor and request_id=(p->>'request_id')::uuid for update;
    if not found then raise exception 'ESHA404:request_not_found:Consultation request not found.'; end if;
    if r.input_hash is distinct from p->>'input_hash' then raise exception 'ESHA409:idempotency_mismatch:This request ID has different content.'; end if;
    if r.state='committed' then return jsonb_build_object('committed',true,'result',r.result); end if;
    if r.state='failed' then
      if p_action='release' then return jsonb_build_object('released',true); end if;
      raise exception 'ESHA409:request_finished:This consultation request has expired.';
    end if;
    select * into g from public.korlix_esha_consultation_grants where period_key=r.period_key for update;
    if p_action='commit' then
      if g.revoked then raise exception 'ESHA402:membership_revoked:This Esha billing period is no longer active.'; end if;
      if jsonb_typeof(p->'result') is distinct from 'object' or jsonb_typeof(p->'result'->'answer') is distinct from 'string' or
        length(p->'result'->>'answer') not between 1 and 24000 or jsonb_typeof(p->'result'->'productIds') is distinct from 'array' or
        jsonb_array_length(p->'result'->'productIds')>12 then
        raise exception 'ESHA400:invalid_result:Invalid consultation result.';
      end if;
      update public.korlix_esha_consultation_grants set reserved=reserved-1,used=used+1 where period_key=g.period_key;
      update public.korlix_esha_consultation_requests set state='committed',result=p->'result',finished_at=t
        where user_id=p_actor and request_id=r.request_id;
      return jsonb_build_object('committed',true,'result',p->'result');
    end if;
    update public.korlix_esha_consultation_grants set reserved=reserved-1 where period_key=g.period_key;
    update public.korlix_esha_consultation_requests set state='failed',finished_at=t where user_id=p_actor and request_id=r.request_id;
    return jsonb_build_object('released',true);
  elsif p_action<>'snapshot' then raise exception 'ESHA400:invalid_action:Unknown Esha billing action.';
  end if;

  select x.* into chosen from public.korlix_esha_purchases x where x.user_id=p_actor
    order by (x.active and not x.revoked and x.expires_at>t) desc,x.trial,x.expires_at desc,x.observed_at desc limit 1;
  membership_active:=coalesce(chosen.active and not chosen.revoked and chosen.expires_at>t,false);
  fresh:=coalesce(chosen.observed_at>=t-interval '15 minutes',false);
  select * into g from public.korlix_esha_consultation_grants where period_key=chosen.period_key and user_id=p_actor and not revoked and expires_at>t;
  return jsonb_build_object('membership',jsonb_build_object('active',membership_active,'provider',chosen.provider,
    'expiresAt',chosen.expires_at,'trial',coalesce(chosen.trial,false),'verificationFresh',fresh,'autoRenewing',coalesce(chosen.auto_renewing,false)),
    'allowance',jsonb_build_object('configured',g.period_key is not null,'limit',g.quantity,'used',coalesce(g.used,0),
      'reserved',coalesce(g.reserved,0),'remaining',case when membership_active then greatest(0,g.quantity-g.used-g.reserved) else 0 end,
      'periodEndsAt',case when g.period_key is not null then g.expires_at else null end));
end $$;
revoke all on function public.korlix_esha_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_esha_billing_command(uuid,text,jsonb) to service_role;
