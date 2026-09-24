begin;
create function public.korlix_meta_conversion_destination_valid(d jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
begin
 return coalesce(jsonb_typeof(d)='object' and d ?& array['pixel_id','name'] and (d-array['pixel_id','name'])='{}'::jsonb
  and jsonb_typeof(d->'pixel_id')='string' and d->>'pixel_id' ~ '^[0-9]{1,40}$'
  and jsonb_typeof(d->'name')='string' and length(d->>'name') between 1 and 1000 and trim(d->>'name')=d->>'name' and d->>'name' !~ '[[:cntrl:]]',false);
end $$;
revoke all on function public.korlix_meta_conversion_destination_valid(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_meta_conversion_destination_valid(jsonb) to service_role;

create table public.korlix_funnel_meta_conversion_destinations (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 version integer not null default 1 check(version>0),
 destination jsonb check(destination is null or public.korlix_meta_conversion_destination_valid(destination)),
 context_fingerprint text check(context_fingerprint ~ '^[a-f0-9]{64}$'),
 context_snapshot jsonb check(jsonb_typeof(context_snapshot)='object'),
 checked_at timestamptz,
 saved_at timestamptz,
 updated_at timestamptz not null default now(),
 check((destination is null and context_fingerprint is null and context_snapshot is null and checked_at is null and saved_at is null) or
  (destination is not null and context_fingerprint is not null and context_snapshot is not null and checked_at is not null and saved_at is not null))
);
alter table public.korlix_funnel_meta_conversion_destinations enable row level security;
revoke all on public.korlix_funnel_meta_conversion_destinations from public,anon,authenticated,service_role;
grant select,insert,update on public.korlix_funnel_meta_conversion_destinations to service_role;
comment on table public.korlix_funnel_meta_conversion_destinations is 'Private, owner-confirmed conversion destination and last checked Meta metadata. Listed account data source metadata only; no claim of event write permission. No visitor data or upload authorization. Cleared rows retain versions; deletes cascade with campaign.';

create function public.korlix_funnel_meta_destination_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare g jsonb;ctx jsonb;w public.korlix_funnel_meta_conversion_destinations;fp text;ready boolean;checked timestamptz;
begin
 if p_action is null or p_action not in ('read','save','clear') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose a conversion destination action.';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'read' then array['campaign_id','configured','config_hash'] when 'save' then array['campaign_id','configured','config_hash','version','fingerprint','confirmed','destination','checked_at'] else array['campaign_id','configured','config_hash','version','fingerprint','confirmed'] end)) then raise exception 'Unexpected conversion destination fields.';end if;
 -- Existing service-only context repeats current Enterprise/ownership and takes
 -- funnel/campaign/connection locks. Its fingerprint binds account and link.
 g:=public.korlix_funnel_meta_campaign_link_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',p_data->'campaign_id','configured',p_data->'configured','config_hash',p_data->'config_hash'));
 select * into w from public.korlix_funnel_meta_conversion_destinations where campaign_id=(g->>'campaign_id')::uuid for update;
 ready:=coalesce(g->'lookup_ready'='true'::jsonb and g->'link_current'='true'::jsonb,false);
 ctx:=jsonb_build_object('account',g->'account','connection_version',g->'connection_version','provider_campaign_id',g->'link'->'provider_campaign_id','link_current',g->'link_current','editable',g->'editable');
 fp:=encode(sha256(convert_to(jsonb_build_object('contract','meta_destination_v1','context',g->'fingerprint','version',coalesce(w.version,0))::text,'UTF8')),'hex');
 if p_action<>'read' then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'The conversion destination, campaign or Meta connection changed. Refresh before saving.' using errcode='40001';end if;
  if jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$' then raise exception 'Refresh the conversion destination.';end if;
  if (p_data->>'version')::bigint is distinct from coalesce(w.version,0) then raise exception 'The conversion destination changed. Refresh it.' using errcode='40001';end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm this conversion destination change.';end if;
  if p_action='save' then
   if not ready then raise exception 'Connect and link the active Meta advertising account before choosing a conversion destination.' using errcode='40001';end if;
   if not public.korlix_meta_conversion_destination_valid(p_data->'destination') then raise exception 'Choose a listed Meta data source.';end if;
   if jsonb_typeof(p_data->'checked_at') is distinct from 'string' then raise exception 'Refresh Meta data sources.';end if;
   checked:=(p_data->>'checked_at')::timestamptz;
   if not isfinite(checked) or checked<now()-interval '5 minutes' or checked>now()+interval '1 minute' then raise exception 'The data source check expired. Reload Meta data sources.' using errcode='40001';end if;
   -- HTTP authenticates the signed choice and repeats provider discovery before
   -- this internal-only write. This is not evidence of Conversions API write access.
   insert into public.korlix_funnel_meta_conversion_destinations(campaign_id,destination,context_fingerprint,context_snapshot,checked_at,saved_at)
    values((g->>'campaign_id')::uuid,p_data->'destination',g->>'fingerprint',ctx,checked,now())
    on conflict(campaign_id) do update set destination=excluded.destination,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,checked_at=excluded.checked_at,saved_at=excluded.saved_at,version=korlix_funnel_meta_conversion_destinations.version+1,updated_at=now();
  else
   insert into public.korlix_funnel_meta_conversion_destinations(campaign_id) values((g->>'campaign_id')::uuid)
    on conflict(campaign_id) do update set destination=null,context_fingerprint=null,context_snapshot=null,checked_at=null,saved_at=null,version=korlix_funnel_meta_conversion_destinations.version+1,updated_at=now();
  end if;
  return public.korlix_funnel_meta_destination_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',p_data->'campaign_id','configured',p_data->'configured','config_hash',p_data->'config_hash'));
 end if;
 return jsonb_build_object('source','meta_conversion_destination','funnel_id',g->'funnel_id','campaign_id',g->'campaign_id','campaign_name',g->'campaign_name','version',coalesce(w.version,0),'fingerprint',fp,'context',ctx,'lookup_ready',ready,
  'selection_current',coalesce(ready and w.context_fingerprint=g->>'fingerprint',false),'selection',case when w.destination is null then null else jsonb_build_object('destination',w.destination,'context',w.context_snapshot,'checked_at',w.checked_at,'saved_at',w.saved_at) end,
  'event_name','Lead','delivery_state','not_implemented','send_ready',false,'provider_verified',false);
end $$;
revoke all on function public.korlix_funnel_meta_destination_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_funnel_meta_destination_v1(uuid,text,uuid,jsonb) to service_role;
commit;
