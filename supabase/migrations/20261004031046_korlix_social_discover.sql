-- Discover data and media are service-only. Every viewer is a verified, active
-- Social member; public videos mean public to eligible Social members.
create table public.korlix_social_videos (
 id uuid primary key, seq bigint generated always as identity unique,
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 caption text not null default '' check(char_length(caption)<=500),
 checksum text not null check(checksum ~ '^[a-f0-9]{64}$'),
 state text not null default 'uploading' check(state in('uploading','ready','published','deleted')),
 size_bytes integer not null default 52428800 check(size_bytes between 1 and 53477376),
 duration_ms integer check(duration_ms between 500 and 60000),
 created_at timestamptz not null default now(), published_at timestamptz
);
create index korlix_social_videos_feed on public.korlix_social_videos(seq desc) where state='published';
create index korlix_social_videos_owner on public.korlix_social_videos(owner,seq desc);
create table public.korlix_social_discover_news (
 id uuid primary key, title text not null check(char_length(title) between 1 and 120),
 summary text not null check(char_length(summary) between 1 and 460),
 category text not null check(category in('world','jamaica','business','technology','sports','entertainment')),
 url text not null unique check(url like 'https://%'), source text not null,
 published_at timestamptz not null, checked_at timestamptz not null default now(),
 deleted boolean not null default false
);
create index korlix_social_discover_news_date on public.korlix_social_discover_news(published_at desc,id) where not deleted;
create table public.korlix_social_discover_edition (
 id boolean primary key default true check(id), refreshed_at timestamptz,
 next_attempt timestamptz not null default now(), lease uuid, lease_until timestamptz
);
insert into public.korlix_social_discover_edition(id) values(true);
create table public.korlix_social_discover_marks (
 member uuid not null references public.korlix_social_profiles(id) on delete cascade,
 video uuid references public.korlix_social_videos(id) on delete cascade,
 news uuid references public.korlix_social_discover_news(id) on delete cascade,
 liked boolean not null default false, saved boolean not null default false,
 check(num_nonnulls(video,news)=1), unique(member,video),unique(member,news)
);
create index korlix_social_discover_marks_video on public.korlix_social_discover_marks(video) where liked;
create index korlix_social_discover_marks_news on public.korlix_social_discover_marks(news);
create table public.korlix_social_discover_gc(path text primary key,created_at timestamptz not null default now());
do $$ declare t text; begin
 foreach t in array array['korlix_social_videos','korlix_social_discover_news','korlix_social_discover_edition','korlix_social_discover_marks','korlix_social_discover_gc'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;
revoke all on sequence public.korlix_social_videos_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_social_videos_seq_seq to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-social-videos','korlix-social-videos',false,52428800,array['video/mp4','image/jpeg']);
create policy korlix_social_videos_browser_deny on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'korlix-social-videos') with check(bucket_id<>'korlix-social-videos');
alter table public.korlix_social_reports drop constraint korlix_social_reports_kind_check;
alter table public.korlix_social_reports add constraint korlix_social_reports_kind_check check(kind in('member','topic','reply','message','group_message','video','news'));
create index korlix_social_reports_discover_target on public.korlix_social_reports(reporter,kind,target_id) where kind in('video','news');

create function public.korlix_social_video_gc() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if tg_op='DELETE' or (new.state='deleted' and old.state<>'deleted') then
  insert into korlix_social_discover_gc(path) values(old.owner||'/'||old.id||'.mp4'),(old.owner||'/'||old.id||'.jpg') on conflict do nothing;
 end if;
 return null;
end $$;
create trigger korlix_social_video_cleanup after delete or update on public.korlix_social_videos for each row execute function public.korlix_social_video_gc();

create function public.korlix_social_video_card(v public.korlix_social_videos,m uuid) returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',v.id,'seq',v.seq,'caption',v.caption,'state',v.state,'duration_ms',v.duration_ms,
  'created_at',coalesce(v.published_at,v.created_at),'author',(select korlix_social_card(p) from korlix_social_profiles p where p.id=v.owner),
  'thumbnail_path',case when v.state in('ready','published') then v.owner||'/'||v.id||'.jpg' else null end,
  'liked',coalesce((select liked from korlix_social_discover_marks where member=m and video=v.id),false),
  'saved',coalesce((select saved from korlix_social_discover_marks where member=m and video=v.id),false),
  'like_count',(select count(*) from korlix_social_discover_marks where video=v.id and liked));
$$;

create function public.korlix_social_discover_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; v korlix_social_videos; n korlix_social_discover_news; rep korlix_social_reports;
 target uuid; request_id uuid; items jsonb; snap jsonb; content_kind text; caption_text text; before_seq bigint;
 mode text:=coalesce(p_data->>'feed','all'); is_mod boolean;
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 is_mod:=exists(select 1 from korlix_social_moderators where user_id=p_actor);
 if p_action='moderate' then
  if not is_mod then raise exception 'Moderator access required.' using errcode='42501'; end if;
  select * into rep from korlix_social_reports where id=(p_data->>'id')::uuid for update;
  if rep.kind is null or rep.kind not in('video','news') then return korlix_social_groups_v1(p_actor,p_action,p_data); end if;
  if rep.state<>'open' then raise exception 'This report was already resolved.'; end if;
  if p_data->>'decision'='remove' then
   if rep.kind='video' then update korlix_social_videos set state='deleted',caption='' where id=rep.target_id;
   else update korlix_social_discover_news set deleted=true where id=rep.target_id; end if;
  elsif p_data->>'decision' is distinct from 'resolve' then raise exception 'Choose an available moderation action.'; end if;
  update korlix_social_reports set state='resolved',resolved_at=now(),resolved_by=p_actor,decision=p_data->>'decision' where id=rep.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='discover_news' then
  perform korlix_social_limit(p_actor,'discover-read',120,60);
  select coalesce(jsonb_agg(x.card order by x.published_at desc,x.id),'[]') into items from(
   select article.id,article.published_at,to_jsonb(article)-'deleted'||jsonb_build_object('saved',coalesce(m.saved,false),'liked',coalesce(m.liked,false)) card
   from korlix_social_discover_news article left join korlix_social_discover_marks m on m.news=article.id and m.member=me.id
   where not article.deleted and (case when mode='saved' then coalesce(m.saved,false) else article.published_at>now()-interval '3 days' end)
    and not exists(select 1 from korlix_social_reports r where r.reporter=me.id and r.kind='news' and r.target_id=article.id)
   order by article.published_at desc,article.id limit 60)x;
  return jsonb_build_object('items',items,'refreshed_at',(select refreshed_at from korlix_social_discover_edition),
   'refreshing',coalesce((select lease_until>now() from korlix_social_discover_edition),false));
 end if;
 if p_action='discover_videos' then
  perform korlix_social_limit(p_actor,'discover-read',120,60);
  if mode not in('all','following','mine','saved') then raise exception 'Choose a video feed.'; end if;
  before_seq:=coalesce((p_data->>'before')::bigint,9223372036854775807);
  select coalesce(jsonb_agg(x.card order by x.seq desc),'[]') into items from(
   select vid.seq,korlix_social_video_card(vid,me.id) card from korlix_social_videos vid join korlix_social_profiles p on p.id=vid.owner
   where vid.seq<before_seq and not p.suspended and not korlix_social_blocked(me.id,vid.owner)
    and (case when mode='mine' then vid.owner=me.id and vid.state in('ready','published','uploading') else vid.state='published' end)
    and (mode<>'following' or vid.owner=me.id or exists(select 1 from korlix_social_connections c where c.state='accepted' and least(c.requester,c.recipient)=least(me.id,vid.owner) and greatest(c.requester,c.recipient)=greatest(me.id,vid.owner)))
    and (mode<>'saved' or exists(select 1 from korlix_social_discover_marks m where m.member=me.id and m.video=vid.id and m.saved))
    and not exists(select 1 from korlix_social_reports r where r.reporter=me.id and r.kind='video' and r.target_id=vid.id)
   order by vid.seq desc limit 21)x;
  return jsonb_build_object('items',items);
 end if;
 if p_action='upload_access' then perform korlix_social_limit(p_actor,'discover-upload-attempt',30,3600); return jsonb_build_object('ok',true); end if;
 perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 target:=(case when p_action='report' then p_data->>'target' else p_data->>'id' end)::uuid;
 content_kind:=case when p_action='discover_mark' or p_action='report' then p_data->>'kind' else 'video' end;
 if target is null or content_kind is null or content_kind not in('video','news') then raise exception 'Choose Discover content.'; end if;
 if content_kind='video' then select * into v from korlix_social_videos where id=target for update;
 else select * into n from korlix_social_discover_news where id=target; end if;
 if p_action='video_reserve' then
  if v.id is not null then
   if v.owner<>me.id or v.checksum is distinct from p_data->>'checksum' or v.state='deleted' then raise exception 'This upload cannot be reused. Choose the video again.' using errcode='42501'; end if;
  else
   if (select coalesce(sum(size_bytes),0) from korlix_social_videos where owner=me.id and state<>'deleted')>471859200 or
     (select count(*) from korlix_social_videos where owner=me.id and state<>'deleted')>=50 then raise exception 'Your video storage is full. Delete an older video before uploading.' using errcode='54000'; end if;
   perform korlix_social_limit(p_actor,'discover-upload',10,86400);
   insert into korlix_social_videos(id,owner,checksum) values(target,me.id,p_data->>'checksum') returning * into v;
  end if;
  return jsonb_build_object('id',v.id,'state',v.state,'video_path',v.owner||'/'||v.id||'.mp4','thumbnail_path',v.owner||'/'||v.id||'.jpg');
 end if;
 if p_action in('video_ready','discover_publish','discover_delete') then
  if p_action='discover_delete' and v.owner=me.id and v.state='deleted' then return jsonb_build_object('ok',true); end if;
  if v.id is null or v.owner<>me.id or v.state='deleted' then raise exception 'Video not found.' using errcode='P0002'; end if;
  if p_action='video_ready' and v.state='uploading' then
   if (select coalesce(sum(size_bytes),0) from korlix_social_videos where owner=me.id and state<>'deleted' and id<>v.id)+(p_data->>'size_bytes')::integer>524288000 then raise exception 'Your video storage is full.' using errcode='54000'; end if;
   update korlix_social_videos set state='ready',duration_ms=(p_data->>'duration_ms')::integer,size_bytes=(p_data->>'size_bytes')::integer where id=v.id;
  elsif p_action='discover_publish' then
   if v.state not in('ready','published') then raise exception 'Finish uploading before publishing.'; end if;
   if p_data->'accepted_rules' is distinct from 'true'::jsonb then raise exception 'Confirm that you have permission to share this video.'; end if;
   caption_text:=trim(coalesce(p_data->>'caption',''));
   if char_length(caption_text)>500 then raise exception 'Keep the caption within 500 characters.'; end if;
   update korlix_social_videos set state='published',caption=caption_text,published_at=coalesce(published_at,now()) where id=v.id;
  elsif p_action='discover_delete' then update korlix_social_videos set state='deleted',caption='' where id=v.id;
  end if;
  return jsonb_build_object('ok',true,'id',v.id,'state',(select state from korlix_social_videos where id=v.id));
 end if;
 -- Moderator playback is limited to the video in a real report, never a broad bypass.
 if p_action='video_link' and is_mod and p_data->>'report' is not null then
  if v.state in('ready','published') and exists(select 1 from korlix_social_reports where id=(p_data->>'report')::uuid and korlix_social_reports.kind='video' and target_id=v.id) then
   return jsonb_build_object('path',v.owner||'/'||v.id||'.mp4');
  end if;
  raise exception 'Reported video unavailable.' using errcode='P0002';
 end if;
 if content_kind='video' then
  if v.id is null or (v.state<>'published' and not(p_action='video_link' and v.owner=me.id and v.state='ready')) or
   exists(select 1 from korlix_social_profiles where id=v.owner and suspended) or korlix_social_blocked(me.id,v.owner) then raise exception 'Video unavailable.' using errcode='P0002'; end if;
 else if n.id is null or n.deleted then raise exception 'Story unavailable.' using errcode='P0002'; end if; end if;
 if p_action='video_link' then
  perform korlix_social_limit(p_actor,'discover-play',120,60);
  return jsonb_build_object('path',v.owner||'/'||v.id||'.mp4');
 end if;
 if p_action='discover_mark' then
  perform korlix_social_limit(p_actor,'discover-mark',90,60);
  if p_data->>'field' not in('saved','liked') or jsonb_typeof(p_data->'value') is distinct from 'boolean' then raise exception 'Choose save or like.'; end if;
  if content_kind='video' then insert into korlix_social_discover_marks(member,video) values(me.id,target) on conflict(member,video) do nothing;
  else insert into korlix_social_discover_marks(member,news) values(me.id,target) on conflict(member,news) do nothing; end if;
  update korlix_social_discover_marks set saved=case when p_data->>'field'='saved' then (p_data->>'value')::boolean else saved end,
   liked=case when p_data->>'field'='liked' then (p_data->>'value')::boolean else liked end
   where member=me.id and ((content_kind='video' and video=target)or(content_kind='news' and news=target));
  return jsonb_build_object('ok',true);
 end if;
 if p_action='report' then
  request_id:=(p_data->>'id')::uuid;caption_text:=trim(coalesce(p_data->>'reason',''));
  if request_id is null or char_length(caption_text) not between 1 and 1000 then raise exception 'Add a report reason within 1,000 characters.'; end if;
  if exists(select 1 from korlix_social_reports where id=request_id and reporter=me.id and target_id=target and korlix_social_reports.kind=content_kind) then return jsonb_build_object('ok',true); end if;
  perform korlix_social_limit(p_actor,'report',20,86400);
  snap:=case when content_kind='video' then jsonb_build_object('id',v.id,'author',v.owner,'body',v.caption,'duration_ms',v.duration_ms) else to_jsonb(n)-'deleted' end;
  insert into korlix_social_reports(id,reporter,kind,target_id,reason,snapshot) values(request_id,me.id,content_kind,target,caption_text,snap);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Discover action not found.' using errcode='P0002';
end $$;

-- Service worker only; no HTTP route accepts these actions or lease tokens.
create function public.korlix_social_discover_worker(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path=public as $$
declare e korlix_social_discover_edition; token uuid; item jsonb; paths jsonb;
begin
 if p_action='claim' then
  select * into e from korlix_social_discover_edition where id for update;
  if e.next_attempt>now() or e.lease_until>now() then return '{}'::jsonb; end if;
  token:=gen_random_uuid(); update korlix_social_discover_edition set lease=token,lease_until=now()+interval '3 minutes',next_attempt=now()+interval '15 minutes' where id;
  return jsonb_build_object('claim',token);
 elsif p_action in('news_ready','news_failed') then
  select * into e from korlix_social_discover_edition where id for update;
  if e.lease is distinct from (p_data->>'claim')::uuid or e.lease_until<now() then raise exception 'News lease expired.'; end if;
  if p_action='news_ready' then
   if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 12 then raise exception 'Invalid news edition.'; end if;
   for item in select value from jsonb_array_elements(p_data->'items') loop
    insert into korlix_social_discover_news(id,title,summary,category,url,source,published_at) values((item->>'id')::uuid,item->>'title',item->>'summary',item->>'category',item->>'url',item->>'source',(item->>'published_at')::timestamptz)
    on conflict(id) do update set title=excluded.title,summary=excluded.summary,category=excluded.category,checked_at=now();
   end loop;
   update korlix_social_discover_edition set refreshed_at=now(),next_attempt=now()+interval '3 hours',lease=null,lease_until=null where id;
  else update korlix_social_discover_edition set next_attempt=now()+interval '15 minutes',lease=null,lease_until=null where id; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='cleanup' then
  update korlix_social_videos set state='deleted' where state in('uploading','ready') and created_at<now()-interval '1 day';
  delete from korlix_social_discover_news n where n.checked_at<now()-interval '30 days' and not exists(select 1 from korlix_social_discover_marks m where m.news=n.id and m.saved);
  select coalesce(jsonb_agg(path),'[]') into paths from(select path from korlix_social_discover_gc where created_at<now()-interval '10 minutes' order by created_at,path limit 100)x;
  return jsonb_build_object('paths',paths);
 elsif p_action='enqueue' then
  insert into korlix_social_discover_gc(path) select jsonb_array_elements_text(p_data->'paths') on conflict(path) do update set created_at=now();
  return jsonb_build_object('ok',true);
 elsif p_action='cleaned' then
  delete from korlix_social_discover_gc where path in(select jsonb_array_elements_text(p_data->'paths'));
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Worker action not found.';
end $$;
revoke all on function public.korlix_social_video_gc(),public.korlix_social_video_card(public.korlix_social_videos,uuid),public.korlix_social_discover_v1(uuid,text,jsonb),public.korlix_social_discover_worker(text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_video_gc(),public.korlix_social_video_card(public.korlix_social_videos,uuid),public.korlix_social_discover_v1(uuid,text,jsonb),public.korlix_social_discover_worker(text,jsonb) to service_role;
