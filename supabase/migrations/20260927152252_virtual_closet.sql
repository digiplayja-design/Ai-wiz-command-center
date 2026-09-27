-- KORLIX Virtual Closet: server-owned records and private media.
create table public.korlix_closet_assets (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('photo','garment','look')),
 name text not null check(length(name) between 1 and 80),
 category text not null check(category in ('photo','tops','bottoms','dresses','outerwear','shoes','accessories','look')),
 state text not null default 'uploading' check(state in ('uploading','ready','deleting')),
 path text not null, thumb_path text not null, digest text not null,
 bytes bigint not null check(bytes between 1 and 26214400),
 width integer not null, height integer not null,
 lease uuid not null, lease_until timestamptz not null,
 created_at timestamptz not null default now(),
 check(path like user_id::text || '/' || id::text || '/%'),
 check(thumb_path like user_id::text || '/' || id::text || '/%')
);
create index korlix_closet_assets_owner on public.korlix_closet_assets(user_id,created_at desc);
create table public.korlix_closet_jobs (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('tryon','style')),
 state text not null default 'running' check(state in ('running','completed','failed')),
 photo_id uuid, garment_ids uuid[] not null default '{}',
 prompt text not null check(length(prompt)<=1500),
 usage_id uuid not null references public.usage_counters(id),
 result jsonb not null default '{}', error text,
 created_at timestamptz not null default now(), completed_at timestamptz
);
create index korlix_closet_jobs_owner on public.korlix_closet_jobs(user_id,created_at desc);
create index korlix_closet_jobs_usage on public.korlix_closet_jobs(usage_id);
create unique index korlix_closet_one_running on public.korlix_closet_jobs(user_id) where state='running';
alter table public.korlix_closet_assets enable row level security;
alter table public.korlix_closet_jobs enable row level security;
revoke all on public.korlix_closet_assets,public.korlix_closet_jobs from public,anon,authenticated;
grant all on public.korlix_closet_assets,public.korlix_closet_jobs to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('korlix-virtual-closet','korlix-virtual-closet',false,26214400,array['image/jpeg','image/png'])
on conflict(id) do nothing;
create policy korlix_closet_server_only on storage.objects as restrictive for all to anon,authenticated
using(bucket_id <> 'korlix-virtual-closet') with check(bucket_id <> 'korlix-virtual-closet');

create function public.korlix_closet_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public as $$
declare a public.korlix_closet_assets; j public.korlix_closet_jobs;
 v_ids uuid[]; v_count integer; v_lease uuid; v_kind text; v_total bigint;
begin
 if p_actor is null then raise exception 'Sign in to use Virtual Closet.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,221));
 -- Interrupted jobs stay visible and are never retried or charged automatically.
 update korlix_closet_jobs set state='failed',error='This session was interrupted. Your wardrobe is safe; start a new preview.',completed_at=now()
 where user_id=p_actor and state='running' and created_at < now()-interval '12 minutes';
 if p_action='list' then
  return jsonb_build_object('assets',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from korlix_closet_assets x where user_id=p_actor),'[]'::jsonb),
   'jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from korlix_closet_jobs where user_id=p_actor order by created_at desc limit 8) x),'[]'::jsonb));
 elsif p_action='asset_get' then
  select * into a from korlix_closet_assets where id=p_id and user_id=p_actor;
  if not found then raise exception 'This wardrobe item was not found.' using errcode='P0002'; end if;
  return to_jsonb(a);
 elsif p_action='asset_begin' then
  select * into a from korlix_closet_assets where id=p_id and user_id=p_actor;
  if found then
   if a.digest<>p_data->>'digest' or a.kind<>p_data->>'kind' then raise exception 'Use a new upload for this file.' using errcode='40001'; end if;
   if a.state='ready' then return to_jsonb(a); end if;
   if a.state<>'uploading' or a.lease_until>now() then raise exception 'This upload is still finishing. Refresh shortly.' using errcode='40001'; end if;
   update korlix_closet_assets set lease=(p_data->>'lease')::uuid,lease_until=now()+interval '3 minutes' where id=p_id returning * into a;
   return to_jsonb(a);
  end if;
  v_kind=p_data->>'kind';
  select count(*),coalesce(sum(bytes),0) into v_count,v_total from korlix_closet_assets where user_id=p_actor;
  if v_total+(p_data->>'bytes')::bigint>262144000 then raise exception 'Your closet storage is full. Remove an item first.' using errcode='54000'; end if;
  select count(*) into v_count from korlix_closet_assets where user_id=p_actor and kind=v_kind;
  if v_count >= (case v_kind when 'photo' then 5 when 'garment' then 100 else 50 end) then
   raise exception 'Your closet has reached its item limit. Remove an item first.' using errcode='54000';
  end if;
  insert into korlix_closet_assets(id,user_id,kind,name,category,path,thumb_path,digest,bytes,width,height,lease,lease_until)
  values(p_id,p_actor,v_kind,p_data->>'name',p_data->>'category',p_data->>'path',p_data->>'thumb_path',p_data->>'digest',
   (p_data->>'bytes')::bigint,(p_data->>'width')::integer,(p_data->>'height')::integer,(p_data->>'lease')::uuid,now()+interval '3 minutes') returning * into a;
  return to_jsonb(a);
 elsif p_action='asset_finish' then
  update korlix_closet_assets set state='ready' where id=p_id and user_id=p_actor and state='uploading' and lease=(p_data->>'lease')::uuid returning * into a;
  if not found then raise exception 'This upload has changed. Refresh your closet.' using errcode='40001'; end if;
  return to_jsonb(a);
 elsif p_action='asset_delete_begin' then
  select * into a from korlix_closet_assets where id=p_id and user_id=p_actor;
  if not found then raise exception 'This wardrobe item was not found.' using errcode='P0002'; end if;
  if a.state='uploading' and a.lease_until>now() then raise exception 'Wait for the upload to finish before removing it.' using errcode='40001'; end if;
  if exists(select 1 from korlix_closet_jobs where user_id=p_actor and state='running' and (photo_id=p_id or p_id=any(garment_ids))) then
   raise exception 'This item is being used in a preview. Remove it after the preview finishes.' using errcode='40001'; end if;
  update korlix_closet_assets set state='deleting' where id=p_id returning * into a; return to_jsonb(a);
 elsif p_action='asset_delete_finish' then
  delete from korlix_closet_assets where id=p_id and user_id=p_actor and state='deleting'; return '{}'::jsonb;
 elsif p_action='job_get' then
  select * into j from korlix_closet_jobs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This styling session was not found.' using errcode='P0002'; end if; return to_jsonb(j);
 elsif p_action='job_begin' then
  select * into j from korlix_closet_jobs where id=p_id and user_id=p_actor;
  if found then return to_jsonb(j)||jsonb_build_object('replayed',true); end if;
  if exists(select 1 from korlix_closet_jobs where user_id=p_actor and state='running') then raise exception 'Your current styling session is still running. Reopen it from your closet.' using errcode='40001'; end if;
  if (select count(*) from korlix_closet_jobs where user_id=p_actor and created_at>now()-interval '1 hour')>=20 then raise exception 'Please wait before starting more styling sessions.' using errcode='54000'; end if;
  if not exists(select 1 from usage_counters where id=(p_data->>'usage_id')::uuid and user_id=p_actor) then raise exception 'Usage is unavailable. Try again shortly.' using errcode='40001'; end if;
  v_kind=p_data->>'kind';
  select coalesce(array_agg(value::uuid),'{}') into v_ids from jsonb_array_elements_text(p_data->'garment_ids');
  if v_kind='tryon' then
   if not exists(select 1 from korlix_closet_assets where id=(p_data->>'photo_id')::uuid and user_id=p_actor and kind='photo' and state='ready') then raise exception 'Choose your own uploaded photo.' using errcode='P0002'; end if;
   if cardinality(v_ids) not between 1 and 4 or cardinality(v_ids)<>(select count(distinct x) from unnest(v_ids) x) then raise exception 'Choose one to four different wardrobe items.'; end if;
   if (select count(*) from korlix_closet_assets where id=any(v_ids) and user_id=p_actor and kind='garment' and state='ready')<>cardinality(v_ids) then raise exception 'Choose items from your own wardrobe.' using errcode='P0002'; end if;
   if (select count(*) from korlix_closet_assets where user_id=p_actor and kind='look')>=50 then raise exception 'Remove a saved look before creating another.' using errcode='54000'; end if;
   if (select coalesce(sum(bytes),0) from korlix_closet_assets where user_id=p_actor)>236978176 then raise exception 'Make room in your closet before creating a look.' using errcode='54000'; end if;
  end if;
  insert into korlix_closet_jobs(id,user_id,kind,photo_id,garment_ids,prompt,usage_id)
  values(p_id,p_actor,v_kind,(p_data->>'photo_id')::uuid,v_ids,p_data->>'prompt',(p_data->>'usage_id')::uuid) returning * into j;
  return to_jsonb(j)||jsonb_build_object('replayed',false);
 elsif p_action='job_finish' then
  select * into j from korlix_closet_jobs where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'This styling session was not found.' using errcode='P0002'; end if;
  if j.state<>'running' then return to_jsonb(j); end if;
  if j.kind='tryon' and not exists(select 1 from korlix_closet_assets where id=(p_data->'result'->>'asset_id')::uuid and user_id=p_actor and state='ready' and kind='look') then raise exception 'The preview has not finished saving.' using errcode='40001'; end if;
  update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=j.usage_id and user_id=p_actor;
  if not found then raise exception 'Usage is unavailable.' using errcode='40001'; end if;
  update korlix_closet_jobs set state='completed',result=p_data->'result',completed_at=now() where id=p_id returning * into j; return to_jsonb(j);
 elsif p_action='job_fail' then
  update korlix_closet_jobs set state='failed',error=left(p_data->>'error',250),completed_at=now() where id=p_id and user_id=p_actor and state='running' returning * into j;
  return coalesce(to_jsonb(j),'{}'::jsonb);
 end if;
 raise exception 'Unknown closet operation.';
end $$;
revoke all on function public.korlix_closet_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_closet_v1(uuid,text,uuid,jsonb) to service_role;
