-- K136S — Nova Secure Spoken Learning (build136). STAGED by K136S-F1; APPLY is a separate, explicit step.
-- Three service-role-only tables: learning sessions, single-use approvals (hash only), insert-only audit.
-- Follows the repo convention used by the live-convo memory tables: RLS enabled, all grants revoked
-- from anon/authenticated, so only the service role (the backend) can touch them.

create table if not exists public.k136s_learning_sessions (
  id text primary key,
  user_id text not null,
  account_id text not null,
  agent_id text not null,
  state text not null,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz,
  state_expires_at timestamptz,
  vault_verified_at timestamptz,
  payload jsonb not null default '{}'::jsonb
);
create index if not exists k136s_learning_sessions_user_agent_idx on public.k136s_learning_sessions (user_id, agent_id);
create index if not exists k136s_learning_sessions_state_idx on public.k136s_learning_sessions (state);

create table if not exists public.k136s_approvals (
  id text primary key,
  session_id text not null,
  user_id text not null,
  account_id text not null,
  agent_id text not null,
  token_hash text not null,           -- SHA-256 of the single-use token; the raw token is never stored
  content_hash text not null,         -- binds the approval to the exact previewed change
  elevated boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,    -- 120 s after issue
  consumed_at timestamptz             -- set exactly once
);
create unique index if not exists k136s_approvals_token_hash_idx on public.k136s_approvals (token_hash);
create index if not exists k136s_approvals_session_idx on public.k136s_approvals (session_id);
create index if not exists k136s_approvals_expires_idx on public.k136s_approvals (expires_at);

create table if not exists public.k136s_audit_events (
  id bigserial primary key,
  event_type text not null,
  at timestamptz not null default now(),
  session_id text,
  user_id text,
  account_id text,
  agent_id text,
  approval_id text,
  memory_key text,
  content_hash text,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists k136s_audit_events_session_idx on public.k136s_audit_events (session_id);
create index if not exists k136s_audit_events_at_idx on public.k136s_audit_events (at);
create index if not exists k136s_audit_events_type_idx on public.k136s_audit_events (event_type);

alter table public.k136s_learning_sessions enable row level security;
alter table public.k136s_approvals enable row level security;
alter table public.k136s_audit_events enable row level security;

revoke all on table public.k136s_learning_sessions from anon, authenticated;
revoke all on table public.k136s_approvals from anon, authenticated;
revoke all on table public.k136s_audit_events from anon, authenticated;
