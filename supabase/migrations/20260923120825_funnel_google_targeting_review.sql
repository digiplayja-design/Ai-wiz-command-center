begin;
alter table public.korlix_funnel_google_targeting
  add column draft_revision integer not null default 1,
  add column review_fingerprint text,
  add column reviewed_at timestamptz,
  add column reviewed_snapshot jsonb;
-- Existing draft versions become revision identifiers without changing their
-- content, context hash, version, saved timestamp or owner setup reviews.
update public.korlix_funnel_google_targeting set draft_revision=version;
alter table public.korlix_funnel_google_targeting
  add constraint google_targeting_revision_valid check(draft_revision>0 and draft_revision<=version),
  add constraint google_targeting_review_hash_valid check(review_fingerprint is null or review_fingerprint ~ '^[a-f0-9]{64}$'),
  add constraint google_targeting_review_snapshot_valid check(reviewed_snapshot is null or coalesce((jsonb_typeof(reviewed_snapshot)='object' and octet_length(reviewed_snapshot::text)<=98304 and reviewed_snapshot ?& array['assets','context','labels','catalog_version','draft_revision','saved_at'] and (reviewed_snapshot-array['assets','context','labels','catalog_version','draft_revision','saved_at'])='{}'::jsonb and public.korlix_google_targeting_valid_v1(reviewed_snapshot->'assets') and jsonb_typeof(reviewed_snapshot->'context')='object' and jsonb_typeof(reviewed_snapshot->'labels')='object' and jsonb_typeof(reviewed_snapshot->'catalog_version')='string' and jsonb_typeof(reviewed_snapshot->'draft_revision')='number' and jsonb_typeof(reviewed_snapshot->'saved_at')='string'),false)),
  add constraint google_targeting_review_consistent check((reviewed_snapshot is null and review_fingerprint is null and reviewed_at is null) or (reviewed_snapshot is not null and review_fingerprint is not null and reviewed_at is not null));
comment on table public.korlix_funnel_google_targeting is 'Private targeting drafts and owner targeting reviews. No Google approval, ad creation or spending authorization.';
create or replace function public.korlix_funnel_google_targeting_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; saved public.korlix_funnel_google_targeting;
  context jsonb; fingerprint text; assets jsonb; catalog jsonb:=public.korlix_google_targeting_catalog_v1(); labels jsonb; review_checks jsonb; review_ready boolean; current_review_fingerprint text;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Search targeting drafts require Enterprise.' using errcode='42501'; end if;
  if p_action is null or p_action not in ('read','save','review','clear_review') then raise exception 'Unknown targeting draft action.'; end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if c.platform<>'google' then raise exception 'Choose a Google campaign for a targeting draft.'; end if;
  select * into saved from public.korlix_funnel_google_targeting where campaign_id=c.id for update;
  context:=jsonb_build_object('campaign_name',c.name,'headline',c.headline,'body',c.body,'cta',c.cta,'audience',c.audience,'daily_cents',c.daily_cents,'days',c.days,'campaign_state',c.state,'page_state',f.state,'page_version',f.published_version,'brand',coalesce(f.published->>'brand',''),'destination',(p_data->>'public_base')||'/f/'||f.slug||'?utm_source=google&utm_medium=paid&utm_campaign=k143_'||replace(c.id::text,'-',''));
  fingerprint:=encode(sha256(convert_to(jsonb_build_object('context',context,'page_content',f.published,'reviewed_page_version',c.reviewed_page_version,'catalog_version',catalog->>'version')::text,'UTF8')),'hex');
  if p_action='save' then
    if c.state='archived' then raise exception 'Reopen this campaign before editing its targeting draft.'; end if;
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) or p_data->>'fingerprint' is distinct from fingerprint then raise exception 'The draft, campaign or landing page changed. Reload the saved draft before saving again.' using errcode='40001'; end if;
    if not public.korlix_google_targeting_valid_v1(p_data->'assets') then raise exception 'Check countries, exclusions, content languages, location reach and bidding preference.'; end if;
    labels:=jsonb_build_object(
      'countries',coalesce((select jsonb_object_agg(x->>'code',x->>'name') from jsonb_array_elements(catalog->'countries') x where p_data->'assets'->'countries' ? (x->>'code') or p_data->'assets'->'excluded_countries' ? (x->>'code')),'{}'::jsonb),
      'content_languages',coalesce((select jsonb_object_agg(x->>'code',x->>'name') from jsonb_array_elements(catalog->'languages') x where p_data->'assets'->'content_languages' ? (x->>'code')),'{}'::jsonb)
    );
    insert into public.korlix_funnel_google_targeting(campaign_id,assets,context_fingerprint,context_snapshot,labels_snapshot) values(c.id,p_data->'assets',fingerprint,context,labels)
    on conflict(campaign_id) do update set assets=excluded.assets,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,labels_snapshot=excluded.labels_snapshot,version=public.korlix_funnel_google_targeting.version+1,draft_revision=public.korlix_funnel_google_targeting.draft_revision+1,updated_at=now() returning * into saved;
  end if;
  assets:=coalesce(saved.assets,'{"countries":[],"excluded_countries":[],"content_languages":[],"location_mode":"undecided","bidding":"undecided"}'::jsonb);
  review_checks:=jsonb_build_object(
    'saved_draft',saved.campaign_id is not null,
    'complete_choices',jsonb_array_length(assets->'countries')>0 and jsonb_array_length(assets->'content_languages')>0 and assets->>'location_mode'<>'undecided' and assets->>'bidding'<>'undecided',
    'current_context',coalesce(saved.context_fingerprint=fingerprint,false),
    'page_published',f.state='published' and f.published is not null,
    'plan_reviewed',coalesce(c.state='reviewed' and c.reviewed_page_version=f.published_version,false)
  );
  select bool_and(value='true'::jsonb) into review_ready from jsonb_each(review_checks);
  current_review_fingerprint:=encode(sha256(convert_to(jsonb_build_object('assets',assets,'labels',saved.labels_snapshot,'catalog_version',catalog->>'version','context_fingerprint',fingerprint,'draft_revision',coalesce(saved.draft_revision,0))::text,'UTF8')),'hex');
  if p_action in ('review','clear_review') then
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) then raise exception 'The draft or review changed. Reload before reviewing again.' using errcode='40001'; end if;
    if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Review and confirm this targeting action.'; end if;
    if p_action='review' then
      if p_data->>'review_fingerprint' is distinct from current_review_fingerprint then raise exception 'The draft or landing page changed. Reload this targeting review.' using errcode='40001'; end if;
      if not review_ready then raise exception 'Save complete current targeting choices, publish the page and review the campaign plan first.'; end if;
      update public.korlix_funnel_google_targeting set reviewed_snapshot=jsonb_build_object('assets',saved.assets,'context',saved.context_snapshot,'labels',saved.labels_snapshot,'catalog_version',catalog->>'version','draft_revision',saved.draft_revision,'saved_at',saved.updated_at),review_fingerprint=current_review_fingerprint,reviewed_at=now(),version=version+1 where campaign_id=c.id returning * into saved;
    elsif saved.campaign_id is not null then
      update public.korlix_funnel_google_targeting set reviewed_snapshot=null,review_fingerprint=null,reviewed_at=null,version=version+1 where campaign_id=c.id returning * into saved;
    end if;
  end if;
  return jsonb_build_object('source','google_targeting_draft','funnel_id',f.id,'campaign_id',c.id,'version',coalesce(saved.version,0),'fingerprint',fingerprint,'context',context,'saved_context',saved.context_snapshot,'assets',assets,'updated_at',saved.updated_at,'draft_current',coalesce(saved.context_fingerprint=fingerprint,false),'editable',c.state<>'archived','draft_complete',jsonb_array_length(assets->'countries')>0 and jsonb_array_length(assets->'content_languages')>0 and assets->>'location_mode'<>'undecided' and assets->>'bidding'<>'undecided','catalog',catalog,'saved_labels',saved.labels_snapshot,'ad_publishing_ready',false,'draft_revision',coalesce(saved.draft_revision,0),'review_fingerprint',current_review_fingerprint,'review_checks',review_checks,'review_ready',review_ready,'review_current',coalesce(review_ready and saved.review_fingerprint=current_review_fingerprint,false),'reviewed_at',saved.reviewed_at,'reviewed_snapshot',saved.reviewed_snapshot);
end $$;
revoke all on function public.korlix_funnel_google_targeting_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_targeting_v1(uuid,text,uuid,jsonb) to service_role;
commit;
