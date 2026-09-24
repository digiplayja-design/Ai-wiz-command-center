begin;
-- Public share codes identify a KORLIX campaign link, not an ad click or person.
create table public.korlix_funnel_attribution_links (
 campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
 code text not null unique default replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','') check(code ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now()
);
create table public.korlix_funnel_attribution_events (
 lead_id uuid primary key references public.korlix_funnel_leads(id) on delete cascade,
 campaign_id uuid not null references public.korlix_funnel_attribution_links(campaign_id) on delete cascade,
 mechanism text not null default 'campaign_link_v1' check(mechanism='campaign_link_v1'),
 captured_at timestamptz not null
);
create index korlix_funnel_attribution_events_campaign_date on public.korlix_funnel_attribution_events(campaign_id,captured_at,lead_id);
alter table public.korlix_funnel_attribution_links enable row level security;
alter table public.korlix_funnel_attribution_events enable row level security;
revoke all on public.korlix_funnel_attribution_links,public.korlix_funnel_attribution_events from public,anon,authenticated;
grant select,insert on public.korlix_funnel_attribution_links,public.korlix_funnel_attribution_events to service_role;
comment on table public.korlix_funnel_attribution_events is 'Immutable first-party link association at inquiry capture. No historical backfill, ad-platform verification, person deduplication or revenue claim. Inquiry deletion cascades.';

create function public.korlix_funnel_attribution_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels;c public.korlix_funnel_campaigns;k public.korlix_funnel_attribution_links;l public.korlix_funnel_leads;
 out jsonb;rows jsonb;days integer;today date:=(now() at time zone 'UTC')::date;first_day date;source text;tag text;
begin
 if p_action is null or p_action not in ('read','create_link','resolve','capture') then raise exception 'Unknown attribution action.';end if;
 if p_action in ('resolve','capture') then
  if p_actor is not null then raise exception 'Invalid public attribution context.';end if;
  -- Same funnel lock as the original capture transaction and cleanup.
  select * into f from public.korlix_funnels where id=p_funnel and slug=p_data->>'slug' for update;
  if not found or f.state<>'published' or not exists(select 1 from public.user_profiles where id=f.user_id and lower(trim(tier))='enterprise') then raise exception 'This page is not available.' using errcode='P0002';end if;
  select a.* into k from public.korlix_funnel_attribution_links a join public.korlix_funnel_campaigns x on x.id=a.campaign_id where x.funnel_id=f.id and a.code=p_data->>'code';
  if not found then
   if p_action='resolve' then return null;end if;
   raise exception 'This campaign link changed. Reload before submitting.' using errcode='40001';
  end if;
  if p_action='resolve' then return jsonb_build_object('code',k.code);end if;
  -- A retry may not attach evidence to an earlier untracked inquiry or move it.
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  if found then return public.korlix_funnel_v1(null,'lead',null,p_data-array['code','campaign_id']);end if;
  out:=public.korlix_funnel_v1(null,'lead',null,p_data-array['code','campaign_id']);
  select * into l from public.korlix_funnel_leads where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
  -- Cleanup tombstones deliberately suppress both the inquiry and its evidence.
  if found then insert into public.korlix_funnel_attribution_events(lead_id,campaign_id,captured_at) values(l.id,k.campaign_id,l.created_at);end if;
  return out;
 end if;
 if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Campaign attribution requires Enterprise.' using errcode='42501';end if;
 select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
 if not found then raise exception 'Funnel not found.' using errcode='P0002';end if;
 select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id;
 if not found then raise exception 'Campaign not found.' using errcode='P0002';end if;
 if p_data->>'days' is null or p_data->>'days' not in ('7','30','90') then raise exception 'Choose 7, 30 or 90 reporting days.';end if;
 days:=(p_data->>'days')::integer;first_day:=today-(days-1);
 if p_action='create_link' then
  if f.state<>'published' or c.state='archived' then raise exception 'Publish the page and reopen the campaign before creating its link.' using errcode='40001';end if;
  insert into public.korlix_funnel_attribution_links(campaign_id) values(c.id) on conflict(campaign_id) do nothing;
 end if;
 select * into k from public.korlix_funnel_attribution_links where campaign_id=c.id;
 source:=case c.platform when 'meta' then 'facebook' when 'google' then 'google' else 'other' end;tag:='k143_'||replace(c.id::text,'-','');
 with candidates as (
  select l0.id,l0.created_at,l0.utm,a.campaign_id as attributed_campaign from public.korlix_funnel_leads l0
  left join public.korlix_funnel_attribution_events a on a.lead_id=l0.id
  where l0.funnel_id=f.id and l0.created_at>=first_day::timestamp at time zone 'UTC' and l0.created_at<(today+1)::timestamp at time zone 'UTC'
   and (a.campaign_id=c.id or (a.campaign_id is null and l0.utm->>'utm_source'=source and l0.utm->>'utm_campaign'=tag))
 ),counts as (
  select (created_at at time zone 'UTC')::date as day,
   count(*) filter(where attributed_campaign=c.id) as link_inquiries,
   count(*) filter(where attributed_campaign is null) as tag_only_inquiries,
   count(*) filter(where attributed_campaign=c.id and (utm->>'utm_source' is distinct from source or utm->>'utm_campaign' is distinct from tag)) as tag_conflicts
  from candidates group by 1
 ) select jsonb_agg(jsonb_build_object('day',d::date,'link_inquiries',coalesce(x.link_inquiries,0),'tag_only_inquiries',coalesce(x.tag_only_inquiries,0),'tag_conflicts',coalesce(x.tag_conflicts,0)) order by d)
 into rows from generate_series(first_day::timestamp,today::timestamp,interval '1 day') d left join counts x on x.day=d::date;
 return jsonb_build_object('source','campaign_link_attribution','funnel_id',f.id,'campaign_id',c.id,'name',c.name,'platform',c.platform,'state',c.state,'page_state',f.state,'slug',f.slug,
  'link',case when k.campaign_id is null then null else jsonb_build_object('code',k.code,'created_at',k.created_at) end,
  'days',days,'from_day',first_day,'through_day',today,'timezone','UTC','includes_today',true,'checked_at',now(),
  'provider_verified',false,'rows',rows,'totals',(select jsonb_build_object('link_inquiries',sum((v->>'link_inquiries')::bigint),'tag_only_inquiries',sum((v->>'tag_only_inquiries')::bigint),'tag_conflicts',sum((v->>'tag_conflicts')::bigint)) from jsonb_array_elements(rows)v));
end $$;
revoke all on function public.korlix_funnel_attribution_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_attribution_v1(uuid,text,uuid,jsonb) to service_role;
commit;
