begin;
-- Preserve legacy country drafts, reviews, versions and fingerprints byte-for-byte.
-- KORLIX local draft bounds and review limits do not assert provider eligibility.
create function public.korlix_meta_radius_valid_v1(v jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare k text; n numeric;
begin
  if v is null or jsonb_typeof(v)<>'object' or not(v ?& array['label','latitude_micro','longitude_micro','radius_meters']) or (v-array['label','latitude_micro','longitude_micro','radius_meters'])<>'{}'::jsonb then return false; end if;
  if jsonb_typeof(v->'label')<>'string' or char_length(v->>'label') not between 1 and 80 or btrim(v->>'label')<>v->>'label' or (v->>'label') ~ ('[[:cntrl:]<>'||chr(127)||'-'||chr(159)||chr(8232)||chr(8233)||']') then return false; end if;
  foreach k in array array['latitude_micro','longitude_micro','radius_meters'] loop
    if jsonb_typeof(v->k)<>'number' then return false; end if;
    n:=(v->>k)::numeric;
    if n<>trunc(n) then return false; end if;
    if k='latitude_micro' and abs(n)>90000000 then return false; end if;
    if k='longitude_micro' and abs(n)>180000000 then return false; end if;
    if k='radius_meters' and n not between 1000 and 80000 then return false; end if;
  end loop;
  return true;
end $$;
revoke all on function public.korlix_meta_radius_valid_v1(jsonb) from public,anon,authenticated;
grant execute on function public.korlix_meta_radius_valid_v1(jsonb) to service_role;
create or replace function public.korlix_meta_targeting_valid_v1(v jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare a jsonb; catalog jsonb:=public.korlix_meta_targeting_catalog_v1();
begin
  if v is null or jsonb_typeof(v)<>'object' or not(v ?& array['countries','age_min','age_max','placements','categories']) or (v-array['countries','age_min','age_max','placements','categories','custom_locations'])<>'{}'::jsonb then return false; end if;
  a:=v->'countries';
  if jsonb_typeof(a)<>'array' then return false; end if;
  if jsonb_array_length(a)>20 or exists(select 1 from jsonb_array_elements(a) x where jsonb_typeof(x)<>'string') or (select count(*)<>count(distinct x) from jsonb_array_elements_text(a) x) then return false; end if;
  if exists(select 1 from jsonb_array_elements_text(a) x where not exists(select 1 from jsonb_array_elements(catalog->'countries') o where o->>'code'=x)) then return false; end if;
  if jsonb_typeof(v->'age_min')<>'number' or jsonb_typeof(v->'age_max')<>'number' or (v->>'age_min')!~'^[0-9]{2}$' or (v->>'age_max')!~'^[0-9]{2}$' then return false; end if;
  if (v->>'age_min')::int<18 or (v->>'age_max')::int>65 or (v->>'age_max')::int<(v->>'age_min')::int then return false; end if;
  if jsonb_typeof(v->'placements')<>'string' or v->>'placements' not in ('undecided','automatic','facebook_feed') then return false; end if;
  a:=v->'categories';
  if jsonb_typeof(a)<>'array' then return false; end if;
  if jsonb_array_length(a)<1 or jsonb_array_length(a)>5 or exists(select 1 from jsonb_array_elements(a) x where jsonb_typeof(x)<>'string') or (select count(*)<>count(distinct x) from jsonb_array_elements_text(a) x) then return false; end if;
  if exists(select 1 from jsonb_array_elements_text(a) x where x not in ('UNDECIDED','NONE','HOUSING','EMPLOYMENT','FINANCIAL_PRODUCTS_SERVICES','ISSUES_ELECTIONS_POLITICS','ONLINE_GAMBLING_AND_GAMING')) or (a ?| array['UNDECIDED','NONE'] and jsonb_array_length(a)<>1) then return false; end if;
  if v ? 'custom_locations' then
    if jsonb_typeof(v->'custom_locations')<>'array' or jsonb_array_length(v->'countries')>0 then return false; end if;
    if jsonb_array_length(v->'custom_locations')>10 then return false; end if;
    if exists(select 1 from jsonb_array_elements(v->'custom_locations') x where not public.korlix_meta_radius_valid_v1(x)) then return false; end if;
    if (select count(*)<>count(distinct jsonb_build_array(x->'latitude_micro',x->'longitude_micro',x->'radius_meters')) from jsonb_array_elements(v->'custom_locations') x) then return false; end if;
  end if;
  return a ? 'NONE' or ((v->>'age_min')::int=18 and (v->>'age_max')::int=65);
end $$;
revoke all on function public.korlix_meta_targeting_valid_v1(jsonb) from public,anon,authenticated;
grant execute on function public.korlix_meta_targeting_valid_v1(jsonb) to service_role;
create or replace function public.korlix_funnel_meta_targeting_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare creative jsonb; setup jsonb; saved public.korlix_funnel_meta_targeting; c public.korlix_funnel_campaigns;
  context jsonb; fingerprint text; assets jsonb; catalog jsonb:=public.korlix_meta_targeting_catalog_v1(); labels jsonb; checks jsonb; ready boolean; review_hash text; creative_snapshot jsonb;
begin
  if p_action is null or p_action not in ('read','save','review','clear_review') then raise exception 'Unknown Meta targeting action.'; end if;
  -- Existing reader enforces entitlement, ownership, platform and stable locks:
  -- funnel -> campaign -> connection -> setup -> creative, then targeting here.
  creative:=public.korlix_funnel_meta_creative_v1(p_actor,'read',p_funnel,p_data); setup:=creative->'setup';
  select * into c from public.korlix_funnel_campaigns where id=(creative->>'campaign_id')::uuid;
  select * into saved from public.korlix_funnel_meta_targeting where campaign_id=c.id for update;
  context:=setup->'current_snapshot';
  fingerprint:=encode(sha256(convert_to(jsonb_build_object('setup_fingerprint',setup->>'fingerprint','catalog_version',catalog->>'version')::text,'UTF8')),'hex');
  if p_action='save' then
    if c.state='archived' then raise exception 'Reopen this campaign before editing Meta targeting.'; end if;
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) or p_data->>'fingerprint' is distinct from fingerprint then raise exception 'The targeting draft, campaign, Page identity or landing page changed. Reload before saving.' using errcode='40001'; end if;
    if not public.korlix_meta_targeting_valid_v1(p_data->'assets') then raise exception 'Check countries or radius areas, draft ages, categories and placement preference.'; end if;
    labels:=coalesce((select jsonb_object_agg(x->>'code',x->>'name') from jsonb_array_elements(catalog->'countries') x where p_data->'assets'->'countries' ? (x->>'code')),'{}'::jsonb);
    insert into public.korlix_funnel_meta_targeting(campaign_id,assets,context_fingerprint,context_snapshot,labels_snapshot) values(c.id,p_data->'assets',fingerprint,context,labels)
    on conflict(campaign_id) do update set assets=excluded.assets,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,labels_snapshot=excluded.labels_snapshot,version=public.korlix_funnel_meta_targeting.version+1,draft_revision=public.korlix_funnel_meta_targeting.draft_revision+1,updated_at=now() returning * into saved;
  end if;
  assets:=coalesce(saved.assets,'{"countries":[],"age_min":18,"age_max":65,"placements":"undecided","categories":["UNDECIDED"]}'::jsonb);
  checks:=jsonb_build_object('saved_draft',saved.campaign_id is not null,'complete_choices',(jsonb_array_length(assets->'countries')>0 or (jsonb_array_length(coalesce(assets->'custom_locations','[]'::jsonb))>0 and assets->'categories' ? 'NONE')) and assets->>'placements'<>'undecided' and not(assets->'categories' ? 'UNDECIDED'),'current_context',coalesce(saved.context_fingerprint=fingerprint,false),'page_published',setup->'checks'->'page_published','plan_reviewed',setup->'checks'->'plan_reviewed','creative_saved',(creative->>'version')::int>0,'creative_complete',creative->'creative_complete','creative_current',creative->'draft_current');
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  creative_snapshot:=jsonb_build_object('version',creative->'version','assets',creative->'assets','image',creative->'image','context',creative->'saved_context','saved_at',creative->'updated_at');
  review_hash:=encode(sha256(convert_to(jsonb_build_object('assets',assets,'labels',saved.labels_snapshot,'context_fingerprint',fingerprint,'catalog_version',catalog->>'version','draft_revision',coalesce(saved.draft_revision,0),'creative',creative_snapshot)::text,'UTF8')),'hex');
  if p_action in ('review','clear_review') then
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) then raise exception 'The draft or review changed. Reload before reviewing.' using errcode='40001'; end if;
    if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Review and confirm this preparation action.'; end if;
    if p_action='review' then
      if p_data->>'review_fingerprint' is distinct from review_hash then raise exception 'The creative, targeting or campaign context changed. Reload this preparation review.' using errcode='40001'; end if;
      if not ready or c.state='archived' then raise exception 'Save complete current targeting and creative drafts, publish the page and review the campaign plan first.'; end if;
      update public.korlix_funnel_meta_targeting set reviewed_snapshot=jsonb_build_object('assets',saved.assets,'context',saved.context_snapshot,'labels',saved.labels_snapshot,'catalog_version',catalog->>'version','draft_revision',saved.draft_revision,'saved_at',saved.updated_at,'creative',creative_snapshot),review_fingerprint=review_hash,reviewed_at=now(),version=version+1 where campaign_id=c.id returning * into saved;
    elsif saved.campaign_id is not null then
      update public.korlix_funnel_meta_targeting set reviewed_snapshot=null,review_fingerprint=null,reviewed_at=null,version=version+1 where campaign_id=c.id returning * into saved;
    end if;
  end if;
  return jsonb_build_object('source','meta_targeting_draft','funnel_id',p_funnel,'campaign_id',c.id,'version',coalesce(saved.version,0),'fingerprint',fingerprint,'creative',creative,'saved_context',saved.context_snapshot,'assets',assets,'updated_at',saved.updated_at,'draft_current',coalesce(saved.context_fingerprint=fingerprint,false),'editable',c.state<>'archived','draft_complete',checks->'complete_choices','catalog',catalog,'saved_labels',saved.labels_snapshot,'ad_publishing_ready',false,'radius_supported',true,'draft_revision',coalesce(saved.draft_revision,0),'review_fingerprint',review_hash,'review_checks',checks,'review_ready',ready,'review_current',coalesce(ready and saved.review_fingerprint=review_hash,false),'reviewed_at',saved.reviewed_at,'reviewed_snapshot',saved.reviewed_snapshot);
end $$;
revoke all on function public.korlix_funnel_meta_targeting_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_targeting_v1(uuid,text,uuid,jsonb) to service_role;
commit;
