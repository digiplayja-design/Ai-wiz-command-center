begin;
create table public.korlix_funnel_meta_creations (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempt_id uuid not null unique,
  state text not null default 'unknown' check(state in ('unknown','created')),
  fingerprint text not null check(fingerprint ~ '^[a-f0-9]{64}$'),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object' and octet_length(snapshot::text)<=131072),
  resources jsonb not null default '{}' check(jsonb_typeof(resources)='object' and octet_length(resources::text)<=2048 and (resources-array['image_hash','campaign','ad_set','creative','ad'])='{}'::jsonb),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check((state='unknown' and completed_at is null) or (state='created' and completed_at is not null and resources ?& array['image_hash','campaign','ad_set','creative','ad']))
);
alter table public.korlix_funnel_meta_creations enable row level security;
revoke all on public.korlix_funnel_meta_creations from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_meta_creations to service_role;
create index korlix_funnel_meta_creations_owner on public.korlix_funnel_meta_creations(user_id,created_at);
comment on table public.korlix_funnel_meta_creations is 'Private one-attempt Meta paused creation ledger with durable partial receipts. Unknown never authorizes replay or continuation. No tokens or image bytes. Read-only reconciliation requires a complete matching paused graph.';

create function public.korlix_funnel_meta_create_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; saved public.korlix_funnel_meta_creations;
  prep jsonb; setup jsonb; draft jsonb; proposal jsonb; fp text; checks jsonb; ready boolean; today date; start_day date; finish_day date;
  dispatch boolean:=false; result jsonb; k text; v text; n integer;
begin
  if p_actor is null or p_action is null or p_action not in ('read','prepare','claim','progress','finish') then raise exception 'Unknown Meta creation action.'; end if;
  if p_action not in ('progress','finish') and not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Meta campaign creation requires Enterprise.' using errcode='42501'; end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if c.platform<>'meta' then raise exception 'Choose a Meta campaign plan.'; end if;
  if p_action in ('progress','finish') then
    -- Internal receipt persistence only, including after late entitlement loss.
    select * into saved from public.korlix_funnel_meta_creations where campaign_id=c.id and user_id=p_actor and attempt_id=(p_data->>'attempt_id')::uuid for update;
    if not found then raise exception 'Creation attempt not found.' using errcode='P0002'; end if;
    if p_action='progress' then
      k:=p_data->>'resource';v:=p_data->>'value';
      select count(*) into n from jsonb_object_keys(saved.resources);
      if saved.state<>'unknown' or k is distinct from (array['image_hash','campaign','ad_set','creative','ad'])[n+1] then raise exception 'Creation progress cannot be repeated or reordered.' using errcode='40001'; end if;
      if jsonb_typeof(p_data->'value') is distinct from 'string' or not coalesce(v ~ case when k='image_hash' then '^[a-f0-9]{32}$' else '^[1-9][0-9]{0,39}$' end,false) then raise exception 'Invalid Meta resource receipt.'; end if;
      update public.korlix_funnel_meta_creations set resources=resources||jsonb_build_object(k,v) where campaign_id=c.id;
    else
      result:=p_data->'resources';
      if result is null or jsonb_typeof(result)<>'object' or not(result ?& array['image_hash','campaign','ad_set','creative','ad']) or (result-array['image_hash','campaign','ad_set','creative','ad'])<>'{}'::jsonb then raise exception 'A complete Meta creation result is required.'; end if;
      for k,v in select key,value from jsonb_each_text(result) loop
        if jsonb_typeof(result->k)<>'string' or not coalesce(v ~ case when k='image_hash' then '^[a-f0-9]{32}$' else '^[1-9][0-9]{0,39}$' end,false) or (saved.resources ? k and saved.resources->k is distinct from result->k) then raise exception 'Meta creation resources changed.' using errcode='40001'; end if;
      end loop;
      -- A stored upload receipt anchors reconciliation to the uploaded image.
      if not(saved.resources ? 'image_hash') then raise exception 'The image upload outcome is uncertain; check Meta directly.' using errcode='40001'; end if;
      update public.korlix_funnel_meta_creations set state='created',resources=result,completed_at=coalesce(completed_at,now()) where campaign_id=c.id;
    end if;
    return jsonb_build_object('recorded',true);
  end if;
  prep:=public.korlix_funnel_meta_targeting_v1(p_actor,'read',p_funnel,p_data);setup:=prep->'creative'->'setup';
  draft:=jsonb_build_object('plan',setup->'current_snapshot'->'campaign','page',setup->'current_snapshot'->'landing_page','identity',setup->'current_snapshot'->'meta','creative',prep->'creative'->'assets','image',prep->'creative'->'image','targeting',prep->'assets');
  select * into saved from public.korlix_funnel_meta_creations where campaign_id=c.id for update;
  if exists(select 1 from pg_timezone_names where name=draft->'identity'->'account'->>'timezone') then today:=(now() at time zone (draft->'identity'->'account'->>'timezone'))::date; end if;
  checks:=jsonb_build_object('platform_enabled',coalesce(p_data->'create_enabled'='true'::jsonb,false),'setup_review_current',setup->'review_current','creative_targeting_review_current',prep->'review_current','facebook_feed',coalesce(draft->'targeting'->>'placements'='facebook_feed',false),'no_special_category',coalesce(draft->'targeting'->'categories'='["NONE"]'::jsonb,false),'account_calendar',today is not null,'no_previous_attempt',saved.campaign_id is null);
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  fp:=encode(sha256(convert_to(jsonb_build_object('draft',draft,'checks',checks,'setup',setup->'fingerprint','review',prep->'review_fingerprint')::text,'UTF8')),'hex');
  if p_action in ('prepare','claim') and saved.campaign_id is null then
    if not ready then raise exception 'Complete current reviews, Facebook Feed selection and platform setup before paused creation.' using errcode='40001'; end if;
    if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign, reviews or Meta connection changed. Reload creation details.' using errcode='40001'; end if;
    if p_data->'confirmed' is distinct from 'true'::jsonb or p_data->'budget_acknowledged' is distinct from 'true'::jsonb then raise exception 'Confirm the upload, paused resources and average daily budget.'; end if;
    if not coalesce(p_data->>'start_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',false) or p_data->>'attempt_id' is null then raise exception 'Choose a valid creation date.'; end if;
    start_day:=(p_data->>'start_date')::date;
    if start_day<today+1 or start_day>today+30 then raise exception 'Choose tomorrow through the next 30 days in the ad account timezone.'; end if;
    finish_day:=start_day+(draft->'plan'->>'days')::integer;
    proposal:=draft||jsonb_build_object('start_date',start_day,'end_date',finish_day-1,'start_time',(start_day::timestamp at time zone (draft->'identity'->'account'->>'timezone')),'end_time',(finish_day::timestamp at time zone (draft->'identity'->'account'->>'timezone'))-interval '1 second','provider_name','KORLIX '||(p_data->>'attempt_id'),'budget_acknowledged',true);
    if p_action='claim' then
      if not coalesce(p_data->>'request_hash' ~ '^[a-f0-9]{64}$',false) then raise exception 'Invalid creation request.'; end if;
      insert into public.korlix_funnel_meta_creations(campaign_id,user_id,attempt_id,fingerprint,request_hash,snapshot) values(c.id,p_actor,(p_data->>'attempt_id')::uuid,fp,p_data->>'request_hash',proposal) returning * into saved;
      dispatch:=true;
    end if;
  end if;
  return jsonb_build_object('source','meta_paused_creation','funnel_id',f.id,'campaign_id',c.id,'fingerprint',fp,'checks',checks,'create_ready',ready and saved.campaign_id is null,'today',today,'earliest_start',today+1,'latest_start',today+30,'draft',draft,'preparation',prep,'proposal',proposal,'attempt',case when saved.campaign_id is null then null else jsonb_build_object('id',saved.attempt_id,'state',saved.state,'snapshot',saved.snapshot,'resources',saved.resources,'created_at',saved.created_at,'completed_at',saved.completed_at) end,'dispatch',dispatch,'activation_supported',false,'ad_publishing_ready',false);
end $$;
revoke all on function public.korlix_funnel_meta_create_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_create_v1(uuid,text,uuid,jsonb) to service_role;
commit;
