-- Esha-only prepared voice accounting. No deployment or paid session activation.
-- All duration is integer milliseconds; reported fractions are rounded up by
-- the server. Reserved/uncertain time is never released by an elapsed lease.
create table public.korlix_esha_voice_budgets (
  period_key text primary key references public.korlix_esha_consultation_grants(period_key) on delete cascade,
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  limit_ms integer not null check (limit_ms in (300000,1800000)),
  used_ms bigint not null default 0 check (used_ms>=0),
  reserved_ms bigint not null default 0 check (reserved_ms>=0),
  created_at timestamptz not null default now()
);
create index korlix_esha_voice_budgets_user on public.korlix_esha_voice_budgets(user_id);
create table public.korlix_esha_voice_sessions (
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  request_id uuid not null,
  period_key text not null references public.korlix_esha_voice_budgets(period_key) on delete cascade,
  input_hash text not null check (input_hash~'^[a-f0-9]{64}$'),
  request_hash text check (request_hash is null or request_hash~'^[a-f0-9]{64}$'),
  model text not null default 'gpt-live-1' check (model='gpt-live-1'),
  deep_thinking_consent boolean not null default false,
  state text not null check (state in ('reserved','starting','active','closing','uncertain','closed','cancelled')),
  authorized_ms integer not null check (authorized_ms between 15000 and 1800000),
  reserved_ms bigint not null check (reserved_ms>=15000),
  usage_ms bigint not null default 0 check (usage_ms>=0),
  settled_ms bigint check (settled_ms>=0),
  provider_session_id text unique check (provider_session_id is null or provider_session_id~'^live_[A-Za-z0-9_-]{1,180}$'),
  provider_expires_at timestamptz,
  final_event_id text,
  final_reason text,
  uncertainty_reason text,
  close_reason text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  authorized_until timestamptz,
  close_requested_at timestamptz,
  finished_at timestamptz,
  primary key(user_id,request_id),
  check ((state in ('closed','cancelled'))=(settled_ms is not null)),
  check (state<>'cancelled' or (started_at is null and provider_session_id is null and settled_ms=0)),
  check (state<>'closed' or (provider_session_id is not null and final_event_id is not null))
);
create unique index korlix_esha_voice_one_unfinished on public.korlix_esha_voice_sessions(user_id)
  where state not in ('closed','cancelled');
create index korlix_esha_voice_sessions_period on public.korlix_esha_voice_sessions(period_key);
create index korlix_esha_voice_sessions_closure on public.korlix_esha_voice_sessions(authorized_until)
  where state not in ('closed','cancelled');
create table public.korlix_esha_voice_delegations (
  user_id uuid not null,
  voice_request_id uuid not null,
  delegation_id text not null check (delegation_id~'^[A-Za-z0-9_-]{1,200}$'),
  consultation_request_id uuid not null,
  input_hash text not null check (input_hash~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  primary key(user_id,voice_request_id,delegation_id),
  unique(user_id,consultation_request_id),
  foreign key(user_id,voice_request_id) references public.korlix_esha_voice_sessions(user_id,request_id) on delete cascade
);
alter table public.korlix_esha_voice_budgets enable row level security;
alter table public.korlix_esha_voice_sessions enable row level security;
alter table public.korlix_esha_voice_delegations enable row level security;
revoke all on public.korlix_esha_voice_budgets,public.korlix_esha_voice_sessions,public.korlix_esha_voice_delegations from public,anon,authenticated;
grant select,insert,update on public.korlix_esha_voice_budgets,public.korlix_esha_voice_sessions to service_role;
grant select,insert on public.korlix_esha_voice_delegations to service_role;

create function public.korlix_esha_voice_command(p_actor uuid,p_action text,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  t timestamptz;
  r public.korlix_esha_voice_sessions;
  budget public.korlix_esha_voice_budgets;
  chosen public.korlix_esha_purchases;
  g public.korlix_esha_consultation_grants;
  d public.korlix_esha_voice_delegations;
  billing jsonb;
  extra jsonb:='{}';
  answer jsonb;
  cap_ms integer;
  hold_ms integer;
  observed_ms bigint;
  charge_ms bigint;
  active_period boolean;
begin
  if p_actor is null then raise exception 'ESHA401:authentication_required:Sign in to use Esha.'; end if;
  if p_action not in ('snapshot','status','reserve','begin','attach','request_close','uncertain','usage','settle','delegation') then
    raise exception 'ESHA400:invalid_action:Unknown Esha voice action.';
  end if;
  if p->>'trial_limit_seconds' is distinct from '300' or p->>'monthly_limit_seconds' is distinct from '1800' then
    raise exception 'ESHA503:voice_allowance_unconfigured:Esha voice allowances do not match the approved offer.';
  end if;
  -- Same first account lock as consultation debit, refund and entitlement change.
  -- Snapshot may create the account through the existing membership RPC.
  if p_action='snapshot' then billing:=public.korlix_esha_billing_command(p_actor,'snapshot','{}'); end if;
  perform 1 from public.korlix_esha_billing_accounts where user_id=p_actor for update;
  if not found then raise exception 'ESHA404:voice_session_not_found:Voice session not found.'; end if;
  t:=clock_timestamp();
  if p_action<>'snapshot' then
    if coalesce(p->>'request_id','')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'ESHA400:invalid_voice_request:Send a valid voice request ID.';
    end if;
    select * into r from public.korlix_esha_voice_sessions where user_id=p_actor and request_id=(p->>'request_id')::uuid for update;
    if p_action<>'reserve' and not found then raise exception 'ESHA404:voice_session_not_found:Voice session not found.'; end if;
  end if;

  if p_action='reserve' then
    if coalesce(p->>'input_hash','')!~'^[a-f0-9]{64}$' or p->>'model' is distinct from 'gpt-live-1' or
      coalesce(p->>'reserve_seconds','')!~'^[1-9][0-9]{0,5}$' or
      jsonb_typeof(p->'deep_thinking_consent') is distinct from 'boolean' then
      raise exception 'ESHA400:invalid_voice_request:Send a valid voice reservation.';
    end if;
    hold_ms:=(p->>'reserve_seconds')::integer*1000;
    if hold_ms not between 15000 and 1800000 then
      raise exception 'ESHA503:voice_budget_unconfigured:Esha voice session bounds are being configured.';
    end if;
    if r.request_id is not null then
      if r.input_hash<>p->>'input_hash' or r.authorized_ms<>hold_ms or
        r.deep_thinking_consent<>(p->>'deep_thinking_consent')::boolean then
        raise exception 'ESHA409:idempotency_mismatch:This voice request ID has different content or bounds.';
      end if;
      extra:=jsonb_build_object('created',false,'replay',true);
    else
      if exists(select 1 from public.korlix_esha_voice_sessions where user_id=p_actor and state not in ('closed','cancelled')) then
        raise exception 'ESHA409:voice_session_in_progress:Finish reconciling the previous voice session first.';
      end if;
      select x.* into chosen from public.korlix_esha_purchases x where x.user_id=p_actor and x.active and not x.revoked and x.expires_at>t
        order by x.trial,x.expires_at desc,x.observed_at desc limit 1;
      if not found then raise exception 'ESHA402:membership_required:An active Esha membership is required.'; end if;
      if chosen.observed_at<t-interval '15 minutes' then
        raise exception 'ESHA503:verification_stale:Restore your membership so Esha can verify your access.';
      end if;
      select * into g from public.korlix_esha_consultation_grants where period_key=chosen.period_key and user_id=p_actor and not revoked and expires_at>t for update;
      if not found or g.quantity<>(case when chosen.trial then 2 else 10 end) then
        raise exception 'ESHA503:allowance_policy_mismatch:This Esha billing period needs the approved allowance configuration.';
      end if;
      if least(g.expires_at,chosen.expires_at)<t+make_interval(secs=>hold_ms/1000.0) then
        raise exception 'ESHA402:membership_expiring:This voice session would outlast the verified membership period.';
      end if;
      cap_ms:=case when g.trial then 300000 else 1800000 end;
      insert into public.korlix_esha_voice_budgets(period_key,user_id,limit_ms) values(g.period_key,p_actor,cap_ms) on conflict do nothing;
      select * into budget from public.korlix_esha_voice_budgets where period_key=g.period_key for update;
      if budget.user_id<>p_actor or budget.limit_ms<>cap_ms then
        raise exception 'ESHA409:period_ownership_mismatch:This voice billing period has incompatible ownership or limits.';
      end if;
      if budget.used_ms+budget.reserved_ms+hold_ms>budget.limit_ms then
        raise exception 'ESHA402:voice_allowance_exhausted:There is not enough unreserved voice time for this session.';
      end if;
      update public.korlix_esha_voice_budgets set reserved_ms=reserved_ms+hold_ms where period_key=g.period_key;
      insert into public.korlix_esha_voice_sessions(user_id,request_id,period_key,input_hash,deep_thinking_consent,state,authorized_ms,reserved_ms)
        values(p_actor,(p->>'request_id')::uuid,g.period_key,p->>'input_hash',(p->>'deep_thinking_consent')::boolean,'reserved',hold_ms,hold_ms)
        returning * into r;
      extra:=jsonb_build_object('created',true,'replay',false);
    end if;
  elsif p_action='begin' then
    if r.input_hash is distinct from p->>'input_hash' or coalesce(p->>'request_hash','')!~'^[a-f0-9]{64}$' or
      (r.request_hash is not null and r.request_hash<>p->>'request_hash') then
      raise exception 'ESHA409:idempotency_mismatch:This voice request was prepared with different content.';
    end if;
    if r.state<>'reserved' then extra:=jsonb_build_object('started',false,'duplicate',true);
    else
      select * into g from public.korlix_esha_consultation_grants where period_key=r.period_key and user_id=p_actor;
      select * into chosen from public.korlix_esha_purchases where purchase_key=g.purchase_key and user_id=p_actor;
      if g.period_key is null or g.revoked or chosen.purchase_key is null or not chosen.active or chosen.revoked or
        chosen.period_key<>r.period_key or least(g.expires_at,chosen.expires_at)<t+make_interval(secs=>r.authorized_ms/1000.0) then
        raise exception 'ESHA402:membership_required:An active Esha membership is required.';
      end if;
      if chosen.observed_at<t-interval '15 minutes' then
        raise exception 'ESHA503:verification_stale:Restore your membership so Esha can verify your access.';
      end if;
      update public.korlix_esha_voice_sessions set state='starting',request_hash=p->>'request_hash',started_at=t,
        authorized_until=t+make_interval(secs=>r.authorized_ms/1000.0) where user_id=p_actor and request_id=r.request_id returning * into r;
      extra:=jsonb_build_object('started',true,'duplicate',false);
    end if;
  elsif p_action='request_close' then
    if coalesce(p->>'reason','') not in ('user_stop','paused','background','transport_error') then
      raise exception 'ESHA400:invalid_voice_request:Send a valid voice stop reason.';
    end if;
    if r.state='reserved' then
      update public.korlix_esha_voice_budgets set reserved_ms=reserved_ms-r.reserved_ms where period_key=r.period_key;
      update public.korlix_esha_voice_sessions set state='cancelled',settled_ms=0,finished_at=t,close_requested_at=t,
        close_reason=p->>'reason',final_reason='not_started' where user_id=p_actor and request_id=r.request_id returning * into r;
    elsif r.state not in ('closed','cancelled') then
      update public.korlix_esha_voice_sessions set state='closing',close_requested_at=coalesce(close_requested_at,t),
        close_reason=coalesce(close_reason,p->>'reason') where user_id=p_actor and request_id=r.request_id returning * into r;
    end if;
  elsif p_action='uncertain' then
    if coalesce(p->>'reason','') not in ('create_unconfirmed','transport_lost','finalization_unconfirmed','storage_unconfirmed') then
      raise exception 'ESHA400:invalid_voice_request:Send a valid voice uncertainty reason.';
    end if;
    if r.state='reserved' then raise exception 'ESHA409:voice_not_started:This voice request has not been authorized to start.'; end if;
    if r.state not in ('closed','cancelled') then
      update public.korlix_esha_voice_sessions set state='uncertain',uncertainty_reason=p->>'reason'
        where user_id=p_actor and request_id=r.request_id returning * into r;
    end if;
  elsif p_action='attach' then
    if coalesce(p->>'provider_session_id','')!~'^live_[A-Za-z0-9_-]{1,180}$' or
      (p->>'provider_expires_at' is not null and not pg_catalog.isfinite((p->>'provider_expires_at')::timestamptz)) then
      raise exception 'ESHA502:invalid_voice_session:The voice provider returned an invalid session.';
    end if;
    if r.started_at is null or r.state in ('closed','cancelled') then
      raise exception 'ESHA409:voice_session_finished:This voice request cannot accept a provider session.';
    end if;
    if r.provider_session_id is not null and (r.provider_session_id<>p->>'provider_session_id' or
      (r.provider_expires_at is not null and p->>'provider_expires_at' is not null and
        r.provider_expires_at is distinct from (p->>'provider_expires_at')::timestamptz)) then
      raise exception 'ESHA409:idempotency_mismatch:This voice request already belongs to another provider session.';
    end if;
    update public.korlix_esha_voice_sessions set provider_session_id=p->>'provider_session_id',
      provider_expires_at=coalesce(provider_expires_at,(p->>'provider_expires_at')::timestamptz),
      state=case when close_requested_at is not null then 'closing'
        when coalesce(provider_expires_at,(p->>'provider_expires_at')::timestamptz) is not null then 'active' else 'starting' end
      where user_id=p_actor and request_id=r.request_id returning * into r;
  elsif p_action in ('usage','settle') then
    if r.provider_session_id is null or r.provider_session_id is distinct from p->>'provider_session_id' or
      coalesce(p->>'usage_ms','')!~'^[0-9]{1,12}$' then
      raise exception 'ESHA502:invalid_voice_usage:The voice provider returned invalid duration or session identity.';
    end if;
    observed_ms:=(p->>'usage_ms')::bigint;
    if p_action='settle' then
      if coalesce(p->>'final_event_id','')!~'^[A-Za-z0-9_-]{1,200}$' or
        coalesce(p->>'reason','') not in ('close_requested','expired','content','remote_hangup','connection_lost') then
        raise exception 'ESHA502:invalid_voice_usage:The voice provider returned an invalid final event.';
      end if;
      if observed_ms<r.usage_ms then
        raise exception 'ESHA409:voice_final_usage_conflict:Final voice duration is below previously observed cumulative usage.';
      end if;
      -- Customer minutes use trusted final duration only. The conservative
      -- 15-second startup reservation is not an invented minimum consumption.
      charge_ms:=observed_ms;
      if r.state='closed' then
        if r.settled_ms<>charge_ms or r.final_reason<>p->>'reason' then
          raise exception 'ESHA409:voice_final_usage_conflict:This finalized voice session has conflicting usage evidence.';
        end if;
        extra:=jsonb_build_object('duplicate',true);
      else
        -- Actual overshoot is retained honestly and blocks more reservations;
        -- it is never truncated to the authorization or allowance limit.
        update public.korlix_esha_voice_budgets set reserved_ms=reserved_ms-r.reserved_ms,used_ms=used_ms+charge_ms where period_key=r.period_key;
        update public.korlix_esha_voice_sessions set state='closed',usage_ms=greatest(usage_ms,observed_ms),settled_ms=charge_ms,
          final_event_id=p->>'final_event_id',final_reason=p->>'reason',finished_at=t
          where user_id=p_actor and request_id=r.request_id returning * into r;
      end if;
    elsif r.state='closed' then
      if observed_ms>r.settled_ms then raise exception 'ESHA409:voice_final_usage_conflict:This finalized voice session has conflicting usage evidence.'; end if;
    else
      if observed_ms>r.reserved_ms then
        update public.korlix_esha_voice_budgets set reserved_ms=reserved_ms+observed_ms-r.reserved_ms where period_key=r.period_key;
      end if;
      update public.korlix_esha_voice_sessions set usage_ms=greatest(usage_ms,observed_ms),reserved_ms=greatest(reserved_ms,observed_ms)
        where user_id=p_actor and request_id=r.request_id returning * into r;
    end if;
  elsif p_action='delegation' then
    if r.provider_session_id is null or r.provider_session_id is distinct from p->>'provider_session_id' or
      coalesce(p->>'delegation_id','')!~'^[A-Za-z0-9_-]{1,200}$' or coalesce(p->>'input_hash','')!~'^[a-f0-9]{64}$' or
      coalesce(p->>'consultation_request_id','')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'ESHA400:invalid_voice_delegation:Invalid voice delegation identity.';
    end if;
    if not r.deep_thinking_consent then raise exception 'ESHA403:deep_thinking_consent_required:Enable deep thinking before starting a new voice session.'; end if;
    if r.state<>'active' or r.authorized_until<=t or r.usage_ms>=r.authorized_ms then
      raise exception 'ESHA409:voice_session_finished:This voice session is no longer accepting deep-thinking requests.';
    end if;
    select * into g from public.korlix_esha_consultation_grants where period_key=r.period_key and user_id=p_actor;
    select * into chosen from public.korlix_esha_purchases where purchase_key=g.purchase_key and user_id=p_actor;
    if g.period_key is null or g.revoked or chosen.purchase_key is null or not chosen.active or chosen.revoked or
      chosen.period_key<>r.period_key or least(g.expires_at,chosen.expires_at)<=t then
      raise exception 'ESHA402:membership_required:An active Esha membership is required.';
    end if;
    if chosen.observed_at<t-interval '15 minutes' then raise exception 'ESHA503:verification_stale:Restore your membership so Esha can verify your access.'; end if;
    select * into d from public.korlix_esha_voice_delegations
      where user_id=p_actor and voice_request_id=r.request_id and delegation_id=p->>'delegation_id';
    if found then
      if d.input_hash<>p->>'input_hash' then raise exception 'ESHA409:idempotency_mismatch:This delegation has different content.'; end if;
      extra:=jsonb_build_object('created',false,'consultationRequestId',d.consultation_request_id);
    else
      if g.used+g.reserved>=g.quantity then raise exception 'ESHA402:allowance_exhausted:No deep-thinking consultations remain in this billing period.'; end if;
      if exists(select 1 from public.korlix_esha_consultation_requests where user_id=p_actor and request_id=(p->>'consultation_request_id')::uuid) then
        raise exception 'ESHA409:idempotency_mismatch:This consultation request ID was already used outside this delegation.';
      end if;
      insert into public.korlix_esha_voice_delegations(user_id,voice_request_id,delegation_id,consultation_request_id,input_hash)
        values(p_actor,r.request_id,p->>'delegation_id',(p->>'consultation_request_id')::uuid,p->>'input_hash');
      extra:=jsonb_build_object('created',true,'consultationRequestId',p->>'consultation_request_id');
    end if;
  end if;

  billing:=public.korlix_esha_billing_command(p_actor,'snapshot','{}');
  if r.request_id is not null then
    select * into g from public.korlix_esha_consultation_grants where period_key=r.period_key and user_id=p_actor;
    select * into chosen from public.korlix_esha_purchases where purchase_key=g.purchase_key and user_id=p_actor;
  else
    select x.* into chosen from public.korlix_esha_purchases x where x.user_id=p_actor
      order by (x.active and not x.revoked and x.expires_at>t) desc,x.trial,x.expires_at desc,x.observed_at desc limit 1;
    select * into g from public.korlix_esha_consultation_grants where period_key=chosen.period_key and user_id=p_actor;
  end if;
  select * into budget from public.korlix_esha_voice_budgets where period_key=g.period_key and user_id=p_actor;
  cap_ms:=coalesce(budget.limit_ms,case when g.period_key is not null then case when g.trial then 300000 else 1800000 end end);
  active_period:=coalesce(chosen.active and not chosen.revoked and chosen.period_key=g.period_key and not g.revoked and
    least(g.expires_at,chosen.expires_at)>t,false);
  answer:=jsonb_build_object('membership',billing->'membership','usage',jsonb_build_object(
    'voice',jsonb_build_object('configured',g.period_key is not null,'limitSeconds',cap_ms/1000.0,
      'usedSeconds',coalesce(budget.used_ms,0)/1000.0,'reservedSeconds',coalesce(budget.reserved_ms,0)/1000.0,
      'remainingSeconds',case when active_period then greatest(0,cap_ms-coalesce(budget.used_ms,0)-coalesce(budget.reserved_ms,0))/1000.0 else 0 end,
      'periodEndsAt',g.expires_at),
    'deep',jsonb_build_object('configured',g.period_key is not null,'limit',g.quantity,'used',coalesce(g.used,0),
      'reserved',coalesce(g.reserved,0),'remaining',case when active_period then greatest(0,g.quantity-g.used-g.reserved) else 0 end,'periodEndsAt',g.expires_at)));
  if r.request_id is not null then
    answer:=answer||jsonb_build_object('requestId',r.request_id,'sessionId',r.provider_session_id,'model',r.model,
      'state',case when r.state='cancelled' then 'closed' else r.state end,'finalizationConfirmed',r.state in ('closed','cancelled'),
      'deepThinkingConsent',r.deep_thinking_consent,'authorizedSeconds',r.authorized_ms/1000.0,'observedSeconds',r.usage_ms/1000.0,
      'settledSeconds',r.settled_ms/1000.0,'authorizedUntil',r.authorized_until,'providerExpiresAt',r.provider_expires_at,
      'closeRequested',r.close_requested_at is not null,'closeRequired',r.state not in ('closed','cancelled') and
        (r.state in ('closing','uncertain') or not active_period or chosen.observed_at<t-interval '15 minutes' or
          coalesce(r.authorized_until<=t,false) or r.usage_ms>=r.authorized_ms),
      'overrun',greatest(r.usage_ms,coalesce(r.settled_ms,0))>r.authorized_ms,'finalReason',r.final_reason);
    if p_action='status' then
      -- A charged Sol response can finish after voice closes. Return only the
      -- already validated saved result, scoped by this account/session/mapping.
      answer:=answer||jsonb_build_object('deepResults',coalesce((
        select jsonb_agg(x.result) from (
          select jsonb_build_object('requestId',q.request_id,'answer',q.result->'answer','productIds',q.result->'productIds') result
          from public.korlix_esha_voice_delegations mapped
          join public.korlix_esha_consultation_requests q on q.user_id=mapped.user_id and q.request_id=mapped.consultation_request_id
          where mapped.user_id=p_actor and mapped.voice_request_id=r.request_id and q.state='committed' and q.input_hash=mapped.input_hash
          order by q.finished_at desc,q.request_id limit 10
        )x),'[]'::jsonb));
    end if;
  end if;
  return answer||extra;
end $$;
revoke all on function public.korlix_esha_voice_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_esha_voice_command(uuid,text,jsonb) to service_role;
