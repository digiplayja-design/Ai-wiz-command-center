begin;
create table public.korlix_meta_delivery_connections (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 user_id uuid not null references public.korlix_meta_connections(user_id) on delete cascade,
 binding_id uuid not null unique,system_user_id text not null check(system_user_id ~ '^[0-9]{1,40}$'),
 destination_fingerprint text not null check(destination_fingerprint ~ '^[a-f0-9]{64}$'),
 sealed jsonb not null check(jsonb_typeof(sealed)='object' and sealed ?& array['v','iv','tag','ciphertext'] and sealed-array['v','iv','tag','ciphertext']='{}'::jsonb and sealed->'v'='1'::jsonb and sealed->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and sealed->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(sealed->>'ciphertext') between 1 and 20000),
 expires_at timestamptz check(expires_at is null or isfinite(expires_at)),checked_at timestamptz not null default clock_timestamp()
);
create table public.korlix_meta_delivery_settings (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 revision uuid not null default gen_random_uuid(),enabled boolean not null default false,
 context_hash text not null check(context_hash ~ '^[a-f0-9]{64}$'),measurement_revision uuid,
 armed_at timestamptz not null default clock_timestamp()
);
create table public.korlix_meta_delivery_attempts (
 lead_id uuid primary key references public.korlix_meta_measurement_receipts(lead_id) on delete cascade,
 event_id uuid not null unique,id uuid not null unique default gen_random_uuid(),
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 revision uuid not null,context_hash text not null check(context_hash ~ '^[a-f0-9]{64}$'),
 grant_binding uuid not null,destination jsonb not null check(public.korlix_meta_conversion_destination_valid(destination)),
 state text not null default 'checking' check(state in ('checking','blocked','uncertain','received')),
 request_hash text check(request_hash ~ '^[a-f0-9]{64}$'),trace_id text check(trace_id ~ '^[A-Za-z0-9_-]{1,200}$'),
 has_warnings boolean not null default false,created_at timestamptz not null default clock_timestamp(),dispatched_at timestamptz,received_at timestamptz,
 check((state in ('checking','blocked') and request_hash is null and dispatched_at is null and trace_id is null and received_at is null) or
  (state='uncertain' and request_hash is not null and dispatched_at is not null and trace_id is null and received_at is null) or
  (state='received' and request_hash is not null and dispatched_at is not null and trace_id is not null and received_at is not null))
);
create index korlix_meta_delivery_attempts_campaign on public.korlix_meta_delivery_attempts(campaign_id,created_at);
create table public.korlix_meta_delivery_observations (
 id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.korlix_meta_delivery_attempts(id) on delete cascade,
 recorded_at timestamptz not null default clock_timestamp(),state text not null check(state in ('checking','blocked','uncertain','received')),
 has_warnings boolean not null default false
);
create index korlix_meta_delivery_observations_attempt on public.korlix_meta_delivery_observations(attempt_id,recorded_at);
alter table public.korlix_meta_delivery_connections enable row level security;
alter table public.korlix_meta_delivery_settings enable row level security;
alter table public.korlix_meta_delivery_attempts enable row level security;
alter table public.korlix_meta_delivery_observations enable row level security;
revoke all on public.korlix_meta_delivery_connections,public.korlix_meta_delivery_settings,public.korlix_meta_delivery_attempts,public.korlix_meta_delivery_observations from public,anon,authenticated,service_role;
grant select,insert,update,delete on public.korlix_meta_delivery_connections to service_role;
grant select,insert,update on public.korlix_meta_delivery_settings to service_role;
grant select,insert on public.korlix_meta_delivery_attempts,public.korlix_meta_delivery_observations to service_role;
grant update(state,request_hash,trace_id,has_warnings,dispatched_at,received_at) on public.korlix_meta_delivery_attempts to service_role;
comment on table public.korlix_meta_delivery_connections is 'Separate encrypted Meta system-user token, bound to owner/campaign/destination; never reuse the advertising USER token for CAPI. Disconnect of the Meta connection cascades credentials. Scope and readable pixel identity do not prove event-write acceptance.';
comment on table public.korlix_meta_delivery_attempts is 'At most one HTTP dispatch per future v2 receipt. Stable event ID; no raw click, browser data or credential copies. Received means events_received=1 only, not matching, processing, attributed credit or sales.';
comment on table public.korlix_meta_delivery_observations is 'Append-only, bounded local delivery state evidence. No raw provider message text. Cascade with inquiry deletion.';

create function public.korlix_meta_delivery_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 s public.korlix_meta_delivery_settings;a public.korlix_meta_delivery_attempts;r public.korlix_meta_measurement_receipts;
 m public.korlix_meta_measurement_settings;u public.korlix_meta_delivery_connections;f public.korlix_funnels;
 d jsonb;ctx text;fp text;grant_ready boolean;authorize_ready boolean;ready boolean;current_setup boolean;eligible boolean;rows jsonb;
 campaign uuid:=(p_data->>'campaign_id')::uuid;expiry timestamptz;
 allowed text[]:=array['campaign_id','configured','config_hash','measurement_configured','measurement_config_hash','public_origin','delivery_configured'];
begin
 if p_action is null or p_action not in ('read','authorize','disconnect','credentials','settings','claim','dispatch','blocked','received') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose a Meta delivery action.';end if;
 allowed:=allowed||case p_action when 'authorize' then array['fingerprint','confirmed','binding_id','system_user_id','sealed','expires_at'] when 'disconnect' then array['fingerprint','confirmed'] when 'credentials' then array['fingerprint'] when 'settings' then array['fingerprint','confirmed','enabled'] when 'claim' then array['fingerprint','confirmed','event_id'] when 'dispatch' then array['id','request_hash'] when 'blocked' then array['id'] when 'received' then array['id','trace_id','has_warnings'] else array[]::text[] end;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(allowed)) then raise exception 'Unexpected Meta delivery fields.';end if;
 if jsonb_typeof(p_data->'measurement_configured') is distinct from 'boolean' or jsonb_typeof(p_data->'delivery_configured') is distinct from 'boolean' or coalesce(p_data->>'measurement_config_hash','') !~ '^[a-f0-9]{64}$' then raise exception 'Meta delivery configuration is unavailable.';end if;
 -- Existing destination function checks Enterprise, ownership and takes
 -- funnel/campaign/advertising-connection locks before the new locks below.
 d:=public.korlix_funnel_meta_destination_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',campaign,'configured',p_data->'configured','config_hash',p_data->'config_hash'));
 select * into f from public.korlix_funnels where id=p_funnel;
 select * into m from public.korlix_meta_measurement_settings where campaign_id=campaign for update;
 select * into u from public.korlix_meta_delivery_connections where campaign_id=campaign for update;
 select * into s from public.korlix_meta_delivery_settings where campaign_id=campaign for update;
 authorize_ready:=coalesce(p_data->'delivery_configured'='true'::jsonb and d->'selection_current'='true'::jsonb and d->'context'->'editable'='true'::jsonb,false);
 grant_ready:=coalesce(authorize_ready and u.user_id=p_actor and u.destination_fingerprint=d->>'fingerprint' and (u.expires_at is null or u.expires_at>clock_timestamp()+interval '60 seconds'),false);
 ready:=coalesce(grant_ready and p_data->'measurement_configured'='true'::jsonb and m.enabled and m.config_hash=p_data->>'measurement_config_hash' and m.public_origin=p_data->>'public_origin' and f.state='published' and nullif(f.published->>'privacy_url','') is not null and exists(select 1 from public.korlix_funnel_attribution_links where campaign_id=campaign),false);
 ctx:=encode(sha256(convert_to(jsonb_build_object('contract','meta_delivery_v1','destination',d->'fingerprint','grant',u.binding_id,'measurement',m.revision,'measurement_config',p_data->'measurement_config_hash','public_origin',p_data->'public_origin','configured',p_data->'delivery_configured')::text,'UTF8')),'hex');
 fp:=encode(sha256(convert_to(jsonb_build_object('context',ctx,'revision',s.revision)::text,'UTF8')),'hex');
 current_setup:=coalesce(ready and s.enabled and s.context_hash=ctx and s.measurement_revision=m.revision,false);
 if p_action='read' then
  select coalesce(jsonb_agg(x.value order by x.captured_at desc,x.event_id),'[]') into rows from (
   select rr.captured_at,rr.event_id,jsonb_build_object('event_id',rr.event_id,'captured_at',rr.captured_at,
    'state',case when aa.state='checking' and aa.created_at<clock_timestamp()-interval '2 minutes' then 'blocked' when aa.state is not null then aa.state
     when current_setup and rr.settings_revision=m.revision and rr.captured_at>s.armed_at and rr.captured_at<=clock_timestamp() and rr.captured_at>clock_timestamp()-interval '7 days' and rr.observed_at<=clock_timestamp() then 'ready' else 'ineligible' end,
    'received_at',aa.received_at,'has_warnings',coalesce(aa.has_warnings,false)) value
   from public.korlix_meta_measurement_receipts rr left join public.korlix_meta_delivery_attempts aa on aa.lead_id=rr.lead_id
   where rr.campaign_id=campaign and rr.state='prepared' and rr.consent='granted' and (aa.id is not null or s.enabled and rr.captured_at>s.armed_at)
   order by rr.captured_at desc,rr.event_id limit 50
  )x;
  return jsonb_build_object('source','meta_conversion_delivery','funnel_id',p_funnel,'campaign_id',campaign,'campaign_name',d->'campaign_name','configured',p_data->'delivery_configured'='true'::jsonb,'can_authorize',authorize_ready,'can_enable',ready,'enabled',coalesce(s.enabled,false),'current',current_setup,'fingerprint',fp,'since',case when s.enabled then s.armed_at else null end,
   'authorization',jsonb_build_object('connected',u.campaign_id is not null,'current',grant_ready,'expires_at',u.expires_at,'checked_at',u.checked_at),
   'destination',case when d->'selection'='null'::jsonb then null else d->'selection'->'destination' end,
   'rows',rows,'row_limit',50,'provider_verified',false);
 end if;
 if p_action in ('authorize','disconnect','credentials','settings','claim') then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'Meta delivery setup changed. Refresh before continuing.' using errcode='40001';end if;
  if p_action<>'credentials' and p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm the Meta delivery action.';end if;
 end if;
 if p_action='authorize' then
  if not authorize_ready then raise exception 'Finish Meta account and data source setup before authorizing conversion delivery.' using errcode='40001';end if;
  if p_data->'expires_at'<>'null'::jsonb then
   if jsonb_typeof(p_data->'expires_at') is distinct from 'string' then raise exception 'Invalid conversion authorization expiry.';end if;
   expiry:=(p_data->>'expires_at')::timestamptz;
   if not isfinite(expiry) or expiry<=clock_timestamp()+interval '60 seconds' then raise exception 'Conversion authorization expired.' using errcode='40001';end if;
  end if;
  if not(p_data?'expires_at') or jsonb_typeof(p_data->'sealed') is distinct from 'object' or jsonb_typeof(p_data->'system_user_id') is distinct from 'string' or coalesce(p_data->>'system_user_id','') !~ '^[0-9]{1,40}$' then raise exception 'Invalid conversion authorization.';end if;
  insert into public.korlix_meta_delivery_connections(campaign_id,user_id,binding_id,system_user_id,destination_fingerprint,sealed,expires_at)
   values(campaign,p_actor,(p_data->>'binding_id')::uuid,p_data->>'system_user_id',d->>'fingerprint',p_data->'sealed',expiry)
   on conflict(campaign_id) do update set user_id=excluded.user_id,binding_id=excluded.binding_id,system_user_id=excluded.system_user_id,destination_fingerprint=excluded.destination_fingerprint,sealed=excluded.sealed,expires_at=excluded.expires_at,checked_at=clock_timestamp();
  update public.korlix_meta_delivery_settings set enabled=false,revision=gen_random_uuid(),armed_at=clock_timestamp() where campaign_id=campaign;
  return '{}';
 elsif p_action='disconnect' then
  delete from public.korlix_meta_delivery_connections where campaign_id=campaign;
  update public.korlix_meta_delivery_settings set enabled=false,revision=gen_random_uuid(),armed_at=clock_timestamp() where campaign_id=campaign;
  return '{}';
 elsif p_action='credentials' then
  if not grant_ready then raise exception 'Authorize current Meta conversion access first.' using errcode='40001';end if;
  return jsonb_build_object('sealed',u.sealed,'binding_id',u.binding_id,'system_user_id',u.system_user_id,'destination',d->'selection'->'destination','account',d->'context'->'account');
 elsif p_action='settings' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'Choose whether to prepare future Meta inquiries.';end if;
  if p_data->'enabled'='true'::jsonb and not ready then raise exception 'Finish Meta destination, conversion authorization and website consent setup first.' using errcode='40001';end if;
  insert into public.korlix_meta_delivery_settings(campaign_id,enabled,context_hash,measurement_revision) values(campaign,(p_data->>'enabled')::boolean,ctx,m.revision)
   on conflict(campaign_id) do update set enabled=excluded.enabled,context_hash=excluded.context_hash,measurement_revision=excluded.measurement_revision,revision=gen_random_uuid(),armed_at=clock_timestamp();
  return '{}';
 end if;
 if p_action='claim' then
  select * into r from public.korlix_meta_measurement_receipts where campaign_id=campaign and event_id=(p_data->>'event_id')::uuid;
  if r.lead_id is null then raise exception 'Meta inquiry evidence not found.' using errcode='P0002';end if;
  select * into a from public.korlix_meta_delivery_attempts where lead_id=r.lead_id for update;
 else
  select * into a from public.korlix_meta_delivery_attempts where id=(p_data->>'id')::uuid and campaign_id=campaign for update;
  if a.id is null then raise exception 'Meta delivery attempt no longer exists.' using errcode='P0002';end if;
  select * into r from public.korlix_meta_measurement_receipts where lead_id=a.lead_id;
 end if;
 eligible:=coalesce(current_setup and r.consent='granted' and r.policy_version='meta_measurement_v2' and r.state='prepared' and r.settings_revision=m.revision and r.captured_at>s.armed_at and r.captured_at<=clock_timestamp() and r.captured_at>clock_timestamp()-interval '7 days' and r.observed_at<=clock_timestamp(),false);
 if p_action='claim' then
  if not eligible or a.id is not null then raise exception 'This Meta inquiry cannot be sent or already has a delivery attempt. Refresh its status.' using errcode='40001';end if;
  insert into public.korlix_meta_delivery_attempts(lead_id,event_id,campaign_id,revision,context_hash,grant_binding,destination)
   values(r.lead_id,r.event_id,campaign,s.revision,ctx,u.binding_id,d->'selection'->'destination') returning * into a;
  insert into public.korlix_meta_delivery_observations(attempt_id,state) values(a.id,'checking');
  return jsonb_build_object('id',a.id,'sealed',u.sealed,'binding_id',u.binding_id,'system_user_id',u.system_user_id,'account',d->'context'->'account','destination',a.destination,'receipt',
   jsonb_build_object('event_id',r.event_id,'captured_at',r.captured_at,'observed_at',r.observed_at,'click_id',r.click_id,'client_user_agent',r.client_user_agent,'event_source_url',r.event_source_url,'consent',r.consent,'policy_version',r.policy_version,'event_name',r.event_name,'action_source',r.action_source,'state',r.state));
 elsif p_action='dispatch' then
  if not eligible or a.state<>'checking' or a.context_hash<>ctx or a.revision<>s.revision or a.grant_binding<>u.binding_id or a.created_at<clock_timestamp()-interval '2 minutes' then raise exception 'Inquiry or Meta setup changed before dispatch. No upload was started.' using errcode='40001';end if;
  if coalesce(p_data->>'request_hash','') !~ '^[a-f0-9]{64}$' then raise exception 'Invalid delivery fingerprint.';end if;
  update public.korlix_meta_delivery_attempts set state='uncertain',request_hash=p_data->>'request_hash',dispatched_at=clock_timestamp() where id=a.id;
  insert into public.korlix_meta_delivery_observations(attempt_id,state) values(a.id,'uncertain');
 elsif p_action='blocked' then
  if a.state='checking' then
   update public.korlix_meta_delivery_attempts set state='blocked' where id=a.id;
   insert into public.korlix_meta_delivery_observations(attempt_id,state) values(a.id,'blocked');
  end if;
 elsif p_action='received' then
  if a.state<>'uncertain' or coalesce(p_data->>'trace_id','') !~ '^[A-Za-z0-9_-]{1,200}$' or jsonb_typeof(p_data->'has_warnings') is distinct from 'boolean' then raise exception 'Meta receipt could not be recorded.' using errcode='40001';end if;
  update public.korlix_meta_delivery_attempts set state='received',trace_id=p_data->>'trace_id',has_warnings=(p_data->>'has_warnings')::boolean,received_at=clock_timestamp() where id=a.id;
  insert into public.korlix_meta_delivery_observations(attempt_id,state,has_warnings) values(a.id,'received',(p_data->>'has_warnings')::boolean);
 end if;
 return '{}';
end $$;
revoke all on function public.korlix_meta_delivery_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_meta_delivery_v1(uuid,text,uuid,jsonb) to service_role;
commit;
