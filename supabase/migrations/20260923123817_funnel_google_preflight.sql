begin;
-- One transaction holds the existing funnel -> campaign -> connection locks
-- while all four component readers run. No rows are written or reviewed.
create function public.korlix_funnel_google_preflight_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare setup jsonb; creative jsonb; keywords jsonb; targeting jsonb; checks jsonb; complete boolean;
begin
  if p_action is distinct from 'read' then raise exception 'The preparation checklist is read only.'; end if;
  setup:=public.korlix_funnel_google_preparation_v1(p_actor,'read',p_funnel,p_data);
  creative:=public.korlix_funnel_google_creative_v1(p_actor,'read',p_funnel,p_data);
  keywords:=public.korlix_funnel_google_keywords_v1(p_actor,'read',p_funnel,p_data);
  targeting:=public.korlix_funnel_google_targeting_v1(p_actor,'read',p_funnel,p_data);
  checks:=jsonb_build_object('page_published',setup->'checks'->'page_published','plan_reviewed',setup->'checks'->'plan_reviewed','setup_reviewed',setup->'review_current','copy_reviewed',creative->'review_current','keywords_reviewed',keywords->'review_current','targeting_reviewed',targeting->'review_current');
  select bool_and(value='true'::jsonb) into complete from jsonb_each(checks);
  return jsonb_build_object('source','google_preflight','funnel_id',p_funnel,'campaign_id',setup->'campaign_id','checked_at',clock_timestamp(),'checks',checks,'preparation_complete',complete,'ad_publishing_ready',false,'setup',setup,'creative',creative,'keywords',keywords,'targeting',targeting);
end $$;
revoke all on function public.korlix_funnel_google_preflight_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_preflight_v1(uuid,text,uuid,jsonb) to service_role;
comment on function public.korlix_funnel_google_preflight_v1(uuid,text,uuid,jsonb) is 'Read-only combined Google campaign preparation checklist. No provider request, approval, ad creation or spending.';
commit;
