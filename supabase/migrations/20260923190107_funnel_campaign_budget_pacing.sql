begin;
create table public.korlix_funnel_campaign_budget_windows (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  start_date date check(start_date between date '2000-01-01' and date '2100-12-31'),
  version integer not null default 1 check(version > 0),
  updated_at timestamptz not null default now()
);
alter table public.korlix_funnel_campaign_budget_windows enable row level security;
revoke all on public.korlix_funnel_campaign_budget_windows from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_campaign_budget_windows to service_role;
comment on table public.korlix_funnel_campaign_budget_windows is
  'Private UTC reporting windows. Current campaign duration and USD plan apply. No provider schedule, budget enforcement or spending authorization. Cleared rows retain their version to prevent stale recreation.';

create function public.korlix_funnel_campaign_budget_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  f public.korlix_funnels;
  c public.korlix_funnel_campaigns;
  w public.korlix_funnel_campaign_budget_windows;
  d date;
  today date := (now() at time zone 'UTC')::date;
  reports jsonb;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then
    raise exception 'Campaign budget tracking requires Enterprise.' using errcode='42501';
  end if;
  select * into f from public.korlix_funnels where id=p_funnel and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  if p_action is null or p_action not in ('read','save','clear') or jsonb_typeof(p_data) is distinct from 'object' then
    raise exception 'Choose a supported budget tracking action.';
  end if;
  if jsonb_typeof(p_data->'campaign_id') is distinct from 'string' or coalesce(p_data->>'campaign_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'Choose a campaign.';
  end if;
  if exists(select 1 from jsonb_object_keys(p_data) k where k <> all(case p_action
    when 'read' then array['campaign_id']
    when 'save' then array['campaign_id','version','campaign_version','start_date']
    else array['campaign_id','version','campaign_version','confirmed'] end)) then
    raise exception 'Unexpected budget tracking fields.';
  end if;
  select * into c from public.korlix_funnel_campaigns where id=(p_data->>'campaign_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Campaign not found.' using errcode='P0002'; end if;
  select * into w from public.korlix_funnel_campaign_budget_windows where campaign_id=c.id for update;
  if p_action <> 'read' then
    if c.state='archived' then raise exception 'Reopen this archived plan before changing its reporting window.'; end if;
    if jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$'
      or jsonb_typeof(p_data->'campaign_version') is distinct from 'number' or coalesce(p_data->>'campaign_version','') !~ '^[0-9]{1,10}$' then
      raise exception 'Refresh the budget tracker before saving.';
    end if;
    if (p_data->>'version')::bigint is distinct from coalesce(w.version,0)
      or (p_data->>'campaign_version')::bigint is distinct from c.version then
      raise exception 'The campaign, reports or reporting window changed. Refresh before saving.' using errcode='40001';
    end if;
    if p_action='save' then
      if jsonb_typeof(p_data->'start_date') is distinct from 'string' or coalesce(p_data->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        raise exception 'Choose a valid UTC start date.';
      end if;
      begin d:=(p_data->>'start_date')::date;
      exception when datetime_field_overflow or invalid_datetime_format then raise exception 'Choose a valid UTC start date.';
      end;
      if d < today-730 or d > today+365 then raise exception 'Choose a start date within the past two years or next year.'; end if;
    else
      if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm clearing the reporting window.'; end if;
      d:=null;
    end if;
    insert into public.korlix_funnel_campaign_budget_windows(campaign_id,start_date) values(c.id,d)
      on conflict(campaign_id) do update set start_date=excluded.start_date,version=korlix_funnel_campaign_budget_windows.version+1,updated_at=now()
      returning * into w;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('day',day,'spend_cents',spend_cents) order by day),'[]'::jsonb)
    into reports from public.korlix_funnel_campaign_reports where campaign_id=c.id;
  return jsonb_build_object(
    'funnel_id',f.id,'campaign_id',c.id,'name',c.name,'state',c.state,'campaign_version',c.version,
    'daily_cents',c.daily_cents,'days',c.days,'currency','USD',
    'version',coalesce(w.version,0),'start_date',w.start_date,'updated_at',w.updated_at,
    'as_of_date',today,'checked_at',now(),'reports',reports,
    'reporting_source','manual','budget_enforced',false,'ad_publishing_ready',false);
end $$;
revoke all on function public.korlix_funnel_campaign_budget_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_campaign_budget_v1(uuid,text,uuid,jsonb) to service_role;
commit;
