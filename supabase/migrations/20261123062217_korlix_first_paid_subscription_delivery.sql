-- Optional attribution for a checkout on the KORLIX AI hub. Store receipts stay in the billing tables.
create table public.korlix_measurement_checkouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  store text not null,
  sku text not null,
  instance_id text not null check (instance_id ~ '^[a-f0-9]{32}$'),
  granted_at timestamptz not null default clock_timestamp(),
  binding_hash text check (binding_hash ~ '^[a-f0-9]{64}$'),
  next_check_at timestamptz not null default now(),
  check ((store='ios' and sku in ('com.korlixdeveloper.korlixai.pro.monthly','com.korlixdeveloper.korlixai.ultra.monthly'))
      or (store='android' and sku in ('korlix_pro','korlix_ultra')))
);
create index korlix_measurement_due on public.korlix_measurement_checkouts(next_check_at) where binding_hash is not null;
create index korlix_measurement_owner on public.korlix_measurement_checkouts(user_id,store);
create table public.korlix_first_payment_deliveries (
  user_id uuid primary key references auth.users(id) on delete cascade,
  receipt_id uuid not null unique default gen_random_uuid(),
  paid_at timestamptz not null,
  state text not null default 'reserved' check (state in ('reserved','accepted','uncertain')),
  updated_at timestamptz not null default now()
);
alter table public.korlix_measurement_checkouts enable row level security;
alter table public.korlix_first_payment_deliveries enable row level security;
revoke all on public.korlix_measurement_checkouts,public.korlix_first_payment_deliveries from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_measurement_checkouts,public.korlix_first_payment_deliveries to service_role;

-- Claim a batch across replicas. The lease bounds retries when a store is down or a trial is still free.
create function public.korlix_measurement_due() returns setof public.korlix_measurement_checkouts
language plpgsql security invoker set search_path = pg_catalog, public as $$
begin
  delete from public.korlix_measurement_checkouts
  where granted_at < now()-interval '40 days' or (binding_hash is null and granted_at < now()-interval '7 days');
  return query
    with due as (
      select id from public.korlix_measurement_checkouts
      where binding_hash is not null and next_check_at <= now()
      order by next_check_at limit 20 for update skip locked
    )
    update public.korlix_measurement_checkouts c set next_check_at=now()+interval '30 minutes'
    from due where c.id=due.id returning c.*;
end;
$$;

-- Serialize sending against opt-out and deduplicate by KORLIX account across both stores.
create function public.korlix_reserve_first_payment(p_checkout uuid,p_store text,p_sku text,p_hash text,
    p_started timestamptz,p_paid timestamptz) returns table(receipt_id uuid,instance_id text)
language plpgsql security invoker set search_path = pg_catalog, public as $$
declare
  c public.korlix_measurement_checkouts;
  receipt uuid;
begin
  select * into c from public.korlix_measurement_checkouts where id=p_checkout for update;
  if not found or c.store is distinct from p_store or c.sku is distinct from p_sku
     or c.binding_hash is null or c.binding_hash is distinct from p_hash or p_started is null or p_paid is null
     or p_started<c.granted_at or p_paid<p_started or p_paid>clock_timestamp() or p_paid<now()-interval '71 hours' then return;
  end if;
  insert into public.korlix_first_payment_deliveries(user_id,paid_at) values(c.user_id,p_paid)
  on conflict (user_id) do nothing returning korlix_first_payment_deliveries.receipt_id into receipt;
  delete from public.korlix_measurement_checkouts where id=c.id;
  if receipt is not null then return query select receipt,c.instance_id; end if;
end;
$$;
revoke all on function public.korlix_measurement_due(),public.korlix_reserve_first_payment(uuid,text,text,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.korlix_measurement_due(),public.korlix_reserve_first_payment(uuid,text,text,text,timestamptz,timestamptz) to service_role;
