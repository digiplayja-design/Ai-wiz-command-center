begin;
create table public.korlix_funnel_meta_preparations (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  version integer not null default 1 check(version>0),
  fingerprint text check(fingerprint is null or fingerprint ~ '^[a-f0-9]{64}$'),
  snapshot jsonb check(snapshot is null or (jsonb_typeof(snapshot)='object' and octet_length(snapshot::text)<=32768)),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  check((snapshot is null and fingerprint is null and reviewed_at is null) or (snapshot is not null and fingerprint is not null and reviewed_at is not null))
);
alter table public.korlix_funnel_meta_preparations enable row level security;
revoke all on public.korlix_funnel_meta_preparations from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_meta_preparations to service_role;
comment on table public.korlix_funnel_meta_preparations is 'Private owner-reviewed campaign/account/Page snapshots. Not ad creation, ad eligibility, or spending authorization.';

create function public.korlix_funnel_meta_preparation_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; m public.korlix_meta_connections; saved public.korlix_funnel_meta_preparations;
  account jsonb; page jsonb; checks jsonb; current_snapshot jsonb; current_fingerprint text; ready boolean; configured boolean; connected boolean;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Meta setup reviews require Enterprise.' using errcode='42501'; end if;
  if p_action not in ('read','review','clear') then raise exception 'Unknown Meta setup action.'; end if;
  -- Same funnel -> campaign lock order as the existing plan workspace. Meta
  -- commands never lock funnels, so their connection lock cannot form a cycle.
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if c.platform<>'meta' then raise exception 'Choose a Meta campaign plan for this setup review.'; end if;
  select * into m from public.korlix_meta_connections where user_id=p_actor for share;
  select * into saved from public.korlix_funnel_meta_preparations where campaign_id=c.id for update;
  select x into account from jsonb_array_elements(coalesce(m.accounts,'[]')) x where x->>'id'=m.selected_account limit 1;
  select x into page from jsonb_array_elements(coalesce(m.pages,'[]')) x where x->>'id'=m.selected_page limit 1;
  configured:=coalesce(p_data->>'configured'='true',false);
  connected:=coalesce(m.user_id is not null and m.config_hash=p_data->>'config_hash' and not m.needs_reconnect and m.expires_at>now()+interval '60 seconds',false);
  checks:=jsonb_build_object(
    'page_published',f.state='published' and f.published is not null,
    'plan_reviewed',coalesce(c.state='reviewed' and c.reviewed_page_version=f.published_version and length(trim(c.headline))>0 and length(trim(c.body))>0 and length(trim(c.cta))>0 and length(trim(c.audience))>0,false),
    'meta_configured',configured,'meta_connected',connected,
    'account_selected',account is not null,'account_active',coalesce(account->>'status'='1',false),
    'currency_supported',coalesce(account->>'currency'='USD',false),
    'page_selected',page is not null and not coalesce(m.pages_access_denied,false)
  );
  select bool_and(value='true'::jsonb) into ready from jsonb_each(checks);
  current_snapshot:=jsonb_build_object(
    'campaign',jsonb_build_object('id',c.id,'name',c.name,'headline',c.headline,'body',c.body,'cta',c.cta,'audience',c.audience,'daily_cents',c.daily_cents,'days',c.days,'currency','USD','planned_total_cents',c.daily_cents*c.days),
    'landing_page',jsonb_build_object('slug',f.slug,'version',f.published_version,'brand',coalesce(f.published->>'brand',''),'headline',coalesce(f.published->>'headline',''),'subheadline',coalesce(f.published->>'subheadline',''),'cta',coalesce(f.published->>'cta',''),'destination',(p_data->>'public_base')||'/f/'||f.slug||'?utm_source=facebook&utm_medium=paid&utm_campaign=k143_'||replace(c.id::text,'-','')),
    'meta',jsonb_build_object('connection_version',m.version,'account',case when account is null then null else jsonb_build_object('id',account->>'id','name',account->>'name','currency',account->>'currency','timezone',account->>'timezone','status',account->'status') end,'page',case when page is null then null else jsonb_build_object('id',page->>'id','name',page->>'name','category',page->>'category') end,'accounts_refreshed_at',m.refreshed_at,'pages_refreshed_at',m.pages_refreshed_at)
  );
  -- Hash only reviewed content and publication/connection identity. Manual
  -- reporting and unpublished page edits do not invalidate this review.
  current_fingerprint:=encode(sha256(convert_to(jsonb_build_object('snapshot',current_snapshot,'page_content',f.published,'page_state',f.state,'plan_state',c.state,'reviewed_page_version',c.reviewed_page_version,'binding',m.binding_id,'stored_config',m.config_hash,'current_config',p_data->>'config_hash','configured',configured)::text,'UTF8')),'hex');
  if p_action in ('review','clear') then
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) then raise exception 'This Meta setup review changed. Refresh and review it again.' using errcode='40001'; end if;
    if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm this Meta setup action.'; end if;
    if p_action='review' then
      if p_data->>'fingerprint' is distinct from current_fingerprint then raise exception 'The campaign, landing page or Meta selection changed. Refresh this review.' using errcode='40001'; end if;
      if not ready then raise exception 'Complete the setup checks before saving a Meta setup review.'; end if;
      insert into public.korlix_funnel_meta_preparations(campaign_id,snapshot,fingerprint,reviewed_at)
        values(c.id,current_snapshot,current_fingerprint,now()) on conflict(campaign_id) do update set snapshot=excluded.snapshot,fingerprint=excluded.fingerprint,reviewed_at=excluded.reviewed_at,version=public.korlix_funnel_meta_preparations.version+1,updated_at=now() returning * into saved;
    elsif saved.campaign_id is not null then
      update public.korlix_funnel_meta_preparations set snapshot=null,fingerprint=null,reviewed_at=null,version=version+1,updated_at=now() where campaign_id=c.id returning * into saved;
    end if;
  end if;
  return jsonb_build_object('source','meta_setup','funnel_id',f.id,'campaign_id',c.id,'version',coalesce(saved.version,0),'fingerprint',current_fingerprint,'checks',checks,'ready_for_review',ready,'review_current',coalesce(ready and saved.fingerprint=current_fingerprint,false),'reviewed_at',saved.reviewed_at,'reviewed_snapshot',saved.snapshot,'current_snapshot',current_snapshot,'ad_publishing_ready',false);
end $$;
revoke all on function public.korlix_funnel_meta_preparation_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_preparation_v1(uuid,text,uuid,jsonb) to service_role;
commit;
