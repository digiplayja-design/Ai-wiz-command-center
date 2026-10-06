-- Durable, owner-bound preparation for Stripe Accounts v2 merchant onboarding.
-- Apply before deploying its server callers. No Stripe accounts or payment rows
-- are created by this migration; the backend owns all provider API requests.
begin;

create table public.korlix_schedule_stripe_setup (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.korlix_schedule_profiles(owner_id),
 config_hash text not null check(length(config_hash) between 1 and 256),
 livemode boolean not null,
 country text not null check(country ~ '^[A-Z]{2}$'),
 display_name text not null check(length(btrim(display_name)) between 1 and 120),
 contact_email text not null check(length(contact_email) between 3 and 254 and contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
 account_id text unique check(account_id ~ '^acct_[A-Za-z0-9]+$'),
 created_at timestamptz not null default now(),
 confirmed_at timestamptz,
 review_hash text check(review_hash ~ '^[a-f0-9]{64}$'),
 review_expires_at timestamptz,
 review_connection_id uuid references public.korlix_schedule_connections(id),
 review_connection_revision integer,
 unique(owner_id,livemode),
 check((review_hash is null) = (review_expires_at is null)),
 check((review_connection_id is null) = (review_connection_revision is null))
);
alter table public.korlix_schedule_stripe_setup enable row level security;
-- All access goes through the verified-owner backend. Browser roles have neither
-- table privileges nor policies; service_role intentionally bypasses RLS.
revoke all on table public.korlix_schedule_stripe_setup from public,anon,authenticated;
grant select,insert,update on table public.korlix_schedule_stripe_setup to service_role;

-- The legacy OAuth confirmation path must respect reservations made before the
-- new onboarding flow connects an account. Share its account advisory lock so
-- reservation and connection claims serialize even across different owners.
create function public.korlix_schedule_stripe_setup_owner_guard_v1() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if new.provider='stripe' then
  perform pg_advisory_xact_lock(hashtextextended('schedule-stripe:'||new.remote_id,0));
  if exists(select 1 from public.korlix_schedule_stripe_setup
            where account_id=new.remote_id and owner_id<>new.owner_id) then
   raise exception 'This merchant account is linked to another KORLIX host.';
  end if;
 end if;
 return new;
end;
$$;
revoke all on function public.korlix_schedule_stripe_setup_owner_guard_v1() from public,anon,authenticated;
grant execute on function public.korlix_schedule_stripe_setup_owner_guard_v1() to service_role;
create trigger korlix_schedule_stripe_setup_owner_guard
 before insert or update of owner_id,provider,remote_id on public.korlix_schedule_connections
 for each row execute function public.korlix_schedule_stripe_setup_owner_guard_v1();

create function public.korlix_schedule_stripe_setup_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 s public.korlix_schedule_stripe_setup;
 c public.korlix_schedule_connections;
 identity jsonb;
begin
 if not public.korlix_schedule_active_v1(p_actor)
    or not exists(select 1 from public.korlix_schedule_profiles where owner_id=p_actor) then
  raise exception using errcode='42501',message='Save your verified host profile first.';
 end if;

 if p_action='status' then
  if jsonb_typeof(p_data->'livemode') is distinct from 'boolean' then
   raise exception 'Choose the configured payment environment.';
  end if;
  select * into s from public.korlix_schedule_stripe_setup
   where owner_id=p_actor and livemode=(p_data->>'livemode')::boolean;
  if s.id is null then return null;end if;
  return jsonb_build_object('id',s.id,'livemode',s.livemode,'country',s.country,
   'display_name',s.display_name,'account_id',s.account_id,'created_at',s.created_at,
   'confirmed_at',s.confirmed_at,'configuration_matches',s.config_hash is not distinct from p_data->>'config_hash');
 end if;

 -- Shares the owner lock used by Connections, so reviewing or confirming a
 -- merchant cannot interleave with the same owner's disconnect or OAuth switch.
 perform 1 from public.user_profiles where id=p_actor for update;
 if not public.korlix_schedule_active_v1(p_actor) then
  raise exception using errcode='42501',message='Save your verified host profile first.';
 end if;
 if p_action='prepare' then
  if p_data->>'confirmed' is distinct from 'true'
     or jsonb_typeof(p_data->'livemode') is distinct from 'boolean'
     or coalesce(length(p_data->>'config_hash'),0) not between 1 and 256 then
   raise exception 'Confirm merchant setup in the configured payment environment.';
  end if;
  select * into s from public.korlix_schedule_stripe_setup
   where owner_id=p_actor and livemode=(p_data->>'livemode')::boolean for update;
  if s.id is not null then
   if s.config_hash is distinct from p_data->>'config_hash' then
    raise exception using errcode='40001',message='The payment configuration changed. Review merchant setup with your administrator.';
   end if;
   -- The original request parameters remain immutable for Stripe idempotency.
   return to_jsonb(s);
  end if;
  if coalesce(p_data->>'country','') !~ '^[A-Z]{2}$'
     or coalesce(length(btrim(p_data->>'display_name')),0) not between 1 and 120
     or coalesce(length(p_data->>'contact_email'),0) not between 3 and 254
     or coalesce(p_data->>'contact_email','') !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
   raise exception 'Provide a country, business name, and verified contact email.';
  end if;
  insert into public.korlix_schedule_stripe_setup(owner_id,config_hash,livemode,country,display_name,contact_email)
   values(p_actor,p_data->>'config_hash',(p_data->>'livemode')::boolean,p_data->>'country',btrim(p_data->>'display_name'),p_data->>'contact_email')
   returning * into s;
  return to_jsonb(s);
 end if;

 select * into s from public.korlix_schedule_stripe_setup where id=p_id and owner_id=p_actor for update;
 if s.id is null then raise exception using errcode='P0002',message='Merchant setup not found.';end if;
 if p_action='private' then return to_jsonb(s);end if;
 if s.config_hash is distinct from p_data->>'config_hash'
    or to_jsonb(s.livemode) is distinct from p_data->'livemode' then
  raise exception using errcode='40001',message='The payment configuration changed. Review merchant setup again.';
 end if;

 if p_action='created' then
  if coalesce(p_data->>'account_id','') !~ '^acct_[A-Za-z0-9]+$'
     or (s.account_id is not null and s.account_id is distinct from p_data->>'account_id') then
   raise exception using errcode='40001',message='The merchant account does not match this setup.';
  end if;
  -- Stripe v2 idempotency keys expire after 30 days. Never risk recreating an
  -- account when the local acknowledgement is missing outside the safe window.
  if s.account_id is null and s.created_at<=now()-interval '29 days' then
   raise exception using errcode='40001',message='Merchant setup needs administrator recovery before retrying.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('schedule-stripe:'||(p_data->>'account_id'),0));
  if exists(select 1 from public.korlix_schedule_connections where provider='stripe'
            and remote_id=p_data->>'account_id' and owner_id<>p_actor)
     or exists(select 1 from public.korlix_schedule_stripe_setup where account_id=p_data->>'account_id' and owner_id<>p_actor) then
   raise exception 'This merchant account is linked to another KORLIX host.';
  end if;
  update public.korlix_schedule_stripe_setup set account_id=p_data->>'account_id' where id=s.id returning * into s;
  return to_jsonb(s);
 end if;

 if s.account_id is null or s.account_id is distinct from p_data->>'account_id' then
  raise exception using errcode='40001',message='The merchant account does not match this setup.';
 end if;
 if p_action not in ('review','confirm') then raise exception 'Unsupported merchant setup action.';end if;
 if (select count(*) from public.korlix_schedule_connections where owner_id=p_actor and provider='stripe' and state='connected' and enabled)>1 then
  raise exception using errcode='40001',message='Review your existing merchant connections before continuing.';
 end if;
 select * into c from public.korlix_schedule_connections
  where owner_id=p_actor and provider='stripe' and state='connected' and enabled for update;

 if p_action='review' then
  if coalesce(p_data->>'review_hash','') !~ '^[a-f0-9]{64}$' then raise exception 'Invalid merchant review.';end if;
  update public.korlix_schedule_stripe_setup
   set review_hash=p_data->>'review_hash',review_expires_at=now()+interval '10 minutes',
       review_connection_id=c.id,review_connection_revision=c.revision
   where id=s.id returning * into s;
  return jsonb_build_object('id',s.id,'review_expires_at',s.review_expires_at,
   'replaces_existing',c.id is not null and c.remote_id<>s.account_id);
 end if;

 if p_data->>'confirmed' is distinct from 'true'
    or s.review_hash is null or s.review_hash is distinct from p_data->>'review_hash'
    or s.review_expires_at<=now()
    or s.review_connection_id is distinct from c.id
    or s.review_connection_revision is distinct from c.revision then
  raise exception using errcode='40001',message='The merchant review expired or your connection changed. Review again.';
 end if;
 identity:=p_data->'identity';
 if jsonb_typeof(identity) is distinct from 'object'
    or identity->>'id' is distinct from s.account_id
    or identity->'livemode' is distinct from to_jsonb(s.livemode)
    or identity->>'readiness_source' is distinct from 'accounts_v2'
    or jsonb_typeof(identity->'charges_enabled') is distinct from 'boolean'
    or jsonb_typeof(identity->'card_payments_status') is distinct from 'string'
    or jsonb_typeof(identity->'payouts_status') is distinct from 'string'
    or coalesce(length(btrim(identity->>'label')),0) not between 1 and 256
    or coalesce(length(p_data->>'sealed_grant'),0) not between 1 and 16384 then
  raise exception 'Merchant identity could not be verified.';
 end if;
 if (identity->>'charges_enabled')::boolean is distinct from
    (identity->>'card_payments_status'='active' and identity->>'payouts_status'='active') then
  raise exception 'Merchant capabilities could not be verified.';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('schedule-stripe:'||s.account_id,0));
 if exists(select 1 from public.korlix_schedule_connections where provider='stripe' and remote_id=s.account_id and owner_id<>p_actor)
    or exists(select 1 from public.korlix_schedule_stripe_setup where account_id=s.account_id and owner_id<>p_actor) then
  raise exception 'This merchant account is linked to another KORLIX host.';
 end if;
 if exists(select 1 from public.korlix_schedule_payments p
   join public.korlix_schedule_bookings b on b.id=p.booking_id
   join public.korlix_schedule_connections old on old.id=p.connection_id
   where old.owner_id=p_actor and old.provider='stripe' and old.remote_id<>s.account_id
    and (b.state='awaiting_payment' and b.hold_expires_at>now()
         or p.payment_state='unpaid' and p.checkout_wire is not null and not p.checkout_closed
         or p.refund_state in ('required','sending','pending'))) then
  raise exception 'Complete open payments and refunds before changing merchants.';
 end if;
 update public.korlix_schedule_connections set enabled=false,revision=revision+1,updated_at=now()
  where owner_id=p_actor and provider='stripe' and remote_id<>s.account_id and enabled;
 insert into public.korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,charges_enabled,livemode,enabled)
  values(p_actor,'stripe',s.account_id,identity->>'label',p_data->>'sealed_grant',s.config_hash,
         (identity->>'charges_enabled')::boolean,s.livemode,true)
  on conflict(owner_id,provider,remote_id) do update
   set sealed_grant=excluded.sealed_grant,config_hash=excluded.config_hash,state='connected',
       charges_enabled=excluded.charges_enabled,livemode=excluded.livemode,label=excluded.label,
       enabled=true,revision=korlix_schedule_connections.revision+1,last_error=null,updated_at=now()
  returning * into c;
 update public.korlix_schedule_stripe_setup
  set confirmed_at=coalesce(confirmed_at,now()),review_hash=null,review_expires_at=null,
      review_connection_id=null,review_connection_revision=null where id=s.id;
 insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'stripe_onboarding_confirmed');
 return jsonb_build_object('id',c.id,'saved',true);
end;
$$;
revoke all on function public.korlix_schedule_stripe_setup_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_schedule_stripe_setup_v1(uuid,text,uuid,jsonb) to service_role;
commit;
