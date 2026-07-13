-- KORLIX_LIVE_CONVO_BUILD129_SQL_BEGIN
-- Run this migration in the production Supabase SQL Editor before deploying
-- the Build 129 backend. Only the backend service role can access these rows.

create table if not exists public.korlix_live_convo_monthly_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  month_key date not null,
  tier text not null default 'basic',
  session_count integer not null default 0 check (session_count >= 0),
  duration_seconds bigint not null default 0 check (duration_seconds >= 0),
  response_count bigint not null default 0 check (response_count >= 0),
  total_tokens bigint not null default 0 check (total_tokens >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  input_audio_tokens bigint not null default 0 check (input_audio_tokens >= 0),
  output_audio_tokens bigint not null default 0 check (output_audio_tokens >= 0),
  image_tokens bigint not null default 0 check (image_tokens >= 0),
  transcription_tokens bigint not null default 0 check (transcription_tokens >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, month_key)
);

create table if not exists public.korlix_live_convo_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  month_key date not null,
  tier text not null default 'basic',
  status text not null default 'reserved'
    check (status in ('reserved', 'active', 'ended')),
  max_duration_seconds integer not null check (max_duration_seconds > 0),
  max_response_count integer not null check (max_response_count > 0),
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  response_count integer not null default 0 check (response_count >= 0),
  total_tokens bigint not null default 0 check (total_tokens >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  input_audio_tokens bigint not null default 0 check (input_audio_tokens >= 0),
  output_audio_tokens bigint not null default 0 check (output_audio_tokens >= 0),
  image_tokens bigint not null default 0 check (image_tokens >= 0),
  transcription_tokens bigint not null default 0 check (transcription_tokens >= 0),
  end_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists korlix_live_convo_sessions_user_month_idx
  on public.korlix_live_convo_sessions (user_id, month_key, started_at desc);

alter table public.korlix_live_convo_monthly_usage enable row level security;
alter table public.korlix_live_convo_sessions enable row level security;

revoke all on table public.korlix_live_convo_monthly_usage
  from public, anon, authenticated;
revoke all on table public.korlix_live_convo_sessions
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.korlix_live_convo_monthly_usage to service_role;
grant select, insert, update, delete
  on table public.korlix_live_convo_sessions to service_role;

create or replace function public.korlix_live_convo_reserve_session(
  p_session_id uuid,
  p_user_id uuid,
  p_tier text,
  p_monthly_session_limit integer,
  p_monthly_duration_limit integer,
  p_monthly_token_limit bigint,
  p_max_session_seconds integer,
  p_max_response_count integer
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', timezone('utc', now()))::date;
  v_tier text := coalesce(nullif(lower(trim(p_tier)), ''), 'basic');
  v_session_limit integer := greatest(coalesce(p_monthly_session_limit, 0), 0);
  v_duration_limit integer := greatest(coalesce(p_monthly_duration_limit, 0), 0);
  v_token_limit bigint := greatest(coalesce(p_monthly_token_limit, 0), 0);
  v_usage public.korlix_live_convo_monthly_usage%rowtype;
  v_used_tokens bigint;
begin
  if p_session_id is null or p_user_id is null then
    return jsonb_build_object(
      'allowed', false,
      'code', 'invalid_session_request',
      'message', 'A valid LIVE CONVO session and user are required.'
    );
  end if;

  insert into public.korlix_live_convo_monthly_usage (
    user_id,
    month_key,
    tier,
    updated_at
  ) values (
    p_user_id,
    v_month,
    v_tier,
    now()
  )
  on conflict (user_id, month_key) do update
    set tier = excluded.tier,
        updated_at = now();

  select *
    into v_usage
    from public.korlix_live_convo_monthly_usage
   where user_id = p_user_id
     and month_key = v_month
   for update;

  v_used_tokens := v_usage.total_tokens + v_usage.transcription_tokens;

  if v_usage.session_count >= v_session_limit then
    return jsonb_build_object(
      'allowed', false,
      'code', 'monthly_session_limit_reached',
      'message', 'Your LIVE CONVO session allowance has been used for this month.',
      'usage', to_jsonb(v_usage)
    );
  end if;

  if v_usage.duration_seconds >= v_duration_limit then
    return jsonb_build_object(
      'allowed', false,
      'code', 'monthly_duration_limit_reached',
      'message', 'Your LIVE CONVO time allowance has been used for this month.',
      'usage', to_jsonb(v_usage)
    );
  end if;

  if v_used_tokens >= v_token_limit then
    return jsonb_build_object(
      'allowed', false,
      'code', 'monthly_token_limit_reached',
      'message', 'Your LIVE CONVO usage allowance has been used for this month.',
      'usage', to_jsonb(v_usage)
    );
  end if;

  insert into public.korlix_live_convo_sessions (
    id,
    user_id,
    month_key,
    tier,
    status,
    max_duration_seconds,
    max_response_count
  ) values (
    p_session_id,
    p_user_id,
    v_month,
    v_tier,
    'reserved',
    greatest(coalesce(p_max_session_seconds, 1), 1),
    greatest(coalesce(p_max_response_count, 1), 1)
  )
  on conflict (id) do nothing;

  if not found then
    return jsonb_build_object(
      'allowed', false,
      'code', 'duplicate_session_id',
      'message', 'Could not reserve a unique LIVE CONVO session.'
    );
  end if;

  update public.korlix_live_convo_monthly_usage
     set session_count = session_count + 1,
         tier = v_tier,
         updated_at = now()
   where user_id = p_user_id
     and month_key = v_month
   returning * into v_usage;

  return jsonb_build_object(
    'allowed', true,
    'sessionId', p_session_id::text,
    'tier', v_tier,
    'monthKey', v_month::text,
    'maxSessionSeconds', greatest(coalesce(p_max_session_seconds, 1), 1),
    'maxResponses', greatest(coalesce(p_max_response_count, 1), 1),
    'monthlySessionLimit', v_session_limit,
    'monthlyDurationLimit', v_duration_limit,
    'monthlyTokenLimit', v_token_limit,
    'remainingSessions', greatest(v_session_limit - v_usage.session_count, 0),
    'remainingSeconds', greatest(v_duration_limit - v_usage.duration_seconds, 0),
    'remainingTokens', greatest(
      v_token_limit - (v_usage.total_tokens + v_usage.transcription_tokens),
      0
    )
  );
end;
$$;

create or replace function public.korlix_live_convo_report_usage(
  p_session_id uuid,
  p_user_id uuid,
  p_duration_seconds integer,
  p_response_count integer,
  p_total_tokens bigint,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_input_audio_tokens bigint,
  p_output_audio_tokens bigint,
  p_image_tokens bigint,
  p_transcription_tokens bigint,
  p_monthly_duration_limit integer,
  p_monthly_token_limit bigint,
  p_ended boolean default false,
  p_end_reason text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_session public.korlix_live_convo_sessions%rowtype;
  v_usage public.korlix_live_convo_monthly_usage%rowtype;
  v_duration_limit integer := greatest(coalesce(p_monthly_duration_limit, 0), 0);
  v_token_limit bigint := greatest(coalesce(p_monthly_token_limit, 0), 0);
  v_duration integer;
  v_responses integer;
  v_total bigint;
  v_input bigint;
  v_output bigint;
  v_input_audio bigint;
  v_output_audio bigint;
  v_image bigint;
  v_transcription bigint;
  d_duration bigint;
  d_responses bigint;
  d_total bigint;
  d_input bigint;
  d_output bigint;
  d_input_audio bigint;
  d_output_audio bigint;
  d_image bigint;
  d_transcription bigint;
  v_session_limit_reached boolean;
  v_monthly_limit_reached boolean;
begin
  select *
    into v_session
    from public.korlix_live_convo_sessions
   where id = p_session_id
     and user_id = p_user_id
   for update;

  if not found then
    return jsonb_build_object(
      'allowed', false,
      'code', 'session_not_found',
      'message', 'LIVE CONVO usage session was not found.'
    );
  end if;

  insert into public.korlix_live_convo_monthly_usage (
    user_id,
    month_key,
    tier,
    updated_at
  ) values (
    p_user_id,
    v_session.month_key,
    v_session.tier,
    now()
  )
  on conflict (user_id, month_key) do nothing;

  select *
    into v_usage
    from public.korlix_live_convo_monthly_usage
   where user_id = p_user_id
     and month_key = v_session.month_key
   for update;

  -- Every client report is cumulative. Keep session counters monotonic so
  -- retries and out-of-order heartbeats cannot double-charge the user.
  v_duration := greatest(
    v_session.duration_seconds,
    least(
      greatest(coalesce(p_duration_seconds, 0), 0),
      v_session.max_duration_seconds
    )
  );
  v_responses := greatest(
    v_session.response_count,
    least(
      greatest(coalesce(p_response_count, 0), 0),
      v_session.max_response_count
    )
  );
  v_total := greatest(v_session.total_tokens, greatest(coalesce(p_total_tokens, 0), 0));
  v_input := greatest(v_session.input_tokens, greatest(coalesce(p_input_tokens, 0), 0));
  v_output := greatest(v_session.output_tokens, greatest(coalesce(p_output_tokens, 0), 0));
  v_input_audio := greatest(v_session.input_audio_tokens, greatest(coalesce(p_input_audio_tokens, 0), 0));
  v_output_audio := greatest(v_session.output_audio_tokens, greatest(coalesce(p_output_audio_tokens, 0), 0));
  v_image := greatest(v_session.image_tokens, greatest(coalesce(p_image_tokens, 0), 0));
  v_transcription := greatest(v_session.transcription_tokens, greatest(coalesce(p_transcription_tokens, 0), 0));

  d_duration := v_duration - v_session.duration_seconds;
  d_responses := v_responses - v_session.response_count;
  d_total := v_total - v_session.total_tokens;
  d_input := v_input - v_session.input_tokens;
  d_output := v_output - v_session.output_tokens;
  d_input_audio := v_input_audio - v_session.input_audio_tokens;
  d_output_audio := v_output_audio - v_session.output_audio_tokens;
  d_image := v_image - v_session.image_tokens;
  d_transcription := v_transcription - v_session.transcription_tokens;

  v_session_limit_reached :=
    v_duration >= v_session.max_duration_seconds
    or v_responses >= v_session.max_response_count;

  update public.korlix_live_convo_sessions
     set status = case
           when status = 'ended' then 'ended'
           when coalesce(p_ended, false) or v_session_limit_reached then 'ended'
           else 'active'
         end,
         last_seen_at = now(),
         ended_at = case
           when status = 'ended' then ended_at
           when coalesce(p_ended, false) or v_session_limit_reached
             then coalesce(ended_at, now())
           else ended_at
         end,
         duration_seconds = v_duration,
         response_count = v_responses,
         total_tokens = v_total,
         input_tokens = v_input,
         output_tokens = v_output,
         input_audio_tokens = v_input_audio,
         output_audio_tokens = v_output_audio,
         image_tokens = v_image,
         transcription_tokens = v_transcription,
         end_reason = case
           when status = 'ended' then end_reason
           when coalesce(p_ended, false) or v_session_limit_reached
             then coalesce(nullif(trim(p_end_reason), ''), end_reason, 'completed')
           else end_reason
         end,
         updated_at = now()
   where id = p_session_id;

  update public.korlix_live_convo_monthly_usage
     set duration_seconds = duration_seconds + d_duration,
         response_count = response_count + d_responses,
         total_tokens = total_tokens + d_total,
         input_tokens = input_tokens + d_input,
         output_tokens = output_tokens + d_output,
         input_audio_tokens = input_audio_tokens + d_input_audio,
         output_audio_tokens = output_audio_tokens + d_output_audio,
         image_tokens = image_tokens + d_image,
         transcription_tokens = transcription_tokens + d_transcription,
         updated_at = now()
   where user_id = p_user_id
     and month_key = v_session.month_key
   returning * into v_usage;

  v_monthly_limit_reached :=
    v_usage.duration_seconds >= v_duration_limit
    or (v_usage.total_tokens + v_usage.transcription_tokens) >= v_token_limit;

  return jsonb_build_object(
    'allowed', not (v_session_limit_reached or v_monthly_limit_reached),
    'limitReached', v_session_limit_reached or v_monthly_limit_reached,
    'sessionLimitReached', v_session_limit_reached,
    'monthlyLimitReached', v_monthly_limit_reached,
    'sessionId', p_session_id::text,
    'durationSeconds', v_duration,
    'responseCount', v_responses,
    'totalTokens', v_total,
    'transcriptionTokens', v_transcription,
    'remainingSessionSeconds', greatest(v_session.max_duration_seconds - v_duration, 0),
    'remainingResponses', greatest(v_session.max_response_count - v_responses, 0),
    'remainingMonthlySeconds', greatest(v_duration_limit - v_usage.duration_seconds, 0),
    'remainingMonthlyTokens', greatest(
      v_token_limit - (v_usage.total_tokens + v_usage.transcription_tokens),
      0
    ),
    'message', case
      when v_session_limit_reached then 'This LIVE CONVO session reached its fair-use limit.'
      when v_monthly_limit_reached then 'Your LIVE CONVO monthly allowance has been reached.'
      else null
    end
  );
end;
$$;

create or replace function public.korlix_live_convo_cancel_reservation(
  p_session_id uuid,
  p_user_id uuid,
  p_reason text default 'provider_failed'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_session public.korlix_live_convo_sessions%rowtype;
begin
  select *
    into v_session
    from public.korlix_live_convo_sessions
   where id = p_session_id
     and user_id = p_user_id
   for update;

  if not found then
    return jsonb_build_object('ok', true, 'cancelled', false);
  end if;

  if v_session.status = 'reserved'
     and v_session.duration_seconds = 0
     and v_session.response_count = 0
     and v_session.total_tokens = 0
     and v_session.transcription_tokens = 0 then
    delete from public.korlix_live_convo_sessions
     where id = p_session_id;

    update public.korlix_live_convo_monthly_usage
       set session_count = greatest(session_count - 1, 0),
           updated_at = now()
     where user_id = p_user_id
       and month_key = v_session.month_key;

    return jsonb_build_object(
      'ok', true,
      'cancelled', true,
      'reservationRemoved', true
    );
  end if;

  update public.korlix_live_convo_sessions
     set status = 'ended',
         ended_at = coalesce(ended_at, now()),
         end_reason = coalesce(nullif(trim(p_reason), ''), end_reason, 'provider_failed'),
         updated_at = now()
   where id = p_session_id;

  return jsonb_build_object(
    'ok', true,
    'cancelled', true,
    'reservationRemoved', false
  );
end;
$$;

create or replace function public.korlix_live_convo_get_usage(
  p_user_id uuid,
  p_tier text,
  p_monthly_session_limit integer,
  p_monthly_duration_limit integer,
  p_monthly_token_limit bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', timezone('utc', now()))::date;
  v_tier text := coalesce(nullif(lower(trim(p_tier)), ''), 'basic');
  v_session_limit integer := greatest(coalesce(p_monthly_session_limit, 0), 0);
  v_duration_limit integer := greatest(coalesce(p_monthly_duration_limit, 0), 0);
  v_token_limit bigint := greatest(coalesce(p_monthly_token_limit, 0), 0);
  v_usage public.korlix_live_convo_monthly_usage%rowtype;
begin
  select *
    into v_usage
    from public.korlix_live_convo_monthly_usage
   where user_id = p_user_id
     and month_key = v_month;

  if not found then
    return jsonb_build_object(
      'tier', v_tier,
      'monthKey', v_month::text,
      'sessionCount', 0,
      'durationSeconds', 0,
      'responseCount', 0,
      'totalTokens', 0,
      'transcriptionTokens', 0,
      'monthlySessionLimit', v_session_limit,
      'monthlyDurationLimit', v_duration_limit,
      'monthlyTokenLimit', v_token_limit,
      'remainingSessions', v_session_limit,
      'remainingSeconds', v_duration_limit,
      'remainingTokens', v_token_limit
    );
  end if;

  return jsonb_build_object(
    'tier', v_usage.tier,
    'monthKey', v_usage.month_key::text,
    'sessionCount', v_usage.session_count,
    'durationSeconds', v_usage.duration_seconds,
    'responseCount', v_usage.response_count,
    'totalTokens', v_usage.total_tokens,
    'transcriptionTokens', v_usage.transcription_tokens,
    'monthlySessionLimit', v_session_limit,
    'monthlyDurationLimit', v_duration_limit,
    'monthlyTokenLimit', v_token_limit,
    'remainingSessions', greatest(v_session_limit - v_usage.session_count, 0),
    'remainingSeconds', greatest(v_duration_limit - v_usage.duration_seconds, 0),
    'remainingTokens', greatest(
      v_token_limit - (v_usage.total_tokens + v_usage.transcription_tokens),
      0
    )
  );
end;
$$;

revoke all on function public.korlix_live_convo_reserve_session(
  uuid, uuid, text, integer, integer, bigint, integer, integer
) from public, anon, authenticated;
revoke all on function public.korlix_live_convo_report_usage(
  uuid, uuid, integer, integer, bigint, bigint, bigint, bigint,
  bigint, bigint, bigint, integer, bigint, boolean, text
) from public, anon, authenticated;
revoke all on function public.korlix_live_convo_cancel_reservation(
  uuid, uuid, text
) from public, anon, authenticated;
revoke all on function public.korlix_live_convo_get_usage(
  uuid, text, integer, integer, bigint
) from public, anon, authenticated;

grant execute on function public.korlix_live_convo_reserve_session(
  uuid, uuid, text, integer, integer, bigint, integer, integer
) to service_role;
grant execute on function public.korlix_live_convo_report_usage(
  uuid, uuid, integer, integer, bigint, bigint, bigint, bigint,
  bigint, bigint, bigint, integer, bigint, boolean, text
) to service_role;
grant execute on function public.korlix_live_convo_cancel_reservation(
  uuid, uuid, text
) to service_role;
grant execute on function public.korlix_live_convo_get_usage(
  uuid, text, integer, integer, bigint
) to service_role;

-- KORLIX_LIVE_CONVO_BUILD129_SQL_END
