-- Support intake is validated by the backend. The former NULL-user policies
-- allowed anyone with the publishable key to write arbitrary workflow states.
revoke all on public.account_deletion_requests, public.reports from public, anon, authenticated;
grant select, insert, update, delete on public.account_deletion_requests, public.reports to service_role;
alter table public.account_deletion_requests enable row level security;
alter table public.reports enable row level security;
drop policy if exists "Users can request account deletion" on public.account_deletion_requests;
drop policy if exists "Users can create reports" on public.reports;
create policy account_deletion_requests_server_only on public.account_deletion_requests
  as restrictive for all to anon, authenticated using (false) with check (false);
create policy reports_server_only on public.reports
  as restrictive for all to anon, authenticated using (false) with check (false);

-- PostgreSQL 17's MAINTAIN privilege was not part of the earlier TRUNCATE /
-- REFERENCES / TRIGGER revocation. Clients do not run database maintenance.
revoke maintain on all tables in schema public from public, anon, authenticated;

-- Existing app objects are already hardened. Close the default grants as well,
-- so new postgres-owned tables/RPCs do not reopen the same paths. Supabase's
-- platform-owned role is deliberately not changed by an application migration.
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
-- A schema-scoped revoke cannot remove PostgreSQL's global PUBLIC execute default.
alter default privileges for role postgres
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  grant execute on functions to service_role;

-- Serialize retries across backend workers without deleting or relabeling any
-- historical support records. Older duplicate requests remain available to staff.
create index account_deletion_requests_pending_user_idx
  on public.account_deletion_requests (user_id, created_at, id)
  where status = 'requested' and user_id is not null;

create function public.korlix_request_account_deletion(p_user_id uuid, p_email text, p_reason text)
returns jsonb language plpgsql security invoker set search_path = pg_catalog, public as $$
declare request_row public.account_deletion_requests;
begin
  if p_user_id is null then raise exception 'Sign in required.' using errcode = '42501'; end if;
  if p_email is null or length(btrim(p_email)) not between 3 and 254
    or position('@' in p_email) < 2 or length(coalesce(p_reason, '')) > 2000 then
    raise exception 'Check your account deletion request.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('account-deletion:' || p_user_id::text, 0));
  select * into request_row from public.account_deletion_requests
    where user_id = p_user_id and status = 'requested'
    order by created_at, id limit 1;
  if not found then
    insert into public.account_deletion_requests (user_id, email, reason, status)
      values (p_user_id, btrim(p_email), coalesce(p_reason, ''), 'requested')
      returning * into request_row;
  end if;
  return to_jsonb(request_row);
end;
$$;
revoke all on function public.korlix_request_account_deletion(uuid, text, text) from public, anon, authenticated;
grant execute on function public.korlix_request_account_deletion(uuid, text, text) to service_role;
