-- Albums follow Social's service-only, security-invoker authorization boundary.
create table public.korlix_social_albums (
 id uuid primary key,
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 title text not null check(char_length(title) between 1 and 80),
 visibility text not null default 'connections' check(visibility in ('private','connections','members')),
 cover_id uuid, deleted boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index korlix_social_albums_owner on public.korlix_social_albums(owner,created_at desc,id);
create table public.korlix_social_album_photos (
 id uuid primary key, album_id uuid not null references public.korlix_social_albums(id) on delete cascade,
 seq bigint generated always as identity unique,
 photo_path text unique not null, sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 bytes integer not null check(bytes between 1 and 8388608),
 deleted boolean not null default false, created_at timestamptz not null default now()
);
create index korlix_social_album_photos_album on public.korlix_social_album_photos(album_id,seq);
alter table public.korlix_social_albums enable row level security;
alter table public.korlix_social_album_photos enable row level security;
revoke all on public.korlix_social_albums,public.korlix_social_album_photos from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_albums,public.korlix_social_album_photos to service_role;
revoke all on sequence public.korlix_social_album_photos_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_social_album_photos_seq_seq to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-social-albums','korlix-social-albums',false,8388608,array['image/jpeg']);
create policy korlix_social_albums_browser_deny on storage.objects as restrictive
 for all to anon,authenticated using(bucket_id <> 'korlix-social-albums') with check(bucket_id <> 'korlix-social-albums');

create function public.korlix_social_album_card(a public.korlix_social_albums) returns jsonb
 language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',a.id,'title',a.title,'visibility',a.visibility,'cover_id',a.cover_id,
  'created_at',a.created_at,'photo_count',(select count(*) from korlix_social_album_photos where album_id=a.id and not deleted),
  'cover', (select jsonb_build_object('id',p.id,'photo_path',p.photo_path) from korlix_social_album_photos p
   where p.album_id=a.id and not p.deleted order by (p.id=a.cover_id) desc nulls last,p.seq limit 1));
$$;

create function public.korlix_social_albums_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
 language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; owner_profile korlix_social_profiles; a korlix_social_albums; photo_row korlix_social_album_photos;
 target uuid; album_id uuid := (p_data->>'album')::uuid; photo_id uuid := (p_data->>'photo')::uuid;
 connected boolean; items jsonb; paths jsonb; title_text text := trim(p_data->>'title');
 audience text := coalesce(p_data->>'visibility','connections');
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action='albums' then
  target:=coalesce((p_data->>'peer')::uuid,me.id);
 else
  target:=me.id;
  if p_action<>'album_create' then
   select * into a from korlix_social_albums where id=album_id;
   if a.id is null then raise exception 'Album not found.' using errcode='P0002'; end if;
   target:=a.owner;
  end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
 select * into owner_profile from korlix_social_profiles where id=target;
 connected:=exists(select 1 from korlix_social_connections where state='accepted' and
  least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target));
 if owner_profile.id is null or owner_profile.suspended or korlix_social_blocked(me.id,target) or
  (target<>me.id and not owner_profile.discoverable and not connected) then
  raise exception 'This profile is unavailable.' using errcode='42501';
 end if;
 if p_action='albums' then
  select coalesce(jsonb_agg(x.card order by x.created_at desc,x.id),'[]') into items from (
   select id,created_at,korlix_social_album_card(x) card from korlix_social_albums x where owner=target and not deleted
   and (target=me.id or visibility='members' or (visibility='connections' and connected)) order by created_at desc,id limit 20)x;
  return jsonb_build_object('items',items,'owner',korlix_social_card(owner_profile),'owned',target=me.id);
 end if;
 if p_action='album' then
  if a.deleted or (target<>me.id and not (a.visibility='members' or (a.visibility='connections' and connected))) then
   raise exception 'Album not available to you.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'photo_path',photo_path,'created_at',created_at) order by seq),'[]')
   into items from korlix_social_album_photos where korlix_social_album_photos.album_id=a.id and not deleted;
  return jsonb_build_object('album',korlix_social_album_card(a),'items',items,'owned',target=me.id);
 end if;
 if target<>me.id then raise exception 'Only the album owner can change it.' using errcode='42501'; end if;
 -- One owner lock bounds album/photo counts even across concurrent uploads.
 perform pg_advisory_xact_lock(hashtextextended('social-albums:'||me.id::text,0));
 if p_action='album_create' then
  if title_text is null or char_length(title_text) not between 1 and 80 or audience not in ('private','connections','members') then raise exception 'Add an album name and choose who can view it.'; end if;
  select * into a from korlix_social_albums where id=album_id;
  if a.id is not null then
   if a.owner<>me.id or a.deleted or a.title<>title_text or a.visibility<>audience then raise exception 'Album ID unavailable.' using errcode='42501'; end if;
  else
   if (select count(*) from korlix_social_albums where owner=me.id and not deleted)>=20 then raise exception 'You can keep up to 20 albums.' using errcode='54000'; end if;
   perform korlix_social_limit(p_actor,'album-create',20,86400);
   insert into korlix_social_albums(id,owner,title,visibility) values(album_id,me.id,title_text,audience) returning * into a;
  end if;
  return jsonb_build_object('album',korlix_social_album_card(a));
 end if;
 select * into a from korlix_social_albums where id=album_id for update;
 if a.deleted and p_action<>'album_delete' then raise exception 'Album was deleted.' using errcode='P0002'; end if;
 if p_action='album_save' then
  if title_text is null or char_length(title_text) not between 1 and 80 or audience not in ('private','connections','members') then raise exception 'Add an album name and choose who can view it.'; end if;
  update korlix_social_albums set title=title_text,visibility=audience,updated_at=now() where id=a.id returning * into a;
 elsif p_action='album_delete' then
  update korlix_social_albums set deleted=true,updated_at=now() where id=a.id;
  update korlix_social_album_photos set deleted=true where korlix_social_album_photos.album_id=a.id;
  select coalesce(jsonb_agg(photo_path),'[]') into paths from korlix_social_album_photos where korlix_social_album_photos.album_id=a.id;
  return jsonb_build_object('ok',true,'remove_paths',paths);
 elsif p_action in ('album_upload_begin','album_photo_add') then
  select * into photo_row from korlix_social_album_photos where id=photo_id;
  if photo_row.id is not null then
   if photo_row.album_id<>a.id or photo_row.deleted or (p_action='album_photo_add' and photo_row.sha256<>p_data->>'sha256') then raise exception 'Photo ID unavailable.' using errcode='42501'; end if;
   return jsonb_build_object('existing',true,'photo',jsonb_build_object('id',photo_row.id,'photo_path',photo_row.photo_path));
  end if;
  if (select count(*) from korlix_social_album_photos where korlix_social_album_photos.album_id=a.id and not deleted)>=100 or
   (select count(*) from korlix_social_album_photos q join korlix_social_albums x on x.id=q.album_id where x.owner=me.id and not q.deleted and not x.deleted)>=500 then
   raise exception 'Albums hold up to 100 photos, with 500 photos per profile.' using errcode='54000';
  end if;
  if p_action='album_upload_begin' then
   perform korlix_social_limit(p_actor,'album-upload',120,3600);
   return jsonb_build_object('owner',me.id,'album',a.id);
  end if;
  if (p_data->>'path') is null or (p_data->>'path') !~ ('^'||me.id::text||'/'||a.id::text||'/[a-f0-9-]{36}\.jpg$') then raise exception 'Invalid photo path.'; end if;
  insert into korlix_social_album_photos(id,album_id,photo_path,sha256,bytes)
   values(photo_id,a.id,p_data->>'path',p_data->>'sha256',(p_data->>'bytes')::integer) returning * into photo_row;
  update korlix_social_albums set cover_id=coalesce(cover_id,photo_row.id),updated_at=now() where id=a.id;
  return jsonb_build_object('photo',jsonb_build_object('id',photo_row.id,'photo_path',photo_row.photo_path));
 elsif p_action in ('album_photo_delete','album_cover') then
  select * into photo_row from korlix_social_album_photos where id=photo_id and korlix_social_album_photos.album_id=a.id;
  if photo_row.id is null then raise exception 'Photo not found.' using errcode='P0002'; end if;
  if p_action='album_cover' then
   if photo_row.deleted then raise exception 'Photo was deleted.' using errcode='P0002'; end if;
   update korlix_social_albums set cover_id=photo_row.id,updated_at=now() where id=a.id returning * into a;
  else
   update korlix_social_album_photos set deleted=true where id=photo_row.id;
   update korlix_social_albums set cover_id=case when cover_id=photo_row.id then null else cover_id end,updated_at=now() where id=a.id;
   return jsonb_build_object('ok',true,'remove_paths',jsonb_build_array(photo_row.photo_path));
  end if;
 else raise exception 'Album action unavailable.';
 end if;
 return jsonb_build_object('album',korlix_social_album_card(a));
end $$;
revoke all on function public.korlix_social_album_card(public.korlix_social_albums),public.korlix_social_albums_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_album_card(public.korlix_social_albums),public.korlix_social_albums_v1(uuid,text,jsonb) to service_role;
