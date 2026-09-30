-- US payroll is an Enterprise-owner capability. Provider credentials never reach the Data API.
create table public.korlix_payroll_accounts (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null unique references public.korlix_bookkeeping_businesses(id),
 owner_id uuid not null references auth.users(id),
 legal_name text not null check (length(trim(legal_name)) between 1 and 160),
 country text not null default 'US' check (country='US'),
 currency text not null default 'USD' check (currency='USD'),
 environment text check (environment in ('demo','production')),
 status text not null default 'draft' check (status in ('draft','connecting','connected','connection_review')),
 provider_company_id uuid,
 sealed_tokens text,
 token_expires_at timestamptz,
 refresh_pending boolean not null default false,
 connection_id uuid,
 admin_email text,
 terms_accepted_at timestamptz,
 lease_id uuid,
 lease_until timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(environment,provider_company_id)
);
create index korlix_payroll_accounts_owner_idx on public.korlix_payroll_accounts(owner_id);
create table public.korlix_payroll_audit (
 id bigint generated always as identity primary key,
 account_id uuid not null references public.korlix_payroll_accounts(id),
 actor_id uuid not null references auth.users(id),
 action text not null,
 created_at timestamptz not null default now()
);
create index korlix_payroll_audit_account_idx on public.korlix_payroll_audit(account_id,created_at desc);
create index korlix_payroll_audit_actor_idx on public.korlix_payroll_audit(actor_id,created_at desc);
create table public.korlix_payroll_limits (
 actor_id uuid primary key references auth.users(id),
 window_start timestamptz not null default now(),
 requests integer not null default 0
);
alter table public.korlix_payroll_accounts enable row level security;
alter table public.korlix_payroll_audit enable row level security;
alter table public.korlix_payroll_limits enable row level security;
revoke all on public.korlix_payroll_accounts, public.korlix_payroll_audit, public.korlix_payroll_limits from public,anon,authenticated;
grant select,insert,update on public.korlix_payroll_accounts, public.korlix_payroll_limits to service_role;
grant select,insert on public.korlix_payroll_audit to service_role;
revoke all on sequence public.korlix_payroll_audit_id_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_payroll_audit_id_seq to service_role;

create function public.korlix_payroll_public_v1(a public.korlix_payroll_accounts) returns jsonb
language sql immutable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('id',a.id,'business_id',a.business_id,'legal_name',a.legal_name,
 'country',a.country,'currency',a.currency,'environment',a.environment,'status',a.status,
 'terms_accepted',a.terms_accepted_at is not null,'created_at',a.created_at,
 'needs_attention',a.refresh_pending or a.status in ('connection_review','connecting'));
$$;
revoke all on function public.korlix_payroll_public_v1(public.korlix_payroll_accounts) from public,anon,authenticated;
grant execute on function public.korlix_payroll_public_v1(public.korlix_payroll_accounts) to service_role;

create function public.korlix_payroll_v1(p_actor uuid,p_action text,p_account uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_payroll_accounts; b public.korlix_bookkeeping_businesses; n integer;
begin
 if not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise' and is_disabled is not true) then
  raise exception using errcode='42501',message='Active Enterprise business account required.';
 end if;
 if p_action='list' then
  return jsonb_build_object('accounts',coalesce((select jsonb_agg(public.korlix_payroll_public_v1(pa) order by pa.created_at) from public.korlix_payroll_accounts pa join public.korlix_bookkeeping_businesses bb on bb.id=pa.business_id and bb.owner_id=p_actor where pa.owner_id=p_actor),'[]'::jsonb),
   'businesses',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.korlix_bookkeeping_businesses where owner_id=p_actor),'[]'::jsonb));
 end if;
 -- A shared database budget bounds requests across replicas and accounts.
 insert into public.korlix_payroll_limits(actor_id) values(p_actor) on conflict do nothing;
 update public.korlix_payroll_limits set requests=case when window_start < now()-interval '1 minute' then 1 else requests+1 end,
  window_start=case when window_start < now()-interval '1 minute' then now() else window_start end
  where actor_id=p_actor returning requests into n;
 if n>180 then raise exception using errcode='54000',message='Too many payroll requests. Try again shortly.'; end if;
 if p_action='create' then
  select * into b from public.korlix_bookkeeping_businesses where id=(p_data->>'business_id')::uuid and owner_id=p_actor for update;
  if not found then raise exception using errcode='P0002',message='Business not found.'; end if;
  if p_data->>'country' is distinct from 'US' or p_data->>'confirmed' is distinct from 'true' then
   raise exception 'Confirm this is a US business you are authorized to manage.';
  end if;
  select * into a from public.korlix_payroll_accounts where business_id=b.id;
  if not found then
   insert into public.korlix_payroll_accounts(business_id,owner_id,legal_name) values(b.id,p_actor,trim(p_data->>'legal_name')) returning * into a;
   insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'workspace_created');
  elsif a.owner_id<>p_actor then raise exception using errcode='P0002',message='Payroll workspace not found.';
  end if;
  return jsonb_build_object('account',public.korlix_payroll_public_v1(a));
 end if;
 select pa.* into a from public.korlix_payroll_accounts pa join public.korlix_bookkeeping_businesses bb on bb.id=pa.business_id and bb.owner_id=p_actor where pa.id=p_account and pa.owner_id=p_actor for update of pa;
 if not found then raise exception using errcode='P0002',message='Payroll workspace not found.'; end if;
 if p_action='get' then
  return jsonb_build_object('account',public.korlix_payroll_public_v1(a),'audit',coalesce((select jsonb_agg(x) from (select action,created_at from public.korlix_payroll_audit where account_id=a.id order by created_at desc,id desc limit 20)x),'[]'::jsonb));
 elsif p_action='begin_connection' then
  if a.status<>'draft' then raise exception using errcode='40001',message='A provider connection already exists or needs review. Refresh the workspace.'; end if;
  if p_data->>'environment' not in ('demo','production') then raise exception 'Invalid payroll environment.'; end if;
  update public.korlix_payroll_accounts set status='connecting',environment=p_data->>'environment',connection_id=(p_data->>'connection_id')::uuid,admin_email=p_data->>'email',updated_at=now() where id=a.id;
  insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'provider_connection_started');
  return jsonb_build_object('legal_name',a.legal_name);
 elsif p_action='finish_connection' then
  if a.status<>'connecting' or a.connection_id is distinct from (p_data->>'connection_id')::uuid then raise exception using errcode='40001',message='Connection changed. Contact payroll support.'; end if;
  if length(coalesce(p_data->>'sealed_tokens',''))<40 then raise exception 'Missing protected credentials.'; end if;
  update public.korlix_payroll_accounts set status='connected',provider_company_id=(p_data->>'company_id')::uuid,
   sealed_tokens=p_data->>'sealed_tokens',token_expires_at=(p_data->>'expires_at')::timestamptz,updated_at=now() where id=a.id returning * into a;
  insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'provider_connected');
 elsif p_action='connection_failed' then
  if a.status='connecting' and a.connection_id=(p_data->>'connection_id')::uuid then
   update public.korlix_payroll_accounts set status='connection_review',updated_at=now() where id=a.id returning * into a;
   insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'provider_connection_needs_review');
  end if;
 elsif p_action='lease' then
  if a.status<>'connected' or a.environment is distinct from p_data->>'environment' then raise exception using errcode='40001',message='This payroll workspace is not connected to the active provider environment.'; end if;
  if a.lease_until>now() then raise exception using errcode='40001',message='Another payroll request is in progress. Try again shortly.'; end if;
  if a.refresh_pending then raise exception using errcode='40001',message='Payroll credentials need administrator review before continuing.'; end if;
  update public.korlix_payroll_accounts set lease_id=(p_data->>'lease_id')::uuid,lease_until=now()+interval '90 seconds' where id=a.id;
  return jsonb_build_object('company_id',a.provider_company_id,'sealed_tokens',a.sealed_tokens,'expires_at',a.token_expires_at,
   'terms_accepted',a.terms_accepted_at is not null,'admin_email',a.admin_email);
 elsif p_action='release' then
  update public.korlix_payroll_accounts set lease_id=null,lease_until=null where id=a.id and lease_id=(p_data->>'lease_id')::uuid;
 elsif p_action in ('refresh_started','refresh_saved','terms_accepted','flow_opened') then
  if a.lease_id is distinct from (p_data->>'lease_id')::uuid or a.lease_until<=now() then raise exception using errcode='40001',message='Payroll session changed. Refresh before continuing.'; end if;
  if p_action='refresh_started' then
   update public.korlix_payroll_accounts set refresh_pending=true where id=a.id;
  elsif p_action='refresh_saved' then
   if length(coalesce(p_data->>'sealed_tokens',''))<40 then raise exception 'Missing protected credentials.'; end if;
   update public.korlix_payroll_accounts set sealed_tokens=p_data->>'sealed_tokens',token_expires_at=(p_data->>'expires_at')::timestamptz,refresh_pending=false,updated_at=now() where id=a.id;
  elsif p_action='terms_accepted' then
   update public.korlix_payroll_accounts set terms_accepted_at=now(),updated_at=now() where id=a.id;
   insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'provider_terms_accepted');
  else
   if a.terms_accepted_at is null then raise exception 'Accept payroll terms first.'; end if;
   insert into public.korlix_payroll_audit(account_id,actor_id,action) values(a.id,p_actor,'secure_session_opened:'||left(p_data->>'flow_type',80));
  end if;
 else raise exception 'Unsupported payroll action.';
 end if;
 return jsonb_build_object('account',public.korlix_payroll_public_v1(a));
end;
$$;
revoke all on function public.korlix_payroll_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_payroll_v1(uuid,text,uuid,jsonb) to service_role;
