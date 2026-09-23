begin;
create function public.korlix_meta_creative_valid_v1(v jsonb)
returns boolean language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare k text; s text; lim integer;
begin
  if v is null or jsonb_typeof(v)<>'object' or not(v ?& array['primary_text','headline','description','cta','image_id','image_alt']) or (v-array['primary_text','headline','description','cta','image_id','image_alt'])<>'{}'::jsonb then return false; end if;
  foreach k in array array['primary_text','headline','description','image_alt'] loop
    if jsonb_typeof(v->k)<>'string' then return false; end if;
    s:=v->>k; lim:=case k when 'primary_text' then 1000 when 'headline' then 100 when 'description' then 200 else 180 end;
    if s<>btrim(s) or char_length(s)>lim or s ~ '[[:cntrl:]]' or s ~ U&'[\00AD\061C\200B-\200F\2028-\202E\2060-\206F\FEFF]' then return false; end if;
  end loop;
  if jsonb_typeof(v->'cta')<>'string' or v->>'cta' not in ('LEARN_MORE','CONTACT_US','SIGN_UP','SHOP_NOW','GET_QUOTE') then return false; end if;
  if v->'image_id'='null'::jsonb then return v->>'image_alt'=''; end if;
  return jsonb_typeof(v->'image_id')='string' and v->>'image_id' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$';
end $$;
revoke all on function public.korlix_meta_creative_valid_v1(jsonb) from public,anon,authenticated;
grant execute on function public.korlix_meta_creative_valid_v1(jsonb) to service_role;
create table public.korlix_funnel_meta_creatives (
  campaign_id uuid primary key references public.korlix_funnel_campaigns(id) on delete cascade,
  version integer not null default 1 check(version>0),
  assets jsonb not null check(public.korlix_meta_creative_valid_v1(assets)),
  image_id uuid references public.korlix_funnel_images(id) on delete no action deferrable initially deferred,
  image_snapshot jsonb,
  context_fingerprint text not null check(context_fingerprint ~ '^[a-f0-9]{64}$'),
  context_snapshot jsonb not null check(jsonb_typeof(context_snapshot)='object' and octet_length(context_snapshot::text)<=32768),
  updated_at timestamptz not null default now(),
  check(image_id is not distinct from (assets->>'image_id')::uuid),
  check((image_id is null and image_snapshot is null) or (image_id is not null and image_snapshot is not null and jsonb_typeof(image_snapshot)='object' and image_snapshot->>'id'=image_id::text))
);
create index korlix_meta_creative_image_idx on public.korlix_funnel_meta_creatives(image_id) where image_id is not null;
alter table public.korlix_funnel_meta_creatives enable row level security;
revoke all on public.korlix_funnel_meta_creatives from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_meta_creatives to service_role;
comment on table public.korlix_funnel_meta_creatives is 'Private single-image Meta draft preparation. App text limits, immutable private image references, cached identity context. No provider upload, policy approval, ad creation or spending authorization.';
create function public.korlix_funnel_meta_creative_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare setup jsonb; saved public.korlix_funnel_meta_creatives; c public.korlix_funnel_campaigns; img public.korlix_funnel_images;
  assets jsonb; snapshot jsonb; image_snapshot jsonb; fingerprint text;
begin
  if p_action not in ('read','save') then raise exception 'Unknown Meta ad draft action.'; end if;
  -- Reuse the setup reader's Enterprise/ownership/platform checks and stable
  -- funnel -> campaign -> connection -> setup lock order. No provider calls.
  setup:=public.korlix_funnel_meta_preparation_v1(p_actor,'read',p_funnel,p_data);
  select * into c from public.korlix_funnel_campaigns where id=(setup->>'campaign_id')::uuid;
  select * into saved from public.korlix_funnel_meta_creatives where campaign_id=c.id for update;
  snapshot:=setup->'current_snapshot'; fingerprint:=setup->>'fingerprint';
  if p_action='save' then
    if c.state='archived' then raise exception 'Reopen this campaign before editing its Meta ad draft.'; end if;
    if (p_data->>'version')::integer is distinct from coalesce(saved.version,0) or p_data->>'fingerprint' is distinct from fingerprint then raise exception 'The draft, campaign, Page identity or landing page changed. Reload before saving again.' using errcode='40001'; end if;
    assets:=p_data->'assets';
    if not public.korlix_meta_creative_valid_v1(assets) then raise exception 'Check the Meta ad text, button and image selection.'; end if;
    if assets->>'image_id' is not null then
      select * into img from public.korlix_funnel_images where id=(assets->>'image_id')::uuid and user_id=p_actor for key share;
      if not found then raise exception 'This image is no longer available. Reload and choose another image.' using errcode='40001'; end if;
      image_snapshot:=jsonb_build_object('id',img.id,'label',img.label,'width',img.width,'height',img.height,'sha256',img.sha256);
    end if;
    insert into public.korlix_funnel_meta_creatives(campaign_id,assets,image_id,image_snapshot,context_fingerprint,context_snapshot)
    values(c.id,assets,img.id,image_snapshot,fingerprint,snapshot)
    on conflict(campaign_id) do update set assets=excluded.assets,image_id=excluded.image_id,image_snapshot=excluded.image_snapshot,context_fingerprint=excluded.context_fingerprint,context_snapshot=excluded.context_snapshot,version=public.korlix_funnel_meta_creatives.version+1,updated_at=now() returning * into saved;
  end if;
  assets:=coalesce(saved.assets,'{"primary_text":"","headline":"","description":"","cta":"LEARN_MORE","image_id":null,"image_alt":""}'::jsonb);
  return jsonb_build_object('source','meta_ad_draft','funnel_id',p_funnel,'campaign_id',c.id,'version',coalesce(saved.version,0),'fingerprint',fingerprint,'setup',setup,'saved_context',saved.context_snapshot,'assets',assets,'image',saved.image_snapshot,'updated_at',saved.updated_at,'draft_current',coalesce(saved.context_fingerprint=fingerprint,false),'editable',c.state<>'archived','creative_complete',length(assets->>'primary_text')>0 and length(assets->>'headline')>0 and saved.image_id is not null and length(assets->>'image_alt')>0,'ad_publishing_ready',false);
end $$;
revoke all on function public.korlix_funnel_meta_creative_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_meta_creative_v1(uuid,text,uuid,jsonb) to service_role;

-- Preserve the original owner/public image behavior; protect creative references.
create or replace function public.korlix_funnel_images_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
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
          (select count(*) from public.korlix_funnel_meta_creatives mc where mc.image_id=a0.id) creative_count,
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
    if exists(select 1 from public.korlix_funnel_meta_creatives where image_id=a.id) then
      raise exception 'This image is used by a saved Meta ad draft. Remove it from that draft first.' using errcode='40001';
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
