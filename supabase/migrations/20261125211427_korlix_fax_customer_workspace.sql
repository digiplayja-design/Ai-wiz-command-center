-- A fax account owns its contacts, signup request, and short-lived hub handoffs.
alter table public.korlix_fax_lines add column requested_plan text
  check (requested_plan in ('solo','business'));

create table public.korlix_fax_contacts (
  user_id uuid not null references auth.users(id) on delete cascade,
  phone text not null check (phone ~ '^[+]1[2-9][0-9]{2}[2-9][0-9]{6}$'),
  name text not null check (length(trim(name)) between 1 and 80),
  updated_at timestamptz not null default now(),
  primary key(user_id,phone)
);
create index korlix_fax_contact_recent on public.korlix_fax_contacts(user_id,updated_at desc);
create table public.korlix_fax_handoffs (
  code_hash text primary key check (code_hash ~ '^[a-f0-9]{64}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '90 seconds')
);
alter table public.korlix_fax_contacts enable row level security;
alter table public.korlix_fax_handoffs enable row level security;
revoke all on public.korlix_fax_contacts,public.korlix_fax_handoffs from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_fax_contacts,public.korlix_fax_handoffs to service_role;

create function public.korlix_fax_redeem_handoff(p_code text,p_device uuid,p_hash text)
returns boolean language plpgsql security invoker set search_path='' as $$
declare account_id uuid;
begin
  delete from public.korlix_fax_handoffs where code_hash=p_code and expires_at>now()
  returning user_id into account_id;
  if account_id is null then return false; end if;
  return public.korlix_fax_open_session(account_id,p_device,p_hash);
end;
$$;

create function public.korlix_fax_monthly_usage(p_user uuid,p_start timestamptz,p_end timestamptz)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('pages',coalesce(sum(pages),0),'pendingReports',count(*) filter(where pages is null),
    'inboundPages',coalesce(sum(pages) filter(where direction='inbound'),0),
    'outboundPages',coalesce(sum(pages) filter(where direction='outbound'),0))
    from public.korlix_fax_documents
    where user_id=p_user and status in ('delivered','received') and updated_at>=p_start and updated_at<p_end;
$$;
create index korlix_fax_usage_period on public.korlix_fax_documents(user_id,updated_at)
  where status in ('delivered','received');
revoke all on function public.korlix_fax_redeem_handoff(text,uuid,text),
  public.korlix_fax_monthly_usage(uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.korlix_fax_redeem_handoff(text,uuid,text),
  public.korlix_fax_monthly_usage(uuid,timestamptz,timestamptz) to service_role;
