begin;
alter table public.korlix_funnel_google_commands drop constraint korlix_funnel_google_commands_action_check;
alter table public.korlix_funnel_google_commands add constraint korlix_funnel_google_commands_action_check check(action in ('activate','pause','budget'));
alter table public.korlix_funnel_google_commands add column daily_cents integer;
alter table public.korlix_funnel_google_commands add constraint korlix_funnel_google_commands_budget_check check(
  (action='budget' and daily_cents is not null and daily_cents between 100 and 1000000) or (action<>'budget' and daily_cents is null));
comment on table public.korlix_funnel_google_commands is 'Private serialized Google status and budget command journal. Unknown blocks all later commands; confirmed budget receipts determine the managed budget without rewriting creation history. No tokens or automatic retry.';
create or replace function public.korlix_funnel_google_controls_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; last_command public.korlix_funnel_google_commands;
  creation jsonb; snapshot jsonb; current_draft jsonb; checks jsonb; fp text; ready boolean; budget_enabled boolean; managed jsonb; budget_command public.korlix_funnel_google_commands; cents integer; dispatch boolean:=false;
begin
  if p_actor is null or p_action is null or p_action not in ('read','claim','finish') then raise exception 'Unknown Google controls action.'; end if;
  if p_action='finish' then
    -- Internal receipt persistence only; never authorizes another provider write.
    select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
    if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
    select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
    if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
    update public.korlix_funnel_google_commands set state='confirmed',confirmed_at=coalesce(confirmed_at,now())
      where id=(p_data->>'command_id')::uuid and campaign_id=c.id and user_id=p_actor returning * into last_command;
    if not found then raise exception 'Command not found.' using errcode='P0002'; end if;
    return jsonb_build_object('recorded',true);
  end if;
  -- Existing reader supplies entitlement and coherent funnel/campaign/connection
  -- locks in the established order. Preparation need not be current for pause.
  creation:=public.korlix_funnel_google_create_v1(p_actor,'read',p_funnel,p_data);
  select * into last_command from public.korlix_funnel_google_commands where campaign_id=(p_data->>'campaign_id')::uuid order by sequence desc limit 1 for update;
  snapshot:=creation->'attempt'->'snapshot';current_draft:=creation->'draft';
  budget_enabled:=coalesce(p_data->'controls_enabled'='true'::jsonb and p_data->'budget_enabled'='true'::jsonb,false);
  select * into budget_command from public.korlix_funnel_google_commands where campaign_id=(p_data->>'campaign_id')::uuid and action='budget' and state='confirmed' order by sequence desc limit 1;
  managed:=case when creation->'attempt'->>'state'='created' then jsonb_build_object(
    'daily_cents',coalesce(budget_command.daily_cents,(snapshot->'plan'->>'daily_cents')::integer),
    'original_daily_cents',(snapshot->'plan'->>'daily_cents')::integer,
    'command_id',budget_command.id,'confirmed_at',budget_command.confirmed_at) else null end;
  checks:=jsonb_build_object(
    'platform_enabled',coalesce(p_data->'controls_enabled'='true'::jsonb,false),
    'creation_recorded',coalesce(creation->'attempt'->>'state'='created',false),
    'no_uncertain_command',coalesce(last_command.state<>'unknown',true),
    'command_capacity',coalesce(last_command.sequence,0)<1000,
    'preparation_current',creation->'preparation'->'preparation_complete',
    'saved_content_current',coalesce((snapshot-'identity'-'start_date'-'end_date'-'provider_name'-'no_eu_political_ads'-'budget_acknowledged')=(current_draft-'identity'),false),
    'schedule_open',coalesce((creation->>'today')::date<=(snapshot->>'end_date')::date,false));
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  fp:=encode(sha256(convert_to(jsonb_build_object('creation',creation->'fingerprint','attempt',creation->'attempt','checks',checks,'last',to_jsonb(last_command),'budget_enabled',budget_enabled,'managed_budget',managed)::text,'UTF8')),'hex');
  if p_action='claim' then
    if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign or command record changed. Reload Google status.' using errcode='40001'; end if;
    if p_data->>'action' is null or p_data->>'action' not in ('activate','pause','budget') or p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm a supported Google control.'; end if;
    if not (checks->>'platform_enabled')::boolean or not (checks->>'creation_recorded')::boolean or not (checks->>'no_uncertain_command')::boolean or not (checks->>'command_capacity')::boolean then raise exception 'Google controls are unavailable or a command outcome is uncertain.' using errcode='40001'; end if;
    if p_data->>'action'='activate' and (not ready or p_data->'spend_acknowledged' is distinct from 'true'::jsonb) then raise exception 'Activation requires current saved preparation and explicit spending authorization.'; end if;
    if p_data->>'action'='budget' then
      if not budget_enabled or jsonb_typeof(p_data->'daily_cents') is distinct from 'number' or coalesce(p_data->>'daily_cents','') !~ '^[0-9]{3,7}$' then raise exception 'Confirm a supported average daily budget.'; end if;
      cents:=(p_data->>'daily_cents')::integer;
      if cents not between 100 and 1000000 or cents=(managed->>'daily_cents')::integer or p_data->'spend_acknowledged' is distinct from 'true'::jsonb then raise exception 'Confirm the changed average daily budget and spending impact.'; end if;
      if cents>(managed->>'daily_cents')::integer and not ready then raise exception 'A budget increase requires current saved preparation and an open schedule.' using errcode='40001'; end if;
      if p_data->'observed'->>'kind' is distinct from 'budget' or p_data->'observed'->'daily_cents' is distinct from p_data->'daily_cents' or p_data->'observed'->'budget'->'daily_cents' is distinct from managed->'daily_cents' then raise exception 'Reload the budget proposal before confirming.'; end if;
    elsif p_data ? 'daily_cents' then raise exception 'Status commands cannot change a budget.';
    end if;
    if not coalesce(jsonb_typeof(p_data->'observed')='object',false) then raise exception 'Reload Google status before confirming.'; end if;
    insert into public.korlix_funnel_google_commands(id,campaign_id,user_id,sequence,action,fingerprint,observed,daily_cents)
      values((p_data->>'command_id')::uuid,(p_data->>'campaign_id')::uuid,p_actor,coalesce(last_command.sequence,0)+1,p_data->>'action',fp,p_data->'observed',cents) returning * into last_command;
    dispatch:=true;
  end if;
  return jsonb_build_object('source','google_campaign_controls','funnel_id',p_funnel,'campaign_id',creation->'campaign_id','creation',creation-'dispatch','checks',checks,'activation_ready',ready,'fingerprint',fp,
    'budget_enabled',budget_enabled,'managed_budget',managed,'latest_command',case when last_command.id is null then null else to_jsonb(last_command)-'user_id'-'campaign_id'-'fingerprint' end,'dispatch',dispatch);
end $$;
revoke all on function public.korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb) to service_role;
commit;
