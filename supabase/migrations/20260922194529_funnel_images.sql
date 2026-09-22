begin;
-- Small, optimized brand images only. Keep bytes separate from page JSON and
-- list responses; account deletion removes bytes transactionally with metadata.
create table public.korlix_funnel_images (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null check(length(label) between 1 and 100),
  sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
  width integer not null check(width between 1 and 1600),
  height integer not null check(height between 1 and 1600),
  content bytea not null check(octet_length(content) between 1 and 524288),
  created_at timestamptz not null default now(),
  unique(user_id,sha256)
);
alter table public.korlix_funnel_images enable row level security;
revoke all on public.korlix_funnel_images from public,anon,authenticated;
grant select,insert,delete on public.korlix_funnel_images to service_role;
-- FOR KEY SHARE in the document trigger requires UPDATE privilege, but there
-- is no API operation which mutates an existing image. Image IDs are immutable.
grant update on public.korlix_funnel_images to service_role;

create function public.korlix_funnel_image_refs_v1() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
declare image jsonb; image_id uuid;
begin
  for image in select value from jsonb_array_elements(jsonb_build_array(
    new.draft->'logo',new.draft->'hero_image',new.published->'logo',new.published->'hero_image'))
    where value <> 'null'::jsonb order by value->>'id'
  loop
    if jsonb_typeof(image)<>'object' or coalesce(image->>'id','') !~ '^[a-f0-9-]{36}$'
       or jsonb_typeof(image->'alt') is distinct from 'string' or length(image->>'alt')>180 then
      raise exception 'Choose a saved image and a description.';
    end if;
    begin image_id := (image->>'id')::uuid;
    exception when invalid_text_representation then raise exception 'Choose a saved image.'; end;
    perform 1 from public.korlix_funnel_images where id=image_id and user_id=new.user_id for key share;
    if not found then raise exception 'An image is unavailable. Choose it again before saving.' using errcode='40001'; end if;
  end loop;
  return new;
end $$;
revoke all on function public.korlix_funnel_image_refs_v1() from public,anon,authenticated;
grant execute on function public.korlix_funnel_image_refs_v1() to service_role;
create trigger korlix_funnel_image_refs before insert or update of draft,published,user_id
  on public.korlix_funnels for each row execute function public.korlix_funnel_image_refs_v1();

create function public.korlix_funnel_images_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_funnel_images; bytes bytea; used bigint; n integer;
begin
  if p_action='public' then
    select a0.* into a from public.korlix_funnel_images a0
      join public.korlix_funnels f on f.user_id=a0.user_id
      join public.user_profiles u on u.id=f.user_id
      where a0.id=p_id and f.slug=p_data->>'slug' and f.state='published'
        and lower(trim(u.tier))='enterprise'
        and (f.published->'logo'->>'id'=a0.id::text or f.published->'hero_image'->>'id'=a0.id::text);
    if not found then raise exception 'Image not available.' using errcode='P0002'; end if;
    return jsonb_build_object('content',encode(a.content,'base64'),'width',a.width,'height',a.height);
  end if;
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then
    raise exception 'Funnel Studio requires Enterprise.' using errcode='42501';
  end if;
  if p_action='list' then
    return jsonb_build_object('limit',50,'byte_limit',20971520,
      'used_bytes',coalesce((select sum(octet_length(content)) from public.korlix_funnel_images where user_id=p_actor),0),
      'images',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id) from (
        select a0.id,a0.label,a0.width,a0.height,octet_length(a0.content) bytes,a0.created_at,
          (select count(*) from public.korlix_funnels f where f.user_id=p_actor and
            (f.draft->'logo'->>'id'=a0.id::text or f.draft->'hero_image'->>'id'=a0.id::text or
             f.published->'logo'->>'id'=a0.id::text or f.published->'hero_image'->>'id'=a0.id::text)) page_count
        from public.korlix_funnel_images a0 where a0.user_id=p_actor) x),'[]'::jsonb));
  elsif p_action='put' then
    perform pg_advisory_xact_lock(hashtextextended('funnel-images:'||p_actor,0));
    select * into a from public.korlix_funnel_images where user_id=p_actor and sha256=p_data->>'sha256';
    if not found then
      if length(coalesce(p_data->>'content',''))>699052 then raise exception 'Use a smaller image.'; end if;
      bytes := decode(p_data->>'content','base64');
      if substring(bytes from 1 for 4)<>decode('52494646','hex') or substring(bytes from 9 for 4)<>decode('57454250','hex') then
        raise exception 'Choose a supported image.';
      end if;
      select count(*),coalesce(sum(octet_length(content)),0) into n,used from public.korlix_funnel_images where user_id=p_actor;
      if n>=50 or used+octet_length(bytes)>20971520 then
        raise exception 'Your image library is full. Delete unused images before uploading more.' using errcode='54000';
      end if;
      insert into public.korlix_funnel_images(user_id,label,sha256,width,height,content)
      values(p_actor,p_data->>'label',p_data->>'sha256',(p_data->>'width')::integer,(p_data->>'height')::integer,bytes) returning * into a;
    end if;
    return jsonb_build_object('id',a.id,'label',a.label,'width',a.width,'height',a.height,'bytes',octet_length(a.content));
  end if;
  if p_action='delete' then
    select * into a from public.korlix_funnel_images where id=p_id and user_id=p_actor for update;
  else
    select * into a from public.korlix_funnel_images where id=p_id and user_id=p_actor;
  end if;
  if not found then raise exception 'Image not found. Refresh your image library.' using errcode='P0002'; end if;
  if p_action='get' then
    return jsonb_build_object('content',encode(a.content,'base64'),'width',a.width,'height',a.height);
  elsif p_action='delete' then
    if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm image deletion first.'; end if;
    if exists(select 1 from public.korlix_funnels f where f.user_id=p_actor and
      (f.draft->'logo'->>'id'=a.id::text or f.draft->'hero_image'->>'id'=a.id::text or
       f.published->'logo'->>'id'=a.id::text or f.published->'hero_image'->>'id'=a.id::text)) then
      raise exception 'This image is used by a saved draft or published page. Remove it there first; paused pages also keep their images.' using errcode='40001';
    end if;
    delete from public.korlix_funnel_images where id=a.id;
    return jsonb_build_object('deleted',true);
  end if;
  raise exception 'Unsupported image action.';
end $$;
revoke all on function public.korlix_funnel_images_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_images_v1(uuid,text,uuid,jsonb) to service_role;
comment on table public.korlix_funnel_images is 'Private, immutable optimized WebP brand assets, at most 512 KiB each and 20 MiB/50 assets per Enterprise owner. Service-only access; public images must occur in a currently available published page.';
commit;
