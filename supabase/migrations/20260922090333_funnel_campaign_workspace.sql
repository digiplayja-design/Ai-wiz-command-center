begin;
create table public.korlix_funnel_campaigns (
  id uuid primary key default gen_random_uuid(),
  funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
  name text not null check(length(name) between 1 and 100),
  platform text not null check(platform in ('meta','google','other')),
  headline text not null default '' check(length(headline)<=180),
  body text not null default '' check(length(body)<=2000),
  cta text not null default '' check(length(cta)<=60),
  audience text not null default '' check(length(audience)<=1000),
  daily_cents integer not null check(daily_cents between 100 and 1000000),
  days integer not null check(days between 1 and 90),
  state text not null default 'draft' check(state in ('draft','reviewed','archived')),
  reviewed_page_version integer,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index korlix_funnel_campaigns_funnel on public.korlix_funnel_campaigns(funnel_id,updated_at desc);
create table public.korlix_funnel_campaign_reports (
  campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
  day date not null,
  spend_cents integer not null check(spend_cents between 0 and 100000000),
  clicks integer not null check(clicks between 0 and 100000000),
  impressions integer not null check(impressions between 0 and 1000000000),
  note text not null default '' check(length(note)<=400),
  updated_at timestamptz not null default now(),
  primary key(campaign_id,day)
);
create index korlix_funnel_leads_campaign on public.korlix_funnel_leads(funnel_id,(utm->>'utm_campaign'),created_at);
alter table public.korlix_funnel_campaigns enable row level security;
alter table public.korlix_funnel_campaign_reports enable row level security;
revoke all on public.korlix_funnel_campaigns,public.korlix_funnel_campaign_reports from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_campaigns,public.korlix_funnel_campaign_reports to service_role;

create function public.korlix_funnel_campaign_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_funnel_campaigns; report_day date; out jsonb;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then
    raise exception 'Campaign workspace requires Enterprise.' using errcode='42501';
  end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  if p_action='list' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]'::jsonb) into out from (
      select a.*, f.slug, f.state page_state, f.published_version page_version,
        (a.state='reviewed' and f.state='published' and a.reviewed_page_version=f.published_version) review_current,
        (select count(*) from public.korlix_funnel_leads l where l.funnel_id=f.id and l.utm->>'utm_campaign'='k143_'||replace(a.id::text,'-','') and l.utm->>'utm_source'=case a.platform when 'meta' then 'facebook' when 'google' then 'google' else 'other' end) tagged_leads,
        (select count(*) from public.korlix_funnel_leads l where l.funnel_id=f.id and l.utm->>'utm_campaign'='k143_'||replace(a.id::text,'-','') and l.utm->>'utm_source'=case a.platform when 'meta' then 'facebook' when 'google' then 'google' else 'other' end and exists(select 1 from public.korlix_funnel_campaign_reports r where r.campaign_id=a.id and r.day=(l.created_at at time zone 'UTC')::date)) covered_leads,
        coalesce((select jsonb_agg(to_jsonb(r) order by r.day desc) from public.korlix_funnel_campaign_reports r where r.campaign_id=a.id),'[]'::jsonb) reports
      from public.korlix_funnel_campaigns a where a.funnel_id=f.id
    ) x;
    return jsonb_build_object('campaigns',out,'page',coalesce(f.published,f.draft),'page_state',f.state);
  end if;
  if p_action='create' then
    if (select count(*) from public.korlix_funnel_campaigns where funnel_id=f.id)>=50 then raise exception 'This funnel has reached its 50-campaign limit.' using errcode='54000'; end if;
    insert into public.korlix_funnel_campaigns(funnel_id,name,platform,headline,body,cta,audience,daily_cents,days)
      values(f.id,p_data->>'name',p_data->>'platform',coalesce(p_data->>'headline',''),coalesce(p_data->>'body',''),coalesce(p_data->>'cta',''),coalesce(p_data->>'audience',''),(p_data->>'daily_cents')::integer,(p_data->>'days')::integer) returning * into c;
  else
    select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
    if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
    if (p_data->>'version')::integer is distinct from c.version then raise exception 'This campaign changed. Refresh and review it again.' using errcode='40001'; end if;
    if p_action in ('review','archive','removeReport') and p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm this action.'; end if;
    if c.state='archived' and p_action<>'reopen' then raise exception 'Reopen this archived plan before changing it.'; end if;
    if p_action='save' then
      if p_data->>'platform' is distinct from c.platform then raise exception 'The channel stays fixed to preserve attribution. Create another plan for a new channel.'; end if;
      update public.korlix_funnel_campaigns set name=p_data->>'name',headline=p_data->>'headline',body=p_data->>'body',cta=p_data->>'cta',audience=p_data->>'audience',daily_cents=(p_data->>'daily_cents')::integer,days=(p_data->>'days')::integer,state='draft',reviewed_page_version=null where id=c.id;
    elsif p_action='review' then
      if f.state<>'published' or length(trim(c.headline))=0 or length(trim(c.body))=0 or length(trim(c.cta))=0 or length(trim(c.audience))=0 then raise exception 'Publish your page and complete the copy and audience brief before reviewing.'; end if;
      update public.korlix_funnel_campaigns set state='reviewed',reviewed_page_version=f.published_version where id=c.id;
    elsif p_action='archive' then
      update public.korlix_funnel_campaigns set state='archived' where id=c.id;
    elsif p_action='reopen' then
      if c.state<>'archived' then raise exception 'Only archived plans can be reopened.'; end if;
      update public.korlix_funnel_campaigns set state='draft',reviewed_page_version=null where id=c.id;
    elsif p_action in ('report','removeReport') then
      report_day:=(p_data->>'day')::date;
      if report_day is null or report_day>(now() at time zone 'UTC')::date or report_day<(now() at time zone 'UTC')::date-730 then raise exception 'Choose a reporting date within the last two years, using UTC.'; end if;
      if p_action='report' then
        if not exists(select 1 from public.korlix_funnel_campaign_reports where campaign_id=c.id and day=report_day) and (select count(*) from public.korlix_funnel_campaign_reports where campaign_id=c.id)>=731 then raise exception 'This campaign has reached its reporting limit.' using errcode='54000'; end if;
        insert into public.korlix_funnel_campaign_reports(campaign_id,day,spend_cents,clicks,impressions,note)
          values(c.id,report_day,(p_data->>'spend_cents')::integer,(p_data->>'clicks')::integer,(p_data->>'impressions')::integer,coalesce(p_data->>'note',''))
          on conflict(campaign_id,day) do update set spend_cents=excluded.spend_cents,clicks=excluded.clicks,impressions=excluded.impressions,note=excluded.note,updated_at=now();
      else delete from public.korlix_funnel_campaign_reports where campaign_id=c.id and day=report_day;
      end if;
    else raise exception 'Unsupported campaign action.';
    end if;
    update public.korlix_funnel_campaigns set version=version+1,updated_at=now() where id=c.id returning * into c;
  end if;
  return to_jsonb(c)||jsonb_build_object('slug',f.slug,'page_state',f.state,'page_version',f.published_version);
end $$;
revoke all on function public.korlix_funnel_campaign_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_campaign_v1(uuid,text,uuid,jsonb) to service_role;
comment on table public.korlix_funnel_campaigns is 'Private ad preparation plans; reviewed does not authorize publication or spending. All amounts are USD cents.';
comment on table public.korlix_funnel_campaign_reports is 'Owner-entered daily UTC totals, not synchronized ad-platform data.';
commit;
