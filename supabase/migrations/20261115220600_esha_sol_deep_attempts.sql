-- Add only Esha's owner-selected Sol/high path. Legacy Astra/max and Luna/low
-- constraints, token checks, immutable period caps and debit semantics remain.
-- This file does not enable a model, choose engineering caps or activate voice.
-- The original multi-column input-token CHECK is named ..._check; preserve it.
-- PostgreSQL names the following model/effort CHECK ..._check1.
alter table public.korlix_esha_provider_attempts drop constraint korlix_esha_provider_attempts_check1;
alter table public.korlix_esha_provider_attempts add constraint korlix_esha_provider_attempts_check1
  check ((model='gpt-6-astra' and reasoning_effort='max' and max_output_tokens>=32768) or
    (model='gpt-6-luna' and reasoning_effort='low' and max_output_tokens<=128000) or
    (model='gpt-6.1-sol' and reasoning_effort='high' and max_output_tokens<=128000));

create or replace function public.korlix_esha_begin_provider_attempt(p_actor uuid,p jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  t timestamptz;
  r public.korlix_esha_consultation_requests;
  g public.korlix_esha_consultation_grants;
  purchase public.korlix_esha_purchases;
  budget public.korlix_esha_provider_budgets;
  attempt public.korlix_esha_provider_attempts;
  cap integer;
  tokens integer;
  input_cap integer;
  output_cap integer;
begin
  if p_actor is null then raise exception 'ESHA401:authentication_required:Sign in to use Esha.'; end if;
  if coalesce(p->>'request_id','')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' or
    coalesce(p->>'input_hash','')!~'^[a-f0-9]{64}$' or coalesce(p->>'request_hash','')!~'^[a-f0-9]{64}$' or
    coalesce(p->>'trial_limit','')!~'^[1-9][0-9]{0,5}$' or coalesce(p->>'monthly_limit','')!~'^[1-9][0-9]{0,5}$' or
    coalesce(p->>'input_tokens','')!~'^[1-9][0-9]{0,5}$' or coalesce(p->>'max_input_tokens','')!~'^[1-9][0-9]{0,5}$' or
    coalesce(p->>'max_output_tokens','')!~'^[1-9][0-9]{0,5}$' or
    not ((p->>'model'='gpt-6-astra' and p->>'reasoning_effort'='max') or
      (p->>'model'='gpt-6-luna' and p->>'reasoning_effort'='low') or
      (p->>'model'='gpt-6.1-sol' and p->>'reasoning_effort'='high')) or p->>'model' is null or p->>'reasoning_effort' is null then
    raise exception 'ESHA503:provider_budget_unconfigured:Esha AI processing limits are being configured.';
  end if;
  tokens:=(p->>'input_tokens')::integer;
  input_cap:=(p->>'max_input_tokens')::integer;
  output_cap:=(p->>'max_output_tokens')::integer;
  if tokens>input_cap or input_cap>922000 or output_cap<256 or output_cap>131072 or
    (p->>'model'='gpt-6-astra' and output_cap<32768) or (p->>'model' in ('gpt-6-luna','gpt-6.1-sol') and output_cap>128000) then
    raise exception 'ESHA503:provider_budget_unconfigured:Esha AI processing limits are being configured.';
  end if;

  -- Same first lock as reserve/commit/refund. This serializes both competing
  -- requests and receipt changes before any paid network request is authorized.
  perform 1 from public.korlix_esha_billing_accounts where user_id=p_actor for update;
  if not found then raise exception 'ESHA404:request_not_found:Consultation request not found.'; end if;
  t:=clock_timestamp();
  select * into r from public.korlix_esha_consultation_requests
    where user_id=p_actor and request_id=(p->>'request_id')::uuid for update;
  if not found then raise exception 'ESHA404:request_not_found:Consultation request not found.'; end if;
  if r.input_hash<>p->>'input_hash' then raise exception 'ESHA409:idempotency_mismatch:This request ID has different content.'; end if;
  select * into attempt from public.korlix_esha_provider_attempts where user_id=p_actor and request_id=r.request_id;
  if found then
    if attempt.request_hash<>p->>'request_hash' then raise exception 'ESHA409:idempotency_mismatch:This request was already prepared with different content.'; end if;
    return jsonb_build_object('started',false,'duplicate',true);
  end if;
  if r.state<>'reserved' or r.deadline<=t then
    raise exception 'ESHA409:request_finished:This consultation request has ended.';
  end if;
  select * into g from public.korlix_esha_consultation_grants where period_key=r.period_key and user_id=p_actor for update;
  if not found or g.revoked or g.expires_at<=t then
    raise exception 'ESHA402:membership_required:An active Esha membership is required.';
  end if;
  select * into purchase from public.korlix_esha_purchases where purchase_key=g.purchase_key and user_id=p_actor;
  if not found or not purchase.active or purchase.revoked or purchase.period_key<>r.period_key or purchase.expires_at<=t then
    raise exception 'ESHA402:membership_required:An active Esha membership is required.';
  end if;
  if purchase.observed_at<t-interval '15 minutes' then
    raise exception 'ESHA503:verification_stale:Restore your membership so Esha can verify your access.';
  end if;
  if p->>'model'='gpt-6.1-sol' then
    if g.quantity<>(case when g.trial then 2 else 10 end) then
      raise exception 'ESHA503:allowance_policy_mismatch:This Esha billing period needs the approved deep-thinking allowance.';
    end if;
    -- A voice delegation remains attached to its consented, active session and
    -- original store period at the irreversible provider debit boundary.
    if exists(select 1 from public.korlix_esha_voice_delegations d
      where d.user_id=p_actor and d.consultation_request_id=r.request_id) and not exists(
      select 1 from public.korlix_esha_voice_delegations d
      join public.korlix_esha_voice_sessions v on v.user_id=d.user_id and v.request_id=d.voice_request_id
      where d.user_id=p_actor and d.consultation_request_id=r.request_id and d.input_hash=r.input_hash and v.period_key=r.period_key and
        v.deep_thinking_consent and v.state='active' and v.authorized_until>t and v.usage_ms<v.authorized_ms) then
      raise exception 'ESHA409:voice_session_finished:This voice session no longer authorizes deep thinking.';
    end if;
  end if;
  cap:=case when g.trial then (p->>'trial_limit')::integer else (p->>'monthly_limit')::integer end;
  insert into public.korlix_esha_provider_budgets(period_key,user_id,attempt_limit)
    values(g.period_key,p_actor,cap) on conflict do nothing;
  select * into budget from public.korlix_esha_provider_budgets where period_key=g.period_key for update;
  if budget.user_id<>p_actor then raise exception 'ESHA409:period_ownership_mismatch:This billing period belongs to another account.'; end if;
  if budget.attempt_limit is null then
    update public.korlix_esha_provider_budgets set attempt_limit=cap where period_key=g.period_key;
    budget.attempt_limit:=cap;
  end if;
  -- Restores and configuration changes cannot refill or raise a period's cap.
  if budget.used>=budget.attempt_limit then
    return jsonb_build_object('started',false,'exhausted',true);
  end if;
  update public.korlix_esha_provider_budgets set used=used+1 where period_key=g.period_key;
  insert into public.korlix_esha_provider_attempts(user_id,request_id,period_key,input_hash,request_hash,
    model,reasoning_effort,input_tokens,max_input_tokens,max_output_tokens,started_at)
    values(p_actor,r.request_id,g.period_key,r.input_hash,p->>'request_hash',p->>'model',p->>'reasoning_effort',
      tokens,input_cap,output_cap,t);
  -- This debit is never released, even on timeout, invalid JSON, process crash,
  -- failed commit, or an ambiguous database/network response.
  return jsonb_build_object('started',true);
end $$;
revoke all on function public.korlix_esha_begin_provider_attempt(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_esha_begin_provider_attempt(uuid,jsonb) to service_role;
