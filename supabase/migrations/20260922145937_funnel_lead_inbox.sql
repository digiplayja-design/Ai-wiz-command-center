begin;
-- Stable keyset ordering also covers inquiries with identical receipt timestamps.
create index korlix_funnel_leads_inbox on public.korlix_funnel_leads(funnel_id,created_at desc,id desc);
create function public.korlix_funnel_inbox_v1(p_actor uuid,p_id uuid,p_data jsonb default '{}')
returns jsonb language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare
  needle text := lower(trim(coalesce(p_data->>'search','')));
  source_filter text := trim(coalesce(p_data->>'source',''));
  start_at timestamptz;
  end_at timestamptz;
  snapshot_at timestamptz;
  before_at timestamptz;
  before_id uuid;
  exporting boolean;
  row_limit integer;
  result jsonb;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then
    raise exception 'Funnel Studio requires Enterprise.' using errcode='42501';
  end if;
  if not exists(select 1 from public.korlix_funnels where id=p_id and user_id=p_actor) then
    raise exception 'Funnel not found.' using errcode='P0002';
  end if;
  if jsonb_typeof(p_data) is distinct from 'object' or length(needle)>160 or length(source_filter)>120 then
    raise exception 'Invalid inbox filters.';
  end if;
  begin
    start_at := nullif(p_data->>'from','')::date::timestamp at time zone 'UTC';
    end_at := (nullif(p_data->>'to','')::date + 1)::timestamp at time zone 'UTC';
    snapshot_at := least(coalesce(nullif(p_data->>'snapshot','')::timestamptz,now()),now());
    before_at := nullif(p_data->>'before_at','')::timestamptz;
    before_id := nullif(p_data->>'before_id','')::uuid;
    exporting := coalesce((p_data->>'export')::boolean,false);
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Invalid inbox filters. Refresh and try again.';
  end;
  if (start_at is not null and end_at is not null and start_at>=end_at)
     or ((before_at is null) <> (before_id is null))
     or (exporting and before_at is not null)
     or not isfinite(snapshot_at) then raise exception 'Invalid inbox filters.'; end if;
  row_limit := case when exporting then 5000 else 25 end;
  -- One statement gives counts, results, and source summaries the same read view.
  with all_leads as materialized (
    select * from public.korlix_funnel_leads where funnel_id=p_id and created_at<=snapshot_at
  ), matching as materialized (
    select * from all_leads l
    where (needle='' or strpos(lower(l.name||' '||l.email||' '||l.phone||' '||l.message),needle)>0)
      and (source_filter='' or coalesce(nullif(l.utm->>'utm_source',''),'Direct / untagged')=source_filter)
      and (start_at is null or l.created_at>=start_at) and (end_at is null or l.created_at<end_at)
  ), page_plus as materialized (
    select * from matching l
    where (before_at is null or (l.created_at,l.id)<(before_at,before_id))
    order by l.created_at desc,l.id desc limit row_limit+1
  ), page_rows as (
    select * from page_plus order by created_at desc,id desc limit row_limit
  ), pairs as (
    select coalesce(nullif(utm->>'utm_source',''),'Direct / untagged') source,
      coalesce(nullif(utm->>'utm_campaign',''),'Untagged') campaign,count(*) leads
    from matching group by 1,2 order by 3 desc,1,2 limit 8
  ) select jsonb_build_object(
    'total',(select count(*) from all_leads), 'filtered_total',(select count(*) from matching),
    'snapshot',snapshot_at, 'export_limit',5000,
    'leads',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id desc) from page_rows p),'[]'::jsonb),
    'next',case when not exporting and (select count(*) from page_plus)>row_limit then
      (select jsonb_build_object('created_at',created_at,'id',id) from page_rows order by created_at,id limit 1) else null end,
    'campaigns',coalesce((select jsonb_agg(to_jsonb(p) order by p.leads desc,p.source,p.campaign) from pairs p),'[]'::jsonb)
  ) into result;
  if exporting and (result->>'filtered_total')::bigint>5000 then
    raise exception 'More than 5,000 inquiries match. Narrow the date range or filters before exporting.';
  end if;
  return result;
end $$;
revoke all on function public.korlix_funnel_inbox_v1(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_inbox_v1(uuid,uuid,jsonb) to service_role;
comment on function public.korlix_funnel_inbox_v1(uuid,uuid,jsonb) is 'Service-only Enterprise owner inbox. Literal search, UTC date filters, snapshot keyset pagination and bounded complete exports. No contact or outreach writes.';
commit;
