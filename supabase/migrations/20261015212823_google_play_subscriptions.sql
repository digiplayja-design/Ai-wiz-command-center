-- Google Play facts and purchase tokens are accessible only to the backend.
create table public.korlix_play_billing_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 account_id text not null unique check(account_id ~ '^[0-9a-f]{64}$'),
 base_tier text not null check(base_tier in ('basic','pro','ultra','enterprise')),
 last_applied_tier text not null,
 sync_token uuid, sync_until timestamptz,
 next_sync_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create table public.korlix_play_purchases (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'),
 purchase_token text not null,
 user_id uuid not null references public.korlix_play_billing_accounts(user_id) on delete cascade,
 product_id text not null check(product_id in ('korlix_pro','korlix_ultra')),
 tier text not null check(tier in ('pro','ultra')),
 state text not null, active boolean not null default false,
 expires_at timestamptz, acknowledged boolean not null default false,
 auto_renew boolean not null default false, test_purchase boolean not null default false,
 replaced_by_hash text,
 observed_at timestamptz not null default now()
);
create index korlix_play_purchases_owner on public.korlix_play_purchases(user_id);
create index korlix_play_billing_due on public.korlix_play_billing_accounts(next_sync_at);
alter table public.korlix_play_billing_accounts enable row level security;
alter table public.korlix_play_purchases enable row level security;
revoke all on public.korlix_play_billing_accounts,public.korlix_play_purchases from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_play_billing_accounts,public.korlix_play_purchases to service_role;

create or replace function public.korlix_web_native_tier(p_user_id uuid)
returns text language sql stable security invoker set search_path=pg_catalog,public as $$
 select coalesce((select tier from (
   select a.tier from public.apple_subscription_entitlements a
    where a.user_id=p_user_id and a.status in ('active','grace_period') and a.revoked_at is null and a.expires_at>now()
   union all
   select s.tier from public.subscriptions s where s.user_id=p_user_id
    and s.status in ('active','trialing','grace_period') and s.current_period_end>now()
   union all
   select g.tier from public.korlix_play_purchases g where g.user_id=p_user_id
    and g.active and g.expires_at>now() and g.replaced_by_hash is null
 ) x where tier in ('pro','ultra','enterprise')
 order by case tier when 'enterprise' then 3 when 'ultra' then 2 else 1 end desc limit 1),'basic');
$$;

-- Extend the existing shared resolver. Accounts that have never used Play keep
-- the previous web/Apple behavior. Play expiry is enforced on every profile read.
create or replace function public.korlix_web_billing_profile(p_user_id uuid,p_provider_update boolean default false)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr public.user_profiles; m public.korlix_web_billing_accounts; g public.korlix_play_billing_accounts;
 native_tier text; effective text; web_tier text;
begin
 select * into pr from public.user_profiles where id=p_user_id for update;
 if not found then raise exception 'BILL404: Account profile is unavailable.'; end if;
 select * into m from public.korlix_web_billing_accounts where user_id=p_user_id for update;
 select * into g from public.korlix_play_billing_accounts where user_id=p_user_id for update;
 native_tier:=public.korlix_web_native_tier(p_user_id);
 web_tier:=case when m.livemode and not m.held and m.state in ('active','past_due')
   and m.paid_until>now() then coalesce(m.paid_tier,'basic') else 'basic' end;
 if g.user_id is not null then
   if not p_provider_update and pr.tier<>g.last_applied_tier and (native_tier='basic' or pr.tier<>native_tier) then
     g.base_tier:=pr.tier;
     if m.user_id is not null then m.base_tier:=pr.tier; end if;
   end if;
   select t into effective from unnest(array[g.base_tier,m.base_tier,native_tier,web_tier]) t
    where t is not null order by case t when 'enterprise' then 3 when 'ultra' then 2 when 'pro' then 1 else 0 end desc limit 1;
   update public.korlix_play_billing_accounts set base_tier=g.base_tier,last_applied_tier=effective where user_id=p_user_id;
 elsif m.user_id is not null then
   if not p_provider_update and pr.tier<>m.last_applied_tier and (native_tier='basic' or pr.tier<>native_tier) then m.base_tier:=pr.tier; end if;
   select t into effective from unnest(array[m.base_tier,native_tier,web_tier]) t
    order by case t when 'enterprise' then 3 when 'ultra' then 2 when 'pro' then 1 else 0 end desc limit 1;
 else
   return to_jsonb(pr)||jsonb_build_object('developer_unlimited',public.korlix_has_unlimited_access(p_user_id));
 end if;
 if pr.tier<>effective then update public.user_profiles set tier=effective where id=p_user_id returning * into pr; end if;
 if m.user_id is not null then
   update public.korlix_web_billing_accounts set base_tier=m.base_tier,last_applied_tier=effective where user_id=p_user_id;
 end if;
 return to_jsonb(pr)||jsonb_build_object('developer_unlimited',public.korlix_has_unlimited_access(p_user_id));
end;
$$;

create function public.korlix_play_billing_command(p_actor uuid,p_action text,p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare g public.korlix_play_billing_accounts; r public.korlix_play_purchases;
 pr jsonb; native_other boolean; web_active boolean; play_active boolean; base text; hash text;
begin
 if p_action='lookup' then
   select a.* into g from public.korlix_play_billing_accounts a where
    a.account_id=p->>'account_id' or a.user_id=(select user_id from public.korlix_play_purchases where token_hash=p->>'token_hash');
   return case when found then jsonb_build_object('user_id',g.user_id) else null end;
 end if;
 if p_action='due' then
   return coalesce((select jsonb_agg(x) from (select a.user_id from public.korlix_play_billing_accounts a
    where a.next_sync_at<=now() and (a.sync_until is null or a.sync_until<now())
     and exists(select 1 from public.korlix_play_purchases t where t.user_id=a.user_id and t.replaced_by_hash is null
      and t.state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'))
    order by a.next_sync_at limit 20) x),'[]'::jsonb);
 end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.'; end if;
 pr:=public.korlix_web_billing_profile(p_actor);
 select * into g from public.korlix_play_billing_accounts where user_id=p_actor for update;
 if p_action in ('snapshot','prepare') then
   native_other:=exists(select 1 from public.apple_subscription_entitlements where user_id=p_actor and
     status in ('active','grace_period') and revoked_at is null and expires_at>now()) or
     exists(select 1 from public.subscriptions where user_id=p_actor and status in ('active','trialing','grace_period') and current_period_end>now());
   web_active:=exists(select 1 from public.korlix_web_billing_accounts where user_id=p_actor and
     (held or state='checkout' or (subscription_id is not null and state not in ('canceled','incomplete_expired'))));
   play_active:=exists(select 1 from public.korlix_play_purchases where user_id=p_actor and active and expires_at>now() and replaced_by_hash is null);
   if p_action='prepare' then
     if coalesce((pr->>'is_disabled')::boolean,false) then raise exception 'BILL403: Account is disabled.'; end if;
     if native_other or web_active then raise exception 'BILL409: Manage your existing subscription with its original billing provider.'; end if;
     if pr->>'tier'='enterprise' or (pr->>'tier'<>'basic' and not play_active) then
       raise exception 'BILL409: Your account already has paid or custom access. No additional subscription is needed.';
     end if;
     if coalesce(p->>'account_id','') !~ '^[0-9a-f]{64}$' then raise exception 'BILL400: Invalid billing account.'; end if;
     if g.user_id is null then
       -- Purchase preparation is permitted only with Basic access. No paid
       -- provider tier can accidentally become a permanent manual grant.
       insert into public.korlix_play_billing_accounts(user_id,account_id,base_tier,last_applied_tier)
        values(p_actor,p->>'account_id','basic',pr->>'tier') returning * into g;
     elsif g.account_id<>p->>'account_id' then raise exception 'BILL409: Billing account changed.'; end if;
   end if;
   return jsonb_build_object('tier',pr->>'tier','disabled',pr->'is_disabled','account_id',g.account_id,
    'webSubscriptionActive',web_active,'otherStoreSubscriptionActive',native_other,
    'canPurchase',not native_other and not web_active and not coalesce((pr->>'is_disabled')::boolean,false)
      and (pr->>'tier'='basic' or (play_active and pr->>'tier'<>'enterprise')),
    'entitlement',(select jsonb_build_object('product_id',product_id,'tier',tier,'status',state,'expires_at',expires_at,
      'active',active and expires_at>now(),'auto_renew_status',auto_renew,'environment',case when test_purchase then 'Test' else 'Production' end)
      from public.korlix_play_purchases where user_id=p_actor and replaced_by_hash is null
      order by active desc, expires_at desc nulls last limit 1));
 end if;
 if g.user_id is null then raise exception 'BILL409: Restore the purchase using the KORLIX account that started it.'; end if;
 if p_action='claim' then
   if g.sync_until>now() then raise exception 'BILL409: Subscription is updating. Please retry shortly.'; end if;
   update public.korlix_play_billing_accounts set sync_token=gen_random_uuid(),sync_until=now()+interval '90 seconds',next_sync_at=now()+interval '1 minute'
    where user_id=p_actor returning * into g;
   return jsonb_build_object('sync_token',g.sync_token,'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from
    (select purchase_token,product_id from public.korlix_play_purchases where user_id=p_actor and replaced_by_hash is null
      and state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED')
      order by observed_at desc limit 10) x),'[]'::jsonb));
 end if;
 if p_action='release' then
   update public.korlix_play_billing_accounts set sync_token=null,sync_until=null,next_sync_at=now()+case when coalesce((p->>'success')::boolean,false)
    then interval '10 minutes' else interval '1 minute' end where user_id=p_actor and sync_token::text=p->>'sync_token';
   return jsonb_build_object('ok',true);
 end if;
 if g.sync_token is null or g.sync_token::text is distinct from p->>'sync_token' or g.sync_until<now() then
   raise exception 'BILL409: Subscription changed while verifying. Please retry.';
 end if;
 hash:=p->>'token_hash';
 if p_action='acknowledged' then
   update public.korlix_play_purchases set acknowledged=true where user_id=p_actor and token_hash=hash;
   return jsonb_build_object('ok',true);
 end if;
 if p_action<>'apply' then raise exception 'BILL400: Unsupported billing action.'; end if;
 if coalesce(hash,'') !~ '^[0-9a-f]{64}$' or g.account_id is distinct from p->>'account_id'
    or coalesce(p->>'product_id','') not in ('korlix_pro','korlix_ultra')
    or p->>'tier' is distinct from (case p->>'product_id' when 'korlix_pro' then 'pro' else 'ultra' end) then
   raise exception 'BILL409: Purchase does not match this account.';
 end if;
 select * into r from public.korlix_play_purchases where token_hash=hash for update;
 if found and r.user_id<>p_actor then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if p->>'linked_hash' is not null then
   if p->>'linked_hash'=hash then raise exception 'BILL409: Invalid replacement purchase.'; end if;
   if exists(select 1 from public.korlix_play_purchases where token_hash=p->>'linked_hash' and user_id<>p_actor) then
     raise exception 'BILL409: Linked purchase belongs to another account.';
   end if;
   if not exists(select 1 from public.korlix_play_purchases where token_hash=p->>'linked_hash' and user_id=p_actor) then
     raise exception 'BILL409: Restore your previous Google Play subscription before changing plans.';
   end if;
 end if;
 insert into public.korlix_play_purchases(token_hash,purchase_token,user_id,product_id,tier,state,active,expires_at,acknowledged,auto_renew,test_purchase)
 values(hash,p->>'purchase_token',p_actor,p->>'product_id',p->>'tier',p->>'state',(p->>'active')::boolean,
   (p->>'expires_at')::timestamptz,(p->>'acknowledged')::boolean,(p->>'auto_renew')::boolean,(p->>'test_purchase')::boolean)
 on conflict(token_hash) do update set product_id=excluded.product_id,tier=excluded.tier,state=excluded.state,
   active=excluded.active,expires_at=excluded.expires_at,acknowledged=excluded.acknowledged,auto_renew=excluded.auto_renew,observed_at=now()
   where korlix_play_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 -- A superseded token is never restored by a late notification. Keep its
 -- ownership binding permanently, including after refunds and replacements.
 if (p->>'active')::boolean and r.replaced_by_hash is null and p->>'linked_hash' is not null then
   update public.korlix_play_purchases set replaced_by_hash=hash where token_hash=p->>'linked_hash' and user_id=p_actor;
 end if;
 pr:=public.korlix_web_billing_profile(p_actor,true);
 return jsonb_build_object('tier',pr->>'tier','active',coalesce((p->>'active')::boolean,false) and r.replaced_by_hash is null);
end;
$$;
revoke all on function public.korlix_play_billing_command(uuid,text,jsonb),public.korlix_web_native_tier(uuid),public.korlix_web_billing_profile(uuid,boolean) from public,anon,authenticated;
grant execute on function public.korlix_play_billing_command(uuid,text,jsonb),public.korlix_web_native_tier(uuid),public.korlix_web_billing_profile(uuid,boolean) to service_role;

-- Apple callbacks must reconcile Play in the same transaction too. Otherwise
-- an old Apple notification can make a provider tier look like a manual grant.
do $patch$
declare definition text; anchor text := 'exists(select 1 from public.korlix_web_billing_accounts where user_id=p_user_id)';
begin
 select pg_get_functiondef(p.oid) into strict definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='korlix_apply_apple_subscription_entitlement';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 then
   raise exception 'Apple billing implementation changed; review before applying Play integration';
 end if;
 execute replace(definition,anchor,'('||anchor||' or exists(select 1 from public.korlix_play_billing_accounts where user_id=p_user_id))');
end;
$patch$;
