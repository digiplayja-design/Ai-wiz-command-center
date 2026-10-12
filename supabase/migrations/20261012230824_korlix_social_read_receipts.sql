-- Receipts are recorded by the authenticated reader, never by the sender.
-- No historical group read times are invented from the unread-counter cursor.
create table public.korlix_social_group_message_reads (
 message_id uuid not null references public.korlix_social_group_messages(id) on delete cascade,
 reader uuid not null references public.korlix_social_profiles(id) on delete cascade,
 read_at timestamptz not null default now(),
 primary key(message_id,reader)
);
create index korlix_social_group_message_reads_reader
 on public.korlix_social_group_message_reads(reader);
alter table public.korlix_social_group_message_reads enable row level security;
revoke all on public.korlix_social_group_message_reads from public,anon,authenticated;
grant select,insert,delete on public.korlix_social_group_message_reads to service_role;

create function public.korlix_social_receipts_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare
 me korlix_social_profiles; peer korlix_social_profiles;
 membership korlix_social_group_members;
 target uuid; gid uuid; ids uuid[]; eligible uuid[]; raw_ids jsonb;
 through_seq bigint:=greatest(0,coalesce((p_data->>'through')::bigint,0));
 observed_at timestamptz:=clock_timestamp(); result jsonb;
begin
 if p_action not in ('read','group_read','message_receipts') then
  raise exception 'Read receipt action not found.' using errcode='P0002';
 end if;
 select * into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 target:=(p_data->>'peer')::uuid; gid:=(p_data->>'group')::uuid;
 if (target is null)=(gid is null) or (p_action='read' and target is null)
  or (p_action='group_read' and gid is null) then raise exception 'Choose one conversation.'; end if;
 -- GET query parameters carry JSON text; POST accepts a JSON array directly.
 raw_ids:=case when jsonb_typeof(p_data->'ids')='string' then (p_data->>'ids')::jsonb else p_data->'ids' end;
 if raw_ids is not null then
  if jsonb_typeof(raw_ids) is distinct from 'array' then raise exception 'Choose a list of message IDs.'; end if;
  if jsonb_array_length(raw_ids)>100 then raise exception 'Read receipts support up to 100 messages at a time.'; end if;
  if exists(select 1 from jsonb_array_elements(raw_ids) v where jsonb_typeof(v) is distinct from 'string') then
   raise exception 'Choose valid message IDs.';
  end if;
  select coalesce(array_agg(distinct value::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(raw_ids);
 elsif p_action='message_receipts' then raise exception 'Choose messages to check.';
 end if;
 if p_action<>'message_receipts' then
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 end if;

 if target is not null then
  perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
  select * into peer from korlix_social_profiles where id=target and not suspended;
  if target=me.id or peer.id is null or korlix_social_blocked(me.id,target)
   or not exists(select 1 from korlix_social_connections where state='accepted'
    and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target)) then
   raise exception 'This conversation is unavailable.' using errcode='42501';
  end if;
  if p_action='read' then
   -- Older clients only send a cursor. New clients send the messages actually
   -- displayed in the foreground. Both paths exclude deleted/dumped content.
   update korlix_social_messages m set read_at=coalesce(m.read_at,observed_at)
    where m.sender=target and m.recipient=me.id and not m.deleted
     and not korlix_social_dumped(me.id,'direct',m.id)
     and case when ids is null then m.seq<=through_seq else m.id=any(ids) end;
   return jsonb_build_object('ok',true);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'read_at',m.read_at,
   'read_count',case when m.read_at is null then 0 else 1 end) order by m.seq),'[]') into result
   from korlix_social_messages m where m.id=any(ids) and m.sender=me.id and m.recipient=target
    and not m.deleted and not korlix_social_dumped(me.id,'direct',m.id);
  return jsonb_build_object('items',result);
 end if;

 perform pg_advisory_xact_lock(hashtextextended('social-group:'||gid::text,0));
 select * into membership from korlix_social_group_members where group_id=gid and member=me.id and state='accepted';
 if membership.member is null or not exists(select 1 from korlix_social_groups where id=gid and not archived) then
  raise exception 'This group is unavailable. Accept its invitation before opening it.' using errcode='42501';
 end if;
 if p_action='group_read' then
  select coalesce(array_agg(x.id),'{}'::uuid[]) into eligible from (
   select m.id from korlix_social_group_messages m join korlix_social_profiles p on p.id=m.sender
    where m.group_id=gid and m.seq>membership.joined_after and m.sender<>me.id
     and not m.deleted and not p.suspended and not korlix_social_blocked(me.id,m.sender)
     and not korlix_social_dumped(me.id,'group',m.id)
     and ids is not null and m.id=any(ids)
    order by m.seq desc limit 100
  )x;
  insert into korlix_social_group_message_reads(message_id,reader,read_at)
   select id,me.id,observed_at from unnest(eligible) id on conflict do nothing;
  -- Keep the existing unread counter separate from per-message receipts.
  update korlix_social_group_members set last_read=greatest(last_read,least(through_seq,
   (select coalesce(max(seq),0) from korlix_social_group_messages where group_id=gid)))
   where group_id=gid and member=me.id;
  return jsonb_build_object('ok',true);
 end if;

 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'read_count',jsonb_array_length(r.readers),
  'readers',r.readers) order by m.seq),'[]') into result
 from korlix_social_group_messages m
 cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'handle',p.handle,
   'read_at',receipt.read_at) order by receipt.read_at,p.id),'[]') readers
  from korlix_social_group_message_reads receipt
   join korlix_social_profiles p on p.id=receipt.reader
   join korlix_social_group_members gm on gm.group_id=m.group_id and gm.member=receipt.reader
  where receipt.message_id=m.id and receipt.reader<>me.id and not p.suspended
   and not korlix_social_blocked(me.id,p.id) and gm.state='accepted' and gm.joined_after<m.seq
 )r
 where m.id=any(ids) and m.group_id=gid and m.sender=me.id and m.seq>membership.joined_after
  and not m.deleted and not korlix_social_dumped(me.id,'group',m.id);
 return jsonb_build_object('items',result);
end $$;
revoke all on function public.korlix_social_receipts_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_receipts_v1(uuid,text,jsonb) to service_role;
