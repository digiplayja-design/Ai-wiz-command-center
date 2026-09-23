begin;
-- Conservative draft count: printable ASCII costs one; every other code point
-- costs two. This never treats double-width text as a single character.
create function public.korlix_google_creative_valid_v1(v jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare k text; a jsonb; s text; lim integer;
begin
  if v is null or jsonb_typeof(v)<>'object' or not(v ?& array['headlines','descriptions','path1','path2']) or (v-array['headlines','descriptions','path1','path2'])<>'{}'::jsonb then return false; end if;
  foreach k in array array['headlines','descriptions'] loop
    a:=v->k; lim:=case when k='headlines' then 30 else 90 end;
    if jsonb_typeof(a)<>'array' then return false; end if;
    if jsonb_array_length(a)>(case when k='headlines' then 15 else 4 end) then return false; end if;
    if exists(select 1 from jsonb_array_elements(a) x where jsonb_typeof(x)<>'string') then return false; end if;
    if (select count(*)<>count(distinct lower(x)) from jsonb_array_elements_text(a) x) then return false; end if;
    for s in select jsonb_array_elements_text(a) loop
      if s<>btrim(s) or length(s)=0 or s ~ '[[:cntrl:]{}]' or s ~ U&'[\200B-\200F\2028-\202E\2060-\206F\FEFF]' or char_length(s)+char_length(regexp_replace(s,'[ -~]','','g'))>lim then return false; end if;
    end loop;
  end loop;
  foreach k in array array['path1','path2'] loop
    if jsonb_typeof(v->k)<>'string' then return false; end if;
    s:=v->>k;
    if s<>btrim(s) or s ~ '[[:cntrl:]{} /?#]' or position(chr(92) in s)>0 or s ~ U&'[\200B-\200F\2028-\202E\2060-\206F\FEFF]' or char_length(s)+char_length(regexp_replace(s,'[ -~]','','g'))>15 then return false; end if;
  end loop;
  return not (v->>'path1'='' and v->>'path2'<>'');
end $$;
revoke all on function public.korlix_google_creative_valid_v1(jsonb) from public,anon,authenticated;
grant execute on function public.korlix_google_creative_valid_v1(jsonb) to service_role;
create table public.korlix_funnel_google_creatives (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  version integer not null default 1 check(version>0),
  assets jsonb not null check(public.korlix_google_creative_valid_v1(assets)),
  context_fingerprint text not null check(context_fingerprint ~ '^[a-f0-9]{64}$'),
  context_snapshot jsonb not null check(jsonb_typeof(context_snapshot)='object' and octet_length(context_snapshot::text)<=32768),
  updated_at timestamptz not null default now()
);
alter table public.korlix_funnel_google_creatives enable row level security;
revoke all on public.korlix_funnel_google_creatives from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_google_creatives to service_role;
comment on table public.korlix_funnel_google_creatives is 'Private Google search-ad text drafts. No provider operation, review approval or spending authorization.';
create function public.korlix_funnel_google_creative_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; saved public.korlix_funnel_google_creatives;
  context jsonb; fingerprint text; assets jsonb;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Search-ad drafts require Enterprise.' using errcode='42501'; end if;
  if p_action not in ('read','save') then raise exception 'Unknown search-ad draft action.'; end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  if c.platform<>'google' then raise exception 'Choose a Google campaign for a search-ad draft.'; end if;
  select * into saved from public.korlix_funnel_google_creatives where campaign_id=c.id for update;
  context:=jsonb_build_object('campaign_name',c.name,'headline',c.headline,'body',c.body,'cta',c.cta,'audience',c.audience,'daily_cents',c.daily_cents,'days',c.days,'campaign_state',c.state,'page_state',f.state,'page_version',f.published_version,'brand',coalesce(f.published->>'brand',''),'destination',(p_data->>'public_base')||'/f/'||f.slug||'?utm_source=google&utm_medium=paid&utm_campaign=k143_'||replace(c.id::text,'-',''));
  fingerprint:=encode(sha256(convert_to(jsonb_build_object('context',context,'page_content',f.published,'reviewed_page_version',c.reviewed_page_version)::text,'UTF8')),'hex');
  if p_action='save' then
    if c.state='archived' then raise exception 'Reopen this campaign before editing its search-ad draft.'; end if;
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) or p_data->>'fingerprint' is distinct from fingerprint then raise exception 'The draft, campaign or landing page changed. Reload the saved draft before saving again.' using errcode='40001'; end if;
    if not public.korlix_google_creative_valid_v1(p_data->'assets') then raise exception 'Check the search-ad text, lengths and display paths.'; end if;
    insert into public.korlix_funnel_google_creatives(campaign_id,assets,context_fingerprint,context_snapshot) values(c.id,p_data->'assets',fingerprint,context)
    on conflict(campaign_id) do update set assets=excluded.assets,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,version=public.korlix_funnel_google_creatives.version+1,updated_at=now() returning * into saved;
  end if;
  assets:=coalesce(saved.assets,'{"headlines":[],"descriptions":[],"path1":"","path2":""}'::jsonb);
  return jsonb_build_object('source','google_search_draft','funnel_id',f.id,'campaign_id',c.id,'version',coalesce(saved.version,0),'fingerprint',fingerprint,'context',context,'saved_context',saved.context_snapshot,'assets',assets,'updated_at',saved.updated_at,'draft_current',coalesce(saved.context_fingerprint=fingerprint,false),'editable',c.state<>'archived','text_complete',jsonb_array_length(assets->'headlines')>=3 and jsonb_array_length(assets->'descriptions')>=2,'ad_publishing_ready',false);
end $$;
revoke all on function public.korlix_funnel_google_creative_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_google_creative_v1(uuid,text,uuid,jsonb) to service_role;
commit;
