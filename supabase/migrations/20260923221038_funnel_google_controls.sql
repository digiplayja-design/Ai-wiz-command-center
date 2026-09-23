begin;
create table public.korlix_funnel_google_commands (
  id uuid primary key,
  campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  sequence integer not null check(sequence between 1 and 1000),
  action text not null check(action in ('activate','pause')),
  state text not null default 'unknown' check(state in ('unknown','confirmed')),
  fingerprint text not null check(fingerprint ~ '^[a-f0-9]{64}$'),
  observed jsonb not null check(jsonb_typeof(observed)='object' and octet_length(observed::text)<=16384),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unique(campaign_id,sequence),
  check((state='unknown' and confirmed_at is null) or (state='confirmed' and confirmed_at is not null))
);
create unique index korlix_funnel_google_commands_pending on public.korlix_funnel_google_commands(campaign_id) where state='unknown';
create index korlix_funnel_google_commands_owner on public.korlix_funnel_google_commands(user_id,created_at);
alter table public.korlix_funnel_google_commands enable row level security;
revoke all on public.korlix_funnel_google_commands from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_google_commands to service_role;
comment on table public.korlix_funnel_google_commands is 'Private serialized Google status command journal. Unknown blocks later commands permanently; observations never clear uncertainty. No tokens or automatic retry.';

create function public.korlix_funnel_google_controls_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; last_command public.korlix_funnel_google_commands;
  creation jsonb; snapshot jsonb; current_draft jsonb; checks jsonb; fp text; ready boolean; dispatch boolean:=false;
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
  checks:=jsonb_build_object(
    'platform_enabled',coalesce(p_data->'controls_enabled'='true'::jsonb,false),
    'creation_recorded',coalesce(creation->'attempt'->>'state'='created',false),
    'no_uncertain_command',coalesce(last_command.state<>'unknown',true),
    'command_capacity',coalesce(last_command.sequence,0)<1000,
    'preparation_current',creation->'preparation'->'preparation_complete',
    'saved_content_current',coalesce((snapshot-'identity'-'start_date'-'end_date'-'provider_name'-'no_eu_political_ads'-'budget_acknowledged')=(current_draft-'identity'),false),
    'schedule_open',coalesce((creation->>'today')::date<=(snapshot->>'end_date')::date,false));
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  fp:=encode(sha256(convert_to(jsonb_build_object('creation',creation->'fingerprint','attempt',creation->'attempt','checks',checks,'last',to_jsonb(last_command))::text,'UTF8')),'hex');
  if p_action='claim' then
    if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign or command record changed. Reload Google status.' using errcode='40001'; end if;
    if p_data->>'action' is null or p_data->>'action' not in ('activate','pause') or p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm a supported Google control.'; end if;
    if not (checks->>'platform_enabled')::boolean or not (checks->>'creation_recorded')::boolean or not (checks->>'no_uncertain_command')::boolean or not (checks->>'command_capacity')::boolean then raise exception 'Google controls are unavailable or a command outcome is uncertain.' using errcode='40001'; end if;
    if p_data->>'action'='activate' and (not ready or p_data->'spend_acknowledged' is distinct from 'true'::jsonb) then raise exception 'Activation requires current saved preparation and explicit spending authorization.'; end if;
    if not coalesce(jsonb_typeof(p_data->'observed')='object',false) then raise exception 'Reload Google status before confirming.'; end if;
    insert into public.korlix_funnel_google_commands(id,campaign_id,user_id,sequence,action,fingerprint,observed)
      values((p_data->>'command_id')::uuid,(p_data->>'campaign_id')::uuid,p_actor,coalesce(last_command.sequence,0)+1,p_data->>'action',fp,p_data->'observed') returning * into last_command;
    dispatch:=true;
  end if;
  return jsonb_build_object('source','google_campaign_controls','funnel_id',p_funnel,'campaign_id',creation->'campaign_id','creation',creation-'dispatch','checks',checks,'activation_ready',ready,'fingerprint',fp,
    'latest_command',case when last_command.id is null then null else to_jsonb(last_command)-'user_id'-'campaign_id'-'fingerprint' end,'dispatch',dispatch);
end $$;
revoke all on function public.korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb) to service_role;
commit;
