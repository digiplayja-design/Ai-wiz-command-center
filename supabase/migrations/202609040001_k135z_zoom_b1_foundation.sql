begin;

create extension if not exists pgcrypto;

create table if not exists public.korlix_zoom_oauth_states (
  id uuid primary key default gen_random_uuid(),
  nonce_hash text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_id text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),

  check (
    char_length(nonce_hash)
    between 32 and 256
  ),

  check (
    expires_at >
    created_at
  )
);

create table if not exists public.korlix_zoom_connections (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  agent_id text not null,
  zoom_account_id text not null,

  token_envelope jsonb not null,

  scopes text[] not null
    default array[]::text[],

  status text not null
    default 'connected',

  connected_at timestamptz not null
    default now(),

  revoked_at timestamptz,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  check (
    status in (
      'connected',
      'expired',
      'revoked',
      'error'
    )
  ),

  check (
    jsonb_typeof(
      token_envelope
    ) = 'object'

    and token_envelope ? 'iv'
    and token_envelope ? 'tag'
    and token_envelope ? 'ciphertext'

    and not token_envelope
      ? 'access_token'

    and not token_envelope
      ? 'refresh_token'
  ),

  unique (
    user_id,
    agent_id,
    zoom_account_id
  )
);

create table if not exists public.korlix_zoom_meeting_sessions (
  id uuid primary key default gen_random_uuid(),

  connection_id uuid not null
    references public.korlix_zoom_connections(id)
    on delete cascade,

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  agent_id text not null,

  zoom_meeting_uuid text not null,
  zoom_meeting_id text,
  rtms_stream_id text,

  status text not null
    default 'authorized',

  consent_status text not null
    default 'pending',

  active_ms bigint not null
    default 0
    check (active_ms >= 0),

  raw_audio_stored boolean not null
    default false
    check (raw_audio_stored = false),

  transcript_saved boolean not null
    default false,

  started_at timestamptz,
  paused_at timestamptz,
  stopped_at timestamptz,

  last_event_id text,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  check (
    status in (
      'authorized',
      'initializing',
      'started',
      'paused',
      'stopped',
      'failed'
    )
  ),

  check (
    consent_status in (
      'pending',
      'approved',
      'denied',
      'revoked'
    )
  )
);

create unique index if not exists
  korlix_zoom_session_stream_uq

on public.korlix_zoom_meeting_sessions(
  rtms_stream_id
)

where rtms_stream_id is not null;

create table if not exists public.korlix_zoom_webhook_events (
  event_id text primary key,
  event_name text not null,
  account_id text,
  meeting_uuid text,
  meeting_id text,
  stream_id text,

  processing_status text not null
    default 'accepted',

  received_at timestamptz not null
    default now(),

  processed_at timestamptz,

  check (
    processing_status in (
      'accepted',
      'processed',
      'ignored',
      'failed'
    )
  )
);

create table if not exists public.korlix_zoom_audit_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  event_type text not null,

  user_id uuid
    references auth.users(id)
    on delete set null,

  agent_id text,

  connection_id uuid
    references public.korlix_zoom_connections(id)
    on delete set null,

  session_id uuid
    references public.korlix_zoom_meeting_sessions(id)
    on delete set null,

  actor_type text not null
    default 'system',

  metadata jsonb not null
    default '{}'::jsonb,

  created_at timestamptz not null
    default now(),

  check (
    actor_type in (
      'user',
      'host',
      'zoom',
      'nova',
      'system'
    )
  )
);

alter table
  public.korlix_zoom_oauth_states
enable row level security;

alter table
  public.korlix_zoom_connections
enable row level security;

alter table
  public.korlix_zoom_meeting_sessions
enable row level security;

alter table
  public.korlix_zoom_webhook_events
enable row level security;

alter table
  public.korlix_zoom_audit_events
enable row level security;

revoke all on
  public.korlix_zoom_oauth_states,
  public.korlix_zoom_connections,
  public.korlix_zoom_meeting_sessions,
  public.korlix_zoom_webhook_events,
  public.korlix_zoom_audit_events

from anon, authenticated;

grant all on
  public.korlix_zoom_oauth_states,
  public.korlix_zoom_connections,
  public.korlix_zoom_meeting_sessions,
  public.korlix_zoom_webhook_events,
  public.korlix_zoom_audit_events

to service_role;

commit;
