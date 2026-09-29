create table public.korlix_social_attachments (
 id uuid primary key,
 owner uuid references public.korlix_social_profiles(id) on delete set null,
 peer uuid references public.korlix_social_profiles(id) on delete set null,
 group_id uuid references public.korlix_social_groups(id) on delete set null,
 direct_message uuid unique references public.korlix_social_messages(id) on delete set null,
 group_message uuid unique references public.korlix_social_group_messages(id) on delete set null,
 kind text not null check(kind in ('image','file','voice')),
 filename text not null check(char_length(filename) between 1 and 150),
 content_type text not null, size_bytes integer not null check(size_bytes between 1 and 20971520),
 duration_ms integer check(duration_ms between 1 and 181000),
 object_path text not null unique, checksum text not null check(checksum~'^[a-f0-9]{64}$'),
 state text not null default 'uploading' check(state in ('uploading','ready','attached')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '1 hour',
 purged_at timestamptz,
 check(not (peer is not null and group_id is not null)),
 check(not (direct_message is not null and group_message is not null))
);
create index korlix_social_attachments_owner on public.korlix_social_attachments(owner);
create index korlix_social_attachments_peer on public.korlix_social_attachments(peer);
create index korlix_social_attachments_group on public.korlix_social_attachments(group_id);
create index korlix_social_attachments_expiry on public.korlix_social_attachments(expires_at) where state<>'attached';
alter table public.korlix_social_attachments enable row level security;
revoke all on public.korlix_social_attachments from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_attachments to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-social-attachments','korlix-social-attachments',false,20971520,null)
 on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=null;
create policy korlix_social_attachments_server_only on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'korlix-social-attachments') with check(bucket_id<>'korlix-social-attachments');

create function public.korlix_social_attachment_card(a public.korlix_social_attachments) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',a.id,'kind',a.kind,'filename',a.filename,'content_type',a.content_type,
 'size_bytes',a.size_bytes,'duration_ms',a.duration_ms,'object_path',a.object_path);
$$;
create function public.korlix_social_attach_card(card jsonb,is_group boolean) returns jsonb
language sql stable security invoker set search_path='' as $$
 select card||jsonb_build_object('attachment',case when coalesce((card->>'deleted')::boolean,true) then null else (
 select public.korlix_social_attachment_card(a) from public.korlix_social_attachments a
 where (case when is_group then a.group_message else a.direct_message end)=(card->>'id')::uuid
 and a.state='attached' and a.purged_at is null) end);
$$;

-- Preserve the mature connection, block, group consent and join-history checks.
create function public.korlix_social_media_chat_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 me public.korlix_social_profiles; a public.korlix_social_attachments;
 result jsonb; aid uuid; mid uuid; existing_aid uuid; existing_message boolean; body_text text;
 is_group boolean:=left(p_action,6)='group_';
begin
 if p_action not in ('send','messages','message','group_send','group_messages','group_message') then raise exception 'Chat action not found.' using errcode='P0002'; end if;
 if p_action in ('send','group_send') then
  select * into me from public.korlix_social_profiles where user_id=p_actor and not suspended;
  if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
  mid:=(p_data->>'id')::uuid; aid:=(p_data->>'attachment_id')::uuid;
  if is_group then select exists(select 1 from public.korlix_social_group_messages where id=mid) into existing_message;
  else select exists(select 1 from public.korlix_social_messages where id=mid) into existing_message; end if;
  select id into existing_aid from public.korlix_social_attachments where (case when is_group then group_message else direct_message end)=mid;
  if existing_message and existing_aid is distinct from aid then raise exception 'This message request already has different content. Use a new message.' using errcode='23505'; end if;
  if aid is not null then
   select * into a from public.korlix_social_attachments where id=aid;
   if a.id is null or a.owner is distinct from me.id or a.purged_at is not null or a.state='uploading'
    or (is_group and a.group_id is distinct from (p_data->>'group')::uuid)
    or (not is_group and a.peer is distinct from (p_data->>'peer')::uuid)
    or (a.state='attached' and (case when is_group then a.group_message else a.direct_message end) is distinct from mid)
    or (a.state<>'attached' and a.expires_at<=now())
   then raise exception 'This attachment is unavailable for this conversation. Attach it again.' using errcode='42501'; end if;
   body_text:=btrim(coalesce(p_data->>'body',''));
   if body_text='' then body_text:=case a.kind when 'image' then 'Photo' when 'voice' then 'Voice note' else a.filename end; end if;
   p_data:=p_data||jsonb_build_object('body',body_text);
  end if;
 end if;
 if is_group then result:=public.korlix_social_groups_v1(p_actor,p_action,p_data);
 else result:=public.korlix_social_chat_v1(p_actor,p_action,p_data); end if;
 if p_action in ('send','group_send') then
  if aid is not null then update public.korlix_social_attachments set state='attached',direct_message=case when not is_group then mid end,group_message=case when is_group then mid end where id=aid; end if;
 elsif p_action in ('message','group_message') then
  result:=jsonb_set(result,'{message}',public.korlix_social_attach_card(result->'message',is_group));
 else
  result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(public.korlix_social_attach_card(value,is_group) order by ord) from jsonb_array_elements(result->'items') with ordinality x(value,ord)),'[]'::jsonb));
 end if;
 return result;
end $$;

create function public.korlix_social_attachment_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 me public.korlix_social_profiles; a public.korlix_social_attachments;
 aid uuid; target uuid; gid uuid; result jsonb; ext text;
begin
 select * into me from public.korlix_social_profiles where user_id=p_actor and not suspended;
 if me.id is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action not in ('access','prepare','ready','link','discard') then raise exception 'Attachment action not found.' using errcode='P0002'; end if;
 if p_action in ('access','prepare') then
  target:=(p_data->>'peer')::uuid; gid:=(p_data->>'group')::uuid;
  if (target is null)=(gid is null) then raise exception 'Choose one conversation.'; end if;
  if p_action='prepare' then perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0)); end if;
  if gid is not null then perform public.korlix_social_groups_v1(p_actor,'group_messages',jsonb_build_object('group',gid));
  else perform public.korlix_social_chat_v1(p_actor,'messages',jsonb_build_object('peer',target)); end if;
  if p_action='access' then return jsonb_build_object('ok',true); end if;
  aid:=(p_data->>'id')::uuid; ext:=p_data->>'extension';
  if aid is null or ext is null or ext!~'^[a-z0-9]{1,8}$' then raise exception 'Invalid attachment request.'; end if;
  select * into a from public.korlix_social_attachments where id=aid;
  if found then
   if a.owner is distinct from me.id or a.peer is distinct from target or a.group_id is distinct from gid or a.checksum is distinct from p_data->>'checksum' or a.filename is distinct from p_data->>'filename' or a.kind is distinct from p_data->>'kind' or a.purged_at is not null or (a.state<>'attached' and a.expires_at<=now()) then raise exception 'Choose a new attachment request.' using errcode='23505'; end if;
   return jsonb_build_object('attachment',public.korlix_social_attachment_card(a),'state',a.state);
  end if;
  perform public.korlix_social_limit(p_actor,'attachment-minute',20,60);
  perform public.korlix_social_limit(p_actor,'attachment-day',100,86400);
  if coalesce((select sum(size_bytes) from public.korlix_social_attachments where owner=me.id and purged_at is null),0)+(p_data->>'size_bytes')::bigint>262144000 then raise exception 'Your shared attachments have reached 250 MB. Remove old attachments before uploading more.' using errcode='54000'; end if;
  insert into public.korlix_social_attachments(id,owner,peer,group_id,kind,filename,content_type,size_bytes,duration_ms,object_path,checksum)
   values(aid,me.id,target,gid,p_data->>'kind',p_data->>'filename',p_data->>'content_type',(p_data->>'size_bytes')::integer,(p_data->>'duration_ms')::integer,me.id::text||'/'||aid::text||'.'||ext,p_data->>'checksum') returning * into a;
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
  if a.expires_at<=now() and a.state<>'attached' then raise exception 'Attachment expired. Attach it again.'; end if;
  update public.korlix_social_attachments set state=case when state='uploading' then 'ready' else state end where id=a.id returning * into a;
 elsif p_action='link' then
  if a.state='attached' then
   if a.group_message is not null then result:=public.korlix_social_groups_v1(p_actor,'group_message',jsonb_build_object('group',a.group_id,'id',a.group_message));
   elsif a.direct_message is not null then result:=public.korlix_social_chat_v1(p_actor,'message',jsonb_build_object('peer',case when me.id=a.owner then a.peer else a.owner end,'id',a.direct_message));
   else raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
   if coalesce((result->'message'->>'deleted')::boolean,true) then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
  elsif a.owner is distinct from me.id or a.state<>'ready' or a.expires_at<=now() then raise exception 'Attachment unavailable.' using errcode='P0002'; end if;
 end if;
 return jsonb_build_object('attachment',public.korlix_social_attachment_card(a));
end $$;

create function public.korlix_social_attachment_removed() returns trigger
language plpgsql security invoker set search_path='' as $$ begin
 if new.deleted and not old.deleted then
  update public.korlix_social_attachments set purged_at=now()
   where case when tg_table_name='korlix_social_messages' then direct_message=new.id else group_message=new.id end;
 end if;
 return new;
end $$;
create trigger korlix_social_direct_attachment_removed after update of deleted on public.korlix_social_messages for each row execute function public.korlix_social_attachment_removed();
create trigger korlix_social_group_attachment_removed after update of deleted on public.korlix_social_group_messages for each row execute function public.korlix_social_attachment_removed();

-- Maintenance is service-only: remove Storage objects first, then acknowledge rows.
create function public.korlix_social_attachment_cleanup(p_ids uuid[] default null) returns jsonb
language plpgsql security invoker set search_path='' as $$ begin
 if p_ids is not null then
  delete from public.korlix_social_attachments where id=any(p_ids) and (purged_at is not null or owner is null or (state<>'attached' and expires_at<=now()) or (state='attached' and direct_message is null and group_message is null));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'path',object_path)) from (
  select id,object_path from public.korlix_social_attachments where purged_at is not null or owner is null or (state<>'attached' and expires_at<=now()) or (state='attached' and direct_message is null and group_message is null) order by created_at limit 100
 )x),'[]'::jsonb);
end $$;
revoke all on function public.korlix_social_attachment_card(public.korlix_social_attachments),public.korlix_social_attach_card(jsonb,boolean),public.korlix_social_media_chat_v1(uuid,text,jsonb),public.korlix_social_attachment_v1(uuid,text,jsonb),public.korlix_social_attachment_removed(),public.korlix_social_attachment_cleanup(uuid[]) from public,anon,authenticated;
grant execute on function public.korlix_social_attachment_card(public.korlix_social_attachments),public.korlix_social_attach_card(jsonb,boolean),public.korlix_social_media_chat_v1(uuid,text,jsonb),public.korlix_social_attachment_v1(uuid,text,jsonb),public.korlix_social_attachment_removed(),public.korlix_social_attachment_cleanup(uuid[]) to service_role;
