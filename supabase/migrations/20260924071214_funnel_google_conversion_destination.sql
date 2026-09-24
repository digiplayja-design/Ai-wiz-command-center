begin;
create function public.korlix_google_conversion_destination_valid(d jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare keys text[]:=array['conversion_customer_id','conversion_action_id','resource_name','name','status','type','category','counting_type','primary_for_goal','click_window_days','attribution_model','default_value','default_currency','always_use_default_value'];k text;
begin
 if jsonb_typeof(d) is distinct from 'object' or not(d ?& keys) or (d-keys)<>'{}'::jsonb then return false;end if;
 foreach k in array keys loop
  if jsonb_typeof(d->k) is distinct from (case when k in ('primary_for_goal','always_use_default_value') then 'boolean' when k in ('click_window_days','default_value') then 'number' else 'string' end) then return false;end if;
 end loop;
 if not coalesce(d->>'conversion_customer_id' ~ '^[0-9]{10}$' and d->>'conversion_action_id' ~ '^[1-9][0-9]{0,18}$' and d->>'click_window_days' ~ '^[0-9]{1,2}$',false) then return false;end if;
 return coalesce((d->>'conversion_action_id')::numeric<=9223372036854775807 and d->>'resource_name'='customers/'||(d->>'conversion_customer_id')||'/conversionActions/'||(d->>'conversion_action_id')
  and length(d->>'name') between 1 and 1000 and trim(d->>'name')=d->>'name' and d->>'name' !~ '[[:cntrl:]]'
  and d->>'status'='ENABLED' and d->>'type'='UPLOAD_CLICKS' and d->>'category'='SUBMIT_LEAD_FORM'
  and d->>'counting_type' in ('ONE_PER_CLICK','MANY_PER_CLICK') and (d->>'click_window_days')::integer between 1 and 90
  and d->>'attribution_model' in ('GOOGLE_ADS_LAST_CLICK','GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN')
  and (d->>'default_value')::numeric between 0 and 1000000000000 and d->>'default_currency' ~ '^([A-Z]{3})?$',false);
end $$;
revoke all on function public.korlix_google_conversion_destination_valid(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_google_conversion_destination_valid(jsonb) to service_role;

create table public.korlix_funnel_google_conversion_destinations (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 version integer not null default 1 check(version>0),
 destination jsonb check(destination is null or public.korlix_google_conversion_destination_valid(destination)),
 context_fingerprint text check(context_fingerprint ~ '^[a-f0-9]{64}$'),
 context_snapshot jsonb check(jsonb_typeof(context_snapshot)='object'),
 checked_at timestamptz,
 saved_at timestamptz,
 updated_at timestamptz not null default now(),
 check((destination is null and context_fingerprint is null and context_snapshot is null and checked_at is null and saved_at is null) or
  (destination is not null and context_fingerprint is not null and context_snapshot is not null and checked_at is not null and saved_at is not null))
);
alter table public.korlix_funnel_google_conversion_destinations enable row level security;
revoke all on public.korlix_funnel_google_conversion_destinations from public,anon,authenticated,service_role;
grant select,insert,update on public.korlix_funnel_google_conversion_destinations to service_role;
comment on table public.korlix_funnel_google_conversion_destinations is 'Private, owner-confirmed conversion destination and last checked Google metadata. No visitor data, uploads or upload authorization. Cleared rows retain versions; deletes cascade with campaign.';

create function public.korlix_funnel_google_destination_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare g jsonb;ctx jsonb;w public.korlix_funnel_google_conversion_destinations;fp text;ready boolean;checked timestamptz;
begin
 if p_action is null or p_action not in ('read','save','clear') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose a conversion destination action.';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'read' then array['campaign_id','configured','config_hash'] when 'save' then array['campaign_id','configured','config_hash','version','fingerprint','confirmed','destination','checked_at'] else array['campaign_id','configured','config_hash','version','fingerprint','confirmed'] end)) then raise exception 'Unexpected conversion destination fields.';end if;
 -- Existing service-only context repeats current Enterprise/ownership and takes
 -- funnel/campaign/connection locks. Its fingerprint binds account and link.
 g:=public.korlix_funnel_google_campaign_link_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',p_data->'campaign_id','configured',p_data->'configured','config_hash',p_data->'config_hash'));
 select * into w from public.korlix_funnel_google_conversion_destinations where campaign_id=(g->>'campaign_id')::uuid for update;
 ready:=coalesce(g->'lookup_ready'='true'::jsonb and g->'link_current'='true'::jsonb and g->'account'->'test_account'='false'::jsonb,false);
 ctx:=jsonb_build_object('account',g->'account','root_id',g->'root_id','login_customer_id',g->'login_customer_id','connection_version',g->'connection_version','provider_campaign_id',g->'link'->'provider_campaign_id','link_current',g->'link_current','editable',g->'editable');
 fp:=encode(sha256(convert_to(jsonb_build_object('contract','google_destination_v1','context',g->'fingerprint','version',coalesce(w.version,0))::text,'UTF8')),'hex');
 if p_action<>'read' then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'The conversion destination, campaign or Google connection changed. Refresh before saving.' using errcode='40001';end if;
  if jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$' then raise exception 'Refresh the conversion destination.';end if;
  if (p_data->>'version')::bigint is distinct from coalesce(w.version,0) then raise exception 'The conversion destination changed. Refresh it.' using errcode='40001';end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm this conversion destination change.';end if;
  if p_action='save' then
   if not ready then raise exception 'Connect and link the active Google advertising account before choosing a conversion destination.' using errcode='40001';end if;
   if not public.korlix_google_conversion_destination_valid(p_data->'destination') then raise exception 'Choose an eligible imported lead-form conversion action.';end if;
   if jsonb_typeof(p_data->'checked_at') is distinct from 'string' then raise exception 'Refresh Google conversion actions.';end if;
   checked:=(p_data->>'checked_at')::timestamptz;
   if not isfinite(checked) or checked<now()-interval '5 minutes' or checked>now()+interval '1 minute' then raise exception 'The conversion action check expired. Reload Google conversion actions.' using errcode='40001';end if;
   -- HTTP authenticates the signed choice and repeats provider discovery before
   -- this internal-only write. This is not evidence of Data Manager access.
   insert into public.korlix_funnel_google_conversion_destinations(campaign_id,destination,context_fingerprint,context_snapshot,checked_at,saved_at)
    values((g->>'campaign_id')::uuid,p_data->'destination',g->>'fingerprint',ctx,checked,now())
    on conflict(campaign_id) do update set destination=excluded.destination,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,checked_at=excluded.checked_at,saved_at=excluded.saved_at,version=korlix_funnel_google_conversion_destinations.version+1,updated_at=now();
  else
   insert into public.korlix_funnel_google_conversion_destinations(campaign_id) values((g->>'campaign_id')::uuid)
    on conflict(campaign_id) do update set destination=null,context_fingerprint=null,context_snapshot=null,checked_at=null,saved_at=null,version=korlix_funnel_google_conversion_destinations.version+1,updated_at=now();
  end if;
  return public.korlix_funnel_google_destination_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',p_data->'campaign_id','configured',p_data->'configured','config_hash',p_data->'config_hash'));
 end if;
 return jsonb_build_object('source','google_conversion_destination','funnel_id',g->'funnel_id','campaign_id',g->'campaign_id','campaign_name',g->'campaign_name','version',coalesce(w.version,0),'fingerprint',fp,'context',ctx,'lookup_ready',ready,
  'selection_current',coalesce(ready and w.context_fingerprint=g->>'fingerprint',false),'selection',case when w.destination is null then null else jsonb_build_object('destination',w.destination,'context',w.context_snapshot,'checked_at',w.checked_at,'saved_at',w.saved_at) end,
  'event_name','inquiry_submitted','delivery_state','not_implemented','send_ready',false,'provider_verified',false);
end $$;
revoke all on function public.korlix_funnel_google_destination_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_funnel_google_destination_v1(uuid,text,uuid,jsonb) to service_role;
commit;
