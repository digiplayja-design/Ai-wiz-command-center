-- Replies reference the original row; no permanent copy of removed message text.
alter table public.korlix_social_messages
 add column reply_to uuid references public.korlix_social_messages(id) on delete set null,
 add constraint korlix_social_message_not_self_reply check(reply_to is distinct from id);
create index korlix_social_messages_reply_to on public.korlix_social_messages(reply_to);

create function public.korlix_social_message_card(m public.korlix_social_messages) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',m.id,'seq',m.seq,'sender',m.sender,
  'body',case when m.deleted then '' else m.body end,'created_at',m.created_at,
  'read_at',m.read_at,'deleted',m.deleted,
  'reply_to',case when m.deleted then null else m.reply_to end,
  'reply',case when m.deleted or m.reply_to is null then null else (
   select jsonb_build_object('id',p.id,'seq',p.seq,'sender',p.sender,'deleted',p.deleted,
    'body',case when p.deleted then '' else left(p.body,280) end)
   from korlix_social_messages p where p.id=m.reply_to
    and least(p.sender,p.recipient)=least(m.sender,m.recipient)
    and greatest(p.sender,p.recipient)=greatest(m.sender,m.recipient)
  ) end);
$$;
revoke all on function public.korlix_social_message_card(public.korlix_social_messages) from public,anon,authenticated;
grant execute on function public.korlix_social_message_card(public.korlix_social_messages) to service_role;

-- Separate chat RPC keeps existing forum, profile and call contracts intact.
create function public.korlix_social_chat_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
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
   perform 1 from korlix_social_messages p where p.id=parent_id and not p.deleted
    and least(p.sender,p.recipient)=least(me.id,target) and greatest(p.sender,p.recipient)=greatest(me.id,target) for share;
   if not found then raise exception 'That message is no longer available to reply to in this conversation.'; end if;
  end if;
  perform korlix_social_limit(p_actor,'message',60,60);
  insert into korlix_social_messages(id,sender,recipient,body,reply_to) values(request_id,me.id,target,body_text,parent_id);
  return jsonb_build_object('id',request_id);
 elsif p_action='message' then
  select * into msg from korlix_social_messages where id=(p_data->>'id')::uuid
   and least(sender,recipient)=least(me.id,target) and greatest(sender,recipient)=greatest(me.id,target);
  if msg.id is null then raise exception 'Message not found in this conversation.' using errcode='P0002'; end if;
  return jsonb_build_object('message',korlix_social_message_card(msg),'peer',korlix_social_card(peer));
 end if;
 select coalesce(jsonb_agg(x.card order by x.seq),'[]') into items from (
  select m.seq,korlix_social_message_card(m) card from korlix_social_messages m
  where least(m.sender,m.recipient)=least(me.id,target) and greatest(m.sender,m.recipient)=greatest(me.id,target)
   and (p_data->>'before' is null or m.seq<(p_data->>'before')::bigint)
  order by m.seq desc limit 51
 )x;
 return jsonb_build_object('items',items,'peer',korlix_social_card(peer));
end $$;
revoke all on function public.korlix_social_chat_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_chat_v1(uuid,text,jsonb) to service_role;
-- Existing table RLS and browser-deny privileges stay in force.
