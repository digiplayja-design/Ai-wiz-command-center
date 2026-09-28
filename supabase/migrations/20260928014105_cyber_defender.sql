-- Private text-based Defender checks. Only the verified backend may access these tables.
create table public.korlix_defender_reports (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 state text not null check(state in('preparing','ready','failed','deleted')),
 mode text not null check(mode in('quick','ai')), details jsonb not null default '{}',
 request_hash text not null, result jsonb not null, review jsonb not null default '{}',
 progress jsonb not null default '{}', revision integer not null default 0,
 last_event_id uuid, last_event_hash text,
 usage_id uuid references public.usage_counters(id) on delete set null,
 charged integer not null default 0 check(charged in(0,1)), error text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.korlix_defender_profiles (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 mode text not null default 'personal' check(mode in('personal','business')),
 habits jsonb not null default '{}', revision integer not null default 0,
 last_event_id uuid, last_event_hash text, updated_at timestamptz not null default now()
);
alter table public.korlix_defender_reports enable row level security;
alter table public.korlix_defender_profiles enable row level security;
revoke all on public.korlix_defender_reports,public.korlix_defender_profiles from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_defender_reports,public.korlix_defender_profiles to service_role;
create index korlix_defender_owner_created on public.korlix_defender_reports(owner_id,created_at desc);
create index korlix_defender_owner_active on public.korlix_defender_reports(owner_id,updated_at desc) where state<>'deleted';
create index korlix_defender_usage on public.korlix_defender_reports(usage_id) where usage_id is not null;
create function public.korlix_cyber_defender_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.korlix_defender_reports; old public.korlix_defender_reports;
 f public.korlix_defender_profiles; h text; uid uuid; k text; profile jsonb;
begin
 if p_actor is null then raise exception 'Sign in to use Cybersecurity Defender.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('defender:'||p_actor::text,0));
 for old in select * from public.korlix_defender_reports where owner_id=p_actor and state='preparing' and created_at<now()-interval '8 minutes' for update loop
  if old.charged=1 then
   update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=old.usage_id and user_id=p_actor;
  end if;
  update public.korlix_defender_reports set state='failed',charged=0,error='The deeper review was interrupted. Your credit was returned. Your quick check is still available.',updated_at=now() where id=old.id;
 end loop;
 if p_action in('list','checklist') then
  select * into f from public.korlix_defender_profiles where owner_id=p_actor for update;
  if p_action='checklist' then
   if not found then insert into public.korlix_defender_profiles(owner_id)values(p_actor) returning * into f;end if;
   h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
   if f.last_event_id=(p_data->>'request_key')::uuid then
    if f.last_event_hash is distinct from h then raise exception 'Use a new request for a different change.' using errcode='40001';end if;
   else
    if f.revision is distinct from (p_data->>'revision')::integer then raise exception 'Your checklist changed elsewhere. Refresh before continuing.' using errcode='40001';end if;
    k:=p_data->>'key';
    if k='mode' then
     if p_data->>'mode' is null or p_data->>'mode' not in('personal','business') then raise exception 'Choose Personal or Business.';end if;
     f.mode:=p_data->>'mode';
    else
     if k is null or k not in('mfa','passwords','updates','backups','verify','recovery','sessions','devices','admins','staff','payments','plan') or jsonb_typeof(p_data->'checked') is distinct from 'boolean' then raise exception 'Choose an available checklist item.';end if;
     f.habits:=jsonb_set(f.habits,array[k],p_data->'checked');
    end if;
    update public.korlix_defender_profiles set mode=f.mode,habits=f.habits,revision=revision+1,last_event_id=(p_data->>'request_key')::uuid,last_event_hash=h,updated_at=now() where owner_id=p_actor returning * into f;
   end if;
  end if;
  profile:=case when f.owner_id is null then jsonb_build_object('mode','personal','habits','{}'::jsonb,'revision',0) else to_jsonb(f)-'owner_id'-'last_event_id'-'last_event_hash' end;
  if p_action='checklist' then return jsonb_build_object('profile',profile);end if;
  return jsonb_build_object('profile',profile,'reports',coalesce((select jsonb_agg(jsonb_build_object(
   'id',x.id,'state',x.state,'mode',x.mode,'title',x.result->>'title','concern',case when x.review->>'concern'='high' or x.result->>'concern'='high' then 'high' when x.review->>'concern'='review' and x.result->>'concern'='unknown' then 'review' else x.result->>'concern' end,
   'progress',x.progress,'actionCount',jsonb_array_length(x.result->'actions'),'created_at',x.created_at,'updated_at',x.updated_at) order by x.updated_at desc,x.id) from public.korlix_defender_reports x where x.owner_id=p_actor and x.state<>'deleted'),'[]'));
 end if;
 if p_action in('lookup','create') then
  h:=p_data->>'request_hash';
  if h is null or h!~'^[a-f0-9]{64}$' then raise exception 'This check could not be verified.';end if;
  select * into s from public.korlix_defender_reports where id=p_id and owner_id=p_actor for update;
  if found then
   if s.request_hash is distinct from h or s.state='deleted' then raise exception 'Use a new request after changing your message.' using errcode='40001';end if;
   return (to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash')||jsonb_build_object('replayed',true);
  end if;
  if p_action='lookup' then raise exception 'Report not found.' using errcode='P0002';end if;
  if (select count(*) from public.korlix_defender_reports where owner_id=p_actor and state<>'deleted')>=50 then raise exception 'You have 50 saved reports. Remove one before creating another.' using errcode='54000';end if;
  if (select count(*) from public.korlix_defender_reports where owner_id=p_actor and created_at>now()-interval '1 hour')>=60 then raise exception 'Please wait before creating more reports.' using errcode='54000';end if;
  if p_data->'details'->>'mode'='ai' then
   if exists(select 1 from public.korlix_defender_reports where owner_id=p_actor and state='preparing') then raise exception 'A deeper review is already running. Open Saved reports to follow it.' using errcode='40001';end if;
   if (select count(*) from public.korlix_defender_reports where owner_id=p_actor and mode='ai' and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before requesting more deeper reviews.' using errcode='54000';end if;
   uid:=(p_data->>'usage_id')::uuid;
   perform 1 from public.usage_counters where id=uid and user_id=p_actor for update;
   if not found then raise exception 'Usage could not be verified.' using errcode='40001';end if;
   if (p_data->>'credit_limit')::integer is null or (p_data->>'request_limit')::integer is null then raise exception 'Usage limits could not be verified.' using errcode='42501';end if;
   update public.usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;
   if not found then raise exception 'Your daily generation allowance is used. The free quick check is still available.' using errcode='54000';end if;
  elsif p_data->'details'->>'mode' is distinct from 'quick' then raise exception 'Choose an available check.';end if;
  insert into public.korlix_defender_reports(id,owner_id,state,mode,details,request_hash,result,usage_id,charged)
   values(p_id,p_actor,case when uid is null then 'ready' else 'preparing' end,p_data->'details'->>'mode',p_data->'details',h,p_data->'result',uid,case when uid is null then 0 else 1 end) returning * into s;
  return (to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash')||jsonb_build_object('replayed',false);
 end if;
 select * into s from public.korlix_defender_reports where id=p_id and owner_id=p_actor for update;
 if not found or s.state='deleted' then
  if p_action='remove' and s.state='deleted' then return jsonb_build_object('removed',true);end if;
  raise exception 'Report not found.' using errcode='P0002';
 end if;
 if p_action in('finish','fail') then
  if s.state='preparing' then
   if p_action='fail' then
    if s.charged=1 then update public.usage_counters set credits_used=greatest(coalesce(credits_used,0)-1,0),standard_generations=greatest(coalesce(standard_generations,0)-1,0),updated_at=now() where id=s.usage_id and user_id=p_actor;end if;
    update public.korlix_defender_reports set state='failed',charged=0,error='KORLIX could not finish the deeper review. Your credit was returned. Your quick check is still available.',updated_at=now() where id=s.id returning * into s;
   else
    update public.korlix_defender_reports set state='ready',review=p_data->'review',updated_at=now() where id=s.id returning * into s;
   end if;
  end if;
 elsif p_action='progress' then
  h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
  if s.last_event_id=(p_data->>'request_key')::uuid then
   if s.last_event_hash is distinct from h then raise exception 'Use a new request for a different action.' using errcode='40001';end if;
  else
   if s.revision is distinct from (p_data->>'revision')::integer then raise exception 'Your report changed elsewhere. Refresh before continuing.' using errcode='40001';end if;
   k:=p_data->>'key';
   if k is null or jsonb_typeof(p_data->'checked') is distinct from 'boolean' or not exists(select 1 from jsonb_array_elements(s.result->'actions') a where a->>'id'=k) then raise exception 'Choose an available report action.';end if;
   update public.korlix_defender_reports set progress=jsonb_set(progress,array[k],p_data->'checked'),revision=revision+1,last_event_id=(p_data->>'request_key')::uuid,last_event_hash=h,updated_at=now() where id=s.id returning * into s;
  end if;
 elsif p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before deleting this report.';end if;
  if s.state='preparing' then raise exception 'Wait for the deeper review to finish before deleting it.' using errcode='40001';end if;
  update public.korlix_defender_reports set state='deleted',details='{}',result='{}',review='{}',progress='{}',error=null,last_event_id=null,last_event_hash=null,updated_at=now() where id=s.id;
  return jsonb_build_object('removed',true);
 elsif p_action<>'get' then raise exception 'Unknown Defender action.';
 end if;
 return to_jsonb(s)-'owner_id'-'request_hash'-'usage_id'-'last_event_id'-'last_event_hash';
end $$;
revoke all on function public.korlix_cyber_defender_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_cyber_defender_v1(uuid,text,uuid,jsonb) to service_role;
