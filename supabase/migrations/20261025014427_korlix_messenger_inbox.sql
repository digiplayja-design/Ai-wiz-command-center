-- The standalone inbox reuses accepted Social connections and visible messages.
-- Existing hub connection ordering and response contracts remain unchanged.
create function public.korlix_messenger_inbox_v1(
 p_actor uuid, p_action text, p_data jsonb default '{}'
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 me public.korlix_social_profiles;
 items jsonb;
 query text:=left(trim(coalesce(p_data->>'q','')),100);
 filter_name text:=coalesce(p_data->>'filter','all');
 skip integer:=greatest(0,least(5000,coalesce((p_data->>'offset')::integer,0)));
begin
 if p_actor is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
 if p_action<>'messenger_inbox' or filter_name not in ('all','unread') then
  raise exception 'Choose a valid Messenger inbox filter.';
 end if;
 select * into me from public.korlix_social_profiles where user_id=p_actor;
 if me.id is null then raise exception 'Create a Social profile first.' using errcode='42501'; end if;
 if me.suspended then raise exception 'Your Social access is suspended. Contact KORLIX support.' using errcode='42501'; end if;

 select coalesce(jsonb_agg(x.card order by x.last_seq desc nulls last,x.connected_at desc,x.connection_id),'[]'::jsonb)
 into items from (
  select c.id connection_id,c.created_at connected_at,last_message.seq last_seq,
   public.korlix_social_card(p,me.id)||jsonb_build_object(
    'connection','accepted','incoming',false,'unread',unread.total,
    'last_message',case when last_message.deleted then 'Message removed' else left(last_message.body,100) end,
    'last_message_at',last_message.created_at,
    'last_message_mine',coalesce(last_message.sender=me.id and not last_message.deleted,false),
    'last_message_kind',case when last_message.deleted then 'text' else coalesce(attachment.kind,'text') end,
    'last_message_duration_ms',case when not last_message.deleted and attachment.kind='voice' then attachment.duration_ms end
   ) card
  from public.korlix_social_connections c
  join public.korlix_social_profiles p on p.id=case when c.requester=me.id then c.recipient else c.requester end
  left join lateral (
   select m.id,m.seq,m.sender,m.body,m.created_at,m.deleted
   from public.korlix_social_messages m
   where least(m.sender,m.recipient)=least(me.id,p.id)
    and greatest(m.sender,m.recipient)=greatest(me.id,p.id)
    and not public.korlix_social_dumped(me.id,'direct',m.id)
   order by m.seq desc limit 1
  ) last_message on true
  left join public.korlix_social_attachments attachment
   on attachment.direct_message=last_message.id and attachment.state='attached' and attachment.purged_at is null
  cross join lateral (
   select count(*) total from public.korlix_social_messages m
   where m.sender=p.id and m.recipient=me.id and m.read_at is null and not m.deleted
    and not public.korlix_social_dumped(me.id,'direct',m.id)
  ) unread
  where (c.requester=me.id or c.recipient=me.id) and c.state='accepted'
   and not p.suspended and not public.korlix_social_blocked(me.id,p.id)
   and (filter_name='all' or unread.total>0)
   and (query='' or position(lower(query) in lower(p.name||' '||p.handle||' '||case when last_message.deleted then '' else coalesce(last_message.body,'') end))>0)
  order by last_message.seq desc nulls last,c.created_at desc,c.id limit 41 offset skip
 ) x;
 return jsonb_build_object('items',items,'offset',skip);
end;
$$;
revoke all on function public.korlix_messenger_inbox_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_messenger_inbox_v1(uuid,text,jsonb) to service_role;
