begin;
alter table public.korlix_funnel_meta_commands drop constraint korlix_funnel_meta_commands_action_check;
alter table public.korlix_funnel_meta_commands add constraint korlix_funnel_meta_commands_action_check check(action in ('activate','pause','budget'));
alter table public.korlix_funnel_meta_commands add column daily_cents integer;
alter table public.korlix_funnel_meta_commands add constraint korlix_funnel_meta_commands_budget_check check((action='budget' and daily_cents is not null and daily_cents between 100 and 1000000) or (action<>'budget' and daily_cents is null));
alter table public.korlix_funnel_meta_commands drop constraint korlix_funnel_meta_commands_check;
alter table public.korlix_funnel_meta_commands add constraint korlix_funnel_meta_commands_check check((action='budget' and steps='["budget"]'::jsonb) or (action='pause' and steps='["campaign"]'::jsonb) or (action='activate' and steps in ('["ad","ad_set","campaign"]'::jsonb,'["ad","campaign"]'::jsonb,'["ad_set","campaign"]'::jsonb,'["campaign"]'::jsonb)));
alter table public.korlix_funnel_meta_commands drop constraint korlix_funnel_meta_commands_progress_check;
alter table public.korlix_funnel_meta_commands add constraint korlix_funnel_meta_commands_progress_check check(jsonb_typeof(progress)='object' and octet_length(progress::text)<=256 and ((action='budget' and progress in ('{}'::jsonb,jsonb_build_object('budget',daily_cents))) or (action<>'budget' and (progress-array['ad','ad_set','campaign'])='{}'::jsonb)));
comment on table public.korlix_funnel_meta_commands is 'Private serialized Meta status and budget journal. Unknown blocks all subsequent commands. Confirmed budget receipts determine the managed amount without changing creation history. No retry or automatic settlement.';
create or replace function public.korlix_funnel_meta_controls_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels;c public.korlix_funnel_campaigns;cmd public.korlix_funnel_meta_commands;
 creation jsonb;snapshot jsonb;draft jsonb;checks jsonb;fp text;ready boolean;budget_enabled boolean;managed jsonb;budget_command public.korlix_funnel_meta_commands;cents integer;dispatch boolean:=false;steps jsonb;stage text;target text;n integer;
begin
 if p_actor is null or p_action is null or p_action not in ('read','claim','progress','finish') then raise exception 'Unknown Meta controls action.';end if;
 if p_action in ('progress','finish') then
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002';end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002';end if;
  select * into cmd from public.korlix_funnel_meta_commands where id=(p_data->>'command_id')::uuid and campaign_id=c.id and user_id=p_actor for update;
  if not found then raise exception 'Command not found.' using errcode='P0002';end if;
  select count(*) into n from jsonb_object_keys(cmd.progress);
  if p_action='progress' and cmd.action='budget' then
   if cmd.state<>'unknown' or n<>0 or p_data->>'stage' is distinct from 'budget' or p_data->'daily_cents' is distinct from to_jsonb(cmd.daily_cents) or p_data ? 'status' then raise exception 'The budget receipt is inconsistent or already recorded.' using errcode='40001';end if;
   if p_data->>'resource' is distinct from (select resources->>'ad_set' from public.korlix_funnel_meta_creations where campaign_id=c.id and user_id=p_actor and state='created') then raise exception 'The budget receipt does not match the saved ad set.' using errcode='40001';end if;
   update public.korlix_funnel_meta_commands set progress=jsonb_build_object('budget',cmd.daily_cents) where id=cmd.id;
  elsif p_action='progress' then
   stage:=p_data->>'stage';target:=case when cmd.action='activate' then 'ACTIVE' else 'PAUSED' end;
   if cmd.state<>'unknown' or stage is distinct from cmd.steps->>n or p_data->>'status' is distinct from target then raise exception 'Meta command progress cannot be repeated or reordered.' using errcode='40001';end if;
   if p_data->>'resource' is distinct from (select resources->>stage from public.korlix_funnel_meta_creations where campaign_id=c.id and user_id=p_actor and state='created') then raise exception 'The Meta receipt does not match the saved resource.' using errcode='40001';end if;
   update public.korlix_funnel_meta_commands set progress=progress||jsonb_build_object(stage,target) where id=cmd.id;
  else
   if n<>jsonb_array_length(cmd.steps) then raise exception 'All command receipts are required before completion.' using errcode='40001';end if;
   update public.korlix_funnel_meta_commands set state='confirmed',confirmed_at=coalesce(confirmed_at,now()) where id=cmd.id;
  end if;
  return jsonb_build_object('recorded',true);
 end if;
 creation:=public.korlix_funnel_meta_create_v1(p_actor,'read',p_funnel,p_data);
 select * into cmd from public.korlix_funnel_meta_commands where campaign_id=(p_data->>'campaign_id')::uuid order by sequence desc limit 1 for update;
 snapshot:=creation->'attempt'->'snapshot';draft:=creation->'draft';
 budget_enabled:=coalesce(p_data->'controls_enabled'='true'::jsonb and p_data->'budget_enabled'='true'::jsonb,false);
 select * into budget_command from public.korlix_funnel_meta_commands where campaign_id=(p_data->>'campaign_id')::uuid and action='budget' and state='confirmed' order by sequence desc limit 1;
 managed:=case when creation->'attempt'->>'state'='created' then jsonb_build_object('daily_cents',coalesce(budget_command.daily_cents,(snapshot->'plan'->>'daily_cents')::integer),'original_daily_cents',(snapshot->'plan'->>'daily_cents')::integer,'command_id',budget_command.id,'confirmed_at',budget_command.confirmed_at) else null end;
 checks:=jsonb_build_object(
  'platform_enabled',coalesce(p_data->'controls_enabled'='true'::jsonb,false),
  'creation_recorded',coalesce(creation->'attempt'->>'state'='created',false),
  'no_uncertain_command',coalesce(cmd.state<>'unknown',true),
  'command_capacity',coalesce(cmd.sequence,0)<1000,
  'preparation_current',coalesce(creation->'preparation'->'review_current'='true'::jsonb and creation->'preparation'->'creative'->'setup'->'review_current'='true'::jsonb,false),
  'saved_content_current',coalesce((snapshot-array['identity','start_date','end_date','start_time','end_time','provider_name','budget_acknowledged'])=(draft-'identity'),false),
  'identity_current',coalesce(snapshot->'identity'->'account'=draft->'identity'->'account' and snapshot->'identity'->'page'=draft->'identity'->'page',false),
  'schedule_open',coalesce(now()<=(snapshot->>'end_time')::timestamptz,false));
 select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
 fp:=encode(sha256(convert_to(jsonb_build_object('creation',creation->'fingerprint','attempt',creation->'attempt','checks',checks,'last',to_jsonb(cmd),'budget_enabled',budget_enabled,'managed_budget',managed)::text,'UTF8')),'hex');
 if p_action='claim' then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign or command record changed. Reload Meta status.' using errcode='40001';end if;
  if p_data->>'action' is null or p_data->>'action' not in ('activate','pause','budget') or p_data->'confirmed' is distinct from 'true'::jsonb or p_data->'spend_acknowledged' is distinct from to_jsonb(p_data->>'action' in ('activate','budget')) then raise exception 'Confirm this Meta command and its spending impact.';end if;
  if not(checks->>'platform_enabled')::boolean or not(checks->>'creation_recorded')::boolean or not(checks->>'no_uncertain_command')::boolean or not(checks->>'command_capacity')::boolean then raise exception 'Meta controls are unavailable or a command outcome is uncertain.' using errcode='40001';end if;
  if p_data->'observed'->'status'->>'resource' is distinct from creation->'attempt'->'resources'->>'campaign' then raise exception 'Reload the saved Meta campaign status.';end if;
  steps:='[]'::jsonb;
  if p_data->>'action'='budget' then
   if not budget_enabled or jsonb_typeof(p_data->'daily_cents') is distinct from 'number' or coalesce(p_data->>'daily_cents','') !~ '^[0-9]{3,7}$' then raise exception 'Confirm a supported average daily budget.';end if;
   cents:=(p_data->>'daily_cents')::integer;
   if cents not between 100 and 1000000 or cents=(managed->>'daily_cents')::integer then raise exception 'Confirm a changed average daily budget.';end if;
   if cents>(managed->>'daily_cents')::integer and not ready then raise exception 'A budget increase requires current saved preparation and an open schedule.' using errcode='40001';end if;
   if p_data->'observed'->>'kind' is distinct from 'budget' or p_data->'observed'->'daily_cents' is distinct from p_data->'daily_cents' or p_data->'observed'->'budget'->'daily_cents' is distinct from managed->'daily_cents' or p_data->'observed'->'budget'->>'resource' is distinct from creation->'attempt'->'resources'->>'ad_set' or not coalesce(p_data->'observed'->'status'->>'status' in ('PAUSED','ACTIVE'),false) or not coalesce(p_data->'observed'->'budget'->>'status' in ('PAUSED','ACTIVE'),false) then raise exception 'Reload the exact saved Meta budget before confirming.';end if;
   if p_data->'observed'->'increase' is distinct from to_jsonb(cents>(managed->>'daily_cents')::integer) then raise exception 'Reload the budget proposal.';end if;
   if cents>(managed->>'daily_cents')::integer and p_data->'observed'->'graph'->'resources' is distinct from creation->'attempt'->'resources' then raise exception 'Reload the saved campaign graph.';end if;
   steps:='["budget"]'::jsonb;
  elsif p_data ? 'daily_cents' then raise exception 'Status commands cannot change a budget.';
  elsif p_data->>'action'='activate' then
   if not ready or p_data->'observed'->'can_activate' is distinct from 'true'::jsonb or p_data->'observed'->'status'->>'status' is distinct from 'PAUSED' or p_data->'observed'->'graph'->'resources' is distinct from creation->'attempt'->'resources' then raise exception 'Activation requires current preparation, matching saved content and explicit spending authorization.';end if;
   for stage in select unnest(array['ad','ad_set']) loop
    if p_data->'observed'->'graph'->'statuses'->>stage='PAUSED' then steps:=steps||jsonb_build_array(stage);
    elsif p_data->'observed'->'graph'->'statuses'->>stage is distinct from 'ACTIVE' then raise exception 'Reload Meta child resource status.';end if;
   end loop;
   if p_data->'observed'->'graph'->'statuses'->>'campaign' is distinct from 'PAUSED' then raise exception 'Reload the paused Meta campaign.';end if;
  elsif p_data->'observed'->'can_pause' is distinct from 'true'::jsonb or p_data->'observed'->'status'->>'status' is distinct from 'ACTIVE' then raise exception 'Reload the active Meta campaign before pausing.';
  end if;
  if p_data->>'action'<>'budget' then steps:=steps||'["campaign"]'::jsonb;end if;
  insert into public.korlix_funnel_meta_commands(id,campaign_id,user_id,sequence,action,fingerprint,observed,steps,daily_cents)
   values((p_data->>'command_id')::uuid,(p_data->>'campaign_id')::uuid,p_actor,coalesce(cmd.sequence,0)+1,p_data->>'action',fp,p_data->'observed',steps,cents) returning * into cmd;
  dispatch:=true;
 end if;
 return jsonb_build_object('source','meta_campaign_controls','funnel_id',p_funnel,'campaign_id',creation->'campaign_id','creation',creation-array['dispatch','proposal'],'checks',checks,'activation_ready',ready,'fingerprint',fp,'budget_enabled',budget_enabled,'managed_budget',managed,'latest_command',case when cmd.id is null then null else to_jsonb(cmd)-array['user_id','campaign_id','fingerprint'] end,'dispatch',dispatch);
end $$;
revoke all on function public.korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb) to service_role;
commit;
