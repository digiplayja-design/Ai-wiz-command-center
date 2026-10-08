-- Real account sign-in timestamps and independent self/everyone Auto Dump schedules.
-- Refuse to overwrite a newer production function without review.
do $guard$
begin

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_card(public.korlix_social_profiles,uuid)'::regprocedure) is distinct from '18027037542acc009d2f59c49c3f5227' then
  raise exception 'Social scope baseline changed: public.korlix_social_card(public.korlix_social_profiles,uuid)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_chat_v1(uuid,text,jsonb)'::regprocedure) is distinct from '694efa138acf2f8a09be9031417f8851' then
  raise exception 'Social scope baseline changed: public.korlix_social_chat_v1(uuid,text,jsonb)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_groups_v1(uuid,text,jsonb)'::regprocedure) is distinct from 'b2b6fd06d3a583c534440b9dbdaa52f7' then
  raise exception 'Social scope baseline changed: public.korlix_social_groups_v1(uuid,text,jsonb)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_message_card(public.korlix_social_messages,uuid)'::regprocedure) is distinct from 'ab0ad100a758032741d0a196dd7aa582' then
  raise exception 'Social scope baseline changed: public.korlix_social_message_card(public.korlix_social_messages,uuid)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_group_message_card(public.korlix_social_group_messages,uuid,bigint)'::regprocedure) is distinct from '0328358dfc3f6fa455926e9eaa47aff7' then
  raise exception 'Social scope baseline changed: public.korlix_social_group_message_card(public.korlix_social_group_messages,uuid,bigint)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_dump_at(uuid,text,uuid)'::regprocedure) is distinct from '2a9374353501cba2287c43a5e08f719b' then
  raise exception 'Social scope baseline changed: public.korlix_social_dump_at(uuid,text,uuid)';
 end if;

 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_dump_v1(uuid,text,jsonb)'::regprocedure) is distinct from 'e26a419ffcd80bb5002364ebe71e04ca' then
  raise exception 'Social scope baseline changed: public.korlix_social_dump_v1(uuid,text,jsonb)';
 end if;

end $guard$;


-- Auth records remain private. The service may read this one verified sign-in timestamp.
grant select(last_sign_in_at) on auth.users to service_role;

create table public.korlix_social_shared_message_dumps (
 scope text not null check(scope in ('direct','group')),
 message_id uuid not null,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 dump_at timestamptz not null,
 primary key(scope,message_id)
);
create index korlix_social_shared_message_dumps_sender_idx
 on public.korlix_social_shared_message_dumps(sender);
alter table public.korlix_social_shared_message_dumps enable row level security;
revoke all on public.korlix_social_shared_message_dumps from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_shared_message_dumps to service_role;
alter table public.korlix_social_dump_requests add column dump_scope text not null default 'self' check(dump_scope in ('self','everyone'));

-- Viewer-private and sender-shared schedules coexist; the first deadline wins.
create or replace function public.korlix_social_dump_at(viewer uuid,scope_name text,message_uuid uuid) returns timestamptz
language sql stable security invoker set search_path='' as $$
 select min(dump_at) from (
  select d.dump_at from public.korlix_social_message_dumps d where d.viewer=$1 and d.scope=$2 and d.message_id=$3
  union all
  select d.dump_at from public.korlix_social_shared_message_dumps d where d.scope=$2 and d.message_id=$3
 ) deadlines;
$$;
create function public.korlix_social_dump_metadata(viewer uuid,scope_name text,message_uuid uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('dump_at',least(self_at,everyone_at),'self_dump_at',self_at,'everyone_dump_at',everyone_at,
  'dump_scope',case when self_at is null and everyone_at is null then null when everyone_at is null or self_at<=everyone_at then 'self' else 'everyone' end)
 from (select
  (select dump_at from public.korlix_social_message_dumps where viewer=$1 and scope=$2 and message_id=$3) self_at,
  (select dump_at from public.korlix_social_shared_message_dumps where scope=$2 and message_id=$3) everyone_at) dates;
$$;
-- Return complete conversation schedules so clients scrub previously loaded pages.
-- No viewer-private schedule can be read by another member.
create function public.korlix_social_dump_snapshot(viewer uuid,scope_name text,conversation uuid,floor_seq bigint default 0) returns jsonb
language sql volatile security invoker set search_path=public as $$
 with pending as (
  select message_id,dump_at,'self'::text audience from korlix_social_message_dumps where viewer=$1 and scope=$2
  union all
  select message_id,dump_at,'everyone'::text audience from korlix_social_shared_message_dumps where scope=$2
 ), allowed as (
  select p.* from pending p join korlix_social_messages m on m.id=p.message_id
   where $2='direct' and least(m.sender,m.recipient)=least($1,$3) and greatest(m.sender,m.recipient)=greatest($1,$3)
  union all
  select p.* from pending p join korlix_social_group_messages m on m.id=p.message_id join korlix_social_profiles author on author.id=m.sender
   where $2='group' and m.group_id=$3 and m.seq>$4 and not author.suspended and not korlix_social_blocked($1,m.sender)
 ), combined as (
  select message_id,min(dump_at) dump_at,min(dump_at) filter(where audience='self') self_at,
   min(dump_at) filter(where audience='everyone') everyone_at from allowed group by message_id
 ), clock as (select clock_timestamp() now_at)
 select jsonb_build_object(
  'dump_schedules',coalesce((select jsonb_object_agg(message_id,dump_at) from combined,clock where dump_at>now_at),'{}'),
  'dump_self_schedules',coalesce((select jsonb_object_agg(message_id,self_at) from combined,clock where dump_at>now_at and self_at is not null),'{}'),
  'dump_everyone_schedules',coalesce((select jsonb_object_agg(message_id,everyone_at) from combined,clock where dump_at>now_at and everyone_at is not null),'{}'),
  'dumped_ids',coalesce((select jsonb_agg(message_id) from combined,clock where dump_at<=now_at),'[]'));
$$;

-- A request's audience is immutable, just like its message, operation and delay.
create or replace function public.korlix_social_dump_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; prior korlix_social_dump_requests;
 mid uuid; rid uuid; peer_id uuid; group_uuid uuid; scope_name text; audience text; author_id uuid;
 delay_seconds integer; deadline timestamptz; effective_now timestamptz;
begin
 if p_action not in ('dump_schedule','dump_cancel') then raise exception 'Auto Dump action not found.' using errcode='P0002'; end if;
 select * into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 mid:=(p_data->>'id')::uuid; rid:=(p_data->>'request_id')::uuid;
 peer_id:=(p_data->>'peer')::uuid; group_uuid:=(p_data->>'group')::uuid;
 if mid is null or rid is null or (peer_id is null)=(group_uuid is null) then raise exception 'Choose one message and conversation.'; end if;
 scope_name:=case when group_uuid is null then 'direct' else 'group' end;
 audience:=coalesce(p_data->>'dump_scope','self');
 if audience not in ('self','everyone') then raise exception 'Choose Only me or Everyone for Auto Dump.'; end if;
 if p_action='dump_schedule' then
  if jsonb_typeof(p_data->'seconds') not in ('number','string') or coalesce(p_data->>'seconds','') !~ '^[0-9]+$' then raise exception 'Choose an available Auto Dump time.'; end if;
  delay_seconds:=(p_data->>'seconds')::integer;
  if delay_seconds is null or delay_seconds not in (15,45,60,900,3600,86400) then raise exception 'Choose an available Auto Dump time.'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 -- Existing pair/group locks serialize competing participant changes, and reuse
 -- connection consent, blocks, suspension and group membership checks.
 if scope_name='direct' then
  perform korlix_social_chat_v1(p_actor,'messages',jsonb_build_object('peer',peer_id));
  select m.sender into author_id from korlix_social_messages m where m.id=mid and not m.deleted
   and least(m.sender,m.recipient)=least(me.id,peer_id) and greatest(m.sender,m.recipient)=greatest(me.id,peer_id) for share;
 else
  perform korlix_social_groups_v1(p_actor,'group_messages',jsonb_build_object('group',group_uuid));
  select m.sender into author_id from korlix_social_group_messages m join korlix_social_group_members gm on gm.group_id=m.group_id and gm.member=me.id
   join korlix_social_profiles author on author.id=m.sender
   where m.id=mid and m.group_id=group_uuid and m.seq>gm.joined_after and not m.deleted
    and gm.state='accepted' and not author.suspended and not korlix_social_blocked(me.id,m.sender) for share of m;
 end if;
 if not found then raise exception 'Message not found in this conversation.' using errcode='P0002'; end if;
 if audience='everyone' and author_id<>me.id then raise exception 'Only the sender can dump this message for everyone.' using errcode='42501'; end if;
 select * into prior from korlix_social_dump_requests where viewer=me.id and request_id=rid;
 if prior.request_id is not null and (prior.scope<>scope_name or prior.message_id<>mid or prior.action<>p_action or prior.seconds is distinct from delay_seconds or prior.dump_scope<>audience)
 then raise exception 'This Auto Dump request already has different content.' using errcode='23505'; end if;
 deadline:=korlix_social_dump_at(me.id,scope_name,mid);
 effective_now:=clock_timestamp();
 -- An expiry in either audience is permanent; no cancellation, scope change or
 -- replay can make a removed message accessible again.
 if deadline is not null and deadline<=effective_now then
  return jsonb_build_object('id',mid,'server_time',effective_now,'dumped',true)||korlix_social_dump_metadata(me.id,scope_name,mid);
 end if;
 if prior.request_id is null then
  perform korlix_social_limit(p_actor,'auto-dump-minute',120,60);
  perform korlix_social_limit(p_actor,'auto-dump-day',2000,86400);
  if p_action='dump_schedule' then
   deadline:=effective_now+make_interval(secs=>delay_seconds);
   if audience='everyone' then
    insert into korlix_social_shared_message_dumps(scope,message_id,sender,dump_at) values(scope_name,mid,me.id,deadline)
     on conflict(scope,message_id) do update set dump_at=excluded.dump_at;
   else
    insert into korlix_social_message_dumps(viewer,scope,message_id,dump_at) values(me.id,scope_name,mid,deadline)
     on conflict(viewer,scope,message_id) do update set dump_at=excluded.dump_at;
   end if;
  elsif audience='everyone' then
   delete from korlix_social_shared_message_dumps where scope=scope_name and message_id=mid and sender=me.id;
  else
   delete from korlix_social_message_dumps where viewer=me.id and scope=scope_name and message_id=mid;
  end if;
  insert into korlix_social_dump_requests(viewer,request_id,scope,message_id,action,seconds,dump_scope)
   values(me.id,rid,scope_name,mid,p_action,delay_seconds,audience);
 end if;
 return jsonb_build_object('id',mid,'server_time',effective_now,'dumped',false)||korlix_social_dump_metadata(me.id,scope_name,mid);
end $$;


create or replace function public.korlix_social_card(p public.korlix_social_profiles,viewer uuid) returns jsonb
language plpgsql stable security invoker set search_path=public as $$
declare result jsonb:=korlix_social_card(p)||jsonb_build_object('last_login_at',null); connected boolean; k text; audience text; details jsonb; visibility jsonb:='{}';
begin
 if p.suspended or viewer is null or (viewer<>p.id and korlix_social_blocked(viewer,p.id)) then
  return result - 'profession';
 end if;
 if p.show_online then
  result:=result||jsonb_build_object('last_login_at',(select u.last_sign_in_at from auth.users u where u.id=p.user_id));
 end if;
 connected:=exists(select 1 from korlix_social_connections where state='accepted' and
   least(requester,recipient)=least(viewer,p.id) and greatest(requester,recipient)=greatest(viewer,p.id));
 details:=p.profile_details||jsonb_build_object('profession',p.profession);
 foreach k in array array['status_caption','home_country','city','phone_number','favorite_color','profession','current_job','favorite_food','marital_status','income_level'] loop
  audience:=coalesce(p.profile_visibility->>k,case when k in ('phone_number','income_level') then 'private' else 'members' end);
  visibility:=visibility||jsonb_build_object(k,audience);
  if viewer=p.id or audience='members' or (audience='connections' and connected) then
   result:=result||jsonb_build_object(k,coalesce(details->>k,''));
  else result:=result-k;
  end if;
 end loop;
 if viewer=p.id then result:=result||jsonb_build_object('profile_visibility',visibility); end if;
 return result;
end $$;

create or replace function public.korlix_social_message_card(m public.korlix_social_messages,viewer uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',m.sender,
  'body',case when m.deleted then '' else m.body end,'created_at',m.created_at,
  'read_at',m.read_at,'deleted',m.deleted,'dump_at',korlix_social_dump_at(viewer,'direct',m.id),
  'reply_to',case when m.deleted or q.card is null then null else m.reply_to end,
  'reply',case when m.deleted then null else q.card end)||korlix_social_dump_metadata(viewer,'direct',m.id)
 from (select 1) seed left join lateral (
  select jsonb_build_object('id',p.id,'seq',p.seq,'sender',p.sender,'deleted',p.deleted,
   'body',case when p.deleted then '' else left(p.body,280) end,
   'dump_at',korlix_social_dump_at(viewer,'direct',p.id))||korlix_social_dump_metadata(viewer,'direct',p.id) card
  from korlix_social_messages p where p.id=m.reply_to
   and least(p.sender,p.recipient)=least(m.sender,m.recipient)
   and greatest(p.sender,p.recipient)=greatest(m.sender,m.recipient)
   and not korlix_social_dumped(viewer,'direct',p.id)
 ) q on true;
$$;

create or replace function public.korlix_social_group_message_card(m public.korlix_social_group_messages, viewer uuid, floor_seq bigint) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',case when hidden then null else m.sender end,
  'author',case when hidden then jsonb_build_object('name','Unavailable member') else korlix_social_card(p,viewer) end,
  'body',case when m.deleted or hidden then '' else m.body end,'deleted',m.deleted or hidden,'created_at',m.created_at,
  'dump_at',korlix_social_dump_at(viewer,'group',m.id),
  'reply_to',case when m.deleted or hidden or q.card is null then null else m.reply_to end,
  'reply',case when m.deleted or hidden then null else q.card end)||korlix_social_dump_metadata(viewer,'group',m.id)
 from korlix_social_profiles p cross join lateral(select p.suspended or korlix_social_blocked(viewer,m.sender) hidden) h
 left join lateral (
  select jsonb_build_object('id',r.id,'seq',r.seq,'sender',r.sender,'author',korlix_social_card(rp,viewer),
    'dump_at',korlix_social_dump_at(viewer,'group',r.id),'deleted',r.deleted,'body',case when r.deleted then '' else left(r.body,280) end)||korlix_social_dump_metadata(viewer,'group',r.id) card
  from korlix_social_group_messages r join korlix_social_profiles rp on rp.id=r.sender
  where r.id=m.reply_to and r.group_id=m.group_id and r.seq>floor_seq and not rp.suspended and not korlix_social_blocked(viewer,r.sender) and not korlix_social_dumped(viewer,'group',r.id)
 ) q on true where p.id=m.sender;
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
  return jsonb_build_object('server_time',clock_timestamp(),'message',korlix_social_message_card(msg,me.id),'peer',korlix_social_card(peer,me.id));
 end if;
 select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
  select m.seq,korlix_social_message_card(m,me.id) card from korlix_social_messages m
  where least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)
   and not korlix_social_dumped(me.id,'direct',m.id)
   and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
  order by m.seq desc limit 51
 )x;
 return jsonb_build_object('items',items,'peer',korlix_social_card(peer,me.id),'server_time',clock_timestamp())
  ||korlix_social_dump_snapshot(me.id,'direct',target);
end $$;

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
  select coalesce(jsonb_agg(jsonb_build_object('profile',case when korlix_social_blocked(me.id,p.id) then jsonb_build_object('id',p.id,'name','Unavailable member','color','cyan') else korlix_social_card(p,me.id) end,'state',gm.state,'is_owner',gm.member=g.owner) order by gm.member=g.owner desc,gm.joined_at,gm.invited_at),'[]') into roster
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
  return korlix_social_dump_snapshot(me.id,'group',gid,membership.joined_after)||jsonb_build_object('items',items,'peer',korlix_social_group_card(g,me.id),'server_time',clock_timestamp(),
   'hidden_senders',(select coalesce(jsonb_agg(gm.member),'[]') from korlix_social_group_members gm join korlix_social_profiles p on p.id=gm.member where gm.group_id=gid and (p.suspended or korlix_social_blocked(me.id,gm.member))));
 end if;
 raise exception 'Group action not found.' using errcode='P0002';
end $$;


revoke all on function public.korlix_social_dump_metadata(uuid,text,uuid),public.korlix_social_dump_snapshot(uuid,text,uuid,bigint) from public,anon,authenticated;
grant execute on function public.korlix_social_dump_metadata(uuid,text,uuid),public.korlix_social_dump_snapshot(uuid,text,uuid,bigint) to service_role;
-- Replaced functions retain their existing service-only ACLs. No browser grants,
-- auth trigger, message-body rewrite or Storage deletion is introduced.
