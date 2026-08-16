-- KORLIX_AGENT_EMAIL_BUILD133_BEGIN
-- Build 133 source migration for guarded Autonomous Agent Email.
-- This migration is created only; this patch does not apply it to Supabase.
-- The backend service role remains authoritative for every email action.

create extension if not exists pgcrypto;

create table if not exists public.korlix_agent_email_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  agent_id text not null,
  provider text not null default 'resend'
    check (provider in ('resend')),
  enabled boolean not null default false,
  operating_mode text not null default 'draft_only'
    check (operating_mode in ('draft_only', 'approval_required', 'autopilot')),
  emergency_paused boolean not null default true,
  daily_send_cap integer not null default 25
    check (daily_send_cap between 1 and 500),
  from_name text not null default '',
  from_email text not null default '',
  reply_to_email text not null default '',
  physical_address text not null default '',
  timezone text not null default 'UTC',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, agent_id),
  constraint korlix_agent_email_settings_profile_fk
    foreign key (user_id, agent_id)
    references public.korlix_live_convo_agent_profiles (user_id, agent_id)
    on delete cascade
);

create table if not exists public.korlix_agent_email_recipients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  agent_id text not null,
  email text not null
    check (char_length(btrim(email)) between 3 and 320),
  display_name text not null default '',
  source_kind text not null
    check (source_kind in ('user_entered', 'customer_record', 'approved_import')),
  source_reference text,
  consent_status text not null default 'transactional_only'
    check (consent_status in (
      'transactional_only',
      'marketing_opt_in',
      'unsubscribed',
      'suppressed'
    )),
  consent_source text,
  consent_recorded_at timestamptz,
  unsubscribed_at timestamptz,
  suppressed_at timestamptz,
  suppression_reason text,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint korlix_agent_email_recipients_settings_fk
    foreign key (user_id, agent_id)
    references public.korlix_agent_email_settings (user_id, agent_id)
    on delete cascade,
  constraint korlix_agent_email_recipients_marketing_consent_ck
    check (
      consent_status <> 'marketing_opt_in'
      or consent_recorded_at is not null
    ),
  constraint korlix_agent_email_recipients_unsubscribe_ck
    check (
      consent_status <> 'unsubscribed'
      or unsubscribed_at is not null
    ),
  constraint korlix_agent_email_recipients_suppression_ck
    check (
      consent_status <> 'suppressed'
      or suppressed_at is not null
    )
);

create table if not exists public.korlix_agent_email_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  agent_id text not null,
  name text not null,
  enabled boolean not null default false,
  send_mode text not null default 'draft_only'
    check (send_mode in ('draft_only', 'autopilot')),
  trigger_key text not null,
  recipient_scope jsonb not null default '{}'::jsonb,
  subject_template text not null default '',
  text_template text not null default '',
  html_template text not null default '',
  marketing boolean not null default false,
  max_sends_per_day integer not null default 1
    check (max_sends_per_day between 1 and 500),
  preapproved_at timestamptz,
  preapproved_by uuid,
  approval_version integer not null default 1
    check (approval_version >= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint korlix_agent_email_rules_settings_fk
    foreign key (user_id, agent_id)
    references public.korlix_agent_email_settings (user_id, agent_id)
    on delete cascade,
  constraint korlix_agent_email_rules_autopilot_approval_ck
    check (
      send_mode <> 'autopilot'
      or (
        preapproved_at is not null
        and preapproved_by is not null
      )
    )
);

create table if not exists public.korlix_agent_email_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  agent_id text not null,
  recipient_id uuid references public.korlix_agent_email_recipients(id)
    on delete restrict,
  rule_id uuid references public.korlix_agent_email_rules(id)
    on delete restrict,
  to_email text not null
    check (char_length(btrim(to_email)) between 3 and 320),
  subject text not null default '',
  text_body text not null default '',
  html_body text not null default '',
  message_kind text not null default 'transactional'
    check (message_kind in ('transactional', 'marketing')),
  status text not null default 'draft'
    check (status in (
      'draft',
      'pending_approval',
      'approved',
      'queued',
      'sending',
      'sent',
      'failed',
      'cancelled',
      'suppressed'
    )),
  authorization_type text not null default 'none'
    check (authorization_type in (
      'none',
      'one_time_confirmation',
      'preapproved_rule'
    )),
  authorized_at timestamptz,
  authorized_by uuid,
  confirmation_nonce_hash text,
  idempotency_key text not null,
  provider text not null default 'resend'
    check (provider in ('resend')),
  provider_message_id text,
  physical_address_snapshot text not null default '',
  unsubscribe_url_snapshot text not null default '',
  scheduled_at timestamptz,
  last_attempt_at timestamptz,
  attempt_count integer not null default 0
    check (attempt_count between 0 and 100),
  sent_at timestamptz,
  failure_code text,
  failure_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint korlix_agent_email_messages_settings_fk
    foreign key (user_id, agent_id)
    references public.korlix_agent_email_settings (user_id, agent_id)
    on delete cascade,
  constraint korlix_agent_email_messages_body_ck
    check (
      btrim(text_body) <> ''
      or btrim(html_body) <> ''
    ),
  constraint korlix_agent_email_messages_authorization_ck
    check (
      authorization_type = 'none'
      or (
        authorized_at is not null
        and authorized_by is not null
      )
    ),
  constraint korlix_agent_email_messages_send_state_ck
    check (
      status not in ('approved', 'queued', 'sending', 'sent')
      or (
        authorization_type <> 'none'
        and authorized_at is not null
      )
    ),
  constraint korlix_agent_email_messages_rule_authorization_ck
    check (
      authorization_type <> 'preapproved_rule'
      or rule_id is not null
    ),
  constraint korlix_agent_email_messages_marketing_footer_ck
    check (
      message_kind <> 'marketing'
      or (
        btrim(physical_address_snapshot) <> ''
        and btrim(unsubscribe_url_snapshot) <> ''
      )
    )
);

create table if not exists public.korlix_agent_email_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  agent_id text not null,
  message_id uuid not null
    references public.korlix_agent_email_messages(id)
    on delete cascade,
  event_type text not null,
  provider text not null default 'resend'
    check (provider in ('resend')),
  provider_event_id text,
  event_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint korlix_agent_email_events_settings_fk
    foreign key (user_id, agent_id)
    references public.korlix_agent_email_settings (user_id, agent_id)
    on delete cascade
);

create unique index if not exists korlix_agent_email_recipients_address_uidx
  on public.korlix_agent_email_recipients
  (user_id, agent_id, lower(btrim(email)));

create index if not exists korlix_agent_email_recipients_consent_idx
  on public.korlix_agent_email_recipients
  (user_id, agent_id, consent_status, active);

create index if not exists korlix_agent_email_rules_enabled_idx
  on public.korlix_agent_email_rules
  (user_id, agent_id, enabled, send_mode);

create unique index if not exists korlix_agent_email_messages_idempotency_uidx
  on public.korlix_agent_email_messages
  (user_id, agent_id, idempotency_key);

create unique index if not exists korlix_agent_email_messages_provider_uidx
  on public.korlix_agent_email_messages (provider, provider_message_id)
  where provider_message_id is not null
    and btrim(provider_message_id) <> '';

create index if not exists korlix_agent_email_messages_queue_idx
  on public.korlix_agent_email_messages
  (status, scheduled_at, created_at)
  where status in ('approved', 'queued', 'sending');

create index if not exists korlix_agent_email_messages_daily_cap_idx
  on public.korlix_agent_email_messages
  (user_id, agent_id, sent_at desc)
  where status = 'sent';

create unique index if not exists korlix_agent_email_events_provider_uidx
  on public.korlix_agent_email_events (provider, provider_event_id)
  where provider_event_id is not null
    and btrim(provider_event_id) <> '';

create index if not exists korlix_agent_email_events_message_idx
  on public.korlix_agent_email_events
  (user_id, agent_id, message_id, event_at desc);

create or replace function public.korlix_agent_email_touch_updated_at_build133()
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

drop trigger if exists korlix_agent_email_settings_touch_updated_at_build133
  on public.korlix_agent_email_settings;
create trigger korlix_agent_email_settings_touch_updated_at_build133
before update on public.korlix_agent_email_settings
for each row
execute function public.korlix_agent_email_touch_updated_at_build133();

drop trigger if exists korlix_agent_email_recipients_touch_updated_at_build133
  on public.korlix_agent_email_recipients;
create trigger korlix_agent_email_recipients_touch_updated_at_build133
before update on public.korlix_agent_email_recipients
for each row
execute function public.korlix_agent_email_touch_updated_at_build133();

drop trigger if exists korlix_agent_email_rules_touch_updated_at_build133
  on public.korlix_agent_email_rules;
create trigger korlix_agent_email_rules_touch_updated_at_build133
before update on public.korlix_agent_email_rules
for each row
execute function public.korlix_agent_email_touch_updated_at_build133();

drop trigger if exists korlix_agent_email_messages_touch_updated_at_build133
  on public.korlix_agent_email_messages;
create trigger korlix_agent_email_messages_touch_updated_at_build133
before update on public.korlix_agent_email_messages
for each row
execute function public.korlix_agent_email_touch_updated_at_build133();

alter table public.korlix_agent_email_settings enable row level security;
alter table public.korlix_agent_email_recipients enable row level security;
alter table public.korlix_agent_email_rules enable row level security;
alter table public.korlix_agent_email_messages enable row level security;
alter table public.korlix_agent_email_events enable row level security;

revoke all on table public.korlix_agent_email_settings
  from public, anon, authenticated;
revoke all on table public.korlix_agent_email_recipients
  from public, anon, authenticated;
revoke all on table public.korlix_agent_email_rules
  from public, anon, authenticated;
revoke all on table public.korlix_agent_email_messages
  from public, anon, authenticated;
revoke all on table public.korlix_agent_email_events
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.korlix_agent_email_settings to service_role;
grant select, insert, update, delete
  on table public.korlix_agent_email_recipients to service_role;
grant select, insert, update, delete
  on table public.korlix_agent_email_rules to service_role;
grant select, insert, update
  on table public.korlix_agent_email_messages to service_role;
grant select, insert
  on table public.korlix_agent_email_events to service_role;


create or replace function public.korlix_agent_email_claim_send_build133(
  p_user_id uuid,
  p_agent_id text,
  p_message_id uuid,
  p_claimed_at timestamptz,
  p_confirmation_nonce_hash text
)
returns setof public.korlix_agent_email_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_database_now timestamptz := now();
  v_day_start timestamptz;
  v_settings public.korlix_agent_email_settings%rowtype;
  v_message public.korlix_agent_email_messages%rowtype;
  v_recipient public.korlix_agent_email_recipients%rowtype;
  v_rule public.korlix_agent_email_rules%rowtype;
  v_agent_send_count bigint := 0;
  v_rule_send_count bigint := 0;
  v_message_rule_version integer := null;
  v_failure_retryable boolean := false;
  v_failure_ambiguous boolean := false;
  v_retry_deadline timestamptz := null;
begin
  if p_claimed_at is null
    or abs(extract(epoch from (p_claimed_at - v_database_now))) > 300 then
    raise exception 'agent_email_claimed_at_invalid' using errcode = 'P0001';
  end if;

  select *
    into v_settings
    from public.korlix_agent_email_settings
   where user_id = p_user_id
     and agent_id = p_agent_id
   for update;

  if not found then
    raise exception 'agent_email_settings_required' using errcode = 'P0001';
  end if;

  if v_settings.enabled is not true then
    raise exception 'agent_email_feature_disabled' using errcode = 'P0001';
  end if;

  if v_settings.emergency_paused is true then
    raise exception 'agent_email_emergency_paused' using errcode = 'P0001';
  end if;

  if v_settings.operating_mode = 'draft_only' then
    raise exception 'agent_email_mode_draft_only' using errcode = 'P0001';
  end if;

  begin
    v_day_start :=
      date_trunc(
        'day',
        p_claimed_at at time zone v_settings.timezone
      ) at time zone v_settings.timezone;
  exception
    when invalid_parameter_value then
      raise exception 'agent_email_timezone_invalid' using errcode = 'P0001';
  end;

  select *
    into v_message
    from public.korlix_agent_email_messages
   where id = p_message_id
     and user_id = p_user_id
     and agent_id = p_agent_id
   for update;

  if not found then
    raise exception 'agent_email_message_not_found' using errcode = 'P0001';
  end if;

  if v_message.status = 'sent'
    and v_message.provider_message_id is not null
    and btrim(v_message.provider_message_id) <> '' then
    return next v_message;
    return;
  end if;

  if v_message.provider_message_id is not null
    and btrim(v_message.provider_message_id) <> '' then
    raise exception 'agent_email_send_reconciliation_required' using errcode = 'P0001';
  end if;

  if v_message.status = 'sending' then
    if v_message.last_attempt_at is null
      or v_message.last_attempt_at < p_claimed_at - interval '23 hours' then
      raise exception 'agent_email_send_reconciliation_required' using errcode = 'P0001';
    end if;

    if v_message.last_attempt_at >= p_claimed_at - interval '15 minutes' then
      raise exception 'agent_email_message_send_in_progress' using errcode = 'P0001';
    end if;
  end if;

  if v_message.status = 'failed' then
    v_failure_retryable :=
      lower(coalesce(v_message.metadata ->> 'lastFailureRetryable', 'false'))
      in ('true', '1', 'yes', 'on', 'enabled');

    v_failure_ambiguous :=
      lower(coalesce(v_message.metadata ->> 'lastFailureAmbiguous', 'false'))
      in ('true', '1', 'yes', 'on', 'enabled');

    if not v_failure_retryable then
      raise exception 'agent_email_message_requires_edit_and_reapproval'
        using errcode = 'P0001';
    end if;

    if v_message.last_attempt_at is null then
      raise exception 'agent_email_send_reconciliation_required' using errcode = 'P0001';
    end if;

    if coalesce(v_message.metadata ->> 'retryDeadlineAt', '') <> '' then
      begin
        v_retry_deadline :=
          (v_message.metadata ->> 'retryDeadlineAt')::timestamptz;
      exception
        when invalid_datetime_format then
          raise exception 'agent_email_send_reconciliation_required'
            using errcode = 'P0001';
      end;
    end if;

    if v_message.last_attempt_at < p_claimed_at - interval '23 hours'
      or (v_retry_deadline is not null and v_retry_deadline < p_claimed_at) then
      if v_failure_ambiguous then
        raise exception 'agent_email_send_reconciliation_required'
          using errcode = 'P0001';
      end if;

      raise exception 'agent_email_message_requires_edit_and_reapproval'
        using errcode = 'P0001';
    end if;
  end if;

  if v_message.status not in ('approved', 'queued', 'failed', 'sending')
    or v_message.authorization_type = 'none'
    or v_message.authorized_at is null
    or v_message.authorized_by is null then
    raise exception 'agent_email_message_not_authorized' using errcode = 'P0001';
  end if;

  if v_message.scheduled_at is not null
    and v_message.scheduled_at > p_claimed_at then
    raise exception 'agent_email_scheduled_for_later' using errcode = 'P0001';
  end if;

  if v_message.authorization_type = 'one_time_confirmation' then
    if v_message.authorized_by is distinct from p_user_id then
      raise exception 'agent_email_authorized_user_mismatch' using errcode = 'P0001';
    end if;

    if v_message.confirmation_nonce_hash is null
      or btrim(v_message.confirmation_nonce_hash) = ''
      or coalesce(btrim(p_confirmation_nonce_hash), '') !~ '^[0-9A-Fa-f]{64}$'
      or lower(btrim(v_message.confirmation_nonce_hash)) <>
        lower(btrim(p_confirmation_nonce_hash)) then
      raise exception 'agent_email_confirmation_nonce_mismatch' using errcode = 'P0001';
    end if;
  end if;

  if v_message.recipient_id is null then
    raise exception 'agent_email_recipient_not_found' using errcode = 'P0001';
  end if;

  select *
    into v_recipient
    from public.korlix_agent_email_recipients
   where id = v_message.recipient_id
     and user_id = p_user_id
     and agent_id = p_agent_id
   for update;

  if not found then
    raise exception 'agent_email_recipient_not_found' using errcode = 'P0001';
  end if;

  if v_recipient.active is not true
    or v_recipient.consent_status in ('unsubscribed', 'suppressed') then
    raise exception 'agent_email_recipient_blocked' using errcode = 'P0001';
  end if;

  if lower(btrim(v_message.to_email)) <> lower(btrim(v_recipient.email)) then
    raise exception 'agent_email_recipient_snapshot_mismatch' using errcode = 'P0001';
  end if;

  if v_message.message_kind = 'marketing' then
    if v_recipient.consent_status <> 'marketing_opt_in' then
      raise exception 'agent_email_marketing_consent_required' using errcode = 'P0001';
    end if;

    if lower(coalesce(v_settings.metadata ->> 'marketingEnabled', 'false'))
      not in ('true', '1', 'yes', 'on', 'enabled') then
      raise exception 'agent_email_marketing_disabled' using errcode = 'P0001';
    end if;

    if btrim(v_message.physical_address_snapshot) = ''
      or btrim(v_message.unsubscribe_url_snapshot) = '' then
      raise exception 'agent_email_marketing_footer_required' using errcode = 'P0001';
    end if;
  end if;

  if v_message.authorization_type = 'preapproved_rule' then
    if v_settings.operating_mode <> 'autopilot'
      or v_message.rule_id is null then
      raise exception 'agent_email_rule_not_ready' using errcode = 'P0001';
    end if;

    select *
      into v_rule
      from public.korlix_agent_email_rules
     where id = v_message.rule_id
       and user_id = p_user_id
       and agent_id = p_agent_id
     for update;

    if not found
      or v_rule.enabled is not true
      or v_rule.send_mode <> 'autopilot'
      or v_rule.preapproved_at is null
      or v_rule.preapproved_by is null then
      raise exception 'agent_email_rule_not_ready' using errcode = 'P0001';
    end if;

    if v_message.authorized_by is distinct from v_rule.preapproved_by
      or v_message.authorized_at is distinct from v_rule.preapproved_at then
      raise exception 'agent_email_rule_authorization_stale' using errcode = 'P0001';
    end if;

    if coalesce(v_message.metadata ->> 'ruleApprovalVersion', '') ~ '^[0-9]+$' then
      v_message_rule_version :=
        (v_message.metadata ->> 'ruleApprovalVersion')::integer;
    end if;

    if v_message_rule_version is distinct from v_rule.approval_version then
      raise exception 'agent_email_rule_approval_stale' using errcode = 'P0001';
    end if;

    if not exists (
      select 1
        from jsonb_array_elements_text(
          coalesce(v_rule.recipient_scope -> 'recipientIds', '[]'::jsonb)
        ) as approved_recipient(value)
       where approved_recipient.value = v_message.recipient_id::text
    ) then
      raise exception 'agent_email_rule_recipient_scope_mismatch' using errcode = 'P0001';
    end if;
  end if;

  select count(*)
    into v_agent_send_count
    from public.korlix_agent_email_messages
   where user_id = p_user_id
     and agent_id = p_agent_id
     and status in ('sending', 'sent')
     and coalesce(sent_at, last_attempt_at, updated_at) >= v_day_start
     and id <> p_message_id;

  if v_agent_send_count >= v_settings.daily_send_cap then
    raise exception 'agent_email_daily_cap_reached' using errcode = 'P0001';
  end if;

  if v_message.authorization_type = 'preapproved_rule' then
    select count(*)
      into v_rule_send_count
      from public.korlix_agent_email_messages
     where user_id = p_user_id
       and agent_id = p_agent_id
       and rule_id = v_message.rule_id
       and status in ('sending', 'sent')
       and coalesce(sent_at, last_attempt_at, updated_at) >= v_day_start
       and id <> p_message_id;

    if v_rule_send_count >= v_rule.max_sends_per_day then
      raise exception 'agent_email_rule_daily_cap_reached' using errcode = 'P0001';
    end if;
  end if;

  if v_message.attempt_count >= 100 then
    raise exception 'agent_email_attempt_limit_reached' using errcode = 'P0001';
  end if;

  update public.korlix_agent_email_messages
     set status = 'sending',
         last_attempt_at = p_claimed_at,
         attempt_count = attempt_count + 1,
         failure_code = null,
         failure_message = null
   where id = p_message_id
     and user_id = p_user_id
     and agent_id = p_agent_id
  returning * into v_message;

  return next v_message;
  return;
end;
$$;

revoke all on function public.korlix_agent_email_claim_send_build133(
  uuid,
  text,
  uuid,
  timestamptz,
  text
) from public, anon, authenticated;

grant execute on function public.korlix_agent_email_claim_send_build133(
  uuid,
  text,
  uuid,
  timestamptz,
  text
) to service_role;

comment on table public.korlix_agent_email_settings is
  'Server-authoritative per-agent email controls. Disabled and emergency-paused by default.';
comment on table public.korlix_agent_email_recipients is
  'Explicitly sourced recipients with consent, unsubscribe, and suppression state.';
comment on table public.korlix_agent_email_rules is
  'User-preapproved Agent Email automation rules. Autopilot requires recorded approval.';
comment on table public.korlix_agent_email_messages is
  'Drafts and authorized outbound messages with idempotency and Resend delivery state.';
comment on table public.korlix_agent_email_events is
  'Append-only Agent Email audit and provider delivery events.';

-- Scraped or guessed recipients are forbidden by the source_kind allowlist.
-- No email may leave draft state without one-time confirmation or a preapproved rule.
-- KORLIX_AGENT_EMAIL_BUILD133_END
