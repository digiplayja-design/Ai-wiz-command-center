-- Fail closed if another release changed any replaced function after this baseline.
do $guard$
begin
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_chat_v1(uuid,text,jsonb)'::regprocedure) is distinct from '8a866121f22ca4afd244c8af502bcad2' then
  raise exception 'Auto Dump baseline changed: korlix_social_chat_v1. Review the newer function before applying.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_group_card(public.korlix_social_groups,uuid)'::regprocedure) is distinct from 'efe5dcae75f7a805e5caa36308ded7e2' then
  raise exception 'Auto Dump baseline changed: korlix_social_group_card. Review the newer function before applying.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_group_message_card(public.korlix_social_group_messages,uuid,bigint)'::regprocedure) is distinct from '18d6a78d3950a062661f90e1d76aaa6d' then
  raise exception 'Auto Dump baseline changed: korlix_social_group_message_card. Review the newer function before applying.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_groups_v1(uuid,text,jsonb)'::regprocedure) is distinct from '037115261887fd2a18b061cb9cba0f38' then
  raise exception 'Auto Dump baseline changed: korlix_social_groups_v1. Review the newer function before applying.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_v1(uuid,text,jsonb)'::regprocedure) is distinct from '489122ddf7e361b1860c98645fabe56f' then
  raise exception 'Auto Dump baseline changed: korlix_social_v1. Review the newer function before applying.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_attachment_v1(uuid,text,jsonb)'::regprocedure) is distinct from 'ce8dae7957e9ee1bb4d77f8951c2da93' then
  raise exception 'Auto Dump baseline changed: korlix_social_attachment_v1. Review the newer function before applying.';
 end if;
end $guard$;

-- Auto Dump removes a selected message only from the requesting member's history.
-- Deadlines are evaluated in the database on every read, even while apps are closed.
-- No shared message or Storage object is deleted; other participants keep their copy.
create table public.korlix_social_message_dumps (
 viewer uuid not null references public.korlix_social_profiles(id) on delete cascade,
 scope text not null check(scope in ('direct','group')),
 message_id uuid not null,
 dump_at timestamptz not null,
 primary key(viewer,scope,message_id)
);
create table public.korlix_social_dump_requests (
 viewer uuid not null references public.korlix_social_profiles(id) on delete cascade,
 request_id uuid not null,
 scope text not null check(scope in ('direct','group')),
 message_id uuid not null,
 action text not null check(action in ('dump_schedule','dump_cancel')),
 seconds integer,
 primary key(viewer,request_id),
 check((action='dump_cancel' and seconds is null) or
       (action='dump_schedule' and seconds in (15,45,60,900,3600,86400)))
);
alter table public.korlix_social_message_dumps enable row level security;
alter table public.korlix_social_dump_requests enable row level security;
revoke all on public.korlix_social_message_dumps,public.korlix_social_dump_requests from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_message_dumps,public.korlix_social_dump_requests to service_role;

create function public.korlix_social_dump_at(viewer uuid,scope_name text,message_uuid uuid) returns timestamptz
language sql stable security invoker set search_path='' as $$
 select d.dump_at from public.korlix_social_message_dumps d
 where d.viewer=$1 and d.scope=$2 and d.message_id=$3;
$$;
create function public.korlix_social_dumped(viewer uuid,scope_name text,message_uuid uuid) returns boolean
language sql volatile security invoker set search_path='' as $$
 select coalesce(public.korlix_social_dump_at($1,$2,$3)<=clock_timestamp(),false);
$$;

-- Viewer-aware cards never repeat a dumped original's text in a reply preview.
create function public.korlix_social_message_card(m public.korlix_social_messages,viewer uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',m.sender,
  'body',case when m.deleted then '' else m.body end,'created_at',m.created_at,
  'read_at',m.read_at,'deleted',m.deleted,'dump_at',korlix_social_dump_at(viewer,'direct',m.id),
  'reply_to',case when m.deleted or q.card is null then null else m.reply_to end,
  'reply',case when m.deleted then null else q.card end)
 from (select 1) seed left join lateral (
  select jsonb_build_object('id',p.id,'seq',p.seq,'sender',p.sender,'deleted',p.deleted,
   'body',case when p.deleted then '' else left(p.body,280) end,
   'dump_at',korlix_social_dump_at(viewer,'direct',p.id)) card
  from korlix_social_messages p where p.id=m.reply_to
   and least(p.sender,p.recipient)=least(m.sender,m.recipient)
   and greatest(p.sender,p.recipient)=greatest(m.sender,m.recipient)
   and not korlix_social_dumped(viewer,'direct',p.id)
 ) q on true;
$$;


create or replace function public.korlix_social_chat_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; peer korlix_social_profiles; msg korlix_social_messages; connection_state text;
 target uuid; request_id uuid; parent_id uuid; body_text text; items jsonb;
begin
 if p_action not in ('send','messages','message') then raise exception 'Chat action not found.' using errcode='P0002'; end if;
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required to chat.' using errcode='42501'; end if;
 target:=(p_data->>'peer')::uuid;
 if target is null or target=me.id then raise exception 'Choose another connection.'; end if;
 if p_action='send' then perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0)); end if;
 perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
 select * into peer from korlix_social_profiles where id=target;
 if peer.id is null or peer.suspended or korlix_social_blocked(me.id,target)
 then raise exception 'This connection is unavailable.' using errcode='42501'; end if;
 select state into connection_state from korlix_social_connections
  where least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target);
 if connection_state is null then raise exception 'An accepted connection is needed to access this conversation.' using errcode='42501'; end if;
 if connection_state<>'accepted' then raise exception 'Wait for the follow request to be accepted before messaging.' using errcode='42501'; end if;
 if p_action='send' then
  request_id:=(p_data->>'id')::uuid; parent_id:=(p_data->>'reply_to')::uuid;
  body_text:=trim(coalesce(p_data->>'body',''));
  if request_id is null or char_length(body_text) not between 1 and 2000 then raise exception 'Write a message between 1 and 2,000 characters.'; end if;
  select * into msg from korlix_social_messages where id=request_id;
  if msg.id is not null then
   if msg.sender<>me.id or msg.recipient<>target then raise exception 'Choose a new message ID.' using errcode='42501'; end if;
   if msg.body<>body_text or msg.reply_to is distinct from parent_id then
    raise exception 'This message ID was already used. Change the message before sending again.' using errcode='23505';
   end if;
   return jsonb_build_object('id',msg.id);
  end if;
  if parent_id is not null then
   perform 1 from korlix_social_messages p where p.id=parent_id and not p.deleted and not korlix_social_dumped(me.id,'direct',p.id)
    and least(p.sender,p.recipient)=least(me.id,target) and greatest(p.sender,p.recipient)=greatest(me.id,target) for share;
   if not found then raise exception 'That message is no longer available to reply to in this conversation.'; end if;
  end if;
  perform korlix_social_limit(p_actor,'message',60,60);
  insert into korlix_social_messages(id,sender,recipient,body,reply_to) values(request_id,me.id,target,body_text,parent_id);
  return jsonb_build_object('id',request_id);
 elsif p_action='message' then
  select * into msg from korlix_social_messages where id=(p_data->>'id')::uuid and not korlix_social_dumped(me.id,'direct',id)
   and least(sender,recipient)=least(me.id,target) and greatest(sender,recipient)=greatest(me.id,target);
  if msg.id is null then raise exception 'Message not found in this conversation.' using errcode='P0002'; end if;
  return jsonb_build_object('server_time',clock_timestamp(),'message',korlix_social_message_card(msg,me.id),'peer',korlix_social_card(peer));
 end if;
 select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
  select m.seq,korlix_social_message_card(m,me.id) card from korlix_social_messages m
  where least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)
   and not korlix_social_dumped(me.id,'direct',m.id)
   and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
  order by m.seq desc limit 51
 )x;
 return jsonb_build_object('items',items,'peer',korlix_social_card(peer),'server_time',clock_timestamp(),
  'dump_schedules',(select coalesce(jsonb_object_agg(d.message_id,d.dump_at),'{}') from korlix_social_message_dumps d
   join korlix_social_messages m on m.id=d.message_id where d.viewer=me.id and d.scope='direct' and d.dump_at>clock_timestamp()
    and least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)),
  'dumped_ids',(select coalesce(jsonb_agg(d.message_id),'[]') from korlix_social_message_dumps d
   join korlix_social_messages m on m.id=d.message_id where d.viewer=me.id and d.scope='direct' and d.dump_at<=clock_timestamp()
    and least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)));
end $$;

create or replace function public.korlix_social_group_card(g public.korlix_social_groups, viewer uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',g.id,'name',g.name,'owner',g.owner,'color','cyan','state',gm.state,
  'owner_profile',(select case when korlix_social_blocked(viewer,p.id) then jsonb_build_object('name','Unavailable member') else korlix_social_card(p) end from korlix_social_profiles p where p.id=g.owner),
  'is_owner',g.owner=viewer,'member_count',(select count(*) from korlix_social_group_members where group_id=g.id and state='accepted'),
  'invited_count',(select count(*) from korlix_social_group_members where group_id=g.id and state='invited'),
  'activity_at',g.activity_at,'unread',case when gm.state='accepted' then (
   select count(*) from korlix_social_group_messages m join korlix_social_profiles p on p.id=m.sender
   where m.group_id=g.id and m.seq>greatest(gm.joined_after,gm.last_read) and m.sender<>viewer and not m.deleted
    and not p.suspended and not korlix_social_blocked(viewer,m.sender) and not korlix_social_dumped(viewer,'group',m.id)) else 0 end)
 from korlix_social_group_members gm where gm.group_id=g.id and gm.member=viewer and gm.state in ('accepted','invited') and not g.archived;
$$;

create or replace function public.korlix_social_group_message_card(m public.korlix_social_group_messages, viewer uuid, floor_seq bigint) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',case when hidden then null else m.sender end,
  'author',case when hidden then jsonb_build_object('name','Unavailable member') else korlix_social_card(p) end,
  'body',case when m.deleted or hidden then '' else m.body end,'deleted',m.deleted or hidden,'created_at',m.created_at,
  'dump_at',korlix_social_dump_at(viewer,'group',m.id),
  'reply_to',case when m.deleted or hidden or q.card is null then null else m.reply_to end,
  'reply',case when m.deleted or hidden then null else q.card end)
 from korlix_social_profiles p cross join lateral(select p.suspended or korlix_social_blocked(viewer,m.sender) hidden) h
 left join lateral (
  select jsonb_build_object('id',r.id,'seq',r.seq,'sender',r.sender,'author',korlix_social_card(rp),
    'dump_at',korlix_social_dump_at(viewer,'group',r.id),'deleted',r.deleted,'body',case when r.deleted then '' else left(r.body,280) end) card
  from korlix_social_group_messages r join korlix_social_profiles rp on rp.id=r.sender
  where r.id=m.reply_to and r.group_id=m.group_id and r.seq>floor_seq and not rp.suspended and not korlix_social_blocked(viewer,r.sender) and not korlix_social_dumped(viewer,'group',r.id)
 ) q on true where p.id=m.sender;
$$;

create or replace function public.korlix_social_groups_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; g korlix_social_groups; membership korlix_social_group_members; msg korlix_social_group_messages; rep korlix_social_reports;
 gid uuid; mid uuid; target uuid; parent uuid; successor uuid; targets uuid[]; title_text text; body_text text;
 items jsonb; roster jsonb; creation_data jsonb; current_seq bigint; added integer:=0;
 skip integer:=greatest(0,least(50000,coalesce((p_data->>'offset')::integer,0)));
 query_text text:=left(trim(coalesce(p_data->>'q','')),100);
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action not in ('groups','group_details','group_messages','group_message') then
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 end if;
 if p_action='moderate' then
  if not exists(select 1 from korlix_social_moderators where user_id=p_actor) then raise exception 'Moderator access required.' using errcode='42501'; end if;
  select * into rep from korlix_social_reports where id=(p_data->>'id')::uuid for update;
  if rep.kind is distinct from 'group_message' then return korlix_social_v1(p_actor,p_action,p_data); end if;
  if rep.state<>'open' then raise exception 'This report was already resolved.'; end if;
  if p_data->>'decision'='remove' then update korlix_social_group_messages set body='',deleted=true where id=rep.target_id;
  elsif p_data->>'decision' is distinct from 'resolve' then raise exception 'Choose an available moderation action.'; end if;
  update korlix_social_reports set state='resolved',resolved_at=now(),resolved_by=p_actor,decision=p_data->>'decision' where id=rep.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='groups' then
  select coalesce(jsonb_agg(x.card order by x.activity_at desc,x.id),'[]') into items from (
   select room.id,room.activity_at,korlix_social_group_card(room,me.id) card from korlix_social_groups room
   join korlix_social_group_members gm on gm.group_id=room.id and gm.member=me.id
   where not room.archived and gm.state in ('invited','accepted')
    and (gm.state='accepted' or (not korlix_social_blocked(me.id,room.owner) and exists(select 1 from korlix_social_profiles owner_profile where owner_profile.id=room.owner and not owner_profile.suspended))) and position(lower(query_text) in lower(room.name))>0
   order by room.activity_at desc,room.id limit 41 offset skip
  )x;
  return jsonb_build_object('items',items);
 end if;
 if p_action='group_report' then
  select group_id into gid from korlix_social_group_messages where id=(p_data->>'target')::uuid;
 else gid:=(p_data->>'group')::uuid; end if;
 if gid is null then raise exception 'Choose a group.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('social-group:'||gid::text,0));
 if p_action='group_create' then
  title_text:=trim(coalesce(p_data->>'name',''));
  if char_length(title_text) not between 1 and 80 then raise exception 'Give your group a name of 1–80 characters.'; end if;
  if jsonb_typeof(p_data->'members') is distinct from 'array' then raise exception 'Select connections to invite.'; end if;
  select array_agg(distinct value::uuid order by value::uuid) into targets from jsonb_array_elements_text(p_data->'members');
  if coalesce(cardinality(targets),0) not between 1 and 49 then raise exception 'Select between 1 and 49 connections.'; end if;
  creation_data:=jsonb_build_object('name',title_text,'members',to_jsonb(targets),'creator',me.id);
  select * into g from korlix_social_groups where id=gid;
  if found then
   if g.creation<>creation_data or g.archived or not exists(select 1 from korlix_social_group_members where group_id=gid and member=me.id and state='accepted') then raise exception 'Choose a new group request.' using errcode='23505'; end if;
   return jsonb_build_object('group',korlix_social_group_card(g,me.id));
  end if;
  perform korlix_social_limit(p_actor,'group-create',10,86400);
  insert into korlix_social_groups(id,owner,name,creation) values(gid,me.id,title_text,creation_data) returning * into g;
  insert into korlix_social_group_members(group_id,member,invited_by,state,joined_at) values(gid,me.id,me.id,'accepted',now());
  perform korlix_social_groups_v1(p_actor,'group_invite',jsonb_build_object('group',gid,'members',to_jsonb(targets)));
  return jsonb_build_object('group',korlix_social_group_card(g,me.id));
 end if;
 select * into g from korlix_social_groups where id=gid and not archived;
 select * into membership from korlix_social_group_members where group_id=gid and member=me.id;
 if g.id is null or membership.state is null or membership.state not in ('invited','accepted') then raise exception 'This group is unavailable. You may have left or been removed.' using errcode='42501'; end if;
 if p_action='group_decline' and membership.state='invited' then
  update korlix_social_group_members set state='declined',invited_at=now() where group_id=gid and member=me.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='group_accept' and membership.state='invited' then
  if not exists(select 1 from korlix_social_profiles where id=g.owner and not suspended)
   or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,g.owner) and greatest(requester,recipient)=greatest(me.id,g.owner))
   or exists(select 1 from korlix_social_group_members x where x.group_id=gid and x.state='accepted' and korlix_social_blocked(me.id,x.member))
  then raise exception 'This invitation is unavailable. Connect with the group owner before joining.' using errcode='42501'; end if;
  select coalesce(max(seq),0) into current_seq from korlix_social_group_messages where group_id=gid;
  update korlix_social_group_members set state='accepted',joined_at=now(),joined_after=current_seq,last_read=current_seq where group_id=gid and member=me.id;
  return jsonb_build_object('group',korlix_social_group_card(g,me.id));
 end if;
 if membership.state<>'accepted' then raise exception 'Accept the invitation before opening this group.' using errcode='42501'; end if;
 if p_action='group_accept' then return jsonb_build_object('group',korlix_social_group_card(g,me.id)); end if;
 if p_action='group_invite' then
  if g.owner<>me.id then raise exception 'Only the group owner can invite members.' using errcode='42501'; end if;
  if jsonb_typeof(p_data->'members') is distinct from 'array' then raise exception 'Select connections to invite.'; end if;
  select array_agg(distinct value::uuid order by value::uuid) into targets from jsonb_array_elements_text(p_data->'members');
  if coalesce(cardinality(targets),0) not between 1 and 49 then raise exception 'Select between 1 and 49 connections.'; end if;
  foreach target in array targets loop
   if target=me.id or not exists(select 1 from korlix_social_profiles where id=target and not suspended)
    or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target))
    or exists(select 1 from korlix_social_group_members gm where gm.group_id=gid and gm.state='accepted' and korlix_social_blocked(target,gm.member))
   then raise exception 'One of these connections cannot be invited. Refresh your connections and try again.'; end if;
   if exists(select 1 from korlix_social_group_members where group_id=gid and member=target and state in ('left','declined','removed') and invited_at>now()-interval '1 hour') then raise exception 'Please wait an hour before inviting someone who declined or left again.'; end if;
   if not exists(select 1 from korlix_social_group_members where group_id=gid and member=target and state in ('accepted','invited')) then added:=added+1; end if;
  end loop;
  if (select count(*) from korlix_social_group_members where group_id=gid and state in ('invited','accepted'))+added>50 then raise exception 'Groups support up to 50 members, including pending invitations.'; end if;
  foreach target in array targets loop
   if not exists(select 1 from korlix_social_group_members where group_id=gid and member=target and state in ('accepted','invited')) then perform korlix_social_limit(p_actor,'group-invite',100,86400); end if;
   insert into korlix_social_group_members(group_id,member,invited_by,state) values(gid,target,me.id,'invited')
   on conflict(group_id,member) do update set state='invited',invited_by=me.id,invited_at=now(),joined_at=null
    where korlix_social_group_members.state not in ('invited','accepted');
  end loop;
  return jsonb_build_object('ok',true,'invited',added);
 elsif p_action='group_rename' then
  if g.owner<>me.id then raise exception 'Only the group owner can rename it.' using errcode='42501'; end if;
  title_text:=trim(coalesce(p_data->>'name',''));
  if char_length(title_text) not between 1 and 80 then raise exception 'Use a group name of 1–80 characters.'; end if;
  update korlix_social_groups set name=title_text where id=gid;
  return jsonb_build_object('ok',true);
 elsif p_action in ('group_leave','group_remove') then
  target:=case when p_action='group_leave' then me.id else (p_data->>'member')::uuid end;
  if p_action='group_remove' and (g.owner<>me.id or target=me.id or target is null) then raise exception 'Only the owner can remove another member.' using errcode='42501'; end if;
  if target=me.id and g.owner=me.id then
   select gm.member into successor from korlix_social_group_members gm join korlix_social_profiles p on p.id=gm.member
    where gm.group_id=gid and gm.state='accepted' and gm.member<>me.id and not p.suspended order by gm.joined_at,gm.member limit 1;
   if successor is null then update korlix_social_groups set archived=true where id=gid;
   else update korlix_social_groups set owner=successor where id=gid; end if;
  end if;
  update korlix_social_group_members set state=case when p_action='group_leave' then 'left' else 'removed' end,invited_at=now() where group_id=gid and member=target and state in ('accepted','invited');
  return jsonb_build_object('ok',true);
 elsif p_action='group_details' then
  select coalesce(jsonb_agg(jsonb_build_object('profile',case when korlix_social_blocked(me.id,p.id) then jsonb_build_object('id',p.id,'name','Unavailable member','color','cyan') else korlix_social_card(p) end,'state',gm.state,'is_owner',gm.member=g.owner) order by gm.member=g.owner desc,gm.joined_at,gm.invited_at),'[]') into roster
   from korlix_social_group_members gm join korlix_social_profiles p on p.id=gm.member where gm.group_id=gid and gm.state in ('accepted','invited');
  return jsonb_build_object('group',korlix_social_group_card(g,me.id),'members',roster);
 elsif p_action='group_send' then
  mid:=(p_data->>'id')::uuid; parent:=(p_data->>'reply_to')::uuid; body_text:=trim(coalesce(p_data->>'body',''));
  if mid is null or char_length(body_text) not between 1 and 2000 then raise exception 'Write a message between 1 and 2,000 characters.'; end if;
  select * into msg from korlix_social_group_messages where id=mid;
  if found then
   if msg.sender<>me.id or msg.group_id<>gid then raise exception 'Choose a new message ID.' using errcode='42501'; end if;
   if msg.body<>body_text or msg.reply_to is distinct from parent then raise exception 'This message request was already used.' using errcode='23505'; end if;
   return jsonb_build_object('id',mid);
  end if;
  if parent is not null and not exists(select 1 from korlix_social_group_messages m join korlix_social_profiles p on p.id=m.sender where m.id=parent and not korlix_social_dumped(me.id,'group',m.id) and m.group_id=gid and m.seq>membership.joined_after and not m.deleted and not p.suspended and not korlix_social_blocked(me.id,m.sender)) then raise exception 'That message is no longer available to reply to.'; end if;
  perform korlix_social_limit(p_actor,'group-message',60,60);
  insert into korlix_social_group_messages(id,group_id,sender,body,reply_to) values(mid,gid,me.id,body_text,parent);
  update korlix_social_groups set activity_at=now() where id=gid;
  return jsonb_build_object('id',mid);
 elsif p_action='group_read' then
  update korlix_social_group_members set last_read=greatest(last_read,least(coalesce((p_data->>'through')::bigint,0),(select coalesce(max(seq),0) from korlix_social_group_messages where group_id=gid))) where group_id=gid and member=me.id;
  return jsonb_build_object('ok',true);
 elsif p_action='group_delete_message' then
  update korlix_social_group_messages set body='',deleted=true where id=(p_data->>'id')::uuid and group_id=gid and sender=me.id;
  if not found then raise exception 'Your message was not found.' using errcode='P0002'; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='group_report' then
  select * into msg from korlix_social_group_messages where id=(p_data->>'target')::uuid and group_id=gid and seq>membership.joined_after and not deleted and sender<>me.id and not korlix_social_blocked(me.id,sender);
  body_text:=trim(coalesce(p_data->>'reason','')); mid:=(p_data->>'id')::uuid;
  if msg.id is null then raise exception 'This message is unavailable to report.' using errcode='42501'; end if;
  if mid is null or char_length(body_text) not between 1 and 1000 then raise exception 'Add a reason for your report.'; end if;
  if exists(select 1 from korlix_social_reports where id=mid) then
   if exists(select 1 from korlix_social_reports where id=mid and reporter=me.id and target_id=msg.id and kind='group_message') then return jsonb_build_object('ok',true); end if;
   raise exception 'Choose a new report request.' using errcode='23505';
  end if;
  perform korlix_social_limit(p_actor,'report',20,86400);
  insert into korlix_social_reports(id,reporter,kind,target_id,reason,snapshot) values(mid,me.id,'group_message',msg.id,body_text,jsonb_build_object('id',msg.id,'author',msg.sender,'body',msg.body,'group',gid));
  return jsonb_build_object('ok',true);
 elsif p_action='group_message' then
  select * into msg from korlix_social_group_messages where id=(p_data->>'id')::uuid and group_id=gid and seq>membership.joined_after and not korlix_social_dumped(me.id,'group',id);
  if msg.id is null then raise exception 'Message not found in this group.' using errcode='P0002'; end if;
  return jsonb_build_object('server_time',clock_timestamp(),'message',korlix_social_group_message_card(msg,me.id,membership.joined_after));
 elsif p_action='group_messages' then
  select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
   select m.seq,korlix_social_group_message_card(m,me.id,membership.joined_after) card from korlix_social_group_messages m
   where m.group_id=gid and m.seq>membership.joined_after and not korlix_social_dumped(me.id,'group',m.id) and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
   order by m.seq desc limit 51
  )x;
  return jsonb_build_object('items',items,'peer',korlix_social_group_card(g,me.id),'server_time',clock_timestamp(),
   'dump_schedules',(select coalesce(jsonb_object_agg(d.message_id,d.dump_at),'{}') from korlix_social_message_dumps d
    join korlix_social_group_messages m on m.id=d.message_id where d.viewer=me.id and d.scope='group' and d.dump_at>clock_timestamp()
     and m.group_id=gid and m.seq>membership.joined_after),
   'dumped_ids',(select coalesce(jsonb_agg(d.message_id),'[]') from korlix_social_message_dumps d
    join korlix_social_group_messages m on m.id=d.message_id where d.viewer=me.id and d.scope='group' and d.dump_at<=clock_timestamp()
     and m.group_id=gid and m.seq>membership.joined_after),'hidden_senders',(select coalesce(jsonb_agg(gm.member),'[]') from korlix_social_group_members gm join korlix_social_profiles p on p.id=gm.member where gm.group_id=gid and (p.suspended or korlix_social_blocked(me.id,gm.member))));
 end if;
 raise exception 'Group action not found.' using errcode='P0002';
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
 if p_action in ('messages','send') then return korlix_social_chat_v1(p_actor,p_action,p_data); end if;
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
    'unread',(select count(*) from korlix_social_messages m where m.sender=p.id and m.recipient=me.id and m.read_at is null and not m.deleted and not korlix_social_dumped(me.id,'direct',m.id)),
    'last_message',(select case when m.deleted then 'Message removed' else left(m.body,100) end from korlix_social_messages m where least(m.sender,m.recipient)=least(me.id,p.id) and greatest(m.sender,m.recipient)=greatest(me.id,p.id) and not korlix_social_dumped(me.id,'direct',m.id) order by m.seq desc limit 1)) card
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
   if (a.direct_message is not null and public.korlix_social_dumped(me.id,'direct',a.direct_message))
    or (a.group_message is not null and public.korlix_social_dumped(me.id,'group',a.group_message))
   then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
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
 if (a.direct_message is not null and public.korlix_social_dumped(me.id,'direct',a.direct_message))
  or (a.group_message is not null and public.korlix_social_dumped(me.id,'group',a.group_message))
 then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
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

-- The operation ledger makes uncertain network retries safe. Old operations
-- return the effective current schedule rather than reapplying stale intent.
create function public.korlix_social_dump_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; prior korlix_social_dump_requests;
 mid uuid; rid uuid; peer_id uuid; group_uuid uuid; scope_name text;
 delay_seconds integer; deadline timestamptz; effective_now timestamptz;
begin
 if p_action not in ('dump_schedule','dump_cancel') then raise exception 'Auto Dump action not found.' using errcode='P0002'; end if;
 select * into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 mid:=(p_data->>'id')::uuid; rid:=(p_data->>'request_id')::uuid;
 peer_id:=(p_data->>'peer')::uuid; group_uuid:=(p_data->>'group')::uuid;
 if mid is null or rid is null or (peer_id is null)=(group_uuid is null) then raise exception 'Choose one message and conversation.'; end if;
 scope_name:=case when group_uuid is null then 'direct' else 'group' end;
 if p_action='dump_schedule' then
  delay_seconds:=(p_data->>'seconds')::integer;
  if delay_seconds is null or delay_seconds not in (15,45,60,900,3600,86400) then raise exception 'Choose an available Auto Dump time.'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 -- Reuse all current consent, membership, block and suspension checks. A due
 -- message itself may already be filtered, so authorize its conversation first.
 if scope_name='direct' then
  perform korlix_social_chat_v1(p_actor,'messages',jsonb_build_object('peer',peer_id));
  perform 1 from korlix_social_messages m where m.id=mid and not m.deleted
   and least(m.sender,m.recipient)=least(me.id,peer_id) and greatest(m.sender,m.recipient)=greatest(me.id,peer_id) for share;
 else
  perform korlix_social_groups_v1(p_actor,'group_messages',jsonb_build_object('group',group_uuid));
  perform 1 from korlix_social_group_messages m join korlix_social_group_members gm on gm.group_id=m.group_id and gm.member=me.id
   join korlix_social_profiles author on author.id=m.sender
   where m.id=mid and m.group_id=group_uuid and m.seq>gm.joined_after and not m.deleted
    and gm.state='accepted' and not author.suspended and not korlix_social_blocked(me.id,m.sender) for share of m;
 end if;
 if not found then raise exception 'Message not found in this conversation.' using errcode='P0002'; end if;
 select * into prior from korlix_social_dump_requests where viewer=me.id and request_id=rid;
 if prior.request_id is not null and (prior.scope<>scope_name or prior.message_id<>mid or prior.action<>p_action or prior.seconds is distinct from delay_seconds)
 then raise exception 'This Auto Dump request already has different content.' using errcode='23505'; end if;
 select dump_at into deadline from korlix_social_message_dumps where viewer=me.id and scope=scope_name and message_id=mid for update;
 effective_now:=clock_timestamp();
 -- Expired rows are permanent tombstones, including cancellation and retries.
 if deadline is not null and deadline<=effective_now then
  return jsonb_build_object('id',mid,'dump_at',deadline,'server_time',effective_now,'dumped',true);
 end if;
 if prior.request_id is null then
  perform korlix_social_limit(p_actor,'auto-dump-minute',120,60);
  perform korlix_social_limit(p_actor,'auto-dump-day',2000,86400);
  if p_action='dump_schedule' then
   deadline:=effective_now+make_interval(secs=>delay_seconds);
   insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at) values(me.id,scope_name,mid,deadline)
    on conflict(viewer,scope,message_id) do update set dump_at=excluded.dump_at;
  else
   delete from korlix_social_message_dumps where viewer=me.id and scope=scope_name and message_id=mid;
   deadline:=null;
  end if;
  insert into korlix_social_dump_requests(viewer,request_id,scope,message_id,action,seconds)
   values(me.id,rid,scope_name,mid,p_action,delay_seconds);
 end if;
 return jsonb_build_object('id',mid,'dump_at',deadline,'server_time',effective_now,'dumped',false);
end $$;

revoke all on function public.korlix_social_dump_at(uuid,text,uuid),public.korlix_social_dumped(uuid,text,uuid),
 public.korlix_social_message_card(public.korlix_social_messages,uuid),public.korlix_social_dump_v1(uuid,text,jsonb)
 from public,anon,authenticated;
grant execute on function public.korlix_social_dump_at(uuid,text,uuid),public.korlix_social_dumped(uuid,text,uuid),
 public.korlix_social_message_card(public.korlix_social_messages,uuid),public.korlix_social_dump_v1(uuid,text,jsonb)
 to service_role;
