-- KORLIX_LIVE_CONVO_AGENT_MEMORY_BUILD131_BEGIN
-- Build 131 source migration. This file is committed locally by the patch,
-- but the guarded patch does not apply it to Supabase.

create extension if not exists pgcrypto;

create table if not exists public.korlix_live_convo_agent_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_id text not null,
  agent_key text,
  slug text,
  agent_type text not null default 'custom',
  name text not null,
  display_name text,
  description text not null default '',
  instructions text not null default '',
  system_prompt text not null default '',
  prompt text not null default '',
  training_notes text not null default '',
  icon_name text not null default 'auto_awesome',
  accent_hex text not null default '21D4F4',
  is_builtin boolean not null default false,
  built_in boolean not null default false,
  active boolean not null default true,
  memory_enabled boolean not null default true,
  current_version integer not null default 1 check (current_version >= 1),
  configuration jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, agent_id)
);

create table if not exists public.korlix_live_convo_agent_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id uuid references public.korlix_live_convo_agent_profiles(id)
    on delete cascade,
  agent_id text not null,
  version integer not null check (version >= 1),
  version_number integer,
  name text not null,
  description text not null default '',
  instructions text not null default '',
  system_prompt text not null default '',
  prompt text not null default '',
  training_notes text not null default '',
  change_summary text not null default '',
  snapshot jsonb not null default '{}'::jsonb,
  configuration jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, agent_id, version)
);

create table if not exists public.korlix_live_convo_agent_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id uuid references public.korlix_live_convo_agent_profiles(id)
    on delete cascade,
  version_id uuid references public.korlix_live_convo_agent_versions(id)
    on delete set null,
  agent_id text not null,
  memory_key text,
  "key" text,
  kind text not null default 'fact',
  memory_type text,
  category text,
  scope text not null default 'agent',
  content text not null default '',
  memory_text text,
  summary text,
  value jsonb not null default '{}'::jsonb,
  memory_value jsonb not null default '{}'::jsonb,
  source text,
  source_event_id text,
  session_id text,
  character_id text,
  language text,
  importance double precision not null default 0.5,
  confidence double precision,
  enabled boolean not null default true,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_used_at timestamptz,
  expires_at timestamptz,
  forgotten_at timestamptz,
  deleted_at timestamptz
);

create index if not exists korlix_live_convo_agent_profiles_user_idx
  on public.korlix_live_convo_agent_profiles (user_id, updated_at desc);

create index if not exists korlix_live_convo_agent_profiles_agent_idx
  on public.korlix_live_convo_agent_profiles (user_id, agent_id);

create index if not exists korlix_live_convo_agent_versions_agent_idx
  on public.korlix_live_convo_agent_versions
  (user_id, agent_id, version desc);

create index if not exists korlix_live_convo_agent_memories_agent_idx
  on public.korlix_live_convo_agent_memories
  (user_id, agent_id, updated_at desc);

create index if not exists korlix_live_convo_agent_memories_active_idx
  on public.korlix_live_convo_agent_memories
  (user_id, agent_id, active, enabled)
  where deleted_at is null and forgotten_at is null;

create unique index if not exists
  korlix_live_convo_agent_memories_key_unique_idx
  on public.korlix_live_convo_agent_memories
  (user_id, agent_id, memory_key)
  where memory_key is not null
    and btrim(memory_key) <> ''
    and deleted_at is null;

create or replace function public.korlix_live_convo_agent_touch_updated_at_build131()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists
  korlix_live_convo_agent_profiles_touch_updated_at_build131
  on public.korlix_live_convo_agent_profiles;

create trigger korlix_live_convo_agent_profiles_touch_updated_at_build131
before update on public.korlix_live_convo_agent_profiles
for each row
execute function public.korlix_live_convo_agent_touch_updated_at_build131();

drop trigger if exists
  korlix_live_convo_agent_memories_touch_updated_at_build131
  on public.korlix_live_convo_agent_memories;

create trigger korlix_live_convo_agent_memories_touch_updated_at_build131
before update on public.korlix_live_convo_agent_memories
for each row
execute function public.korlix_live_convo_agent_touch_updated_at_build131();

alter table public.korlix_live_convo_agent_profiles enable row level security;
alter table public.korlix_live_convo_agent_versions enable row level security;
alter table public.korlix_live_convo_agent_memories enable row level security;

revoke all on table public.korlix_live_convo_agent_profiles
  from public, anon, authenticated;
revoke all on table public.korlix_live_convo_agent_versions
  from public, anon, authenticated;
revoke all on table public.korlix_live_convo_agent_memories
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.korlix_live_convo_agent_profiles to service_role;
grant select, insert, update, delete
  on table public.korlix_live_convo_agent_versions to service_role;
grant select, insert, update, delete
  on table public.korlix_live_convo_agent_memories to service_role;

comment on table public.korlix_live_convo_agent_profiles is
  'Private per-user LIVE CONVO agent definitions for Korlix Build 131.';
comment on table public.korlix_live_convo_agent_versions is
  'Immutable training snapshots for each user-owned LIVE CONVO agent.';
comment on table public.korlix_live_convo_agent_memories is
  'Private long-term memories scoped to a user and LIVE CONVO agent.';

-- KORLIX_LIVE_CONVO_AGENT_MEMORY_BUILD131_END
