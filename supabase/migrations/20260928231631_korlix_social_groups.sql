-- Group membership is explicit consent. Browser roles cannot access private data.
create table public.korlix_social_groups (
 id uuid primary key, owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 name text not null check(char_length(name) between 1 and 80),
 created_at timestamptz not null default now(), activity_at timestamptz not null default now(),
 archived boolean not null default false, creation jsonb not null
);
create index korlix_social_groups_owner on public.korlix_social_groups(owner);
create table public.korlix_social_group_members (
 group_id uuid not null references public.korlix_social_groups(id) on delete cascade,
 member uuid not null references public.korlix_social_profiles(id) on delete cascade,
 invited_by uuid references public.korlix_social_profiles(id) on delete set null,
 state text not null check(state in ('invited','accepted','left','declined','removed')),
 invited_at timestamptz not null default now(), joined_at timestamptz,
 joined_after bigint not null default 0, last_read bigint not null default 0,
 primary key(group_id,member)
);
create index korlix_social_group_members_member on public.korlix_social_group_members(member,state,group_id);
create index korlix_social_group_members_inviter on public.korlix_social_group_members(invited_by);
create table public.korlix_social_group_messages (
 id uuid primary key, seq bigint generated always as identity unique,
 group_id uuid not null references public.korlix_social_groups(id) on delete cascade,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 body text not null check(char_length(body)<=2000), created_at timestamptz not null default now(),
 deleted boolean not null default false,
 reply_to uuid references public.korlix_social_group_messages(id) on delete set null,
 check(reply_to is distinct from id)
);
create index korlix_social_group_messages_thread on public.korlix_social_group_messages(group_id,seq desc);
create index korlix_social_group_messages_sender on public.korlix_social_group_messages(sender);
create index korlix_social_group_messages_reply on public.korlix_social_group_messages(reply_to);
do $$ declare t text; begin
 foreach t in array array['groups','group_members','group_messages'] loop
  execute format('alter table public.korlix_social_%I enable row level security',t);
  execute format('revoke all on table public.korlix_social_%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on table public.korlix_social_%I to service_role',t);
 end loop;
end $$;
revoke all on sequence public.korlix_social_group_messages_seq_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_social_group_messages_seq_seq to service_role;
alter table public.korlix_social_reports drop constraint korlix_social_reports_kind_check;
alter table public.korlix_social_reports add constraint korlix_social_reports_kind_check check(kind in ('member','topic','reply','message','group_message'));

create function public.korlix_social_group_card(g public.korlix_social_groups, viewer uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',g.id,'name',g.name,'owner',g.owner,'color','cyan','state',gm.state,
  'owner_profile',(select case when korlix_social_blocked(viewer,p.id) then jsonb_build_object('name','Unavailable member') else korlix_social_card(p) end from korlix_social_profiles p where p.id=g.owner),
  'is_owner',g.owner=viewer,'member_count',(select count(*) from korlix_social_group_members where group_id=g.id and state='accepted'),
  'invited_count',(select count(*) from korlix_social_group_members where group_id=g.id and state='invited'),
  'activity_at',g.activity_at,'unread',case when gm.state='accepted' then (
   select count(*) from korlix_social_group_messages m join korlix_social_profiles p on p.id=m.sender
   where m.group_id=g.id and m.seq>greatest(gm.joined_after,gm.last_read) and m.sender<>viewer and not m.deleted
    and not p.suspended and not korlix_social_blocked(viewer,m.sender)) else 0 end)
 from korlix_social_group_members gm where gm.group_id=g.id and gm.member=viewer and gm.state in ('accepted','invited') and not g.archived;
$$;
create function public.korlix_social_group_message_card(m public.korlix_social_group_messages, viewer uuid, floor_seq bigint) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',case when hidden then null else m.sender end,
  'author',case when hidden then jsonb_build_object('name','Unavailable member') else korlix_social_card(p) end,
  'body',case when m.deleted or hidden then '' else m.body end,'deleted',m.deleted or hidden,'created_at',m.created_at,
  'reply_to',case when m.deleted or hidden or q.card is null then null else m.reply_to end,
  'reply',case when m.deleted or hidden then null else q.card end)
 from korlix_social_profiles p cross join lateral(select p.suspended or korlix_social_blocked(viewer,m.sender) hidden) h
 left join lateral (
  select jsonb_build_object('id',r.id,'seq',r.seq,'sender',r.sender,'author',korlix_social_card(rp),
    'deleted',r.deleted,'body',case when r.deleted then '' else left(r.body,280) end) card
  from korlix_social_group_messages r join korlix_social_profiles rp on rp.id=r.sender
  where r.id=m.reply_to and r.group_id=m.group_id and r.seq>floor_seq and not rp.suspended and not korlix_social_blocked(viewer,r.sender)
 ) q on true where p.id=m.sender;
$$;

create function public.korlix_social_groups_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
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
  if parent is not null and not exists(select 1 from korlix_social_group_messages m join korlix_social_profiles p on p.id=m.sender where m.id=parent and m.group_id=gid and m.seq>membership.joined_after and not m.deleted and not p.suspended and not korlix_social_blocked(me.id,m.sender)) then raise exception 'That message is no longer available to reply to.'; end if;
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
  select * into msg from korlix_social_group_messages where id=(p_data->>'id')::uuid and group_id=gid and seq>membership.joined_after;
  if msg.id is null then raise exception 'Message not found in this group.' using errcode='P0002'; end if;
  return jsonb_build_object('message',korlix_social_group_message_card(msg,me.id,membership.joined_after));
 elsif p_action='group_messages' then
  select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
   select m.seq,korlix_social_group_message_card(m,me.id,membership.joined_after) card from korlix_social_group_messages m
   where m.group_id=gid and m.seq>membership.joined_after and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
   order by m.seq desc limit 51
  )x;
  return jsonb_build_object('items',items,'peer',korlix_social_group_card(g,me.id),'hidden_senders',(select coalesce(jsonb_agg(gm.member),'[]') from korlix_social_group_members gm join korlix_social_profiles p on p.id=gm.member where gm.group_id=gid and (p.suspended or korlix_social_blocked(me.id,gm.member))));
 end if;
 raise exception 'Group action not found.' using errcode='P0002';
end $$;
revoke all on function public.korlix_social_group_card(public.korlix_social_groups,uuid),public.korlix_social_group_message_card(public.korlix_social_group_messages,uuid,bigint),public.korlix_social_groups_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_group_card(public.korlix_social_groups,uuid),public.korlix_social_group_message_card(public.korlix_social_group_messages,uuid,bigint),public.korlix_social_groups_v1(uuid,text,jsonb) to service_role;
