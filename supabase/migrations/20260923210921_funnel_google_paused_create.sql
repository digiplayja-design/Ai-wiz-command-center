begin;
-- One durable dispatch slot per local plan. Ambiguous outcomes are never resent.
create table public.korlix_funnel_google_creations (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempt_id uuid not null unique,
  state text not null default 'unknown' check(state in ('unknown','created')),
  fingerprint text not null check(fingerprint ~ '^[a-f0-9]{64}$'),
  request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object' and octet_length(snapshot::text)<=131072),
  resources jsonb check(resources is null or (jsonb_typeof(resources)='object' and octet_length(resources::text)<=2048)),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check((state='unknown' and resources is null and completed_at is null) or (state='created' and resources is not null and completed_at is not null))
);
alter table public.korlix_funnel_google_creations enable row level security;
revoke all on public.korlix_funnel_google_creations from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_google_creations to service_role;
create index korlix_funnel_google_creations_owner on public.korlix_funnel_google_creations(user_id,created_at);
comment on table public.korlix_funnel_google_creations is 'Private one-dispatch-per-plan Google paused creation ledger. Unknown is not permission to retry. No tokens, serving permission or verified conversions.';

create function public.korlix_funnel_google_create_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; saved public.korlix_funnel_google_creations;
  prep jsonb; draft jsonb; fp text; checks jsonb; ready boolean; today date; start_day date; finish_day date;
  dispatch boolean:=false; account_id text; resource_prefix text; result jsonb;
begin
  if p_actor is null or p_action is null or p_action not in ('read','claim','finish') then raise exception 'Unknown Google creation action.'; end if;
  -- Finish is internal-only and can record a provider outcome after entitlement
  -- changes. It never authorizes a send and still requires exact owner/attempt.
  if p_action<>'finish' and not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Google campaign creation requires Enterprise.' using errcode='42501'; end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if p_action='finish' then
    select * into saved from public.korlix_funnel_google_creations where campaign_id=c.id and user_id=p_actor and attempt_id=(p_data->>'attempt_id')::uuid for update;
    if not found then raise exception 'Creation attempt not found.' using errcode='P0002'; end if;
    result:=p_data->'resources'; account_id:=saved.snapshot->'identity'->'account'->>'id';resource_prefix:='^customers/'||account_id||'/';
    if result is null or jsonb_typeof(result)<>'object' or not(result ?& array['budget','campaign','ad_group','ad']) or (result-array['budget','campaign','ad_group','ad'])<>'{}'::jsonb or
      not coalesce(result->>'budget' ~ (resource_prefix||'campaignBudgets/[1-9][0-9]{0,18}$') and result->>'campaign' ~ (resource_prefix||'campaigns/[1-9][0-9]{0,18}$') and result->>'ad_group' ~ (resource_prefix||'adGroups/[1-9][0-9]{0,18}$') and result->>'ad' ~ (resource_prefix||'adGroupAds/[1-9][0-9]{0,18}~[1-9][0-9]{0,18}$'),false) or split_part(split_part(result->>'ad','/',4),'~',1)<>split_part(result->>'ad_group','/',4) then raise exception 'Invalid Google creation resources.'; end if;
    if saved.state='created' and saved.resources is distinct from result then raise exception 'Creation result already recorded.' using errcode='40001'; end if;
    update public.korlix_funnel_google_creations set state='created',resources=result,completed_at=coalesce(completed_at,now()) where campaign_id=c.id;
    return jsonb_build_object('recorded',true);
  end if;
  if c.platform<>'google' then raise exception 'Choose a Google campaign plan.'; end if;
  prep:=public.korlix_funnel_google_preflight_v1(p_actor,'read',p_funnel,p_data);
  draft:=jsonb_build_object('plan',prep->'setup'->'current_snapshot'->'campaign','page',prep->'setup'->'current_snapshot'->'landing_page','identity',prep->'setup'->'current_snapshot'->'google_ads','creative',prep->'creative'->'assets','keywords',prep->'keywords'->'assets','targeting',prep->'targeting'->'assets');
  select * into saved from public.korlix_funnel_google_creations where campaign_id=c.id for update;
  if exists(select 1 from pg_timezone_names where name=draft->'identity'->'account'->>'timezone') then today:=(now() at time zone (draft->'identity'->'account'->>'timezone'))::date; end if;
  checks:=jsonb_build_object('platform_enabled',coalesce(p_data->'create_enabled'='true'::jsonb,false),'preparation_complete',prep->'preparation_complete','maximize_clicks',coalesce(draft->'targeting'->>'bidding'='maximize_clicks',false),'account_calendar',today is not null,'no_previous_attempt',saved.campaign_id is null);
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  fp:=encode(sha256(convert_to(jsonb_build_object('draft',draft,'checks',checks,'setup',prep->'setup'->'fingerprint','creative',prep->'creative'->'review_fingerprint','keywords',prep->'keywords'->'review_fingerprint','targeting',prep->'targeting'->'review_fingerprint')::text,'UTF8')),'hex');
  if p_action='claim' and saved.campaign_id is null then
    if not ready then raise exception 'Complete the current preparation and platform setup before creating a paused campaign.'; end if;
    if p_data->>'fingerprint' is distinct from fp then raise exception 'The campaign, reviews or account changed. Reload before creating.' using errcode='40001'; end if;
    if p_data->'confirmed' is distinct from 'true'::jsonb or p_data->'budget_acknowledged' is distinct from 'true'::jsonb or p_data->'no_eu_political_ads' is distinct from 'true'::jsonb then raise exception 'Confirm paused creation, the average budget and the political-ad declaration.'; end if;
    if not coalesce(p_data->>'start_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',false) or not coalesce(p_data->>'request_hash' ~ '^[a-f0-9]{64}$',false) or p_data->>'attempt_id' is null then raise exception 'Invalid creation request.'; end if;
    start_day:=(p_data->>'start_date')::date;
    if start_day<today or start_day>today+30 then raise exception 'Choose a start date from today through the next 30 days in the account timezone.'; end if;
    finish_day:=start_day+(draft->'plan'->>'days')::integer-1;
    draft:=draft||jsonb_build_object('start_date',start_day,'end_date',finish_day,'provider_name','KORLIX '||(p_data->>'attempt_id'),'no_eu_political_ads',true,'budget_acknowledged',true);
    insert into public.korlix_funnel_google_creations(campaign_id,user_id,attempt_id,fingerprint,request_hash,snapshot) values(c.id,p_actor,(p_data->>'attempt_id')::uuid,fp,p_data->>'request_hash',draft) returning * into saved;
    dispatch:=true;
  end if;
  return jsonb_build_object('source','google_paused_creation','funnel_id',f.id,'campaign_id',c.id,'fingerprint',fp,'checks',checks,'create_ready',ready and saved.campaign_id is null,'today',today,'latest_start',today+30,'preparation',prep,'draft',draft,
    'attempt',case when saved.campaign_id is null then null else jsonb_build_object('id',saved.attempt_id,'state',saved.state,'snapshot',saved.snapshot,'resources',saved.resources,'created_at',saved.created_at,'completed_at',saved.completed_at) end,'dispatch',dispatch,'ad_publishing_ready',false,'activation_supported',false);
end $$;
revoke all on function public.korlix_funnel_google_create_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_create_v1(uuid,text,uuid,jsonb) to service_role;
commit;
