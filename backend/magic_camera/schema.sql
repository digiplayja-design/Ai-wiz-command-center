-- Service-only state machine. No raw capture is ever readable by a client.
create table public.korlix_magic_jobs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 request_key uuid not null, fingerprint text not null, options jsonb not null,
 state text not null default 'uploading' check(state in ('uploading','queued','processing','ready','failed','deleted')),
 allowance text not null, created_at timestamptz not null default now(), finished_at timestamptz,
 source_purged boolean not null default false, output_purged boolean not null default false,
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
  update public.korlix_magic_jobs set state='failed',finished_at=now(),error='This magic session expired. No credit was used.'
   where state in ('uploading','queued','processing') and lease_until<now();
  return coalesce((select jsonb_agg(to_jsonb(x)) from (select id,owner_id,state,source_purged,output_purged from public.korlix_magic_jobs
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
    update public.korlix_magic_jobs set state='failed',finished_at=now(),error='Upload did not finish. No credit was used.' where id=j.id returning * into j;
   elsif j.state='processing' and j.worker_token::text=p->>'worker_token' and j.lease_until>now() then
    update public.korlix_magic_jobs set state=case when p_action='finish' then 'ready' else 'failed' end,finished_at=now(),
     width=(p->>'width')::integer,height=(p->>'height')::integer,render_ms=(p->>'render_ms')::integer,
     error=case when p_action='fail' then 'This photo could not be transformed. No credit was used. Try a different prompt or photo.' end where id=j.id returning * into j;
   elsif j.state not in ('ready','deleted') then raise exception 'MAG409: This generation lease expired.';end if;
  elsif p_action='delete' then
   if j.state not in ('ready','failed','deleted') then raise exception 'MAG409: Wait for processing to finish before deleting.';end if;
   update public.korlix_magic_jobs set state=case when state='ready' then 'deleted' else state end,deleted_at=now() where id=j.id returning * into j;
  elsif p_action='purged' then
   update public.korlix_magic_jobs set source_purged=true,output_purged=case when state in ('failed','deleted') then true else output_purged end where id=j.id returning * into j;
  elsif p_action<>'get' then raise exception 'MAG400: Unsupported magic action.';
  end if;
 end if;
 return jsonb_build_object('job',to_jsonb(j),'dispatch',dispatch);
end $$;
revoke all on function public.korlix_magic_plan(uuid,boolean),public.korlix_magic_command(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_plan(uuid,boolean),public.korlix_magic_command(uuid,text,uuid,jsonb) to service_role;
