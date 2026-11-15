-- Esha-only provider spending guard. This does not activate AI, choose commercial
-- limits, change existing successful-consultation grants, or affect other apps.
create table public.korlix_esha_provider_budgets (
  period_key text primary key references public.korlix_esha_consultation_grants(period_key) on delete cascade,
  user_id uuid not null references public.korlix_esha_billing_accounts(user_id) on delete cascade,
  attempt_limit integer check (attempt_limit between 1 and 999999),
  used integer not null default 0 check (used >= 0),
  legacy_debits integer not null default 0 check (legacy_debits >= 0 and legacy_debits <= used),
  created_at timestamptz not null default now()
);
create index korlix_esha_provider_budgets_user on public.korlix_esha_provider_budgets(user_id);

-- Older code did not record whether a failed request reached the provider. Debit
-- each pre-migration request conservatively, including unfinished requests, so a
-- deployment cannot reset a partially used period's spending guard. No chosen
-- limit is stored until the server supplies its explicitly configured value.
insert into public.korlix_esha_provider_budgets(period_key,user_id,used,legacy_debits)
  select g.period_key,g.user_id,count(r.request_id)::integer,count(r.request_id)::integer
  from public.korlix_esha_consultation_grants g
  join public.korlix_esha_consultation_requests r on r.period_key=g.period_key
  group by g.period_key,g.user_id;

create table public.korlix_esha_provider_attempts (
  user_id uuid not null,
  request_id uuid not null,
  period_key text not null references public.korlix_esha_provider_budgets(period_key) on delete cascade,
  input_hash text not null check (input_hash ~ '^[a-f0-9]{64}$'),
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  model text not null,
  reasoning_effort text not null,
  input_tokens integer not null check (input_tokens > 0),
  max_input_tokens integer not null check (max_input_tokens between 1 and 922000 and input_tokens <= max_input_tokens),
  max_output_tokens integer not null check (max_output_tokens between 256 and 131072),
  started_at timestamptz not null default now(),
  primary key (user_id,request_id),
  foreign key (user_id,request_id) references public.korlix_esha_consultation_requests(user_id,request_id) on delete cascade,
  check ((model='gpt-6-astra' and reasoning_effort='max' and max_output_tokens>=32768) or
    (model='gpt-6-luna' and reasoning_effort='low' and max_output_tokens<=128000))
);
create index korlix_esha_provider_attempts_period on public.korlix_esha_provider_attempts(period_key);
alter table public.korlix_esha_provider_budgets enable row level security;
alter table public.korlix_esha_provider_attempts enable row level security;
revoke all on public.korlix_esha_provider_budgets,public.korlix_esha_provider_attempts from public,anon,authenticated;
grant select,insert,update on public.korlix_esha_provider_budgets to service_role;
grant select,insert on public.korlix_esha_provider_attempts to service_role;

create function public.korlix_esha_begin_provider_attempt(p_actor uuid,p jsonb)
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
      (p->>'model'='gpt-6-luna' and p->>'reasoning_effort'='low')) or p->>'model' is null or p->>'reasoning_effort' is null then
    raise exception 'ESHA503:provider_budget_unconfigured:Esha AI processing limits are being configured.';
  end if;
  tokens:=(p->>'input_tokens')::integer;
  input_cap:=(p->>'max_input_tokens')::integer;
  output_cap:=(p->>'max_output_tokens')::integer;
  if tokens>input_cap or input_cap>922000 or output_cap<256 or output_cap>131072 or
    (p->>'model'='gpt-6-astra' and output_cap<32768) or (p->>'model'='gpt-6-luna' and output_cap>128000) then
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
