-- KORLIX BabyBlend: private references, portraits and charge-once generation.
create table public.korlix_babyblend_assets (
 id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('source','portrait')),state text not null default 'uploading' check(state in ('uploading','ready','deleting')),
 details jsonb not null default '{}' check(jsonb_typeof(details)='object' and octet_length(details::text)<=2000),
 path text not null,thumb_path text not null,digest text not null check(digest~'^[0-9a-f]{64}$'),thumb_digest text not null check(thumb_digest~'^[0-9a-f]{64}$'),
 bytes bigint not null check(bytes between 1 and 26214400),width integer not null check(width>0),height integer not null check(height>0),
 lease uuid not null,lease_until timestamptz not null,created_at timestamptz not null default now(),
 check(path like user_id::text||'/'||id::text||'/%'),check(thumb_path like user_id::text||'/'||id::text||'/%')
);
create index korlix_babyblend_assets_owner on public.korlix_babyblend_assets(user_id,created_at desc);
create table public.korlix_babyblend_jobs (
 id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,
 photo_ids uuid[] not null check(cardinality(photo_ids)=2 and photo_ids[1]<>photo_ids[2]),
 age text not null check(age in ('baby','toddler','child')),style text not null check(style in ('natural','studio','artistic')),
 state text not null default 'running' check(state in ('running','completed','failed')),
 usage_id uuid not null references public.usage_counters(id),charged integer not null default 0 check(charged in (0,1)),
 result jsonb not null default '{}' check(octet_length(result::text)<=4000),error text,
 consent_version integer not null default 1,created_at timestamptz not null default now(),completed_at timestamptz
);
create index korlix_babyblend_jobs_owner on public.korlix_babyblend_jobs(user_id,created_at desc);
create index korlix_babyblend_jobs_usage on public.korlix_babyblend_jobs(usage_id);
create unique index korlix_babyblend_one_running on public.korlix_babyblend_jobs(user_id) where state='running';
alter table public.korlix_babyblend_assets enable row level security;
alter table public.korlix_babyblend_jobs enable row level security;
revoke all on public.korlix_babyblend_assets,public.korlix_babyblend_jobs from public,anon,authenticated;
grant all on public.korlix_babyblend_assets,public.korlix_babyblend_jobs to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('korlix-babyblend','korlix-babyblend',false,26214400,array['image/jpeg','image/png']) on conflict(id) do nothing;
create policy korlix_babyblend_server_only on storage.objects as restrictive for all to anon,authenticated using(bucket_id<>'korlix-babyblend') with check(bucket_id<>'korlix-babyblend');
create function public.korlix_babyblend_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path=public as $$
declare a public.korlix_babyblend_assets;j public.korlix_babyblend_jobs;v_ids uuid[];v_kind text;v_count integer;v_total bigint;v_reserve bigint;
begin
 if p_actor is null then raise exception 'Sign in to use BabyBlend.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,225));
 update korlix_babyblend_jobs set state='failed',error='This portrait was interrupted. No credit was charged. Start a new BabyBlend.',completed_at=now() where user_id=p_actor and state='running' and created_at<now()-interval '12 minutes';
 if p_action='list' then
  return jsonb_build_object('assets',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from korlix_babyblend_assets x where user_id=p_actor),'[]'::jsonb),'jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from korlix_babyblend_jobs where user_id=p_actor order by created_at desc limit 50)x),'[]'::jsonb));
 elsif p_action='asset_get' then
  select * into a from korlix_babyblend_assets where id=p_id and user_id=p_actor;if not found then raise exception 'This BabyBlend photo was not found.' using errcode='P0002';end if;return to_jsonb(a);
 elsif p_action='asset_begin' then
  select * into a from korlix_babyblend_assets where id=p_id and user_id=p_actor;
  if found then
   if a.digest is distinct from p_data->>'digest' or a.kind is distinct from p_data->>'kind' or a.details is distinct from p_data->'details' then raise exception 'Use a new upload for this photo.' using errcode='40001';end if;
   if a.state='ready' then return to_jsonb(a);end if;
   if a.state<>'uploading' or a.lease_until>now() then raise exception 'This upload is still finishing. Retry after three minutes.' using errcode='40001';end if;
   update korlix_babyblend_assets set lease=(p_data->>'lease')::uuid,lease_until=now()+interval '3 minutes' where id=a.id returning * into a;return to_jsonb(a);
  end if;
  v_kind=p_data->>'kind';
  if v_kind='portrait' and not exists(select 1 from korlix_babyblend_jobs where id=p_id and user_id=p_actor and state='running') then raise exception 'This generation is no longer active. No credit was charged.' using errcode='40001';end if;
  select count(*) into v_count from korlix_babyblend_assets where user_id=p_actor and kind=v_kind;
  if v_count>=(case v_kind when 'source' then 10 else 50 end) then raise exception 'Your BabyBlend photo limit is reached. Remove a saved photo first.' using errcode='54000';end if;
  select coalesce(sum(bytes),0) into v_total from korlix_babyblend_assets where user_id=p_actor;
  v_reserve:=case when v_kind='source' and exists(select 1 from korlix_babyblend_jobs where user_id=p_actor and state='running') then 26214400 else 0 end;
  if v_total+(p_data->>'bytes')::bigint+v_reserve>314572800 then raise exception 'Your BabyBlend storage is full. Remove saved photos to make room.' using errcode='54000';end if;
  insert into korlix_babyblend_assets(id,user_id,kind,details,path,thumb_path,digest,thumb_digest,bytes,width,height,lease,lease_until) values(p_id,p_actor,v_kind,p_data->'details',p_data->>'path',p_data->>'thumb_path',p_data->>'digest',p_data->>'thumb_digest',(p_data->>'bytes')::bigint,(p_data->>'width')::integer,(p_data->>'height')::integer,(p_data->>'lease')::uuid,now()+interval '3 minutes') returning * into a;return to_jsonb(a);
 elsif p_action='asset_finish' then
  update korlix_babyblend_assets set state='ready' where id=p_id and user_id=p_actor and kind='source' and state='uploading' and lease=(p_data->>'lease')::uuid and lease_until>now() returning * into a;
  if not found then raise exception 'This upload changed or expired. Retry the same photo.' using errcode='40001';end if;return to_jsonb(a);
 elsif p_action='asset_delete_begin' then
  select * into a from korlix_babyblend_assets where id=p_id and user_id=p_actor;if not found then raise exception 'This BabyBlend photo was not found.' using errcode='P0002';end if;
  if exists(select 1 from korlix_babyblend_jobs where user_id=p_actor and state='running' and (p_id=any(photo_ids) or id=p_id)) then raise exception 'Wait for this portrait to finish before removing its photos.' using errcode='40001';end if;
  if a.state='uploading' and a.lease_until>now() then raise exception 'Wait three minutes before removing an interrupted upload.' using errcode='40001';end if;
  update korlix_babyblend_assets set state='deleting' where id=p_id returning * into a;return to_jsonb(a);
 elsif p_action='asset_delete_finish' then
  delete from korlix_babyblend_assets where id=p_id and user_id=p_actor and state='deleting';return '{}'::jsonb;
 elsif p_action='job_get' then
  select * into j from korlix_babyblend_jobs where id=p_id and user_id=p_actor;if not found then raise exception 'This BabyBlend session was not found.' using errcode='P0002';end if;return to_jsonb(j);
 elsif p_action='job_begin' then
  select coalesce(array_agg(value::uuid order by ordinality),'{}') into v_ids from jsonb_array_elements_text(p_data->'photo_ids') with ordinality;
  select * into j from korlix_babyblend_jobs where id=p_id and user_id=p_actor;
  if found then
   if j.photo_ids is distinct from v_ids or j.age is distinct from p_data->>'age' or j.style is distinct from p_data->>'style' then raise exception 'Use a new request after changing photos or options.' using errcode='40001';end if;
   return to_jsonb(j)||jsonb_build_object('replayed',true);
  end if;
  if cardinality(v_ids)<>2 or v_ids[1]=v_ids[2] then raise exception 'Choose two different adult photos.';end if;
  if (select count(*) from korlix_babyblend_assets where id=any(v_ids) and user_id=p_actor and kind='source' and state='ready')<>2 then raise exception 'Choose two of your own saved adult photos.' using errcode='P0002';end if;
  if (select count(distinct digest) from korlix_babyblend_assets where id=any(v_ids) and user_id=p_actor)<>2 then raise exception 'Choose a different photo for each person.';end if;
  if exists(select 1 from korlix_babyblend_jobs where user_id=p_actor and state='running') then raise exception 'Your current BabyBlend is still running. Reopen it to follow progress.' using errcode='40001';end if;
  if (select count(*) from korlix_babyblend_jobs where user_id=p_actor and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before creating more portraits.' using errcode='54000';end if;
  if (select count(*) from korlix_babyblend_assets where user_id=p_actor and kind='portrait')>=50 then raise exception 'Remove a saved portrait before creating another.' using errcode='54000';end if;
  if (select coalesce(sum(bytes),0) from korlix_babyblend_assets where user_id=p_actor)>288358400 then raise exception 'Make room in BabyBlend before creating a portrait.' using errcode='54000';end if;
  if not exists(select 1 from usage_counters where id=(p_data->>'usage_id')::uuid and user_id=p_actor) then raise exception 'Usage is unavailable. Try again shortly.' using errcode='40001';end if;
  insert into korlix_babyblend_jobs(id,user_id,photo_ids,age,style,usage_id) values(p_id,p_actor,v_ids,p_data->>'age',p_data->>'style',(p_data->>'usage_id')::uuid) returning * into j;return to_jsonb(j)||jsonb_build_object('replayed',false);
 elsif p_action='job_finish' then
  select * into j from korlix_babyblend_jobs where id=p_id and user_id=p_actor for update;if not found then raise exception 'This BabyBlend session was not found.' using errcode='P0002';end if;
  if j.state<>'running' then return to_jsonb(j);end if;
  if (p_data->'result'->>'assetId')::uuid is distinct from j.id then raise exception 'The saved portrait does not match this session.' using errcode='40001';end if;
  update korlix_babyblend_assets set state='ready' where id=j.id and user_id=p_actor and kind='portrait' and state='uploading' and lease=(p_data->>'lease')::uuid and lease_until>now() returning * into a;
  if not found then raise exception 'The portrait has not finished saving.' using errcode='40001';end if;
  update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=j.usage_id and user_id=p_actor;
  if not found then raise exception 'Usage is unavailable.' using errcode='40001';end if;
  update korlix_babyblend_jobs set state='completed',charged=1,result=p_data->'result',completed_at=now() where id=j.id returning * into j;return to_jsonb(j);
 elsif p_action='job_fail' then
  update korlix_babyblend_jobs set state='failed',error=left(p_data->>'error',300),completed_at=now() where id=p_id and user_id=p_actor and state='running' returning * into j;return coalesce(to_jsonb(j),'{}'::jsonb);
 end if;
 raise exception 'Unknown BabyBlend operation.';
end $$;
revoke all on function public.korlix_babyblend_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_babyblend_v1(uuid,text,uuid,jsonb) to service_role;
