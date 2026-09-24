begin;
create table public.korlix_funnel_meta_commands (
 id uuid primary key,
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 sequence integer not null check(sequence between 1 and 1000),
 action text not null check(action in ('activate','pause')),
 state text not null default 'unknown' check(state in ('unknown','confirmed')),
 fingerprint text not null check(fingerprint ~ '^[a-f0-9]{64}$'),
 observed jsonb not null check(jsonb_typeof(observed)='object' and octet_length(observed::text)<=16384),
 steps jsonb not null check(steps in ('["ad","ad_set","campaign"]'::jsonb,'["ad","campaign"]'::jsonb,'["ad_set","campaign"]'::jsonb,'["campaign"]'::jsonb) and (action='activate' or steps='["campaign"]'::jsonb)),
 progress jsonb not null default '{}' check(jsonb_typeof(progress)='object' and (progress-array['ad','ad_set','campaign'])='{}'::jsonb and octet_length(progress::text)<=256),
 created_at timestamptz not null default now(),
 confirmed_at timestamptz,
 unique(campaign_id,sequence),
 check((state='unknown' and confirmed_at is null) or (state='confirmed' and confirmed_at is not null and jsonb_array_length(steps)=jsonb_array_length(jsonb_path_query_array(progress,'$.keyvalue()'))))
);
create unique index korlix_funnel_meta_commands_pending on public.korlix_funnel_meta_commands(campaign_id) where state='unknown';
create index korlix_funnel_meta_commands_owner on public.korlix_funnel_meta_commands(user_id,created_at);
alter table public.korlix_funnel_meta_commands enable row level security;
revoke all on public.korlix_funnel_meta_commands from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_meta_commands to service_role;
comment on table public.korlix_funnel_meta_commands is 'Private serialized Meta status journal. Activation enables paused children first and campaign last. Ordered partial receipts remain unknown on any failure; no retry, resume or automatic settlement.';
create function public.korlix_funnel_meta_controls_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels;c public.korlix_funnel_campaigns;cmd public.korlix_funnel_meta_commands;
 creation jsonb;snapshot jsonb;draft jsonb;checks jsonb;fp text;ready boolean;dispatch boolean:=false;steps jsonb;stage text;target text;n integer;
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
  if p_action='progress' then
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
 fp:=encode(sha256(convert_to(jsonb_build_object('creation',creation->'fingerprint','attempt',creation->'attempt','checks',checks,'last',to_jsonb(cmd))::text,'UTF8')),'hex');
 if p_action='claim' then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign or command record changed. Reload Meta status.' using errcode='40001';end if;
  if p_data->>'action' is null or p_data->>'action' not in ('activate','pause') or p_data->'confirmed' is distinct from 'true'::jsonb or p_data->'spend_acknowledged' is distinct from to_jsonb(p_data->>'action'='activate') then raise exception 'Confirm this Meta command and its spending impact.';end if;
  if not(checks->>'platform_enabled')::boolean or not(checks->>'creation_recorded')::boolean or not(checks->>'no_uncertain_command')::boolean or not(checks->>'command_capacity')::boolean then raise exception 'Meta controls are unavailable or a command outcome is uncertain.' using errcode='40001';end if;
  if p_data->'observed'->'status'->>'resource' is distinct from creation->'attempt'->'resources'->>'campaign' then raise exception 'Reload the saved Meta campaign status.';end if;
  steps:='[]'::jsonb;
  if p_data->>'action'='activate' then
   if not ready or p_data->'observed'->'can_activate' is distinct from 'true'::jsonb or p_data->'observed'->'status'->>'status' is distinct from 'PAUSED' or p_data->'observed'->'graph'->'resources' is distinct from creation->'attempt'->'resources' then raise exception 'Activation requires current preparation, matching saved content and explicit spending authorization.';end if;
   for stage in select unnest(array['ad','ad_set']) loop
    if p_data->'observed'->'graph'->'statuses'->>stage='PAUSED' then steps:=steps||jsonb_build_array(stage);
    elsif p_data->'observed'->'graph'->'statuses'->>stage is distinct from 'ACTIVE' then raise exception 'Reload Meta child resource status.';end if;
   end loop;
   if p_data->'observed'->'graph'->'statuses'->>'campaign' is distinct from 'PAUSED' then raise exception 'Reload the paused Meta campaign.';end if;
  elsif p_data->'observed'->'can_pause' is distinct from 'true'::jsonb or p_data->'observed'->'status'->>'status' is distinct from 'ACTIVE' then raise exception 'Reload the active Meta campaign before pausing.';
  end if;
  steps:=steps||'["campaign"]'::jsonb;
  insert into public.korlix_funnel_meta_commands(id,campaign_id,user_id,sequence,action,fingerprint,observed,steps)
   values((p_data->>'command_id')::uuid,(p_data->>'campaign_id')::uuid,p_actor,coalesce(cmd.sequence,0)+1,p_data->>'action',fp,p_data->'observed',steps) returning * into cmd;
  dispatch:=true;
 end if;
 return jsonb_build_object('source','meta_campaign_controls','funnel_id',p_funnel,'campaign_id',creation->'campaign_id','creation',creation-array['dispatch','proposal'],'checks',checks,'activation_ready',ready,'fingerprint',fp,'latest_command',case when cmd.id is null then null else to_jsonb(cmd)-array['user_id','campaign_id','fingerprint'] end,'dispatch',dispatch);
end $$;
revoke all on function public.korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb) to service_role;
commit;
