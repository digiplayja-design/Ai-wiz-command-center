-- Voice-note replies use the existing private attachment bucket. Browser roles
-- remain denied; the authenticated backend is the only caller of these RPCs.
alter table public.korlix_social_attachments
 add column topic_id uuid references public.korlix_social_topics(id) on delete set null,
 add column reply_id uuid unique references public.korlix_social_replies(id) on delete set null,
 add constraint korlix_social_attachment_one_destination check(num_nonnulls(peer,group_id,topic_id)<=1),
 add constraint korlix_social_attachment_one_message check(num_nonnulls(direct_message,group_message,reply_id)<=1),
 add constraint korlix_social_wall_voice_only check(topic_id is null or kind='voice');
create index korlix_social_attachments_topic on public.korlix_social_attachments(topic_id);

create function public.korlix_social_wall_voice_access(p_viewer uuid,p_topic uuid,p_reply uuid default null,p_write boolean default false) returns void
language plpgsql stable security invoker set search_path='' as $$
declare t public.korlix_social_topics;
begin
 if not exists(select 1 from public.korlix_social_profiles where id=p_viewer and not suspended) then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 select * into t from public.korlix_social_topics where id=p_topic and surface='wall' and not deleted;
 if t.id is null or public.korlix_social_blocked(p_viewer,t.author) or not exists(select 1 from public.korlix_social_profiles where id=t.author and not suspended) then raise exception 'Wall post unavailable.' using errcode='P0002'; end if;
 if p_write and t.locked then raise exception 'This wall post is locked for new replies.' using errcode='42501'; end if;
 if p_reply is not null and not exists(select 1 from public.korlix_social_replies r join public.korlix_social_profiles p on p.id=r.author where r.id=p_reply and r.topic_id=t.id and not r.deleted and not p.suspended and not public.korlix_social_blocked(p_viewer,r.author)) then raise exception 'Voice reply unavailable.' using errcode='P0002'; end if;
end $$;

create or replace function public.korlix_social_attachment_card(a public.korlix_social_attachments) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',a.id,'kind',a.kind,'filename',a.filename,'content_type',a.content_type,
 'size_bytes',a.size_bytes,'duration_ms',a.duration_ms,'object_path',a.object_path)
 ||case when a.topic_id is not null then jsonb_build_object('scope','wall') else '{}'::jsonb end;
$$;
create or replace function public.korlix_social_attachment_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 me public.korlix_social_profiles; a public.korlix_social_attachments;
 aid uuid; target uuid; gid uuid; tid uuid; result jsonb; ext text;
begin
 select * into me from public.korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action not in ('access','prepare','ready','link','discard') then raise exception 'Attachment action not found.' using errcode='P0002'; end if;
 if p_action in ('access','prepare') then
  target:=(p_data->>'peer')::uuid; gid:=(p_data->>'group')::uuid; tid:=(p_data->>'topic')::uuid;
  if num_nonnulls(target,gid,tid)<>1 then raise exception 'Choose one conversation or wall post.'; end if;
  if p_action='prepare' then perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0)); end if;
  if tid is not null then
   perform public.korlix_social_wall_voice_access(me.id,tid,null,true);
   if p_action='prepare' and (p_data->>'kind' is distinct from 'voice' or p_data->>'content_type' is distinct from 'audio/wav' or p_data->>'extension' is distinct from 'wav' or coalesce((p_data->>'duration_ms')::integer,0) not between 300 and 180000) then raise exception 'Wall replies support recorded voice notes up to 3 minutes.'; end if;
  elsif gid is not null then perform public.korlix_social_groups_v1(p_actor,'group_messages',jsonb_build_object('group',gid));
  else perform public.korlix_social_chat_v1(p_actor,'messages',jsonb_build_object('peer',target)); end if;
  if p_action='access' then return jsonb_build_object('ok',true); end if;
  aid:=(p_data->>'id')::uuid; ext:=p_data->>'extension';
  if aid is null or ext is null or ext!~'^[a-z0-9]{1,8}$' then raise exception 'Invalid attachment request.'; end if;
  select * into a from public.korlix_social_attachments where id=aid;
  if found then
   if a.owner is distinct from me.id or a.peer is distinct from target or a.group_id is distinct from gid or a.topic_id is distinct from tid or a.content_type is distinct from p_data->>'content_type' or a.size_bytes is distinct from (p_data->>'size_bytes')::integer or a.duration_ms is distinct from (p_data->>'duration_ms')::integer or a.checksum is distinct from p_data->>'checksum' or a.filename is distinct from p_data->>'filename' or a.kind is distinct from p_data->>'kind' or a.purged_at is not null or (a.state<>'attached' and a.expires_at<=now()) then raise exception 'Choose a new attachment request.' using errcode='23505'; end if;
   return jsonb_build_object('attachment',public.korlix_social_attachment_card(a),'state',a.state);
  end if;
  perform public.korlix_social_limit(p_actor,'attachment-minute',20,60);
  perform public.korlix_social_limit(p_actor,'attachment-day',100,86400);
  if coalesce((select sum(size_bytes) from public.korlix_social_attachments where owner=me.id and purged_at is null),0)+(p_data->>'size_bytes')::bigint>262144000 then raise exception 'Your shared attachments have reached 250 MB. Remove old attachments before uploading more.' using errcode='54000'; end if;
  insert into public.korlix_social_attachments(id,owner,peer,group_id,topic_id,kind,filename,content_type,size_bytes,duration_ms,object_path,checksum)
   values(aid,me.id,target,gid,tid,p_data->>'kind',p_data->>'filename',p_data->>'content_type',(p_data->>'size_bytes')::integer,(p_data->>'duration_ms')::integer,me.id::text||'/'||aid::text||'.'||ext,p_data->>'checksum') returning * into a;
  return jsonb_build_object('attachment',public.korlix_social_attachment_card(a),'state',a.state);
 end if;
 if p_action in ('ready','discard') then perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0)); end if;
 select * into a from public.korlix_social_attachments where id=(p_data->>'id')::uuid;
 if a.id is null or a.purged_at is not null then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
 if p_action in ('ready','discard') then
  if a.owner is distinct from me.id then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
  if p_action='discard' then
   if a.state='attached' then raise exception 'Remove the message to remove a shared attachment.'; end if;
   update public.korlix_social_attachments set purged_at=now() where id=a.id;
   return jsonb_build_object('ok',true);
  end if;
  if a.topic_id is not null then perform public.korlix_social_wall_voice_access(me.id,a.topic_id,a.reply_id,true); end if;
  if a.expires_at<=now() and a.state<>'attached' then raise exception 'Attachment expired. Attach it again.'; end if;
  update public.korlix_social_attachments set state=case when state='uploading' then 'ready' else state end where id=a.id returning * into a;
 elsif p_action='link' then
  if a.state='attached' then
   if a.reply_id is not null and a.topic_id is not null then
    perform public.korlix_social_wall_voice_access(me.id,a.topic_id,a.reply_id,false);
    return jsonb_build_object('attachment',public.korlix_social_attachment_card(a));
   elsif a.group_message is not null then result:=public.korlix_social_groups_v1(p_actor,'group_message',jsonb_build_object('group',a.group_id,'id',a.group_message));
   elsif a.direct_message is not null then result:=public.korlix_social_chat_v1(p_actor,'message',jsonb_build_object('peer',case when me.id=a.owner then a.peer else a.owner end,'id',a.direct_message));
   else raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
   if coalesce((result->'message'->>'deleted')::boolean,true) then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
  elsif a.owner is distinct from me.id or a.state<>'ready' or a.expires_at<=now() then raise exception 'Attachment unavailable.' using errcode='P0002';
  elsif a.topic_id is not null then perform public.korlix_social_wall_voice_access(me.id,a.topic_id,null,true); end if;
 end if;
 return jsonb_build_object('attachment',public.korlix_social_attachment_card(a));
end $$;

create or replace function public.korlix_social_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; peer korlix_social_profiles; conn korlix_social_connections;
 topic korlix_social_topics; msg korlix_social_messages; reply korlix_social_replies; report korlix_social_reports;
 voice public.korlix_social_attachments; aid uuid; existing_aid uuid;
 target uuid; request_id uuid; result jsonb; items jsonb; card jsonb; snap jsonb;
 skip integer:=greatest(0,least(50000,coalesce((p_data->>'offset')::integer,0)));
 query text:=left(trim(coalesce(p_data->>'q','')),100);
 title_text text; body_text text; handle_text text; action_text text; kind text; mod boolean;
 details jsonb; visibility jsonb; k text; value_text text; max_length integer; feed text; requested_surface text;
begin
 if p_actor is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
 select * into me from korlix_social_profiles where user_id=p_actor;
 select exists(select 1 from korlix_social_moderators where user_id=p_actor) into mod;
 if me.suspended then raise exception 'Your Social access is suspended. Contact KORLIX support.' using errcode='42501'; end if;
 if p_action='bootstrap' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.position),'[]') into items from korlix_social_categories c;
  return jsonb_build_object('profile',case when me.id is null then null else korlix_social_card(me,me.id)||jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online) end,'categories',items,'moderator',mod);
 end if;
 -- Serialize writes for rate limits; pair locks below also protect concurrent send/block/revoke.
 if p_action not in ('members','member','connections','messages','topics','wall','topic','blocks','reports') then
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 end if;
 if p_action='save_profile' then
  select * into me from korlix_social_profiles where user_id=p_actor for update;
  if char_length(trim(coalesce(p_data->>'profession',me.profession,'')))>100 then raise exception 'Keep your profession within 100 characters.'; end if;
  details:=coalesce(me.profile_details,'{}'); visibility:=coalesce(me.profile_visibility,'{}');
  if p_data ? 'profile_visibility' then
   if jsonb_typeof(p_data->'profile_visibility') is distinct from 'object' then raise exception 'Choose valid profile privacy settings.'; end if;
   for k,value_text in select key,value from jsonb_each_text(p_data->'profile_visibility') loop
    if k not in ('status_caption','home_country','city','phone_number','favorite_color','profession','current_job','favorite_food','marital_status','income_level') or value_text is null or value_text not in ('members','connections','private') then raise exception 'Choose valid profile privacy settings.'; end if;
    visibility:=visibility||jsonb_build_object(k,value_text);
   end loop;
  end if;
  for k,max_length in select * from (values ('status_caption',160),('home_country',80),('city',100),('phone_number',40),('favorite_color',60),('profession',100),('current_job',120),('favorite_food',100),('marital_status',60),('income_level',100)) bounds(field,max_chars) loop
   if p_data ? k then
    if jsonb_typeof(p_data->k) is distinct from 'string' then raise exception 'Profile details must be text.'; end if;
    value_text:=trim(p_data->>k);
    if char_length(value_text)>max_length then raise exception 'Keep % within % characters.',replace(k,'_',' '),max_length; end if;
    if k<>'profession' then details:=details||jsonb_build_object(k,value_text); end if;
   end if;
  end loop;
  if me.id is null and p_data->'accepted_rules' is distinct from 'true'::jsonb then raise exception 'Accept the community rules to join.'; end if;
  handle_text:=lower(trim(coalesce(p_data->>'handle',''))); title_text:=trim(coalesce(p_data->>'name','')); body_text:=trim(coalesce(p_data->>'bio',''));
  if handle_text!~'^[a-z0-9_]{3,24}$' or char_length(title_text) not between 1 and 60 or char_length(body_text)>300 then raise exception 'Use a 3–24 character handle, a name up to 60 characters and a bio up to 300 characters.'; end if;
  if coalesce(p_data->>'color','') not in ('cyan','violet','coral','mint','gold','blue') or jsonb_typeof(p_data->'discoverable') is distinct from 'boolean' or jsonb_typeof(p_data->'show_online') is distinct from 'boolean' then raise exception 'Choose your profile visibility settings.'; end if;
  perform korlix_social_limit(p_actor,'profile',30,3600);
  insert into korlix_social_profiles(user_id,handle,name,bio,profession,color,discoverable,show_online) values(p_actor,handle_text,title_text,body_text,trim(coalesce(p_data->>'profession',me.profession,'')),p_data->>'color',(p_data->>'discoverable')::boolean,(p_data->>'show_online')::boolean)
  on conflict(user_id) do update set handle=excluded.handle,name=excluded.name,bio=excluded.bio,profession=excluded.profession,color=excluded.color,discoverable=excluded.discoverable,show_online=excluded.show_online,last_seen=case when excluded.show_online then korlix_social_profiles.last_seen else null end,updated_at=now() returning * into me;
  update korlix_social_profiles set profile_details=details,profile_visibility=visibility where id=me.id returning * into me;
  return jsonb_build_object('profile',korlix_social_card(me,me.id)||jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online));
 end if;
 if me.id is null then raise exception 'Create your Social profile to continue.' using errcode='42501'; end if;
 if p_action='member' then
  target:=(p_data->>'peer')::uuid;
  select * into peer from korlix_social_profiles where id=target;
  select * into conn from korlix_social_connections where least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target);
  if peer.id is null or peer.suspended or korlix_social_blocked(me.id,target) or
   (target<>me.id and not peer.discoverable and coalesce(conn.state,'')<>'accepted') then
   raise exception 'This profile is unavailable.' using errcode='P0002';
  end if;
  return jsonb_build_object('profile',korlix_social_card(peer,me.id)||jsonb_build_object('connection',conn.state,'incoming',coalesce(conn.recipient=me.id,false))||case when target=me.id then jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online) else '{}'::jsonb end);
 end if;
 if p_action='wall' then
  feed:=coalesce(p_data->>'feed','following');
  if feed not in ('following','explore','mine') then raise exception 'Choose a wall feed.'; end if;
  target:=nullif(p_data->>'member','')::uuid;
  if target is not null then
   select * into peer from korlix_social_profiles where id=target;
   if peer.id is null or peer.suspended or korlix_social_blocked(me.id,target) or
    (target<>me.id and not peer.discoverable and not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target))) then
    raise exception 'This profile is unavailable.' using errcode='P0002';
   end if;
  end if;
  select coalesce(jsonb_agg(x.card order by x.created_at desc,x.id),'[]') into items from (
   select t.created_at,t.id,to_jsonb(t)-'author'-'deleted'||jsonb_build_object('author',korlix_social_card(p,me.id),
    'reply_count',(select count(*) from korlix_social_replies r join korlix_social_profiles rp on rp.id=r.author where r.topic_id=t.id and not r.deleted and not rp.suspended and not korlix_social_blocked(me.id,r.author))) card
   from korlix_social_topics t join korlix_social_profiles p on p.id=t.author
   where t.surface='wall' and not t.deleted and not p.suspended and not korlix_social_blocked(me.id,t.author)
   and (target is null or t.author=target)
   and (target is not null or feed='explore' or t.author=me.id or (feed='following' and exists(select 1 from korlix_social_connections c where c.state='accepted' and least(c.requester,c.recipient)=least(me.id,t.author) and greatest(c.requester,c.recipient)=greatest(me.id,t.author))))
   and (query='' or position(lower(query) in lower(t.title||' '||t.body))>0)
   order by t.created_at desc,t.id limit 21 offset skip
  )x;
  return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='presence' then
  update korlix_social_profiles set last_seen=case when p_data->'active'='true'::jsonb and show_online then now() else null end where id=me.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='members' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select korlix_social_card(p,me.id)||jsonb_build_object('connection',c.state,'incoming',c.recipient=me.id) card
   from korlix_social_profiles p left join korlix_social_connections c on least(c.requester,c.recipient)=least(me.id,p.id) and greatest(c.requester,c.recipient)=greatest(me.id,p.id)
   where p.id<>me.id and p.discoverable and not p.suspended and not korlix_social_blocked(me.id,p.id)
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name||' '||coalesce(korlix_social_card(p,me.id)->>'profession','')))>0)
   and (p_data->>'online' is distinct from 'true' or (p.show_online and p.last_seen>now()-interval '90 seconds'))
   order by p.name,p.id limit 41 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='connections' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select korlix_social_card(p,me.id)||jsonb_build_object('connection',c.state,'incoming',c.recipient=me.id,
    'unread',(select count(*) from korlix_social_messages m where m.sender=p.id and m.recipient=me.id and m.read_at is null and not m.deleted),
    'last_message',(select case when m.deleted then 'Message removed' else left(m.body,100) end from korlix_social_messages m where least(m.sender,m.recipient)=least(me.id,p.id) and greatest(m.sender,m.recipient)=greatest(me.id,p.id) order by m.seq desc limit 1)) card
   from korlix_social_connections c join korlix_social_profiles p on p.id=case when c.requester=me.id then c.recipient else c.requester end
   where (c.requester=me.id or c.recipient=me.id) and not p.suspended and not korlix_social_blocked(me.id,p.id)
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name||' '||coalesce(korlix_social_card(p,me.id)->>'profession','')))>0)
   and (coalesce(p_data->>'state','all')='all' or c.state=p_data->>'state')
   order by c.created_at desc,c.id limit 41 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='blocks' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (select korlix_social_card(p,me.id) card from korlix_social_blocks b join korlix_social_profiles p on p.id=b.blocked where b.blocker=me.id order by b.created_at desc,b.blocked limit 41 offset skip)x;
  return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action in ('request','accept','decline','remove','block','unblock','messages','send','read') then
  target:=(p_data->>'peer')::uuid;
  if target is null or target=me.id then raise exception 'Choose another member.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
  select * into peer from korlix_social_profiles where id=target;
  if peer.id is null then raise exception 'Member not found.' using errcode='P0002'; end if;
  select * into conn from korlix_social_connections where least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target);
  if p_action='block' then
   insert into korlix_social_blocks(blocker,blocked)values(me.id,target)on conflict do nothing;
   delete from korlix_social_connections where id=conn.id;
   return jsonb_build_object('ok',true);
  elsif p_action='unblock' then
   delete from korlix_social_blocks where blocker=me.id and blocked=target;
   return jsonb_build_object('ok',true);
  end if;
  if peer.suspended or korlix_social_blocked(me.id,target) then raise exception 'This connection is unavailable.' using errcode='42501'; end if;
  if p_action='request' then
   if not peer.discoverable and conn.id is null then raise exception 'This member is not accepting new requests.' using errcode='42501'; end if;
   if conn.id is not null then return jsonb_build_object('ok',true,'state',conn.state); end if;
   perform korlix_social_limit(p_actor,'request',20,3600);
   insert into korlix_social_connections(requester,recipient)values(me.id,target);
   return jsonb_build_object('ok',true,'state','pending');
  end if;
  if conn.id is null then raise exception 'An accepted follow request is needed to talk.' using errcode='42501'; end if;
  if p_action in ('accept','decline') then
   if conn.recipient<>me.id or conn.state<>'pending' then raise exception 'Only the recipient can respond to a pending request.' using errcode='42501'; end if;
   if p_action='accept' then update korlix_social_connections set state='accepted',accepted_at=now() where id=conn.id;
   else delete from korlix_social_connections where id=conn.id; end if;
   return jsonb_build_object('ok',true);
  elsif p_action='remove' then
   delete from korlix_social_connections where id=conn.id; return jsonb_build_object('ok',true);
  end if;
  if conn.state<>'accepted' then raise exception 'Wait for the follow request to be accepted before messaging.' using errcode='42501'; end if;
  if p_action='messages' then
   select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
    select m.seq,jsonb_build_object('id',m.id,'seq',m.seq,'sender',m.sender,'body',m.body,'created_at',m.created_at,'read_at',m.read_at,'deleted',m.deleted) card
    from korlix_social_messages m where least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)
    and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
    order by m.seq desc limit 51
   )x; return jsonb_build_object('items',items,'peer',korlix_social_card(peer,me.id));
  elsif p_action='read' then
   update korlix_social_messages set read_at=now() where sender=target and recipient=me.id and read_at is null and seq<=coalesce((p_data->>'through')::bigint,0);
   return jsonb_build_object('ok',true);
  elsif p_action='send' then
   request_id:=(p_data->>'id')::uuid; body_text:=trim(coalesce(p_data->>'body',''));
   if request_id is null or char_length(body_text) not between 1 and 2000 then raise exception 'Write a message between 1 and 2,000 characters.'; end if;
   select * into msg from korlix_social_messages where id=request_id;
   if msg.id is not null then
    if msg.sender<>me.id or msg.recipient<>target then raise exception 'Choose a new message ID.' using errcode='42501'; end if;
    return jsonb_build_object('id',msg.id);
   end if;
   perform korlix_social_limit(p_actor,'message',60,60);
   insert into korlix_social_messages(id,sender,recipient,body)values(request_id,me.id,target,body_text);
   return jsonb_build_object('id',request_id);
  end if;
 end if;
 if p_action='delete_message' then
  update korlix_social_messages set body='',deleted=true where id=(p_data->>'id')::uuid and sender=me.id;
  if not found then raise exception 'Message not found.' using errcode='P0002'; end if;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='topics' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select to_jsonb(t)-'author'-'deleted'||jsonb_build_object('author',korlix_social_card(p,me.id),
    'reply_count',(select count(*) from korlix_social_replies r join korlix_social_profiles rp on rp.id=r.author where r.topic_id=t.id and not r.deleted and not rp.suspended and not korlix_social_blocked(me.id,r.author))) card
   from korlix_social_topics t join korlix_social_profiles p on p.id=t.author
   where t.surface='forum' and not t.deleted and not p.suspended and not korlix_social_blocked(me.id,t.author)
   and (coalesce(p_data->>'category','')='' or t.category=p_data->>'category')
   and (query='' or position(lower(query) in lower(t.title||' '||t.body))>0)
   order by t.activity_at desc,t.id limit 21 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='create_topic' then
  requested_surface:=coalesce(p_data->>'surface','forum');
  if requested_surface not in ('forum','wall') then raise exception 'Choose a valid post type.'; end if;
  if requested_surface='wall' then p_data:=p_data||jsonb_build_object('category','community'); end if;
  request_id:=(p_data->>'id')::uuid; title_text:=trim(coalesce(p_data->>'title','')); body_text:=trim(coalesce(p_data->>'body',''));
  if request_id is null or char_length(title_text)>140 or (requested_surface='forum' and title_text='') or char_length(body_text) not between 1 and 8000 then raise exception 'Add a post up to 8,000 characters and a headline up to 140 characters; forum titles are required.'; end if;
  if not exists(select 1 from korlix_social_categories where id=p_data->>'category') then raise exception 'Choose a forum.'; end if;
  select * into topic from korlix_social_topics where id=request_id;
  if topic.id is not null then
   if topic.author<>me.id then raise exception 'Topic ID already used.' using errcode='42501'; end if;
   if topic.surface<>requested_surface or (requested_surface='wall' and (topic.deleted or topic.title<>title_text or topic.body<>body_text)) then raise exception 'This post ID was already used for different content.' using errcode='23505'; end if;
   return jsonb_build_object('id',topic.id);
  end if;
  perform korlix_social_limit(p_actor,'topic',10,3600);
  insert into korlix_social_topics(id,author,category,title,body,surface)values(request_id,me.id,p_data->>'category',title_text,body_text,requested_surface);
  return jsonb_build_object('id',request_id);
 end if;
 if p_action in ('topic','edit_topic','delete_topic','reply') then
  target:=(p_data->>'id')::uuid;
  select * into topic from korlix_social_topics where id=target and not deleted for update;
  if topic.id is null or korlix_social_blocked(me.id,topic.author) or exists(select 1 from korlix_social_profiles where id=topic.author and suspended) then raise exception 'Topic not found.' using errcode='P0002'; end if;
  if p_action='topic' then
   select korlix_social_card(p,me.id) into card from korlix_social_profiles p where p.id=topic.author;
   select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
    select r.seq,to_jsonb(r)-'author'-'deleted'||jsonb_build_object('author',korlix_social_card(p,me.id),'attachment',(select public.korlix_social_attachment_card(a) from public.korlix_social_attachments a where a.reply_id=r.id and a.topic_id=r.topic_id and a.state='attached' and a.purged_at is null)) card
    from korlix_social_replies r join korlix_social_profiles p on p.id=r.author
    where r.topic_id=topic.id and not r.deleted and not p.suspended and not korlix_social_blocked(me.id,r.author) and r.seq>coalesce((p_data->>'after')::bigint,0)
    order by r.seq limit 41
   )x; return jsonb_build_object('topic',to_jsonb(topic)-'author'-'deleted'||jsonb_build_object('author',card),'items',items);
  end if;
  if p_action in ('edit_topic','delete_topic') then
   if topic.author<>me.id then raise exception 'You can only change your own topics.' using errcode='42501'; end if;
   if p_action='delete_topic' then update korlix_social_topics set deleted=true,body='',title='Removed topic',updated_at=now() where id=topic.id;
   else
    title_text:=trim(coalesce(p_data->>'title','')); body_text:=trim(coalesce(p_data->>'body',''));
    if topic.locked then raise exception 'This topic is locked.' using errcode='42501'; end if;
    if char_length(title_text)>140 or (topic.surface='forum' and title_text='') or char_length(body_text) not between 1 and 8000 then raise exception 'Check the title and post length.'; end if;
    update korlix_social_topics set title=title_text,body=body_text,updated_at=now() where id=topic.id;
   end if; return jsonb_build_object('ok',true);
  end if;
  if topic.locked then raise exception 'This topic is locked for new replies.' using errcode='42501'; end if;
  request_id:=(p_data->>'reply_id')::uuid; body_text:=trim(coalesce(p_data->>'body','')); aid:=(p_data->>'attachment_id')::uuid;
  if aid is not null then
   if topic.surface<>'wall' then raise exception 'Voice replies are available on wall posts.'; end if;
   select * into voice from public.korlix_social_attachments where id=aid for update;
   if voice.id is null or voice.owner is distinct from me.id or voice.topic_id is distinct from topic.id or voice.kind<>'voice'
    or voice.peer is not null or voice.group_id is not null or voice.direct_message is not null or voice.group_message is not null
    or voice.purged_at is not null or voice.state='uploading'
    or (voice.state='attached' and voice.reply_id is distinct from request_id)
    or (voice.state<>'attached' and (voice.expires_at<=now() or voice.reply_id is not null))
   then raise exception 'This voice note is unavailable for this wall post. Record it again.' using errcode='42501'; end if;
  end if;
  if request_id is null or char_length(body_text)>4000 or (body_text='' and aid is null) then raise exception 'Write a reply or record a voice note, with a caption up to 4,000 characters.'; end if;
  select * into reply from korlix_social_replies where id=request_id;
  if reply.id is not null then
   if reply.author<>me.id or reply.topic_id<>topic.id then raise exception 'Reply ID already used.' using errcode='42501'; end if;
   select id into existing_aid from public.korlix_social_attachments where reply_id=request_id;
   if topic.surface='wall' and (reply.deleted or reply.body is distinct from body_text or existing_aid is distinct from aid) then raise exception 'This reply request already has different content. Use a new reply.' using errcode='23505'; end if;
   return jsonb_build_object('id',reply.id);
  end if;
  perform korlix_social_limit(p_actor,'reply',60,3600);
  insert into korlix_social_replies(id,topic_id,author,body)values(request_id,topic.id,me.id,body_text);
  if aid is not null then update public.korlix_social_attachments set state='attached',reply_id=request_id where id=aid; end if;
  update korlix_social_topics set activity_at=now() where id=topic.id;
  return jsonb_build_object('id',request_id);
 end if;
 if p_action in ('edit_reply','delete_reply') then
  select * into reply from korlix_social_replies where id=(p_data->>'id')::uuid and author=me.id and not deleted;
  if reply.id is null then raise exception 'Reply not found.' using errcode='P0002'; end if;
  select * into topic from korlix_social_topics where id=reply.topic_id for update;
  if p_action='delete_reply' then update korlix_social_replies set body='',deleted=true,updated_at=now() where id=reply.id;
  else
   body_text:=trim(coalesce(p_data->>'body',''));
   if topic.deleted or topic.locked then raise exception 'This topic is closed.' using errcode='42501'; end if;
   if topic.surface='wall' then perform public.korlix_social_wall_voice_access(me.id,topic.id,reply.id,true); end if;
   if char_length(body_text)>4000 or (body_text='' and not exists(select 1 from public.korlix_social_attachments a where a.reply_id=reply.id and a.topic_id=topic.id and a.kind='voice' and a.state='attached' and a.purged_at is null)) then raise exception 'Check the reply length.'; end if;
   update korlix_social_replies set body=body_text,updated_at=now() where id=reply.id;
  end if; return jsonb_build_object('ok',true);
 end if;
 if p_action='report' then
  target:=(p_data->>'target')::uuid; request_id:=(p_data->>'id')::uuid; kind:=p_data->>'kind'; body_text:=trim(coalesce(p_data->>'reason',''));
  if request_id is null or char_length(body_text) not between 1 and 1000 then raise exception 'Tell us why you are reporting this (up to 1,000 characters).'; end if;
  if kind='member' then select korlix_social_card(p) into snap from korlix_social_profiles p where p.id=target and p.id<>me.id and not p.suspended and (p.discoverable or exists(select 1 from korlix_social_connections c where least(c.requester,c.recipient)=least(me.id,p.id) and greatest(c.requester,c.recipient)=greatest(me.id,p.id)));
  elsif kind='message' then select jsonb_build_object('id',m.id,'author',m.sender,'body',m.body,'created_at',m.created_at) into snap from korlix_social_messages m where m.id=target and m.recipient=me.id and not m.deleted;
  elsif kind='topic' then select jsonb_build_object('id',t.id,'author',t.author,'title',t.title,'body',t.body) into snap from korlix_social_topics t where t.id=target and not t.deleted and not korlix_social_blocked(me.id,t.author);
  elsif kind='reply' then select jsonb_build_object('id',r.id,'author',r.author,'topic_id',r.topic_id,
   'body',case when r.body='' and a.id is not null then 'Voice note' else r.body end,
   'attachment',case when a.id is null then null else jsonb_build_object('id',a.id,'kind',a.kind,'scope','wall','duration_ms',a.duration_ms,'filename',a.filename) end)
   into snap from korlix_social_replies r join korlix_social_topics t on t.id=r.topic_id
   left join public.korlix_social_attachments a on a.reply_id=r.id and a.topic_id=t.id and a.state='attached' and a.purged_at is null
   where r.id=target and not r.deleted and not t.deleted and not korlix_social_blocked(me.id,r.author) and not korlix_social_blocked(me.id,t.author);
  end if;
  if snap is null then raise exception 'This content is unavailable for reporting.' using errcode='P0002'; end if;
  if exists(select 1 from korlix_social_reports where id=request_id and reporter=me.id) then return jsonb_build_object('ok',true); end if;
  perform korlix_social_limit(p_actor,'report',20,86400);
  insert into korlix_social_reports(id,reporter,kind,target_id,reason,snapshot)values(request_id,me.id,kind,target,body_text,snap);
  return jsonb_build_object('ok',true);
 end if;
 if p_action in ('reports','moderate') then
  if not mod then raise exception 'Moderator access required.' using errcode='42501'; end if;
  if p_action='reports' then
   select coalesce(jsonb_agg(x.item),'[]') into items from(select to_jsonb(r) item from korlix_social_reports r where state='open' order by created_at,id limit 41 offset skip)x;
   return jsonb_build_object('items',items,'offset',skip);
  end if;
  select * into report from korlix_social_reports where id=(p_data->>'id')::uuid for update;
  if report.id is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  if report.state<>'open' then raise exception 'This report was already resolved. Refresh the queue.'; end if;
  action_text:=p_data->>'decision';
  if action_text='remove' and report.kind='topic' then update korlix_social_topics set deleted=true,body='',title='Removed topic' where id=report.target_id;
  elsif action_text='remove' and report.kind='reply' then update korlix_social_replies set deleted=true,body='' where id=report.target_id;
  elsif action_text='remove' and report.kind='message' then update korlix_social_messages set deleted=true,body='' where id=report.target_id;
  elsif action_text='lock' and report.kind='topic' then update korlix_social_topics set locked=true where id=report.target_id;
  elsif action_text='suspend' and report.kind='member' then update korlix_social_profiles set suspended=true,last_seen=null where id=report.target_id and id<>me.id;
  elsif action_text<>'resolve' then raise exception 'Choose an available moderation action.';
  end if;
  update korlix_social_reports set state='resolved',resolved_at=now(),resolved_by=p_actor,decision=action_text where id=report.id;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Social action not found.' using errcode='P0002';
end $$;

-- Soft removal and moderation deny new playback links immediately. Hard deletes also
-- mark the storage object before FK references are cleared for later cleanup.
create function public.korlix_social_wall_voice_removed() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='DELETE' then
  if tg_table_name='korlix_social_topics' then update public.korlix_social_attachments set purged_at=coalesce(purged_at,now()),topic_id=null where topic_id=old.id;
  else update public.korlix_social_attachments set purged_at=coalesce(purged_at,now()) where reply_id=old.id; end if;
  return old;
 end if;
 if new.deleted and not old.deleted then
  if tg_table_name='korlix_social_topics' then update public.korlix_social_attachments set purged_at=coalesce(purged_at,now()) where topic_id=new.id;
  else update public.korlix_social_attachments set purged_at=coalesce(purged_at,now()) where reply_id=new.id; end if;
 end if;
 return new;
end $$;
create trigger korlix_social_wall_voice_topic_removed after update of deleted on public.korlix_social_topics for each row execute function public.korlix_social_wall_voice_removed();
create trigger korlix_social_wall_voice_reply_removed after update of deleted on public.korlix_social_replies for each row execute function public.korlix_social_wall_voice_removed();
create trigger korlix_social_wall_voice_topic_deleted before delete on public.korlix_social_topics for each row execute function public.korlix_social_wall_voice_removed();
create trigger korlix_social_wall_voice_reply_deleted before delete on public.korlix_social_replies for each row execute function public.korlix_social_wall_voice_removed();

create or replace function public.korlix_social_attachment_cleanup(p_ids uuid[] default null) returns jsonb
language plpgsql security invoker set search_path='' as $$ begin
 if p_ids is not null then
  delete from public.korlix_social_attachments where id=any(p_ids) and (purged_at is not null or owner is null or (state<>'attached' and expires_at<=now()) or (state='attached' and direct_message is null and group_message is null and reply_id is null));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'path',object_path)) from (
  select id,object_path from public.korlix_social_attachments where purged_at is not null or owner is null or (state<>'attached' and expires_at<=now()) or (state='attached' and direct_message is null and group_message is null and reply_id is null) order by created_at limit 100
 )x),'[]'::jsonb);
end $$;
revoke all on function public.korlix_social_wall_voice_access(uuid,uuid,uuid,boolean),public.korlix_social_wall_voice_removed(),public.korlix_social_attachment_card(public.korlix_social_attachments),public.korlix_social_attachment_v1(uuid,text,jsonb),public.korlix_social_attachment_cleanup(uuid[]),public.korlix_social_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_wall_voice_access(uuid,uuid,uuid,boolean),public.korlix_social_wall_voice_removed(),public.korlix_social_attachment_card(public.korlix_social_attachments),public.korlix_social_attachment_v1(uuid,text,jsonb),public.korlix_social_attachment_cleanup(uuid[]),public.korlix_social_v1(uuid,text,jsonb) to service_role;
