-- TIER-GAS-02. Additive, opt-in wallet. Do not activate or import old balances here.
-- Default product mappings are deliberately NULL and disabled until Console verification.
create schema korlix_gas_v2;
revoke all on schema korlix_gas_v2 from public, anon, authenticated, service_role;

create table korlix_gas_v2.products (
 sku text primary key,
 seconds integer not null check(seconds>0),
 reference_usd_cents integer not null check(reference_usd_cents>0),
 google_product_id text unique check(google_product_id ~ '^[a-z][a-z0-9_.]{0,199}$'),
 enabled boolean not null default false,
 check ((sku,seconds,reference_usd_cents) in (('korlix_ai_gas_1h',3600,3000),('korlix_ai_gas_2h',7200,5500),('korlix_ai_gas_3h',10800,8000),('korlix_ai_gas_5h',18000,12499)))
);
insert into korlix_gas_v2.products(sku,seconds,reference_usd_cents) values
 ('korlix_ai_gas_1h',3600,3000),('korlix_ai_gas_2h',7200,5500),
 ('korlix_ai_gas_3h',10800,8000),('korlix_ai_gas_5h',18000,12499);
create table korlix_gas_v2.wallets (
 user_id uuid primary key references auth.users(id) on delete cascade,
 review_required boolean not null default false,
 created_at timestamptz not null default now()
);
create table korlix_gas_v2.revocations (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 reason text not null check(reason in ('refunded','revoked')),
 created_at timestamptz not null default now()
);
create table korlix_gas_v2.purchases (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 user_id uuid not null references korlix_gas_v2.wallets(user_id) on delete cascade,
 sku text not null references korlix_gas_v2.products(sku),
 product_id text not null,
 granted_seconds integer not null check(granted_seconds>0),
 remaining_seconds integer not null check(remaining_seconds>=0 and remaining_seconds<=granted_seconds),
 reference_usd_cents integer not null,
 purchased_at timestamptz not null,
 is_test boolean not null,
 state text not null default 'active' check(state in ('active','revoked')),
 revoked_seconds integer not null default 0 check(revoked_seconds>=0),
 unrecovered_seconds integer not null default 0 check(unrecovered_seconds>=0),
 created_at timestamptz not null default now()
);
create index gas_v2_purchase_owner on korlix_gas_v2.purchases(user_id,created_at,token_hash);
create table korlix_gas_v2.events (
 user_id uuid not null references korlix_gas_v2.wallets(user_id) on delete cascade,
 event_key text not null,
 kind text not null check(kind in ('grant','usage','revoke')),
 delta_seconds bigint not null,
 session_id uuid,
 token_hash text references korlix_gas_v2.purchases(token_hash) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,event_key)
);
create table korlix_gas_v2.allocations (
 user_id uuid not null,
 event_key text not null,
 token_hash text not null references korlix_gas_v2.purchases(token_hash) on delete cascade,
 seconds integer not null check(seconds>0),
 primary key(user_id,event_key,token_hash),
 foreign key(user_id,event_key) references korlix_gas_v2.events(user_id,event_key) on delete cascade
);
create table korlix_gas_v2.jobs (
 token_hash text primary key references korlix_gas_v2.purchases(token_hash) on delete cascade,
 sealed_token jsonb not null check(jsonb_typeof(sealed_token)='object'),
 attempts integer not null default 0,
 due_at timestamptz not null default now(),
 lease_id uuid,
 lease_until timestamptz,
 done boolean not null default false,
 last_error_code text,
 completed_at timestamptz
);
create index gas_v2_jobs_due on korlix_gas_v2.jobs(due_at) where not done;

-- The service role can execute this RPC, but cannot directly access these tables.
-- This is NOT a public client verification API: only the trusted backend supplies facts.
create function public.korlix_gas_v2_rpc(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $gas$
declare
 u uuid; h text; k text; s uuid; n integer; amount integer; balance bigint;
 pr korlix_gas_v2.products%rowtype; old korlix_gas_v2.purchases%rowtype;
 ev korlix_gas_v2.events%rowtype; job korlix_gas_v2.jobs%rowtype;
 item record; result jsonb; at_time timestamptz; why text; review boolean;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'GAS_INPUT_INVALID'; end if;
 if p_action='catalog' then
  select jsonb_agg(jsonb_build_object('sku',sku,'seconds',seconds,'referenceUsdCents',reference_usd_cents,'productId',google_product_id,'enabled',enabled) order by seconds) into result from korlix_gas_v2.products;
  return result;
 end if;
 if p_action='claim' then
  select * into job from korlix_gas_v2.jobs where not done and due_at<=now() and (lease_until is null or lease_until<=now()) order by due_at,token_hash limit 1 for update skip locked;
  if not found then return 'null'::jsonb; end if;
  update korlix_gas_v2.jobs set lease_id=gen_random_uuid(),lease_until=now()+interval '90 seconds',attempts=attempts+1 where token_hash=job.token_hash returning * into job;
  select * into old from korlix_gas_v2.purchases where token_hash=job.token_hash;
  return jsonb_build_object('tokenHash',job.token_hash,'leaseId',job.lease_id,'userId',old.user_id,'productId',old.product_id,'sealedToken',job.sealed_token);
 end if;
 if p_action in ('finish','retry') then
  h:=p_data->>'tokenHash'; s:=(p_data->>'leaseId')::uuid;
  select * into job from korlix_gas_v2.jobs where token_hash=h for update;
  if not found or job.done or s is null or job.lease_id is distinct from s or job.lease_until<=now() then raise exception 'GAS_LEASE_STALE'; end if;
  if p_action='finish' then
   update korlix_gas_v2.jobs set done=true,completed_at=now(),lease_id=null,lease_until=null,last_error_code=null where token_hash=h;
  else
   why:=p_data->>'errorCode';
   if why is null or why !~ '^[A-Z_]{1,80}$' then raise exception 'GAS_ERROR_CODE_INVALID'; end if;
   update korlix_gas_v2.jobs set due_at=now()+make_interval(secs=>least(3600,5*power(2,least(job.attempts,10)))),lease_id=null,lease_until=null,last_error_code=why where token_hash=h;
  end if;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='revoke' then
  h:=p_data->>'tokenHash'; why:=p_data->>'reason';
  if h is null or h !~ '^[a-f0-9]{64}$' or why is null or why not in ('refunded','revoked') then raise exception 'GAS_REVOCATION_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('korlix_gas_v2/token/'||h,0));
  insert into korlix_gas_v2.revocations(token_hash,reason) values(h,why) on conflict do nothing;
  select * into old from korlix_gas_v2.purchases where token_hash=h;
  if not found then return jsonb_build_object('revoked',true,'knownPurchase',false); end if;
  u:=old.user_id;
  perform 1 from korlix_gas_v2.wallets where user_id=u for update;
  select * into old from korlix_gas_v2.purchases where token_hash=h;
  if old.state='active' then
   update korlix_gas_v2.purchases set state='revoked',revoked_seconds=remaining_seconds,unrecovered_seconds=granted_seconds-remaining_seconds,remaining_seconds=0 where token_hash=h returning * into old;
   insert into korlix_gas_v2.events(user_id,event_key,kind,delta_seconds,token_hash) values(u,'revoke/'||h,'revoke',-old.revoked_seconds,h);
   if old.unrecovered_seconds>0 then update korlix_gas_v2.wallets set review_required=true where user_id=u; end if;
  end if;
  return jsonb_build_object('revoked',true,'knownPurchase',true,'reversedSeconds',old.revoked_seconds,'unrecoveredSeconds',old.unrecovered_seconds);
 end if;
 if p_action not in ('balance','grant_google','debit_verified_gas') or p_action is null then raise exception 'GAS_ACTION_INVALID'; end if;
 u:=(p_data->>'userId')::uuid;
 if u is null or not exists(select 1 from auth.users where id=u) then raise exception 'GAS_USER_INVALID'; end if;
 if p_action='balance' then
  select coalesce(sum(remaining_seconds),0) into balance from korlix_gas_v2.purchases where user_id=u and state='active';
  select review_required into review from korlix_gas_v2.wallets where user_id=u;
  return jsonb_build_object('balanceSeconds',balance,'reviewRequired',coalesce(review,false));
 end if;
 if p_action='grant_google' then
  h:=p_data->>'tokenHash';
  if h is null or h !~ '^[a-f0-9]{64}$' then raise exception 'GAS_TOKEN_HASH_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('korlix_gas_v2/token/'||h,0));
  if exists(select 1 from korlix_gas_v2.revocations where token_hash=h) then raise exception 'GAS_PURCHASE_REVOKED'; end if;
 end if;
 insert into korlix_gas_v2.wallets(user_id) values(u) on conflict do nothing;
 perform 1 from korlix_gas_v2.wallets where user_id=u for update;
 if p_action='grant_google' then
  select * into old from korlix_gas_v2.purchases where token_hash=h;
  if found then
   if old.user_id<>u or old.product_id is distinct from p_data->>'productId' or old.sku is distinct from p_data->>'sku' or old.is_test is distinct from (p_data->>'isTest')::boolean then raise exception 'GAS_PURCHASE_CONFLICT'; end if;
   if old.state<>'active' then raise exception 'GAS_PURCHASE_REVOKED'; end if;
   return public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u))||jsonb_build_object('granted',false,'idempotent',true);
  end if;
  if (p_data->'consumed') is distinct from 'false'::jsonb then raise exception 'GAS_ALREADY_CONSUMED_UNRECORDED'; end if;
  select * into pr from korlix_gas_v2.products where sku=p_data->>'sku' and google_product_id=p_data->>'productId' and enabled;
  if not found then raise exception 'GAS_PRODUCT_UNAVAILABLE'; end if;
  if jsonb_typeof(p_data->'isTest') is distinct from 'boolean' or jsonb_typeof(p_data->'sealedToken') is distinct from 'object' or octet_length((p_data->'sealedToken')::text)>7000 then raise exception 'GAS_PROOF_INVALID'; end if;
  if (p_data->'sealedToken'->>'v') is distinct from '1' or not (p_data->'sealedToken' ?& array['kid','iv','tag','data']) then raise exception 'GAS_PROOF_INVALID'; end if;
  at_time:=(p_data->>'purchasedAt')::timestamptz;
  if at_time is null or not isfinite(at_time) or at_time>now()+interval '5 minutes' then raise exception 'GAS_PURCHASE_TIME_INVALID'; end if;
  insert into korlix_gas_v2.purchases(token_hash,user_id,sku,product_id,granted_seconds,remaining_seconds,reference_usd_cents,purchased_at,is_test) values(h,u,pr.sku,pr.google_product_id,pr.seconds,pr.seconds,pr.reference_usd_cents,at_time,(p_data->>'isTest')::boolean);
  insert into korlix_gas_v2.events(user_id,event_key,kind,delta_seconds,token_hash) values(u,'grant/'||h,'grant',pr.seconds,h);
  insert into korlix_gas_v2.jobs(token_hash,sealed_token) values(h,p_data->'sealedToken');
  return public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u))||jsonb_build_object('granted',true,'idempotent',false);
 end if;
 -- Internal purchased-GAS debit ONLY. Included quota and server-active-time
 -- reservation are separate integration gates. This RPC is not exposed to users.
 k:=p_data->>'eventId';s:=(p_data->>'sessionId')::uuid;n:=(p_data->>'seconds')::integer;
 if k is null or k !~ '^[A-Za-z0-9_-]{1,100}$' or s is null or n is null or n<=0 or n>86400 then raise exception 'GAS_USAGE_INVALID'; end if;
 k:='usage/'||k;
 select * into ev from korlix_gas_v2.events where user_id=u and event_key=k;
 if found then
  if ev.kind<>'usage' or ev.delta_seconds<>-n or ev.session_id is distinct from s then raise exception 'GAS_USAGE_CONFLICT'; end if;
  return public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u))||jsonb_build_object('idempotent',true,'consumedSeconds',n);
 end if;
 if exists(select 1 from korlix_gas_v2.wallets where user_id=u and review_required) then raise exception 'GAS_BILLING_REVIEW_REQUIRED'; end if;
 select coalesce(sum(remaining_seconds),0) into balance from korlix_gas_v2.purchases where user_id=u and state='active';
 if balance<n then raise exception 'GAS_INSUFFICIENT_BALANCE'; end if;
 insert into korlix_gas_v2.events(user_id,event_key,kind,delta_seconds,session_id) values(u,k,'usage',-n,s);
 amount:=n;
 for item in select * from korlix_gas_v2.purchases where user_id=u and state='active' and remaining_seconds>0 order by created_at,token_hash for update loop
  exit when amount=0;
  balance:=least(amount,item.remaining_seconds);
  update korlix_gas_v2.purchases set remaining_seconds=remaining_seconds-balance where token_hash=item.token_hash;
  insert into korlix_gas_v2.allocations(user_id,event_key,token_hash,seconds) values(u,k,item.token_hash,balance);
  amount:=amount-balance;
 end loop;
 if amount<>0 then raise exception 'GAS_BALANCE_INVARIANT'; end if;
 return public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u))||jsonb_build_object('idempotent',false,'consumedSeconds',n);
end $gas$;
revoke all on function public.korlix_gas_v2_rpc(text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_gas_v2_rpc(text,jsonb) to service_role;
-- RLS is defense in depth: no policies are created and no direct client privileges.
alter table korlix_gas_v2.products enable row level security;
alter table korlix_gas_v2.wallets enable row level security;
alter table korlix_gas_v2.revocations enable row level security;
alter table korlix_gas_v2.purchases enable row level security;
alter table korlix_gas_v2.events enable row level security;
alter table korlix_gas_v2.allocations enable row level security;
alter table korlix_gas_v2.jobs enable row level security;
revoke all on all tables in schema korlix_gas_v2 from public,anon,authenticated,service_role;
comment on function public.korlix_gas_v2_rpc(text,jsonb) is 'Server-only AI GAS v2 ledger; no customer access, no live activation. Requires verified Google evidence or trusted metering. Products disabled until mapped.';