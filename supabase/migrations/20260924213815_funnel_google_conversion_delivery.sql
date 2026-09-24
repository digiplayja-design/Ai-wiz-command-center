begin;
create table public.korlix_google_delivery_settings (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 revision uuid not null default gen_random_uuid(),enabled boolean not null default false,
 context_hash text not null check(context_hash ~ '^[a-f0-9]{64}$'),
 measurement_revision uuid,armed_at timestamptz not null default clock_timestamp()
);
create table public.korlix_google_delivery_attempts (
 lead_id uuid primary key references public.korlix_funnel_measurement_receipts(lead_id) on delete cascade,
 event_id uuid not null unique,id uuid not null unique default gen_random_uuid(),
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 revision uuid not null,context_hash text not null check(context_hash ~ '^[a-f0-9]{64}$'),
 grant_binding uuid not null,root_id text not null,account jsonb not null,destination jsonb not null check(public.korlix_google_conversion_destination_valid(destination)),
 state text not null default 'checking' check(state in ('checking','blocked','uncertain','submitted','processing','succeeded','rejected','partial')),
 request_hash text check(request_hash ~ '^[a-f0-9]{64}$'),request_id text check(length(request_id) between 1 and 512 and request_id !~ '[[:cntrl:][:space:]]'),
 has_warnings boolean not null default false,errors jsonb not null default '[]',warnings jsonb not null default '[]',
 created_at timestamptz not null default clock_timestamp(),dispatched_at timestamptz,checked_at timestamptz,
 poll_id uuid,poll_after timestamptz,
 check((state in ('checking','blocked') and request_hash is null and dispatched_at is null and request_id is null) or
  (state='uncertain' and request_hash is not null and dispatched_at is not null and request_id is null) or
  (state in ('submitted','processing','succeeded','rejected','partial') and request_hash is not null and dispatched_at is not null and request_id is not null))
);
create index korlix_google_delivery_attempts_campaign on public.korlix_google_delivery_attempts(campaign_id,created_at);
create table public.korlix_google_delivery_observations (
 id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.korlix_google_delivery_attempts(id) on delete cascade,
 recorded_at timestamptz not null default clock_timestamp(),state text not null,
 evidence jsonb not null default '{}'
);
create index korlix_google_delivery_observations_attempt on public.korlix_google_delivery_observations(attempt_id,recorded_at);
alter table public.korlix_google_delivery_settings enable row level security;
alter table public.korlix_google_delivery_attempts enable row level security;
alter table public.korlix_google_delivery_observations enable row level security;
revoke all on public.korlix_google_delivery_settings,public.korlix_google_delivery_attempts,public.korlix_google_delivery_observations from public,anon,authenticated,service_role;
grant select,insert,update on public.korlix_google_delivery_settings,public.korlix_google_delivery_attempts to service_role;
revoke update on public.korlix_google_delivery_attempts from service_role;
grant update(state,request_hash,request_id,has_warnings,errors,warnings,dispatched_at,checked_at,poll_id,poll_after) on public.korlix_google_delivery_attempts to service_role;
grant select,insert on public.korlix_google_delivery_observations to service_role;
comment on table public.korlix_google_delivery_attempts is 'One dispatch maximum per consent receipt. No raw click or token copies. Request receipt is not processing success or ad attribution. Cascade deletes evidence with inquiry.';
comment on table public.korlix_google_delivery_observations is 'Append-only delivery transitions and bounded, sanitized diagnostic evidence. No raw provider bodies, click identifiers or credentials.';
create function public.korlix_google_delivery_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 s public.korlix_google_delivery_settings;a public.korlix_google_delivery_attempts;r public.korlix_funnel_measurement_receipts;
 m public.korlix_funnel_measurement_settings;u public.korlix_google_upload_connections;f public.korlix_funnels;
 d jsonb;access jsonb;ctx text;fp text;ready boolean;current_setup boolean;poll_ready boolean;eligible boolean;rows jsonb;v jsonb;
 campaign uuid:=(p_data->>'campaign_id')::uuid;
 allowed text[]:=array['campaign_id','ads_configured','ads_config_hash','configured','config_hash','delivery_configured'];
begin
 if p_action is null or p_action not in ('read','settings','claim','dispatch','blocked','received','poll','status') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose a Google delivery action.';end if;
 allowed:=allowed||case p_action when 'settings' then array['fingerprint','confirmed','enabled'] when 'claim' then array['fingerprint','confirmed','event_id'] when 'dispatch' then array['id','request_hash'] when 'blocked' then array['id'] when 'received' then array['id','request_id','has_warnings'] when 'poll' then array['event_id'] when 'status' then array['id','poll_id','state','errors','warnings'] else array[]::text[] end;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(allowed)) then raise exception 'Unexpected Google delivery fields.';end if;
 access:=public.korlix_google_upload_access_v1(p_actor,'read',p_funnel,p_data-'delivery_configured'-'fingerprint'-'confirmed'-'enabled'-'event_id'-'id'-'request_hash'-'request_id'-'has_warnings'-'poll_id'-'state'-'errors'-'warnings');
 d:=public.korlix_funnel_google_destination_v1(p_actor,'read',p_funnel,jsonb_build_object('campaign_id',campaign,'configured',p_data->'ads_configured','config_hash',p_data->'ads_config_hash'));
 select * into f from public.korlix_funnels where id=p_funnel;
 select * into m from public.korlix_funnel_measurement_settings where campaign_id=campaign;
 select * into u from public.korlix_google_upload_connections where user_id=p_actor;
 select * into s from public.korlix_google_delivery_settings where campaign_id=campaign for update;
 ready:=coalesce(p_data->'delivery_configured'='true'::jsonb and access->'authorization'->'current'='true'::jsonb and m.enabled and f.state='published' and nullif(f.published->>'privacy_url','') is not null and exists(select 1 from public.korlix_funnel_attribution_links where campaign_id=campaign),false);
 ctx:=encode(sha256(convert_to(jsonb_build_object('contract','google_delivery_v1','destination',d->'fingerprint','grant',u.binding_id,'grant_version',u.version,'measurement',m.revision,'upload_config',p_data->'config_hash','configured',p_data->'delivery_configured')::text,'UTF8')),'hex');
 fp:=encode(sha256(convert_to(jsonb_build_object('context',ctx,'revision',s.revision)::text,'UTF8')),'hex');
 current_setup:=coalesce(ready and s.enabled and s.context_hash=ctx and s.measurement_revision=m.revision,false);
 poll_ready:=coalesce(p_data->'delivery_configured'='true'::jsonb and access->'authorization'->'current'='true'::jsonb,false);
 if p_action='read' then
  select coalesce(jsonb_agg(x.value order by x.captured_at desc,x.event_id),'[]') into rows from (
   select rr.captured_at,rr.event_id,jsonb_build_object('event_id',rr.event_id,'captured_at',rr.captured_at,'click_type',rr.click_type,
    'state',case when aa.state='checking' and aa.created_at<clock_timestamp()-interval '2 minutes' then 'blocked' when aa.state is not null then aa.state
     when current_setup and rr.settings_revision=m.revision and rr.captured_at> s.armed_at and rr.captured_at<=clock_timestamp() and rr.captured_at>=clock_timestamp()-make_interval(days=>least(7,(d->'selection'->'destination'->>'click_window_days')::int)) and (rr.click_type='gclid' or d->'selection'->'destination'->>'counting_type'='MANY_PER_CLICK') then 'ready' else 'ineligible' end,
    'checked_at',aa.checked_at,'has_warnings',coalesce(aa.has_warnings,false),'errors',coalesce(aa.errors,'[]'),'warnings',coalesce(aa.warnings,'[]'),
    'can_check',coalesce(poll_ready and aa.request_id is not null and aa.grant_binding=u.binding_id and aa.account=u.account and aa.root_id=u.root_id and aa.state in ('submitted','processing') and (aa.poll_after is null or aa.poll_after<=clock_timestamp()),false)) value
   from public.korlix_funnel_measurement_receipts rr left join public.korlix_google_delivery_attempts aa on aa.lead_id=rr.lead_id
   where rr.campaign_id=campaign and rr.platform='google' and rr.consent='granted' and rr.state='awaiting_setup' and (aa.id is not null or s.enabled and rr.captured_at>s.armed_at)
   order by rr.captured_at desc,rr.event_id limit 50
  )x;
  return jsonb_build_object('source','google_conversion_delivery','funnel_id',p_funnel,'campaign_id',campaign,'campaign_name',d->'campaign_name','configured',p_data->'delivery_configured'='true'::jsonb,'can_enable',ready,'enabled',coalesce(s.enabled,false),'current',current_setup,'fingerprint',fp,'since',case when s.enabled then s.armed_at else null end,
   'destination',case when d->'selection'='null'::jsonb then null else jsonb_build_object('name',d->'selection'->'destination'->'name','account_id',d->'selection'->'destination'->'conversion_customer_id','action_id',d->'selection'->'destination'->'conversion_action_id') end,
   'rows',rows,'row_limit',50,'provider_verified',false);
 end if;
 if p_action in ('settings','claim') then
  if p_data->>'fingerprint' is distinct from fp then raise exception 'Delivery setup changed. Refresh before continuing.' using errcode='40001';end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm the Google delivery action.';end if;
 end if;
 if p_action='settings' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'Choose whether to prepare future inquiries.';end if;
  if p_data->'enabled'='true'::jsonb and not ready then raise exception 'Finish Google destination, upload access and consent collection setup first.' using errcode='40001';end if;
  insert into public.korlix_google_delivery_settings(campaign_id,enabled,context_hash,measurement_revision) values(campaign,(p_data->>'enabled')::boolean,ctx,m.revision)
   on conflict(campaign_id) do update set enabled=excluded.enabled,context_hash=excluded.context_hash,measurement_revision=excluded.measurement_revision,revision=gen_random_uuid(),armed_at=clock_timestamp();
  return '{}';
 end if;
 if p_action in ('claim','poll') then
  select * into r from public.korlix_funnel_measurement_receipts where campaign_id=campaign and event_id=(p_data->>'event_id')::uuid;
  if r.lead_id is null then raise exception 'Inquiry evidence not found.' using errcode='P0002';end if;
  select * into a from public.korlix_google_delivery_attempts where lead_id=r.lead_id for update;
 else
  select * into a from public.korlix_google_delivery_attempts where id=(p_data->>'id')::uuid and campaign_id=campaign for update;
  if a.id is null then raise exception 'Delivery attempt no longer exists.' using errcode='P0002';end if;
  select * into r from public.korlix_funnel_measurement_receipts where lead_id=a.lead_id;
 end if;
 eligible:=coalesce(current_setup and r.platform='google' and r.consent='granted' and r.policy_version='measurement_v1' and r.state='awaiting_setup' and r.settings_revision=m.revision and r.captured_at>s.armed_at and r.captured_at<=clock_timestamp() and r.captured_at>=clock_timestamp()-make_interval(days=>least(7,(d->'selection'->'destination'->>'click_window_days')::int)) and (r.click_type='gclid' or d->'selection'->'destination'->>'counting_type'='MANY_PER_CLICK'),false);
 if p_action='claim' then
  if not eligible or a.id is not null then raise exception 'This inquiry cannot be sent or already has a delivery attempt. Refresh its status.' using errcode='40001';end if;
  insert into public.korlix_google_delivery_attempts(lead_id,event_id,campaign_id,revision,context_hash,grant_binding,root_id,account,destination)
   values(r.lead_id,r.event_id,campaign,s.revision,ctx,u.binding_id,u.root_id,u.account,d->'selection'->'destination') returning * into a;
  insert into public.korlix_google_delivery_observations(attempt_id,state) values(a.id,'checking');
  return jsonb_build_object('id',a.id,'sealed',u.sealed,'binding_id',u.binding_id,'root_id',u.root_id,'login_customer_id',u.login_customer_id,'account',u.account,'destination',a.destination,'receipt',jsonb_build_object('event_id',r.event_id,'captured_at',r.captured_at,'click_type',r.click_type,'click_id',r.click_id,'consent',r.consent,'policy_version',r.policy_version,'platform',r.platform,'event_name',r.event_name));
 elsif p_action='dispatch' then
  if not eligible or a.state<>'checking' or a.context_hash<>ctx or a.revision<>s.revision or a.created_at<clock_timestamp()-interval '2 minutes' then raise exception 'Inquiry or Google setup changed before dispatch. No upload was started.' using errcode='40001';end if;
  if coalesce(p_data->>'request_hash','') !~ '^[a-f0-9]{64}$' then raise exception 'Invalid delivery fingerprint.';end if;
  update public.korlix_google_delivery_attempts set state='uncertain',request_hash=p_data->>'request_hash',dispatched_at=clock_timestamp() where id=a.id;
  insert into public.korlix_google_delivery_observations(attempt_id,state,evidence) values(a.id,'uncertain',jsonb_build_object('request_hash',p_data->>'request_hash'));
 elsif p_action='blocked' then
  if a.state='checking' then
   update public.korlix_google_delivery_attempts set state='blocked' where id=a.id;
   insert into public.korlix_google_delivery_observations(attempt_id,state) values(a.id,'blocked');
  end if;
 elsif p_action='received' then
  if a.state<>'uncertain' or coalesce(length(p_data->>'request_id'),0) not between 1 and 512 or p_data->>'request_id' ~ '[[:cntrl:][:space:]]' or jsonb_typeof(p_data->'has_warnings') is distinct from 'boolean' then raise exception 'Delivery receipt could not be recorded.' using errcode='40001';end if;
  update public.korlix_google_delivery_attempts set state='submitted',request_id=p_data->>'request_id',has_warnings=(p_data->>'has_warnings')::boolean where id=a.id;
  insert into public.korlix_google_delivery_observations(attempt_id,state,evidence) values(a.id,'submitted',jsonb_build_object('has_warnings',p_data->'has_warnings'));
 elsif p_action='poll' then
  if not poll_ready or a.grant_binding is distinct from u.binding_id or a.account is distinct from u.account or a.root_id is distinct from u.root_id or a.request_id is null or a.state not in ('submitted','processing') then raise exception 'This delivery cannot be checked with the current Google upload access.' using errcode='40001';end if;
  if a.poll_after>clock_timestamp() then raise exception 'Wait one minute before checking this delivery again.' using errcode='54000';end if;
  update public.korlix_google_delivery_attempts set poll_id=gen_random_uuid(),poll_after=clock_timestamp()+interval '1 minute' where id=a.id returning * into a;
  return jsonb_build_object('id',a.id,'poll_id',a.poll_id,'request_id',a.request_id,'sealed',u.sealed,'binding_id',u.binding_id,'root_id',a.root_id,'destination',a.destination);
 elsif p_action='status' then
  if a.poll_id is distinct from (p_data->>'poll_id')::uuid or a.poll_id is null or a.state not in ('submitted','processing') or a.poll_after<=clock_timestamp() then raise exception 'This status check expired or was already saved.' using errcode='40001';end if;
  if p_data->>'state' is null or p_data->>'state' not in ('processing','succeeded','rejected','partial') then raise exception 'Invalid Google processing status.';end if;
  foreach v in array array[p_data->'errors',p_data->'warnings'] loop
   if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v)>100 then raise exception 'Invalid Google processing evidence.';end if;
   if exists(select 1 from jsonb_array_elements(v)e where jsonb_typeof(e) is distinct from 'object' or not(e?'reason' and e?'count') or (select count(*) from jsonb_object_keys(e))<>2 or coalesce(e->>'reason','') !~ '^[A-Z][A-Z0-9_]{0,159}$' or jsonb_typeof(e->'count') is distinct from 'number' or e->'count' not in ('0'::jsonb,'1'::jsonb)) then raise exception 'Invalid Google processing evidence.';end if;
  end loop;
  if p_data->>'state'='succeeded' and exists(select 1 from jsonb_array_elements(p_data->'errors')e where e->'count'='1'::jsonb) then raise exception 'Conflicting Google processing evidence.';end if;
  update public.korlix_google_delivery_attempts set state=p_data->>'state',errors=p_data->'errors',warnings=p_data->'warnings',has_warnings=has_warnings or jsonb_array_length(p_data->'warnings')>0,checked_at=clock_timestamp(),poll_id=null where id=a.id;
  insert into public.korlix_google_delivery_observations(attempt_id,state,evidence) values(a.id,p_data->>'state',jsonb_build_object('errors',p_data->'errors','warnings',p_data->'warnings'));
 end if;
 return '{}';
end $$;
revoke all on function public.korlix_google_delivery_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_google_delivery_v1(uuid,text,uuid,jsonb) to service_role;

-- Local setup/intake views are not delivery receipts.
create or replace function public.korlix_funnel_measurement_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels;c public.korlix_funnel_campaigns;s public.korlix_funnel_measurement_settings;l public.korlix_funnel_leads;
 out jsonb;rows jsonb;days integer;today date:=(now() at time zone 'UTC')::date;first_day date;
 usable boolean;choice text;kind text;identifier text;observed timestamptz;receipt_state text;disclosure text;
begin
 if p_action is null or p_action not in ('read','settings','resolve','capture') then raise exception 'Unknown measurement action.';end if;
 if p_action in ('resolve','capture') then
  if p_actor is not null then raise exception 'Invalid public measurement context.';end if;
  select * into f from public.korlix_funnels where id=p_funnel and slug=p_data->>'slug' for update;
  if not found or f.state<>'published' or not exists(select 1 from public.user_profiles where id=f.user_id and lower(trim(tier))='enterprise') then raise exception 'This page is not available.' using errcode='P0002';end if;
  select x.* into c from public.korlix_funnel_campaigns x join public.korlix_funnel_attribution_links k on k.campaign_id=x.id where x.funnel_id=f.id and k.code=p_data->>'code';
  if not found then raise exception 'This campaign link changed. Reload before submitting.' using errcode='40001';end if;
 else
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Conversion intake requires Enterprise.' using errcode='42501';end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002';end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id;
  if not found then raise exception 'Campaign not found.' using errcode='P0002';end if;
 end if;
 select * into s from public.korlix_funnel_measurement_settings where campaign_id=c.id;
 usable:=c.platform in ('google','meta') and c.state<>'archived' and f.state='published' and nullif(f.published->>'privacy_url','') is not null and exists(select 1 from public.korlix_funnel_attribution_links where campaign_id=c.id);
 if p_action='resolve' then
  if not (usable and coalesce(s.enabled,false)) then return null;end if;
  return jsonb_build_object('revision',s.revision,'platform',c.platform,'policy_version','measurement_v1');
 end if;
 if p_action='capture' then
  -- Serialize with settings, original capture and cleanup. A retry cannot add consent.
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  if found then return public.korlix_funnel_attribution_v1(null,'capture',f.id,p_data);end if;
  out:=public.korlix_funnel_attribution_v1(null,'capture',f.id,p_data);
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  if not found then return out;end if;
  -- Turning collection off invalidates old form contexts; the inquiry still succeeds.
  if not (usable and coalesce(s.enabled,false)) or p_data->>'settings_revision' is distinct from s.revision::text or p_data->>'platform' is distinct from c.platform then return out;end if;
  if p_data->>'policy_version' is distinct from 'measurement_v1' or p_data->>'measurement_consent' is null or p_data->>'measurement_consent' not in ('granted','declined') then raise exception 'Reload the measurement choice before submitting.';end if;
  choice:=p_data->>'measurement_consent';
  if choice='granted' then
   kind:=p_data->>'click_type';identifier:=p_data->>'click_id';
   if kind is not null or identifier is not null then
    if kind is null or identifier is null or length(identifier) not between 1 and 512 or identifier !~ '^[A-Za-z0-9_-]+$' or not ((c.platform='google' and kind in ('gclid','gbraid','wbraid')) or (c.platform='meta' and kind='fbclid')) or p_data->>'observed_at' is null then raise exception 'Invalid measurement evidence.';end if;
    observed:=(p_data->>'observed_at')::timestamptz;
    if observed<l.created_at-interval '1 hour' or observed>l.created_at+interval '5 minutes' then raise exception 'Expired measurement evidence.';end if;
   end if;
  end if;
  receipt_state:=case when choice='declined' then 'declined' when identifier is null then 'missing_click' else 'awaiting_setup' end;
  disclosure:='Optional: I allow '||(f.published->>'brand')||' to store the advertising click identifier from this link and share it, with the time of this inquiry, with '||case c.platform when 'google' then 'Google' else 'Meta' end||' to measure advertising results. My name, email, phone and message are not included. I can send my inquiry without agreeing.';
  insert into public.korlix_funnel_measurement_receipts(lead_id,campaign_id,platform,consent,policy_version,consent_text,privacy_url,page_version,settings_revision,click_type,click_id,observed_at,captured_at,state)
   values(l.id,c.id,c.platform,choice,'measurement_v1',disclosure,f.published->>'privacy_url',l.published_version,s.revision,kind,identifier,observed,l.created_at,receipt_state);
  return out;
 end if;
 if p_data->>'days' is null or p_data->>'days' not in ('7','30','90') then raise exception 'Choose 7, 30 or 90 reporting days.';end if;
 days:=(p_data->>'days')::integer;first_day:=today-(days-1);
 if p_action='settings' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or not (p_data?'expected_revision') then raise exception 'Choose whether to collect measurement consent.';end if;
  if p_data->>'expected_revision' is distinct from s.revision::text then raise exception 'Measurement settings changed. Refresh before saving.' using errcode='40001';end if;
  if (p_data->>'enabled')::boolean and not usable then raise exception 'Use a published page with a privacy policy, an open Google or Meta campaign and a recognized campaign link.' using errcode='40001';end if;
  if s.campaign_id is null or s.enabled is distinct from (p_data->>'enabled')::boolean then
   insert into public.korlix_funnel_measurement_settings(campaign_id,enabled) values(c.id,(p_data->>'enabled')::boolean)
    on conflict(campaign_id) do update set enabled=excluded.enabled,revision=gen_random_uuid(),updated_at=now() returning * into s;
  end if;
 end if;
 with counts as (
  select (captured_at at time zone 'UTC')::date as day,count(*) as receipts,
   count(*) filter(where state='declined') as declined,count(*) filter(where state='missing_click') as missing_click,count(*) filter(where state='awaiting_setup') as awaiting_setup
  from public.korlix_funnel_measurement_receipts where campaign_id=c.id and captured_at>=first_day::timestamp at time zone 'UTC' and captured_at<(today+1)::timestamp at time zone 'UTC' group by 1
 ) select jsonb_agg(jsonb_build_object('day',d::date,'receipts',coalesce(x.receipts,0),'declined',coalesce(x.declined,0),'missing_click',coalesce(x.missing_click,0),'awaiting_setup',coalesce(x.awaiting_setup,0)) order by d)
 into rows from generate_series(first_day::timestamp,today::timestamp,interval '1 day')d left join counts x on x.day=d::date;
 return jsonb_build_object('source','conversion_intake','funnel_id',f.id,'campaign_id',c.id,'name',c.name,'platform',c.platform,
  'enabled',coalesce(s.enabled,false),'collecting',coalesce(s.enabled,false) and usable,'can_enable',usable,'revision',s.revision,
  'event_name','inquiry_submitted','provider_delivery','separate_workflow','provider_verified',false,'policy_version','measurement_v1',
  'days',days,'from_day',first_day,'through_day',today,'timezone','UTC','includes_today',true,'checked_at',now(),'rows',rows,
  'totals',(select jsonb_build_object('receipts',sum((v->>'receipts')::bigint),'declined',sum((v->>'declined')::bigint),'missing_click',sum((v->>'missing_click')::bigint),'awaiting_setup',sum((v->>'awaiting_setup')::bigint)) from jsonb_array_elements(rows)v));
end $$;
create or replace function public.korlix_funnel_google_destination_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
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
  'event_name','inquiry_submitted','delivery_state','separate_workflow','send_ready',false,'provider_verified',false);
end $$;
create or replace function public.korlix_google_upload_access_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 a public.korlix_google_upload_oauth_attempts;u public.korlix_google_upload_connections;c public.korlix_google_ads_connections;
 owner_id uuid:=p_actor;funnel_id uuid:=p_funnel;campaign_id uuid;d jsonb;ctx jsonb;fp text;ready boolean;current_access boolean;current_attempt boolean;checked timestamptz;
 allowed text[]:=array['campaign_id','ads_configured','ads_config_hash','configured','config_hash'];
begin
 if p_action is null or p_action not in ('read','begin','consume','candidate','failed','claim','finish','disconnect') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose an upload authorization action.';end if;
 allowed:=allowed||case p_action when 'begin' then array['version','fingerprint','confirmed','id','state_hash','proof_hash','verifier_sealed'] when 'consume' then array['id','state_hash'] when 'candidate' then array['id','sealed','scopes','refresh_expires_at'] when 'failed' then array['id'] when 'claim' then array['id','proof_hash','confirmed'] when 'finish' then array['id','checked_at'] when 'disconnect' then array['version','fingerprint','confirmed'] else array[]::text[] end;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(allowed)) then raise exception 'Unexpected upload authorization fields.';end if;
 if p_action='consume' then
  select * into a from public.korlix_google_upload_oauth_attempts where id=(p_data->>'id')::uuid and state_hash=p_data->>'state_hash';
  if a.user_id is null then raise exception 'This Google upload authorization link is invalid or expired.' using errcode='P0002';end if;
  owner_id:=a.user_id;funnel_id:=a.funnel_id;campaign_id:=a.campaign_id;
 else campaign_id:=(p_data->>'campaign_id')::uuid;end if;
 -- Existing destination context authorizes Enterprise ownership and locks the
 -- funnel, campaign and Ads connection in their established order.
 d:=public.korlix_funnel_google_destination_v1(owner_id,'read',funnel_id,jsonb_build_object('campaign_id',campaign_id,'configured',p_data->'ads_configured','config_hash',p_data->'ads_config_hash'));
 ctx:=d->'context';
 select * into c from public.korlix_google_ads_connections where user_id=owner_id for update;
 perform pg_advisory_xact_lock(hashtextextended('korlix-google-upload:'||owner_id::text,0));
 delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id and expires_at<=now();
 select * into u from public.korlix_google_upload_connections where user_id=owner_id for update;
 select * into a from public.korlix_google_upload_oauth_attempts where user_id=owner_id for update;
 ready:=coalesce(p_data->'configured'='true'::jsonb and d->'selection_current'='true'::jsonb and c.user_id is not null,false);
 current_access:=coalesce(ready and not u.needs_reconnect and (u.refresh_expires_at is null or u.refresh_expires_at>now()+interval '60 seconds') and u.config_hash=p_data->>'config_hash' and u.ads_binding_id=c.binding_id and u.root_id=ctx->>'root_id' and (u.login_customer_id is not distinct from ctx->>'login_customer_id') and u.account=ctx->'account',false);
 current_attempt:=coalesce(ready and a.funnel_id=funnel_id and a.campaign_id=campaign_id and a.config_hash=p_data->>'config_hash' and a.destination_fingerprint=d->>'fingerprint' and a.authorization_version=coalesce(u.version,0),false);
 fp:=encode(sha256(convert_to(jsonb_build_object('contract','google_upload_access_v1','destination',d->'fingerprint','authorization_version',coalesce(u.version,0),'pending_id',a.id,'configured',p_data->'configured','config_hash',p_data->'config_hash')::text,'UTF8')),'hex');
 if p_action='read' then
  return jsonb_build_object('source','google_upload_access','funnel_id',funnel_id,'campaign_id',campaign_id,'campaign_name',d->'campaign_name','configured',p_data->'configured'='true'::jsonb,'destination_current',d->'selection_current','can_authorize',ready,'version',coalesce(u.version,0),'fingerprint',fp,
   'authorization',case when u.user_id is null then null else jsonb_build_object('account',u.account,'root_id',u.root_id,'login_customer_id',u.login_customer_id,'connected_at',u.connected_at,'checked_at',u.checked_at,'needs_reconnect',u.needs_reconnect or coalesce(u.refresh_expires_at<=now()+interval '60 seconds',false) or u.config_hash is distinct from p_data->>'config_hash','current',current_access) end,
   'pending',case when a.user_id is null or a.funnel_id<>funnel_id or a.campaign_id<>campaign_id then null else jsonb_build_object('id',a.id,'phase',a.phase,'expires_at',a.expires_at,'current',current_attempt) end,
   'scope_set','ads_datamanager_v1','delivery_state','separate_workflow','send_ready',false,'provider_verified',false);
 end if;
 if p_action in ('begin','disconnect') then
  if p_data->>'fingerprint' is distinct from fp or jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$' then raise exception 'Upload access or destination changed. Refresh before continuing.' using errcode='40001';end if;
  if (p_data->>'version')::bigint is distinct from coalesce(u.version,0) then raise exception 'Upload access changed. Refresh before continuing.' using errcode='40001';end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm the Google upload access change.';end if;
  if p_action='disconnect' then
   delete from public.korlix_google_upload_connections where user_id=owner_id;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
  else
   if not ready then raise exception 'Save a current Google conversion destination and finish platform setup first.' using errcode='40001';end if;
   if a.user_id is not null and a.created_at>now()-interval '30 seconds' then raise exception 'Wait 30 seconds before starting another Google upload authorization.' using errcode='54000';end if;
   if not public.korlix_google_upload_sealed_valid(p_data->'verifier_sealed') then raise exception 'Start a new Google upload authorization.';end if;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
   insert into public.korlix_google_upload_oauth_attempts(user_id,id,funnel_id,campaign_id,state_hash,proof_hash,config_hash,destination_fingerprint,authorization_version,verifier_sealed)
    values(owner_id,(p_data->>'id')::uuid,funnel_id,campaign_id,p_data->>'state_hash',p_data->>'proof_hash',p_data->>'config_hash',d->>'fingerprint',coalesce(u.version,0),p_data->'verifier_sealed');
  end if;
 elsif p_action='failed' then
  if a.id is distinct from (p_data->>'id')::uuid or a.funnel_id<>funnel_id or a.campaign_id<>campaign_id or a.phase not in ('exchanging','verifying') then raise exception 'This upload authorization is no longer active.' using errcode='40001';end if;
  update public.korlix_google_upload_oauth_attempts set phase='failed',candidate=null,verifier_sealed=null where user_id=owner_id;
 else
  if not current_attempt or a.id is distinct from (p_data->>'id')::uuid then raise exception 'The Google account, destination or upload authorization changed. Start again.' using errcode='40001';end if;
  if p_action='consume' then
   if a.state_hash is distinct from p_data->>'state_hash' or a.phase<>'waiting' or a.verifier_sealed is null then raise exception 'This upload authorization link expired or was already used.' using errcode='40001';end if;
   update public.korlix_google_upload_oauth_attempts set phase='exchanging',verifier_sealed=null where user_id=owner_id;
   return jsonb_build_object('user_id',owner_id,'funnel_id',funnel_id,'campaign_id',campaign_id,'id',a.id,'verifier_sealed',a.verifier_sealed);
  elsif p_action='candidate' then
   if a.phase<>'exchanging' or not public.korlix_google_upload_sealed_valid(p_data->'sealed') or p_data->'scopes' is distinct from '["https://www.googleapis.com/auth/adwords","https://www.googleapis.com/auth/datamanager"]'::jsonb then raise exception 'Google upload permissions could not be verified.' using errcode='40001';end if;
   if p_data->>'refresh_expires_at' is not null and (not isfinite((p_data->>'refresh_expires_at')::timestamptz) or (p_data->>'refresh_expires_at')::timestamptz<=now()+interval '60 seconds') then raise exception 'Google upload access is already expired.';end if;
   update public.korlix_google_upload_oauth_attempts set phase='ready',candidate=p_data->'sealed',refresh_expires_at=(p_data->>'refresh_expires_at')::timestamptz where user_id=owner_id;
  elsif p_action='claim' then
   if a.proof_hash is distinct from p_data->>'proof_hash' or p_data->'confirmed' is distinct from 'true'::jsonb or a.phase<>'ready' or a.candidate is null or a.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'Complete Google sign-in in this window, then finish upload authorization.' using errcode='40001';end if;
   update public.korlix_google_upload_oauth_attempts set phase='verifying' where user_id=owner_id;
   return jsonb_build_object('id',a.id,'candidate',a.candidate,'destination',d->'selection'->'destination','context',ctx);
  elsif p_action='finish' then
   if a.phase<>'verifying' or a.candidate is null or a.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'This upload authorization is no longer ready. Start again.' using errcode='40001';end if;
   if jsonb_typeof(p_data->'checked_at') is distinct from 'string' then raise exception 'Repeat the Google access check.';end if;
   checked:=(p_data->>'checked_at')::timestamptz;
   if not isfinite(checked) or checked<now()-interval '5 minutes' or checked>now()+interval '1 minute' then raise exception 'The Google access check expired. Start again.' using errcode='40001';end if;
   insert into public.korlix_google_upload_connections(user_id,binding_id,ads_binding_id,config_hash,sealed,scopes,refresh_expires_at,account,root_id,login_customer_id,version,checked_at)
    values(owner_id,a.id,c.binding_id,a.config_hash,a.candidate,'["https://www.googleapis.com/auth/adwords","https://www.googleapis.com/auth/datamanager"]'::jsonb,a.refresh_expires_at,ctx->'account',ctx->>'root_id',ctx->>'login_customer_id',nextval('public.korlix_google_upload_version_seq'),checked)
    on conflict(user_id) do update set binding_id=excluded.binding_id,ads_binding_id=excluded.ads_binding_id,config_hash=excluded.config_hash,sealed=excluded.sealed,scopes=excluded.scopes,refresh_expires_at=excluded.refresh_expires_at,account=excluded.account,root_id=excluded.root_id,login_customer_id=excluded.login_customer_id,version=excluded.version,connected_at=now(),checked_at=excluded.checked_at,needs_reconnect=false;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
  end if;
 end if;
 return '{}'::jsonb;
end $$;
commit;
