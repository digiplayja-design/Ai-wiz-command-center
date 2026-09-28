-- Profile fields remain opt-in; original browser-deny RLS and grants remain in force.
alter table public.korlix_social_profiles add column profession text not null default '' check(char_length(profession)<=100);
alter table public.korlix_social_profiles add column avatar_path text;
create or replace function public.korlix_social_card(p public.korlix_social_profiles) returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',p.id,'name',case when p.suspended then 'Unavailable member' else p.name end,
 'handle',case when p.suspended then '' else p.handle end,'bio',case when p.suspended then '' else p.bio end,'color',p.color,
 'profession',case when p.suspended then '' else p.profession end,'avatar_path',case when p.suspended then null else p.avatar_path end,
 'online',coalesce(not p.suspended and p.show_online and p.last_seen>now()-interval '90 seconds',false));
$$;
-- Private assets: only the server uploads verified, resized JPEGs. Signed links expire.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-social-avatars','korlix-social-avatars',false,2097152,array['image/jpeg'])
 on conflict(id) do update set public=false,file_size_limit=2097152,allowed_mime_types=array['image/jpeg'];
create policy korlix_social_avatars_server_only on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id <> 'korlix-social-avatars') with check(bucket_id <> 'korlix-social-avatars');

create or replace function public.korlix_social_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; peer korlix_social_profiles; conn korlix_social_connections;
 topic korlix_social_topics; msg korlix_social_messages; reply korlix_social_replies; report korlix_social_reports;
 target uuid; request_id uuid; result jsonb; items jsonb; card jsonb; snap jsonb;
 skip integer:=greatest(0,least(50000,coalesce((p_data->>'offset')::integer,0)));
 query text:=left(trim(coalesce(p_data->>'q','')),100);
 title_text text; body_text text; handle_text text; action_text text; kind text; mod boolean;
begin
 if p_actor is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
 select * into me from korlix_social_profiles where user_id=p_actor;
 select exists(select 1 from korlix_social_moderators where user_id=p_actor) into mod;
 if me.suspended then raise exception 'Your Social access is suspended. Contact KORLIX support.' using errcode='42501'; end if;
 if p_action='bootstrap' then
  select coalesce(jsonb_agg(to_jsonb(c) order by c.position),'[]') into items from korlix_social_categories c;
  return jsonb_build_object('profile',case when me.id is null then null else korlix_social_card(me)||jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online) end,'categories',items,'moderator',mod);
 end if;
 -- Serialize writes for rate limits; pair locks below also protect concurrent send/block/revoke.
 if p_action not in ('members','connections','messages','topics','topic','blocks','reports') then
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 end if;
 if p_action='save_profile' then
  if char_length(trim(coalesce(p_data->>'profession',me.profession,'')))>100 then raise exception 'Keep your profession within 100 characters.'; end if;
  if me.id is null and p_data->'accepted_rules' is distinct from 'true'::jsonb then raise exception 'Accept the community rules to join.'; end if;
  handle_text:=lower(trim(coalesce(p_data->>'handle',''))); title_text:=trim(coalesce(p_data->>'name','')); body_text:=trim(coalesce(p_data->>'bio',''));
  if handle_text!~'^[a-z0-9_]{3,24}$' or char_length(title_text) not between 1 and 60 or char_length(body_text)>300 then raise exception 'Use a 3–24 character handle, a name up to 60 characters and a bio up to 300 characters.'; end if;
  if coalesce(p_data->>'color','') not in ('cyan','violet','coral','mint','gold','blue') or jsonb_typeof(p_data->'discoverable') is distinct from 'boolean' or jsonb_typeof(p_data->'show_online') is distinct from 'boolean' then raise exception 'Choose your profile visibility settings.'; end if;
  perform korlix_social_limit(p_actor,'profile',30,3600);
  insert into korlix_social_profiles(user_id,handle,name,bio,profession,color,discoverable,show_online) values(p_actor,handle_text,title_text,body_text,trim(coalesce(p_data->>'profession',me.profession,'')),p_data->>'color',(p_data->>'discoverable')::boolean,(p_data->>'show_online')::boolean)
  on conflict(user_id) do update set handle=excluded.handle,name=excluded.name,bio=excluded.bio,profession=excluded.profession,color=excluded.color,discoverable=excluded.discoverable,show_online=excluded.show_online,last_seen=case when excluded.show_online then korlix_social_profiles.last_seen else null end,updated_at=now() returning * into me;
  return jsonb_build_object('profile',korlix_social_card(me)||jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online));
 end if;
 if me.id is null then raise exception 'Create your Social profile to continue.' using errcode='42501'; end if;
 if p_action='presence' then
  update korlix_social_profiles set last_seen=case when p_data->'active'='true'::jsonb and show_online then now() else null end where id=me.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='members' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select korlix_social_card(p)||jsonb_build_object('connection',c.state,'incoming',c.recipient=me.id) card
   from korlix_social_profiles p left join korlix_social_connections c on least(c.requester,c.recipient)=least(me.id,p.id) and greatest(c.requester,c.recipient)=greatest(me.id,p.id)
   where p.id<>me.id and p.discoverable and not p.suspended and not korlix_social_blocked(me.id,p.id)
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name||' '||p.profession))>0)
   and (p_data->>'online' is distinct from 'true' or (p.show_online and p.last_seen>now()-interval '90 seconds'))
   order by p.name,p.id limit 41 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='connections' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (
   select korlix_social_card(p)||jsonb_build_object('connection',c.state,'incoming',c.recipient=me.id,
    'unread',(select count(*) from korlix_social_messages m where m.sender=p.id and m.recipient=me.id and m.read_at is null and not m.deleted),
    'last_message',(select case when m.deleted then 'Message removed' else left(m.body,100) end from korlix_social_messages m where least(m.sender,m.recipient)=least(me.id,p.id) and greatest(m.sender,m.recipient)=greatest(me.id,p.id) order by m.seq desc limit 1)) card
   from korlix_social_connections c join korlix_social_profiles p on p.id=case when c.requester=me.id then c.recipient else c.requester end
   where (c.requester=me.id or c.recipient=me.id) and not p.suspended and not korlix_social_blocked(me.id,p.id)
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name||' '||p.profession))>0)
   and (coalesce(p_data->>'state','all')='all' or c.state=p_data->>'state')
   order by c.created_at desc,c.id limit 41 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='blocks' then
  select coalesce(jsonb_agg(x.card),'[]') into items from (select korlix_social_card(p) card from korlix_social_blocks b join korlix_social_profiles p on p.id=b.blocked where b.blocker=me.id order by b.created_at desc,b.blocked limit 41 offset skip)x;
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
   )x; return jsonb_build_object('items',items,'peer',korlix_social_card(peer));
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
   select to_jsonb(t)-'author'-'deleted'||jsonb_build_object('author',korlix_social_card(p),
    'reply_count',(select count(*) from korlix_social_replies r join korlix_social_profiles rp on rp.id=r.author where r.topic_id=t.id and not r.deleted and not rp.suspended and not korlix_social_blocked(me.id,r.author))) card
   from korlix_social_topics t join korlix_social_profiles p on p.id=t.author
   where not t.deleted and not p.suspended and not korlix_social_blocked(me.id,t.author)
   and (coalesce(p_data->>'category','')='' or t.category=p_data->>'category')
   and (query='' or position(lower(query) in lower(t.title||' '||t.body))>0)
   order by t.activity_at desc,t.id limit 21 offset skip
  )x; return jsonb_build_object('items',items,'offset',skip);
 end if;
 if p_action='create_topic' then
  request_id:=(p_data->>'id')::uuid; title_text:=trim(coalesce(p_data->>'title','')); body_text:=trim(coalesce(p_data->>'body',''));
  if request_id is null or char_length(title_text) not between 1 and 140 or char_length(body_text) not between 1 and 8000 then raise exception 'Add a title (up to 140 characters) and a post (up to 8,000 characters).'; end if;
  if not exists(select 1 from korlix_social_categories where id=p_data->>'category') then raise exception 'Choose a forum.'; end if;
  select * into topic from korlix_social_topics where id=request_id;
  if topic.id is not null then
   if topic.author<>me.id then raise exception 'Topic ID already used.' using errcode='42501'; end if;
   return jsonb_build_object('id',topic.id);
  end if;
  perform korlix_social_limit(p_actor,'topic',10,3600);
  insert into korlix_social_topics(id,author,category,title,body)values(request_id,me.id,p_data->>'category',title_text,body_text);
  return jsonb_build_object('id',request_id);
 end if;
 if p_action in ('topic','edit_topic','delete_topic','reply') then
  target:=(p_data->>'id')::uuid;
  select * into topic from korlix_social_topics where id=target and not deleted for update;
  if topic.id is null or korlix_social_blocked(me.id,topic.author) or exists(select 1 from korlix_social_profiles where id=topic.author and suspended) then raise exception 'Topic not found.' using errcode='P0002'; end if;
  if p_action='topic' then
   select korlix_social_card(p) into card from korlix_social_profiles p where p.id=topic.author;
   select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
    select r.seq,to_jsonb(r)-'author'-'deleted'||jsonb_build_object('author',korlix_social_card(p)) card
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
    if char_length(title_text) not between 1 and 140 or char_length(body_text) not between 1 and 8000 then raise exception 'Check the title and post length.'; end if;
    update korlix_social_topics set title=title_text,body=body_text,updated_at=now() where id=topic.id;
   end if; return jsonb_build_object('ok',true);
  end if;
  if topic.locked then raise exception 'This topic is locked for new replies.' using errcode='42501'; end if;
  request_id:=(p_data->>'reply_id')::uuid; body_text:=trim(coalesce(p_data->>'body',''));
  if request_id is null or char_length(body_text) not between 1 and 4000 then raise exception 'Write a reply between 1 and 4,000 characters.'; end if;
  select * into reply from korlix_social_replies where id=request_id;
  if reply.id is not null then
   if reply.author<>me.id or reply.topic_id<>topic.id then raise exception 'Reply ID already used.' using errcode='42501'; end if;
   return jsonb_build_object('id',reply.id);
  end if;
  perform korlix_social_limit(p_actor,'reply',60,3600);
  insert into korlix_social_replies(id,topic_id,author,body)values(request_id,topic.id,me.id,body_text);
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
   if char_length(body_text) not between 1 and 4000 then raise exception 'Check the reply length.'; end if;
   update korlix_social_replies set body=body_text,updated_at=now() where id=reply.id;
  end if; return jsonb_build_object('ok',true);
 end if;
 if p_action='report' then
  target:=(p_data->>'target')::uuid; request_id:=(p_data->>'id')::uuid; kind:=p_data->>'kind'; body_text:=trim(coalesce(p_data->>'reason',''));
  if request_id is null or char_length(body_text) not between 1 and 1000 then raise exception 'Tell us why you are reporting this (up to 1,000 characters).'; end if;
  if kind='member' then select korlix_social_card(p) into snap from korlix_social_profiles p where p.id=target and p.id<>me.id and not p.suspended and (p.discoverable or exists(select 1 from korlix_social_connections c where least(c.requester,c.recipient)=least(me.id,p.id) and greatest(c.requester,c.recipient)=greatest(me.id,p.id)));
  elsif kind='message' then select jsonb_build_object('id',m.id,'author',m.sender,'body',m.body,'created_at',m.created_at) into snap from korlix_social_messages m where m.id=target and m.recipient=me.id and not m.deleted;
  elsif kind='topic' then select jsonb_build_object('id',t.id,'author',t.author,'title',t.title,'body',t.body) into snap from korlix_social_topics t where t.id=target and not t.deleted and not korlix_social_blocked(me.id,t.author);
  elsif kind='reply' then select jsonb_build_object('id',r.id,'author',r.author,'body',r.body) into snap from korlix_social_replies r join korlix_social_topics t on t.id=r.topic_id where r.id=target and not r.deleted and not t.deleted and not korlix_social_blocked(me.id,r.author) and not korlix_social_blocked(me.id,t.author);
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

-- Only the upload route may provide a path. Never expose this action in the JSON router.
create function public.korlix_social_avatar(p_actor uuid,p_action text,p_path text default null) returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; old_path text;
begin
 perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 select * into me from korlix_social_profiles where user_id=p_actor for update;
 if me.id is null or me.suspended then raise exception 'Create an active Social profile before adding a photo.' using errcode='42501'; end if;
 if p_action='begin' then
  perform korlix_social_limit(p_actor,'photo',20,3600);
  return jsonb_build_object('profile_id',me.id);
 end if;
 if p_action<>'save' then raise exception 'Photo action unavailable.'; end if;
 if p_path is not null and p_path !~ ('^'||me.id::text||'/[0-9a-f-]{36}\.jpg$') then raise exception 'Photo path unavailable.' using errcode='42501'; end if;
 old_path:=me.avatar_path;
 update korlix_social_profiles set avatar_path=p_path,updated_at=now() where id=me.id returning * into me;
 return jsonb_build_object('profile',korlix_social_card(me)||jsonb_build_object('discoverable',me.discoverable,'show_online',me.show_online),'old_path',old_path);
end $$;
revoke all on function public.korlix_social_avatar(uuid,text,text) from public,anon,authenticated;
grant execute on function public.korlix_social_avatar(uuid,text,text) to service_role;

-- One-to-one call signaling only. Audio/video packets never enter this database.
create table public.korlix_social_calls (
 id uuid primary key, caller uuid not null references public.korlix_social_profiles(id) on delete cascade,
 callee uuid not null references public.korlix_social_profiles(id) on delete cascade,
 caller_device uuid not null, callee_device uuid,
 mode text not null check(mode in ('audio','video')),
 state text not null default 'ringing' check(state in ('ringing','accepted','ended','declined','missed')),
 created_at timestamptz not null default now(), accepted_at timestamptz, ended_at timestamptz,
 caller_seen timestamptz not null default now(), callee_seen timestamptz,
 check(caller<>callee)
);
create index korlix_social_calls_caller on public.korlix_social_calls(caller,created_at desc);
create index korlix_social_calls_callee on public.korlix_social_calls(callee,created_at desc);
create index korlix_social_calls_cleanup on public.korlix_social_calls(created_at);
create table public.korlix_social_call_signals (
 id uuid primary key, seq bigint generated always as identity unique,
 call_id uuid not null references public.korlix_social_calls(id) on delete cascade,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 kind text not null check(kind in ('offer','answer','candidate','media')),
 payload jsonb not null check(octet_length(payload::text)<=200000), created_at timestamptz not null default now()
);
create index korlix_social_call_signals_stream on public.korlix_social_call_signals(call_id,seq);
create unique index korlix_social_call_description on public.korlix_social_call_signals(call_id,kind) where kind in ('offer','answer');
create index korlix_social_call_signals_sender on public.korlix_social_call_signals(sender);
alter table public.korlix_social_calls enable row level security;
alter table public.korlix_social_call_signals enable row level security;
revoke all on public.korlix_social_calls,public.korlix_social_call_signals from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_calls,public.korlix_social_call_signals to service_role;
revoke all on sequence public.korlix_social_call_signals_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_social_call_signals_seq_seq to service_role;

create function public.korlix_social_call_view(c public.korlix_social_calls,me uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',c.id,'mode',c.mode,'state',c.state,'incoming',c.callee=me,
 'created_at',c.created_at,'accepted_at',c.accepted_at,'ended_at',c.ended_at,'peer',korlix_social_card(p))
 from korlix_social_profiles p where p.id=case when c.caller=me then c.callee else c.caller end;
$$;

create function public.korlix_social_calls_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; peer korlix_social_profiles; c korlix_social_calls; existing korlix_social_call_signals;
 device uuid:=(p_data->>'device')::uuid; target uuid; signal_id uuid; signal_kind text; payload jsonb; items jsonb;
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required to call.' using errcode='42501'; end if;
 if device is null then raise exception 'Reopen Social before calling.'; end if;
 -- Deterministic participant locks prevent simultaneous/crossed calls across tabs.
 -- Mutations on an existing call serialize on its row. Calls never auto-answer.
 if p_action='call_start' then
  target:=(p_data->>'peer')::uuid;
  if target is null or target=me.id then raise exception 'Choose another connection.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-call-member:'||least(me.id,target)::text,0));
  perform pg_advisory_xact_lock(hashtextextended('social-call-member:'||greatest(me.id,target)::text,0));
  perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
  select * into peer from korlix_social_profiles where id=target;
  if peer.id is null or peer.suspended or korlix_social_blocked(me.id,target) or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target)) then raise exception 'An accepted connection is needed to call.' using errcode='42501'; end if;
  select * into c from korlix_social_calls where id=(p_data->>'id')::uuid;
  if c.id is not null then
   if c.caller<>me.id or c.callee<>target or c.caller_device<>device then raise exception 'Call ID unavailable.' using errcode='42501'; end if;
   return jsonb_build_object('call',korlix_social_call_view(c,me.id));
  end if;
  update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now()
   where (caller in(me.id,target) or callee in(me.id,target)) and state in ('ringing','accepted')
    and ((state='ringing' and created_at<now()-interval '45 seconds') or caller_seen<now()-interval '60 seconds' or (state='accepted' and callee_seen<now()-interval '60 seconds') or created_at<now()-interval '4 hours');
  if exists(select 1 from korlix_social_calls where (caller in(me.id,target) or callee in(me.id,target)) and state in ('ringing','accepted')) then raise exception 'You or this connection are already in a call.'; end if;
  perform korlix_social_limit(p_actor,'call',10,600);
  insert into korlix_social_calls(id,caller,callee,caller_device,mode) values((p_data->>'id')::uuid,me.id,target,device,p_data->>'mode') returning * into c;
  return jsonb_build_object('call',korlix_social_call_view(c,me.id));
 end if;
 if p_action='call_inbox' then
  -- Opportunistic deletion bounds persisted SDP/ICE data; no call recordings.
  delete from korlix_social_calls where created_at<now()-interval '24 hours' and (caller=me.id or callee=me.id);
  select * into c from korlix_social_calls where callee=me.id and state='ringing' and created_at>now()-interval '45 seconds' and caller_seen>now()-interval '60 seconds' order by created_at desc limit 1 for update;
  if c.id is null then return jsonb_build_object('call',null); end if;
 else
  select * into c from korlix_social_calls where id=(p_data->>'id')::uuid and (caller=me.id or callee=me.id) for update;
  if c.id is null then raise exception 'Call not found.' using errcode='P0002'; end if;
 end if;
 target:=case when c.caller=me.id then c.callee else c.caller end;
 if c.state in ('ringing','accepted') and
  (korlix_social_blocked(me.id,target) or exists(select 1 from korlix_social_profiles where id=target and suspended)
   or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target))
   or (c.state='ringing' and c.created_at<now()-interval '45 seconds') or c.caller_seen<now()-interval '60 seconds'
   or(c.state='accepted' and c.callee_seen<now()-interval '60 seconds') or c.created_at<now()-interval '4 hours') then
  update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now() where id=c.id returning * into c;
 end if;
 if p_action='call_inbox' then return jsonb_build_object('call',case when c.state='ringing' then korlix_social_call_view(c,me.id) else null end); end if;
 if (c.caller=me.id and c.caller_device<>device) or(c.callee=me.id and c.callee_device is not null and c.callee_device<>device) then raise exception 'This call is open on another device or tab.' using errcode='42501'; end if;
 if p_action='call_accept' then
  if c.callee<>me.id then raise exception 'Only the recipient can answer.' using errcode='42501'; end if;
  if c.state='ringing' then update korlix_social_calls set state='accepted',callee_device=device,callee_seen=now(),accepted_at=now() where id=c.id returning * into c; end if;
 elsif p_action='call_end' then
  if c.state in ('ringing','accepted') then update korlix_social_calls set state=case when c.state='ringing' and c.callee=me.id then 'declined' else 'ended' end,ended_at=now() where id=c.id returning * into c; end if;
 elsif p_action='call_signal' then
  if c.state<>'accepted' then raise exception 'This call is not connected.' using errcode='42501'; end if;
  signal_id:=(p_data->>'signal_id')::uuid; signal_kind:=p_data->>'kind'; payload:=p_data->'payload';
  if signal_id is null or jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>200000 then raise exception 'Invalid call signal.'; end if;
  if signal_kind in ('offer','answer') then
   if (signal_kind='offer' and c.caller<>me.id) or(signal_kind='answer' and c.callee<>me.id) then raise exception 'Signal sender unavailable.' using errcode='42501'; end if;
   if jsonb_typeof(payload->'sdp') is distinct from 'string' or char_length(payload->>'sdp') not between 1 and 190000 then raise exception 'Invalid call description.'; end if;
  elsif signal_kind='candidate' then
   if jsonb_typeof(payload->'candidate') is distinct from 'string' or char_length(payload->>'candidate')>4000 then raise exception 'Invalid network candidate.'; end if;
  elsif signal_kind='media' then
   if jsonb_typeof(payload->'camera') is distinct from 'boolean' or jsonb_typeof(payload->'microphone') is distinct from 'boolean' then raise exception 'Invalid media state.'; end if;
  else raise exception 'Signal unavailable.'; end if;
  select * into existing from korlix_social_call_signals where id=signal_id;
  if existing.id is not null then
   if existing.call_id<>c.id or existing.sender<>me.id or existing.kind<>signal_kind or existing.payload<>payload then raise exception 'Signal ID unavailable.' using errcode='42501'; end if;
  else
   perform korlix_social_limit(p_actor,'call-signal',300,60);
   insert into korlix_social_call_signals(id,call_id,sender,kind,payload) values(signal_id,c.id,me.id,signal_kind,payload);
  end if;
 elsif p_action<>'call_poll' then raise exception 'Call action unavailable.'; end if;
 if c.state in ('ringing','accepted') then
  update korlix_social_calls set caller_seen=case when caller=me.id then now() else caller_seen end,
   callee_seen=case when callee=me.id and state='accepted' then now() else callee_seen end where id=c.id returning * into c;
 else
  delete from korlix_social_call_signals where call_id=c.id;
 end if;
 if p_action='call_poll' and c.state='accepted' then
  select coalesce(jsonb_agg(x.item order by x.seq),'[]') into items from(
   select s.seq,jsonb_build_object('seq',s.seq,'kind',s.kind,'payload',s.payload) item from korlix_social_call_signals s
   where s.call_id=c.id and s.sender<>me.id and s.seq>greatest(0,coalesce((p_data->>'after')::bigint,0)) order by s.seq limit 100)x;
 end if;
 return jsonb_build_object('call',korlix_social_call_view(c,me.id),'signals',coalesce(items,'[]'));
end $$;
revoke all on function public.korlix_social_call_view(public.korlix_social_calls,uuid),public.korlix_social_calls_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_call_view(public.korlix_social_calls,uuid),public.korlix_social_calls_v1(uuid,text,jsonb) to service_role;
