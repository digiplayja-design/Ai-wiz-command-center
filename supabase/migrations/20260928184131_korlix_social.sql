-- KORLIX Social is opt-in. No auth identities/emails are copied to public cards.
-- The backend verifies Supabase sessions. Browser roles cannot call these RPCs
-- or access these tables. Every mutation/permission check is transactional.
create table public.korlix_social_profiles (
 id uuid primary key default gen_random_uuid(), user_id uuid unique not null references auth.users(id) on delete cascade,
 handle text unique not null check (handle ~ '^[a-z0-9_]{3,24}$'),
 name text not null check (char_length(name) between 1 and 60),
 bio text not null default '' check (char_length(bio)<=300),
 color text not null default 'cyan' check (color in ('cyan','violet','coral','mint','gold','blue')),
 discoverable boolean not null default true, show_online boolean not null default false,
 last_seen timestamptz, suspended boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.korlix_social_connections (
 id uuid primary key default gen_random_uuid(),
 requester uuid not null references public.korlix_social_profiles(id) on delete cascade,
 recipient uuid not null references public.korlix_social_profiles(id) on delete cascade,
 state text not null default 'pending' check(state in ('pending','accepted')),
 created_at timestamptz not null default now(), accepted_at timestamptz,
 check(requester<>recipient)
);
create unique index korlix_social_connection_pair on public.korlix_social_connections(least(requester,recipient),greatest(requester,recipient));
create index korlix_social_connection_recipient on public.korlix_social_connections(recipient,state);
create index korlix_social_connection_requester on public.korlix_social_connections(requester,state);
create table public.korlix_social_blocks (
 blocker uuid not null references public.korlix_social_profiles(id) on delete cascade,
 blocked uuid not null references public.korlix_social_profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(blocker,blocked), check(blocker<>blocked)
);
create index korlix_social_blocks_reverse on public.korlix_social_blocks(blocked,blocker);
create table public.korlix_social_messages (
 id uuid primary key, seq bigint generated always as identity unique,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 recipient uuid not null references public.korlix_social_profiles(id) on delete cascade,
 body text not null check(char_length(body)<=2000), created_at timestamptz not null default now(),
 read_at timestamptz, deleted boolean not null default false, check(sender<>recipient)
);
create index korlix_social_messages_pair on public.korlix_social_messages(least(sender,recipient),greatest(sender,recipient),seq desc);
create index korlix_social_messages_unread on public.korlix_social_messages(recipient,sender) where read_at is null and not deleted;
create table public.korlix_social_categories (
 id text primary key, name text not null, description text not null, icon text not null, color text not null, position integer not null
);
insert into public.korlix_social_categories values
 ('sports','Sports','Game days, teams and everything in between.','sports','mint',1),
 ('entertainment','Entertainment','Films, music, culture and the next big thing.','entertainment','violet',2),
 ('politics','Politics','Public policy and different perspectives.','politics','coral',3),
 ('religion','Religion & Beliefs','Faith, philosophy and respectful conversation.','religion','gold',4),
 ('stock-market','Stock Market','Markets, companies and investment ideas.','stock-market','cyan',5),
 ('technology','Technology','AI, new ideas and what comes next.','technology','blue',6),
 ('business','Business','Building, creating and working together.','business','gold',7),
 ('community','Community','Introductions, questions and everyday life.','community','mint',8);
create table public.korlix_social_topics (
 id uuid primary key, author uuid not null references public.korlix_social_profiles(id) on delete cascade,
 category text not null references public.korlix_social_categories(id),
 title text not null check(char_length(title) between 1 and 140), body text not null check(char_length(body)<=8000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), activity_at timestamptz not null default now(),
 locked boolean not null default false, deleted boolean not null default false
);
create index korlix_social_topics_feed on public.korlix_social_topics(category,activity_at desc,id) where not deleted;
create index korlix_social_topics_author on public.korlix_social_topics(author);
create table public.korlix_social_replies (
 id uuid primary key, seq bigint generated always as identity unique,
 topic_id uuid not null references public.korlix_social_topics(id) on delete cascade,
 author uuid not null references public.korlix_social_profiles(id) on delete cascade,
 body text not null check(char_length(body)<=4000), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), deleted boolean not null default false
);
create index korlix_social_replies_thread on public.korlix_social_replies(topic_id,seq);
create index korlix_social_replies_author on public.korlix_social_replies(author);
create table public.korlix_social_reports (
 id uuid primary key, reporter uuid not null references public.korlix_social_profiles(id) on delete cascade,
 kind text not null check(kind in ('member','topic','reply','message')), target_id uuid not null,
 reason text not null check(char_length(reason) between 1 and 1000), snapshot jsonb not null,
 state text not null default 'open' check(state in ('open','resolved')), created_at timestamptz not null default now(), resolved_at timestamptz,
 resolved_by uuid references auth.users(id) on delete set null, decision text
);
create index korlix_social_reports_queue on public.korlix_social_reports(state,created_at);
create index korlix_social_reports_reporter on public.korlix_social_reports(reporter);
create index korlix_social_reports_resolver on public.korlix_social_reports(resolved_by);
-- Moderators are assigned by the project owner through the database, never from user-editable metadata.
create table public.korlix_social_moderators(user_id uuid primary key references auth.users(id) on delete cascade);
create table public.korlix_social_limits(actor uuid not null references auth.users(id) on delete cascade,bucket text not null,window_start timestamptz not null,hits integer not null,primary key(actor,bucket));

do $$ declare t text; begin
 foreach t in array array['profiles','connections','blocks','messages','categories','topics','replies','reports','moderators','limits'] loop
  execute format('alter table public.korlix_social_%I enable row level security',t);
  execute format('revoke all on table public.korlix_social_%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on table public.korlix_social_%I to service_role',t);
 end loop;
end $$;
revoke all on sequence public.korlix_social_messages_seq_seq,public.korlix_social_replies_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_social_messages_seq_seq,public.korlix_social_replies_seq_seq to service_role;

create function public.korlix_social_card(p public.korlix_social_profiles) returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',p.id,'name',case when p.suspended then 'Unavailable member' else p.name end,
 'handle',case when p.suspended then '' else p.handle end,'bio',case when p.suspended then '' else p.bio end,'color',p.color,
 'online',coalesce(not p.suspended and p.show_online and p.last_seen>now()-interval '90 seconds',false));
$$;
create function public.korlix_social_blocked(a uuid,b uuid) returns boolean language sql stable security invoker set search_path=public as $$
 select exists(select 1 from korlix_social_blocks where (blocker=a and blocked=b) or(blocker=b and blocked=a));
$$;
create function public.korlix_social_limit(a uuid,b text,n integer,seconds integer) returns void language plpgsql security invoker set search_path=public as $$
 declare h integer; begin
 insert into korlix_social_limits(actor,bucket,window_start,hits)values(a,b,now(),1)
 on conflict(actor,bucket)do update set hits=case when korlix_social_limits.window_start<now()-make_interval(secs=>seconds) then 1 else korlix_social_limits.hits+1 end,
 window_start=case when korlix_social_limits.window_start<now()-make_interval(secs=>seconds) then now() else korlix_social_limits.window_start end returning hits into h;
 if h>n then raise exception 'You have reached the limit for this action. Please try again later.' using errcode='54000'; end if;
end $$;

create function public.korlix_social_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
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
  if me.id is null and p_data->'accepted_rules' is distinct from 'true'::jsonb then raise exception 'Accept the community rules to join.'; end if;
  handle_text:=lower(trim(coalesce(p_data->>'handle',''))); title_text:=trim(coalesce(p_data->>'name','')); body_text:=trim(coalesce(p_data->>'bio',''));
  if handle_text!~'^[a-z0-9_]{3,24}$' or char_length(title_text) not between 1 and 60 or char_length(body_text)>300 then raise exception 'Use a 3–24 character handle, a name up to 60 characters and a bio up to 300 characters.'; end if;
  if coalesce(p_data->>'color','') not in ('cyan','violet','coral','mint','gold','blue') or jsonb_typeof(p_data->'discoverable') is distinct from 'boolean' or jsonb_typeof(p_data->'show_online') is distinct from 'boolean' then raise exception 'Choose your profile visibility settings.'; end if;
  perform korlix_social_limit(p_actor,'profile',30,3600);
  insert into korlix_social_profiles(user_id,handle,name,bio,color,discoverable,show_online) values(p_actor,handle_text,title_text,body_text,p_data->>'color',(p_data->>'discoverable')::boolean,(p_data->>'show_online')::boolean)
  on conflict(user_id) do update set handle=excluded.handle,name=excluded.name,bio=excluded.bio,color=excluded.color,discoverable=excluded.discoverable,show_online=excluded.show_online,last_seen=case when excluded.show_online then korlix_social_profiles.last_seen else null end,updated_at=now() returning * into me;
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
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name))>0)
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
   and (query='' or position(lower(query) in lower(p.handle||' '||p.name))>0)
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

revoke all on function public.korlix_social_card(public.korlix_social_profiles),public.korlix_social_blocked(uuid,uuid),public.korlix_social_limit(uuid,text,integer,integer),public.korlix_social_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_card(public.korlix_social_profiles),public.korlix_social_blocked(uuid,uuid),public.korlix_social_limit(uuid,text,integer,integer),public.korlix_social_v1(uuid,text,jsonb) to service_role;
