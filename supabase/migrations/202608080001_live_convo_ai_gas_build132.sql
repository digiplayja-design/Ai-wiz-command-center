-- KORLIX_AI_GAS_BUILD132_LIVE_CONVO_ELAPSED_GUARD_START
--
-- Private candidate only. Do not apply from this step.
--
-- The client is not the paid duration authority.
-- The session is locked before elapsed-time calculation.
-- Included monthly time is consumed before purchased AI GAS.
-- Unlimited users remain on the existing backend bypass path.

create or replace function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  p_session_id uuid,
  p_user_id uuid,
  p_response_count integer,
  p_total_tokens bigint,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_input_audio_tokens bigint,
  p_output_audio_tokens bigint,
  p_image_tokens bigint,
  p_transcription_tokens bigint,
  p_monthly_session_limit integer,
  p_monthly_duration_limit integer,
  p_monthly_token_limit bigint,
  p_ended boolean,
  p_end_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $korlix$
declare
  v_session public.korlix_live_convo_sessions%rowtype;

  v_now timestamptz :=
    clock_timestamp();

  v_elapsed_anchor timestamptz;

  v_previous_duration integer := 0;
  v_elapsed_increment integer := 0;
  v_authoritative_duration integer := 0;
  v_duration_delta integer := 0;

  v_max_session_seconds integer := 1;
  v_max_response_count integer := 1;
  v_response_count integer := 0;

  v_usage_before jsonb := '{}'::jsonb;
  v_usage_result jsonb := '{}'::jsonb;
  v_ai_gas_result jsonb := '{}'::jsonb;

  v_remaining_included_seconds integer := 0;
  v_remaining_monthly_tokens bigint := 0;

  v_included_seconds integer := 0;
  v_excess_seconds integer := 0;

  v_previous_total_tokens bigint := 0;
  v_requested_total_tokens bigint := 0;
  v_token_delta bigint := 0;

  v_ai_gas_consumed integer := 0;
  v_ai_gas_balance integer := 0;
  v_ai_gas_idempotent boolean := false;
  v_ai_gas_satisfied boolean := false;

  v_report_allowed boolean := true;
  v_report_monthly_limit boolean := false;
  v_report_session_limit boolean := false;

  v_session_limit_would_block boolean := false;
  v_token_limit_would_block boolean := false;
  v_final_allowed boolean := false;
begin
  if p_session_id is null
     or p_user_id is null then
    raise exception
      using
        errcode = '22023',
        message =
          'A valid LIVE CONVO session and user are required.',
        detail =
          'live_convo_ai_gas_identity_required';
  end if;

  select *
  into v_session
  from public.korlix_live_convo_sessions
  where id = p_session_id
    and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'allowed', false,
      'limitReached', false,
      'code', 'session_not_found',
      'message',
        'LIVE CONVO usage session was not found.',
      'sessionId', p_session_id,
      'serverElapsedGuard', true,
      'clientDurationAccepted', false
    );
  end if;

  v_previous_duration :=
    greatest(
      coalesce(
        v_session.duration_seconds,
        0
      ),
      0
    );

  v_max_session_seconds :=
    greatest(
      coalesce(
        v_session.max_duration_seconds,
        86400
      ),
      1
    );

  v_max_response_count :=
    greatest(
      coalesce(
        v_session.max_response_count,
        100000
      ),
      1
    );

  v_response_count :=
    greatest(
      coalesce(
        v_session.response_count,
        0
      ),
      greatest(
        coalesce(
          p_response_count,
          0
        ),
        0
      )
    );

  v_elapsed_anchor :=
    coalesce(
      v_session.last_seen_at,
      v_session.updated_at,
      v_now
    );

  if v_session.status = 'ended'
     or v_session.ended_at is not null then
    v_elapsed_increment := 0;
  else
    v_elapsed_increment :=
      greatest(
        floor(
          extract(
            epoch
            from (
              v_now
              - v_elapsed_anchor
            )
          )
        )::integer,
        0
      );
  end if;

  v_elapsed_increment :=
    least(
      v_elapsed_increment,
      greatest(
        v_max_session_seconds
        - v_previous_duration,
        0
      )
    );

  v_authoritative_duration :=
    least(
      v_max_session_seconds,
      greatest(
        v_previous_duration,
        v_previous_duration
        + v_elapsed_increment
      )
    );

  v_duration_delta :=
    greatest(
      v_authoritative_duration
      - v_previous_duration,
      0
    );

select public.korlix_live_convo_get_usage(
    p_user_id =>
      (p_user_id)::uuid,

    p_tier =>
      (v_session.tier)::text,

    p_monthly_session_limit =>
      (p_monthly_session_limit)::integer,

    p_monthly_duration_limit =>
      (p_monthly_duration_limit)::integer,

    p_monthly_token_limit =>
      (p_monthly_token_limit)::bigint
  )
  into v_usage_before;

  v_remaining_included_seconds :=
    greatest(
      coalesce(
        nullif(
          v_usage_before
          ->> 'remainingSeconds',
          ''
        )::integer,

        nullif(
          v_usage_before
          ->> 'remainingMonthlySeconds',
          ''
        )::integer,

        nullif(
          v_usage_before
          ->> 'remaining_seconds',
          ''
        )::integer,

        greatest(
          coalesce(
            p_monthly_duration_limit,
            0
          )
          - coalesce(
              nullif(
                v_usage_before
                ->> 'durationSeconds',
                ''
              )::integer,

              nullif(
                v_usage_before
                ->> 'duration_seconds',
                ''
              )::integer,

              0
            ),
          0
        )
      ),
      0
    );

  v_remaining_monthly_tokens :=
    greatest(
      coalesce(
        nullif(
          v_usage_before
          ->> 'remainingTokens',
          ''
        )::bigint,

        nullif(
          v_usage_before
          ->> 'remainingMonthlyTokens',
          ''
        )::bigint,

        nullif(
          v_usage_before
          ->> 'remaining_tokens',
          ''
        )::bigint,

        greatest(
          coalesce(
            p_monthly_token_limit,
            0
          )::bigint
          - coalesce(
              nullif(
                v_usage_before
                ->> 'totalTokens',
                ''
              )::bigint,

              nullif(
                v_usage_before
                ->> 'total_tokens',
                ''
              )::bigint,

              0
            ),
          0
        )
      ),
      0
    );

  v_included_seconds :=
    least(
      v_duration_delta,
      v_remaining_included_seconds
    );

  v_excess_seconds :=
    greatest(
      v_duration_delta
      - v_included_seconds,
      0
    );

  v_previous_total_tokens :=
    greatest(
      coalesce(
        v_session.total_tokens,
        0
      )::bigint,
      0
    );

  v_requested_total_tokens :=
    greatest(
      coalesce(
        p_total_tokens,
        0
      )::bigint,
      v_previous_total_tokens
    );

  v_token_delta :=
    greatest(
      v_requested_total_tokens
      - v_previous_total_tokens,
      0
    );

  v_token_limit_would_block :=
    v_token_delta
    > v_remaining_monthly_tokens;

  v_session_limit_would_block :=
    v_authoritative_duration
      >= v_max_session_seconds
    or v_response_count
      >= v_max_response_count;

  select public.korlix_live_convo_report_usage(
    p_session_id =>
      p_session_id,

    p_user_id =>
      p_user_id,

    p_duration_seconds =>
      v_authoritative_duration,

    p_response_count =>
      p_response_count,

    p_total_tokens =>
      p_total_tokens,

    p_input_tokens =>
      p_input_tokens,

    p_output_tokens =>
      p_output_tokens,

    p_input_audio_tokens =>
      p_input_audio_tokens,

    p_output_audio_tokens =>
      p_output_audio_tokens,

    p_image_tokens =>
      p_image_tokens,

    p_transcription_tokens =>
      p_transcription_tokens,

    p_monthly_duration_limit =>
      p_monthly_duration_limit,

    p_monthly_token_limit =>
      p_monthly_token_limit,

    p_ended =>
      p_ended,

    p_end_reason =>
      p_end_reason
  )
  into v_usage_result;

  v_report_allowed :=
    coalesce(
      nullif(
        v_usage_result
        ->> 'allowed',
        ''
      )::boolean,
      true
    );

  v_report_monthly_limit :=
    coalesce(
      nullif(
        v_usage_result
        ->> 'monthlyLimitReached',
        ''
      )::boolean,

      nullif(
        v_usage_result
        ->> 'monthly_limit_reached',
        ''
      )::boolean,

      false
    );

  v_report_session_limit :=
    coalesce(
      nullif(
        v_usage_result
        ->> 'sessionLimitReached',
        ''
      )::boolean,

      nullif(
        v_usage_result
        ->> 'session_limit_reached',
        ''
      )::boolean,

      false
    );

  if v_excess_seconds > 0 then
select public.korlix_ai_gas_consume(
      p_user_id =>
        (p_user_id)::uuid,

      p_seconds =>
        (v_excess_seconds)::integer,

      p_idempotency_key =>
        format(
          'live-convo:%s:%s:%s',
          p_user_id,
          p_session_id,
          v_authoritative_duration
        ),

      p_live_convo_session_id =>
        p_session_id::text,

      p_metadata =>
        (jsonb_build_object('source', 'live_convo', 'serverElapsedGuard', true, 'includedTimeFirst', true, 'authoritativeDurationSeconds', v_authoritative_duration, 'includedSecondsConsumed', v_included_seconds, 'excessSeconds', v_excess_seconds))::jsonb
    )
    into v_ai_gas_result;

    v_ai_gas_consumed :=
      greatest(
        coalesce(
          nullif(
            v_ai_gas_result
            ->> 'consumedSeconds',
            ''
          )::integer,

          nullif(
            v_ai_gas_result
            ->> 'consumed_seconds',
            ''
          )::integer,

          0
        ),
        0
      );

    v_ai_gas_balance :=
      greatest(
        coalesce(
          nullif(
            v_ai_gas_result
            ->> 'balanceSeconds',
            ''
          )::integer,

          nullif(
            v_ai_gas_result
            ->> 'balance_seconds',
            ''
          )::integer,

          0
        ),
        0
      );

    v_ai_gas_idempotent :=
      coalesce(
        nullif(
          v_ai_gas_result
          ->> 'idempotent',
          ''
        )::boolean,
        false
      );

    v_ai_gas_satisfied :=
      v_ai_gas_consumed
        >= v_excess_seconds
      or v_ai_gas_idempotent;

    if not v_ai_gas_satisfied then
      raise exception
        using
          errcode = 'P0001',
          message =
            'Additional AI GAS is required to continue LIVE CONVO.',
          detail =
            'ai_gas_insufficient_balance';
    end if;
  else
    v_ai_gas_satisfied := true;
  end if;

  v_final_allowed :=
    case
      when v_report_session_limit
        or v_session_limit_would_block
        or v_token_limit_would_block
      then false

      when v_report_allowed
      then true

      when v_report_monthly_limit
        and v_ai_gas_satisfied
      then true

      else false
    end;

  return
    coalesce(
      v_usage_result,
      '{}'::jsonb
    )
    || jsonb_build_object(
      'allowed',
        v_final_allowed,

      'limitReached',
        not v_final_allowed,

      'monthlyLimitReached',
        case
          when v_final_allowed
          then false
          else v_report_monthly_limit
        end,

      'code',
        case
          when v_final_allowed
          then null
          else v_usage_result ->> 'code'
        end,

      'message',
        case
          when v_final_allowed
          then null
          else v_usage_result ->> 'message'
        end,

      'sessionId',
        p_session_id,

      'serverElapsedGuard',
        true,

      'serverElapsedAnchor',
        'last_seen_at_or_updated_at',

      'serverElapsedSeconds',
        v_elapsed_increment,

      'authoritativeDurationSeconds',
        v_authoritative_duration,

      'previousDurationSeconds',
        v_previous_duration,

      'durationDeltaSeconds',
        v_duration_delta,

      'clientDurationAccepted',
        false,

      'consumptionOrder',
        'included_then_ai_gas',

      'includedSecondsConsumed',
        v_included_seconds,

      'aiGasSecondsRequired',
        v_excess_seconds,

      'aiGasSecondsConsumed',
        v_ai_gas_consumed,

      'aiGasSatisfied',
        v_ai_gas_satisfied,

      'aiGasBalanceSeconds',
        v_ai_gas_balance,

      'aiGas',
        coalesce(
          v_ai_gas_result,
          '{}'::jsonb
        )
    );
end;
$korlix$;

revoke all
on function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  uuid, uuid, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, integer, bigint, boolean, text
)
from public;

revoke all
on function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  uuid, uuid, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, integer, bigint, boolean, text
)
from anon;

revoke all
on function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  uuid, uuid, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, integer, bigint, boolean, text
)
from authenticated;

grant execute
on function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  uuid, uuid, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, integer, bigint, boolean, text
)
to service_role;

comment on function public.korlix_live_convo_report_usage_with_ai_gas_build132(
  uuid, uuid, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, integer, bigint, boolean, text
)
is
  'KORLIX Build 132 private server-elapsed LIVE CONVO reporting candidate. Included monthly time is consumed before AI GAS. Client duration is not the paid deduction authority.';

-- KORLIX_AI_GAS_BUILD132_LIVE_CONVO_ELAPSED_GUARD_END
