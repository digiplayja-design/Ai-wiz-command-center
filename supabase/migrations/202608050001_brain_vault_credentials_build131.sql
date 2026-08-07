-- KORLIX_BRAIN_VAULT_CREDENTIALS_BUILD131_V2_BEGIN
-- Separate BRAIN VAULT credential storage for Build 131.
-- The migration is intentionally source-only until a later guarded Supabase step.
-- Plaintext passwords are never stored. The backend stores only a random salt
-- and a Node scrypt-derived hash. Only the backend service role may access rows.

create table if not exists public.korlix_brain_vault_credentials (
  account_id uuid primary key references auth.users(id) on delete cascade,
  manager_user_id uuid not null references auth.users(id) on delete cascade,
  password_hash text not null,
  password_salt text not null,
  password_algorithm text not null default 'scrypt-v1'
    check (password_algorithm in ('scrypt-v1')),
  password_version integer not null default 1
    check (password_version >= 1),
  failed_attempt_count integer not null default 0
    check (failed_attempt_count >= 0 and failed_attempt_count <= 5),
  locked_until timestamptz,
  last_verified_at timestamptz,
  password_changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists korlix_brain_vault_credentials_manager_idx
  on public.korlix_brain_vault_credentials (manager_user_id);

create index if not exists korlix_brain_vault_credentials_locked_idx
  on public.korlix_brain_vault_credentials (locked_until)
  where locked_until is not null;

create or replace function public.korlix_brain_vault_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists korlix_brain_vault_credentials_updated_at
  on public.korlix_brain_vault_credentials;

create trigger korlix_brain_vault_credentials_updated_at
before update on public.korlix_brain_vault_credentials
for each row execute function public.korlix_brain_vault_touch_updated_at();

alter table public.korlix_brain_vault_credentials enable row level security;

revoke all on table public.korlix_brain_vault_credentials
  from public, anon, authenticated;

revoke all on function public.korlix_brain_vault_touch_updated_at()
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.korlix_brain_vault_credentials
  to service_role;

grant execute on function public.korlix_brain_vault_touch_updated_at()
  to service_role;

comment on table public.korlix_brain_vault_credentials is
  'Service-role-only hashes for separate Account Manager controlled BRAIN VAULT passwords.';

-- KORLIX_BRAIN_VAULT_CREDENTIALS_BUILD131_V2_END
