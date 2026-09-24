begin;
create table public.korlix_meta_measurement_settings (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 enabled boolean not null default false,
 revision uuid not null default gen_random_uuid(),
 config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
 public_origin text,
 armed_at timestamptz,
 updated_at timestamptz not null default now(),
 check(not enabled or (public_origin is not null and armed_at is not null))
);
create table public.korlix_meta_measurement_receipts (
 lead_id uuid primary key references public.korlix_funnel_leads(id) on delete cascade,
 event_id uuid not null unique default gen_random_uuid(),
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 event_name text not null default 'Lead' check(event_name='Lead'),
 action_source text not null default 'website' check(action_source='website'),
 consent text not null check(consent in ('granted','declined')),
 policy_version text not null default 'meta_measurement_v2' check(policy_version='meta_measurement_v2'),
 consent_text text not null check(length(consent_text) between 1 and 1000),
 privacy_url text not null,
 page_version integer not null,
 settings_revision uuid not null,
 click_id text,
 observed_at timestamptz,
 client_user_agent text,
 event_source_url text,
 captured_at timestamptz not null,
 state text not null check(state in ('declined','missing_click','missing_browser','prepared')),
 check((state='declined' and consent='declined') or (state<>'declined' and consent='granted')),
 check((state<>'prepared' and click_id is null and observed_at is null and client_user_agent is null and event_source_url is null) or
  (state='prepared' and click_id is not null and observed_at is not null and isfinite(observed_at) and client_user_agent is not null and event_source_url is not null
   and length(click_id) between 1 and 512 and click_id ~ '^[A-Za-z0-9_-]+$'
   and length(client_user_agent) between 1 and 1024 and trim(client_user_agent)=client_user_agent and client_user_agent !~ '[^ -~]'
   and length(event_source_url) between 1 and 2048 and event_source_url ~ '^https://[a-z0-9.-]+/f/[a-z0-9-]+$'))
);
create index korlix_meta_measurement_receipts_campaign_date on public.korlix_meta_measurement_receipts(campaign_id,captured_at,lead_id);
alter table public.korlix_meta_measurement_settings enable row level security;
alter table public.korlix_meta_measurement_receipts enable row level security;
revoke all on public.korlix_meta_measurement_settings,public.korlix_meta_measurement_receipts from public,anon,authenticated,service_role;
grant select,insert,update on public.korlix_meta_measurement_settings to service_role;
grant select,insert on public.korlix_meta_measurement_receipts to service_role;
comment on table public.korlix_meta_measurement_receipts is 'Future-only, optional Meta website measurement consent v2. Prepared means local unverified evidence only, never provider eligibility or delivery. No historical backfill. Incomplete or declined receipts retain no click/browser/address data. Inquiry deletion cascades.';

create function public.korlix_meta_measurement_v2(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels;c public.korlix_funnel_campaigns;s public.korlix_meta_measurement_settings;l public.korlix_funnel_leads;
 out jsonb;rows jsonb;days integer;today date:=(now() at time zone 'UTC')::date;first_day date;
 usable boolean;current_config boolean;collecting boolean;choice text;identifier text;observed timestamptz;agent text;source_url text;receipt_state text;disclosure text;
begin
 if p_action is null or p_action not in ('read','settings','resolve','capture') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Unknown Meta website consent action.';end if;
 if jsonb_typeof(p_data->'configured') is distinct from 'boolean' or coalesce(p_data->>'config_hash','') !~ '^[a-f0-9]{64}$'
  or ((p_data->>'configured')::boolean and (jsonb_typeof(p_data->'public_origin') is distinct from 'string' or length(p_data->>'public_origin') not between 9 and 1000 or p_data->>'public_origin' !~ '^https://[a-z0-9.-]+$')) then raise exception 'Meta website consent configuration is unavailable.';end if;
 if p_action in ('resolve','capture') then
  if p_actor is not null then raise exception 'Invalid public measurement context.';end if;
  select * into f from public.korlix_funnels where id=p_funnel and slug=p_data->>'slug' for update;
  if not found or f.state<>'published' or not exists(select 1 from public.user_profiles where id=f.user_id and lower(trim(tier))='enterprise') then raise exception 'This page is not available.' using errcode='P0002';end if;
  select x.* into c from public.korlix_funnel_campaigns x join public.korlix_funnel_attribution_links k on k.campaign_id=x.id where x.funnel_id=f.id and k.code=p_data->>'code' for update of x;
  if not found then raise exception 'This campaign link changed. Reload before submitting.' using errcode='40001';end if;
 else
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Meta website consent requires Enterprise.' using errcode='42501';end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002';end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002';end if;
  if c.platform<>'meta' then raise exception 'Choose a Meta campaign plan.';end if;
 end if;
 select * into s from public.korlix_meta_measurement_settings where campaign_id=c.id for update;
 usable:=(p_data->>'configured')::boolean and c.platform='meta' and c.state<>'archived' and f.state='published' and nullif(f.published->>'privacy_url','') is not null and exists(select 1 from public.korlix_funnel_attribution_links where campaign_id=c.id);
 current_config:=coalesce(s.config_hash=p_data->>'config_hash' and s.public_origin=p_data->>'public_origin',false);
 collecting:=usable and coalesce(s.enabled,false) and current_config;
 if p_action='resolve' then
  if not collecting then return null;end if;
  return jsonb_build_object('revision',s.revision,'platform','meta','policy_version','meta_measurement_v2');
 end if;
 if p_action='capture' then
  -- One inquiry transaction owns its first receipt; retries cannot add evidence.
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  if found then return public.korlix_funnel_attribution_v1(null,'capture',f.id,p_data);end if;
  out:=public.korlix_funnel_attribution_v1(null,'capture',f.id,p_data);
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  if not found or not collecting or p_data->>'settings_revision' is distinct from s.revision::text then return out;end if;
  if p_data->>'policy_version' is distinct from 'meta_measurement_v2' or p_data->>'measurement_consent' is null or p_data->>'measurement_consent' not in ('granted','declined') then raise exception 'Reload the Meta website consent choice before submitting.';end if;
  if jsonb_typeof(p_data->'observed_at') is distinct from 'string' then raise exception 'Reload the Meta website consent choice before submitting.';end if;
  observed:=(p_data->>'observed_at')::timestamptz;
  if not isfinite(observed) or observed<s.armed_at or observed<l.created_at-interval '1 hour' or observed>l.created_at+interval '5 minutes' then raise exception 'Expired Meta website consent evidence.';end if;
  choice:=p_data->>'measurement_consent';
  if choice='granted' then
   identifier:=p_data->>'click_id';
   if identifier is not null and (jsonb_typeof(p_data->'click_id') is distinct from 'string' or length(identifier) not between 1 and 512 or identifier !~ '^[A-Za-z0-9_-]+$') then raise exception 'Invalid Meta measurement click.';end if;
   if identifier is not null then
    agent:=p_data->>'client_user_agent';source_url:=p_data->>'event_source_url';
    if agent is not null or source_url is not null then
     if jsonb_typeof(p_data->'client_user_agent') is distinct from 'string' or agent is null or length(agent) not between 1 and 1024 or trim(agent)<>agent or agent ~ '[^ -~]'
      or jsonb_typeof(p_data->'event_source_url') is distinct from 'string' or source_url is distinct from s.public_origin||'/f/'||f.slug then raise exception 'Invalid Meta website context.';end if;
    end if;
   end if;
  end if;
  receipt_state:=case when choice='declined' then 'declined' when identifier is null then 'missing_click' when agent is null then 'missing_browser' else 'prepared' end;
  if receipt_state<>'prepared' then identifier:=null;observed:=null;agent:=null;source_url:=null;end if;
  disclosure:='Optional: I allow '||(f.published->>'brand')||' to store and share with Meta the advertising click identifier from this link, the time of this inquiry, my browser information (user agent), and this page''s address without query parameters, to measure advertising results. My name, email, phone, message and IP address are not included. I can send my inquiry without agreeing.';
  insert into public.korlix_meta_measurement_receipts(lead_id,campaign_id,consent,consent_text,privacy_url,page_version,settings_revision,click_id,observed_at,client_user_agent,event_source_url,captured_at,state)
   values(l.id,c.id,choice,disclosure,f.published->>'privacy_url',l.published_version,s.revision,identifier,observed,agent,source_url,l.created_at,receipt_state);
  return out;
 end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'settings' then array['campaign_id','days','configured','config_hash','public_origin','enabled','expected_revision','confirmed'] else array['campaign_id','days','configured','config_hash','public_origin'] end)) then raise exception 'Unexpected Meta website consent fields.';end if;
 if p_data->>'days' is null or p_data->>'days' not in ('7','30','90') then raise exception 'Choose 7, 30 or 90 reporting days.';end if;
 days:=(p_data->>'days')::integer;first_day:=today-(days-1);
 if p_action='settings' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or not (p_data?'expected_revision') or p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm the Meta website consent setting.';end if;
  if p_data->>'expected_revision' is distinct from s.revision::text then raise exception 'Meta website consent settings changed. Refresh before saving.' using errcode='40001';end if;
  if (p_data->>'enabled')::boolean and not usable then raise exception 'Platform setup, a published page with a privacy policy, an open Meta campaign and a recognized campaign link are required.' using errcode='40001';end if;
  if s.campaign_id is null or s.enabled is distinct from (p_data->>'enabled')::boolean or (p_data->>'enabled')::boolean and not current_config then
   insert into public.korlix_meta_measurement_settings(campaign_id,enabled,config_hash,public_origin,armed_at) values(c.id,(p_data->>'enabled')::boolean,p_data->>'config_hash',p_data->>'public_origin',case when (p_data->>'enabled')::boolean then clock_timestamp() end)
    on conflict(campaign_id) do update set enabled=excluded.enabled,config_hash=excluded.config_hash,public_origin=excluded.public_origin,armed_at=excluded.armed_at,revision=gen_random_uuid(),updated_at=now() returning * into s;
  end if;
  return public.korlix_meta_measurement_v2(p_actor,'read',f.id,p_data-array['enabled','expected_revision','confirmed']);
 end if;
 with counts as (
  select (captured_at at time zone 'UTC')::date as day,count(*) as receipts,
   count(*) filter(where state='declined') as declined,count(*) filter(where state='missing_click') as missing_click,count(*) filter(where state='missing_browser') as missing_browser,count(*) filter(where state='prepared') as prepared
  from public.korlix_meta_measurement_receipts where campaign_id=c.id and captured_at>=first_day::timestamp at time zone 'UTC' and captured_at<(today+1)::timestamp at time zone 'UTC' group by 1
 ) select jsonb_agg(jsonb_build_object('day',d::date,'receipts',coalesce(x.receipts,0),'declined',coalesce(x.declined,0),'missing_click',coalesce(x.missing_click,0),'missing_browser',coalesce(x.missing_browser,0),'prepared',coalesce(x.prepared,0)) order by d)
 into rows from generate_series(first_day::timestamp,today::timestamp,interval '1 day')d left join counts x on x.day=d::date;
 return jsonb_build_object('source','meta_website_consent','funnel_id',f.id,'campaign_id',c.id,'name',c.name,'configured',(p_data->>'configured')::boolean,
  'enabled',coalesce(s.enabled,false),'collecting',collecting,'can_enable',usable,'revision',s.revision,'context_current',current_config,'armed_at',s.armed_at,
  'event_name','Lead','action_source','website','send_ready',false,'provider_verified',false,'policy_version','meta_measurement_v2',
  'days',days,'from_day',first_day,'through_day',today,'timezone','UTC','includes_today',true,'checked_at',now(),'rows',rows,
  'totals',(select jsonb_build_object('receipts',sum((v->>'receipts')::bigint),'declined',sum((v->>'declined')::bigint),'missing_click',sum((v->>'missing_click')::bigint),'missing_browser',sum((v->>'missing_browser')::bigint),'prepared',sum((v->>'prepared')::bigint)) from jsonb_array_elements(rows)v));
end $$;
revoke all on function public.korlix_meta_measurement_v2(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_meta_measurement_v2(uuid,text,uuid,jsonb) to service_role;
commit;
