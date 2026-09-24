begin;
create table public.korlix_funnel_measurement_settings (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 enabled boolean not null default false,
 revision uuid not null default gen_random_uuid(),
 updated_at timestamptz not null default now()
);
create table public.korlix_funnel_measurement_receipts (
 lead_id uuid primary key references public.korlix_funnel_leads(id) on delete cascade,
 event_id uuid not null unique default gen_random_uuid(),
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 platform text not null check(platform in ('google','meta')),
 event_name text not null default 'inquiry_submitted' check(event_name='inquiry_submitted'),
 consent text not null check(consent in ('granted','declined')),
 policy_version text not null check(policy_version='measurement_v1'),
 consent_text text not null check(length(consent_text) between 1 and 1000),
 privacy_url text not null,
 page_version integer not null,
 settings_revision uuid not null,
 click_type text,
 click_id text,
 observed_at timestamptz,
 captured_at timestamptz not null,
 state text not null check(state in ('declined','missing_click','awaiting_setup')),
 check((click_type is null and click_id is null and observed_at is null and state in ('declined','missing_click')) or
  (click_type is not null and click_id is not null and observed_at is not null and state='awaiting_setup' and consent='granted'
   and length(click_id) between 1 and 512 and click_id ~ '^[A-Za-z0-9_-]+$' and ((platform='google' and click_type in ('gclid','gbraid','wbraid')) or (platform='meta' and click_type='fbclid')))),
 check((consent='declined' and state='declined') or (consent='granted' and state in ('missing_click','awaiting_setup')))
);
create index korlix_funnel_measurement_receipts_campaign_date on public.korlix_funnel_measurement_receipts(campaign_id,captured_at,lead_id);
alter table public.korlix_funnel_measurement_settings enable row level security;
alter table public.korlix_funnel_measurement_receipts enable row level security;
revoke all on public.korlix_funnel_measurement_settings,public.korlix_funnel_measurement_receipts from public,anon,authenticated,service_role;
grant select,insert,update on public.korlix_funnel_measurement_settings to service_role;
grant select,insert on public.korlix_funnel_measurement_receipts to service_role;
comment on table public.korlix_funnel_measurement_receipts is 'Local inquiry measurement consent and unverified URL click identifier. No provider delivery or acceptance. No automatic uploads. Deleted with inquiry; never backfilled.';

create function public.korlix_funnel_measurement_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
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
  'event_name','inquiry_submitted','provider_delivery','not_implemented','provider_verified',false,'policy_version','measurement_v1',
  'days',days,'from_day',first_day,'through_day',today,'timezone','UTC','includes_today',true,'checked_at',now(),'rows',rows,
  'totals',(select jsonb_build_object('receipts',sum((v->>'receipts')::bigint),'declined',sum((v->>'declined')::bigint),'missing_click',sum((v->>'missing_click')::bigint),'awaiting_setup',sum((v->>'awaiting_setup')::bigint)) from jsonb_array_elements(rows)v));
end $$;
revoke all on function public.korlix_funnel_measurement_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_funnel_measurement_v1(uuid,text,uuid,jsonb) to service_role;
commit;
