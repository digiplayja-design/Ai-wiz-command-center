-- K200: private, immutable mileage history. Distance is exact tenths of a mile.
create table public.korlix_bookkeeping_trips (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 trip_date date not null check(trip_date between date '2000-01-01' and date '2099-12-31'),
 vehicle text not null check(length(btrim(vehicle)) between 1 and 80),
 origin text not null check(length(btrim(origin)) between 1 and 160),
 destination text not null check(length(btrim(destination)) between 1 and 160),
 purpose text not null check(length(btrim(purpose)) between 1 and 500),
 method text not null check(method in ('miles','odometer')),
 manual_tenths integer, start_tenths integer, end_tenths integer,
 distance_tenths integer generated always as (coalesce(manual_tenths,end_tenths-start_tenths)) stored,
 correction_of uuid unique,
 request_key uuid not null, request_data jsonb not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(business_id,id),unique(business_id,request_key),
 foreign key(business_id,correction_of) references public.korlix_bookkeeping_trips(business_id,id),
 check((method='miles' and manual_tenths is not null and start_tenths is null and end_tenths is null) or
       (method='odometer' and manual_tenths is null and start_tenths is not null and end_tenths is not null and start_tenths>=0 and end_tenths>start_tenths and end_tenths<=99999999)),
 check(distance_tenths between 1 and 99999)
);
create index bookkeeping_trips_period on public.korlix_bookkeeping_trips(business_id,trip_date desc,created_at desc,id);
create index bookkeeping_trips_vehicle on public.korlix_bookkeeping_trips(business_id,vehicle,trip_date);
create index bookkeeping_trips_actor on public.korlix_bookkeeping_trips(created_by);
create index bookkeeping_trips_correction on public.korlix_bookkeeping_trips(business_id,correction_of);
create table public.korlix_bookkeeping_trip_voids (
 id uuid primary key default gen_random_uuid(),business_id uuid not null,
 trip_id uuid not null unique,replacement_id uuid unique,
 reason text not null check(length(btrim(reason)) between 1 and 500),
 request_key uuid not null,request_data jsonb not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(business_id,request_key),
 foreign key(business_id,trip_id) references public.korlix_bookkeeping_trips(business_id,id),
 foreign key(business_id,replacement_id) references public.korlix_bookkeeping_trips(business_id,id),
 check(replacement_id is null or replacement_id<>trip_id)
);
create index bookkeeping_trip_voids_original on public.korlix_bookkeeping_trip_voids(business_id,trip_id);
create index bookkeeping_trip_voids_replacement on public.korlix_bookkeeping_trip_voids(business_id,replacement_id);
create index bookkeeping_trip_voids_actor on public.korlix_bookkeeping_trip_voids(created_by);

create function public.korlix_bookkeeping_mileage_guard_v1() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if tg_op<>'INSERT' then raise exception 'Mileage history is immutable.' using errcode='23514'; end if;
 perform 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.created_by for update;
 if not found then raise exception 'Business owner required.' using errcode='23514'; end if;
 if tg_table_name='korlix_bookkeeping_trips' then
  if new.correction_of is not null and exists(select 1 from public.korlix_bookkeeping_trip_voids where trip_id=new.correction_of) then raise exception 'This trip has already been corrected or voided.' using errcode='40001'; end if;
 elsif tg_table_name='korlix_bookkeeping_trip_voids' then
  if new.replacement_id is not null and not exists(select 1 from public.korlix_bookkeeping_trips where id=new.replacement_id and business_id=new.business_id and correction_of=new.trip_id) then raise exception 'Replacement must correct this same trip.' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger bookkeeping_trips_guard before insert or update or delete on public.korlix_bookkeeping_trips for each row execute function public.korlix_bookkeeping_mileage_guard_v1();
create trigger bookkeeping_trip_voids_guard before insert or update or delete on public.korlix_bookkeeping_trip_voids for each row execute function public.korlix_bookkeeping_mileage_guard_v1();
create function public.korlix_bookkeeping_mileage_pair_v1() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if new.correction_of is not null and not exists(select 1 from public.korlix_bookkeeping_trip_voids where trip_id=new.correction_of and replacement_id=new.id and business_id=new.business_id) then raise exception 'A correction must exclude the original atomically.' using errcode='23514'; end if;
 return null;
end $$;
create constraint trigger bookkeeping_trip_correction_pair after insert on public.korlix_bookkeeping_trips deferrable initially deferred for each row execute function public.korlix_bookkeeping_mileage_pair_v1();

create view public.korlix_bookkeeping_mileage_history with(security_invoker=true) as
 select t.id,t.business_id,t.trip_date,t.vehicle,t.origin,t.destination,t.purpose,t.method,
 t.manual_tenths::text manual_tenths,t.start_tenths::text start_tenths,t.end_tenths::text end_tenths,t.distance_tenths::text distance_tenths,
 t.correction_of,t.created_at,v.id void_id,v.created_at voided_at,v.reason void_reason,v.replacement_id,
 case when v.id is null then t.distance_tenths else 0 end::text included_tenths
 from public.korlix_bookkeeping_trips t left join public.korlix_bookkeeping_trip_voids v on v.trip_id=t.id;

create function public.korlix_bookkeeping_mileage_v1(p_actor uuid,p_action text,p_business uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; t public.korlix_bookkeeping_trips; original public.korlix_bookkeeping_trips; v public.korlix_bookkeeping_trip_voids;
 k uuid; old_id uuid; first_day date; last_day date; period_text text; filter_vehicle text; n integer; page_n integer; items jsonb; summary jsonb; result jsonb;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid mileage request.'; end if;
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if p_action in ('list','export') then
  period_text=p_data->>'period';
  if period_text is null or period_text!~'^20[0-9]{2}(-(0[1-9]|1[0-2]))?$' then raise exception 'Choose a month or year between 2000 and 2099.'; end if;
  first_day=(period_text||case when length(period_text)=4 then '-01-01' else '-01' end)::date;
  last_day=first_day+case when length(period_text)=4 then interval '1 year' else interval '1 month' end;
  filter_vehicle=nullif(p_data->>'vehicle','');if length(filter_vehicle)>80 then raise exception 'Invalid vehicle filter.'; end if;
  page_n=coalesce((p_data->>'offset')::integer,0);if page_n<0 or page_n>1000000 then raise exception 'Invalid page offset.'; end if;
  select count(*) into n from public.korlix_bookkeeping_trips where business_id=b.id and trip_date>=first_day and trip_date<last_day and (filter_vehicle is null or vehicle=filter_vehicle);
  if p_action='export' and n>5000 then raise exception 'This export exceeds 5,000 records. Choose a month or a vehicle.' using errcode='54000'; end if;
  select coalesce(jsonb_agg(to_jsonb(h) order by h.trip_date desc,h.created_at desc,h.id),'[]'::jsonb) into items from
   (select * from public.korlix_bookkeeping_mileage_history where business_id=b.id and trip_date>=first_day and trip_date<last_day and (filter_vehicle is null or vehicle=filter_vehicle) order by trip_date desc,created_at desc,id limit case when p_action='export' then 5000 else 50 end offset case when p_action='export' then 0 else page_n end) h;
  select jsonb_build_object('distance_tenths',coalesce(sum(tt.distance_tenths) filter(where vv.id is null),0)::text,'trip_count',count(*) filter(where vv.id is null),'excluded_count',count(vv.id)) into summary from public.korlix_bookkeeping_trips tt left join public.korlix_bookkeeping_trip_voids vv on vv.trip_id=tt.id where tt.business_id=b.id and tt.trip_date>=first_day and tt.trip_date<last_day and (filter_vehicle is null or tt.vehicle=filter_vehicle);
  return jsonb_build_object('period',period_text,'vehicle',filter_vehicle,'business',jsonb_build_object('id',b.id,'name',b.name),'trips',items,'record_count',n,'summary',summary,'offset',page_n,
   'vehicles',(select coalesce(jsonb_agg(x.vehicle order by x.vehicle),'[]'::jsonb) from (select distinct vehicle from public.korlix_bookkeeping_trips where business_id=b.id order by vehicle limit 100) x));
 end if;
 if p_action not in ('post','correct','void') then raise exception 'Unknown mileage action.'; end if;
 if (p_data->'confirmed') is distinct from 'true'::jsonb then raise exception 'Review and confirm this mileage record.'; end if;
 k=(p_data->>'request_key')::uuid;
 if k is null then raise exception 'Request key required.'; end if;
 -- Replays precede active-state checks, so a lost response can be recovered safely.
 select * into t from public.korlix_bookkeeping_trips where business_id=b.id and request_key=k;
 if found then
  if p_action='void' or t.request_data<>p_data or ((p_action='post')<>(t.correction_of is null)) then raise exception 'This request key has already been used.' using errcode='40001'; end if;
  select to_jsonb(h) into result from public.korlix_bookkeeping_mileage_history h where h.id=t.id;
  return jsonb_build_object('trip',result);
 end if;
 select * into v from public.korlix_bookkeeping_trip_voids where business_id=b.id and request_key=k;
 if found then
  if p_action<>'void' or v.request_data<>p_data or v.replacement_id is not null then raise exception 'This request key has already been used.' using errcode='40001'; end if;
  return jsonb_build_object('void',to_jsonb(v)-'request_data'-'request_key'-'created_by');
 end if;
 if p_action in ('correct','void') then
  old_id=(p_data->>'trip_id')::uuid;
  select * into original from public.korlix_bookkeeping_trips where id=old_id and business_id=b.id;
  if not found then raise exception 'Trip not found.' using errcode='P0002'; end if;
  if exists(select 1 from public.korlix_bookkeeping_trip_voids where trip_id=old_id) then raise exception 'This trip has already been corrected or voided. Refresh its history.' using errcode='40001'; end if;
  if coalesce(length(btrim(p_data->>'reason')),0) not between 1 and 500 then raise exception 'Enter a reason for this correction.'; end if;
 end if;
 if p_action in ('post','correct') then
  insert into public.korlix_bookkeeping_trips(business_id,trip_date,vehicle,origin,destination,purpose,method,manual_tenths,start_tenths,end_tenths,correction_of,request_key,request_data,created_by)
   values(b.id,(p_data->>'trip_date')::date,p_data->>'vehicle',p_data->>'origin',p_data->>'destination',p_data->>'purpose',p_data->>'method',(p_data->>'manual_tenths')::integer,(p_data->>'start_tenths')::integer,(p_data->>'end_tenths')::integer,old_id,k,p_data,p_actor) returning * into t;
 end if;
 if old_id is not null then
  insert into public.korlix_bookkeeping_trip_voids(business_id,trip_id,replacement_id,reason,request_key,request_data,created_by) values(b.id,old_id,case when p_action='correct' then t.id else null end,btrim(p_data->>'reason'),k,p_data,p_actor) returning * into v;
 end if;
 insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'mileage_'||p_action,jsonb_build_object('trip_id',coalesce(t.id,old_id),'original_id',old_id,'void_id',v.id));
 if p_action='void' then return jsonb_build_object('void',to_jsonb(v)-'request_data'-'request_key'-'created_by'); end if;
 select to_jsonb(h) into result from public.korlix_bookkeeping_mileage_history h where h.id=t.id;
 return jsonb_build_object('trip',result);
end $$;
alter table public.korlix_bookkeeping_trips enable row level security;
alter table public.korlix_bookkeeping_trip_voids enable row level security;
revoke all on public.korlix_bookkeeping_trips,public.korlix_bookkeeping_trip_voids,public.korlix_bookkeeping_mileage_history from public,anon,authenticated,service_role;
grant select,insert on public.korlix_bookkeeping_trips,public.korlix_bookkeeping_trip_voids to service_role;
grant select on public.korlix_bookkeeping_mileage_history to service_role;
revoke all on function public.korlix_bookkeeping_mileage_guard_v1(),public.korlix_bookkeeping_mileage_pair_v1(),public.korlix_bookkeeping_mileage_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_mileage_v1(uuid,text,uuid,jsonb) to service_role;
