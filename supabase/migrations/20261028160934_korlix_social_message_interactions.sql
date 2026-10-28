-- Message reactions and plain-text style ranges. All access stays behind the
-- existing authenticated conversation checks; no client table grants.
alter table public.korlix_social_messages add column formatting jsonb not null default '[]';
alter table public.korlix_social_group_messages add column formatting jsonb not null default '[]';
create table public.korlix_social_message_reactions (
 direct_message uuid references public.korlix_social_messages(id) on delete cascade,
 group_message uuid references public.korlix_social_group_messages(id) on delete cascade,
 reactor uuid not null references public.korlix_social_profiles(id) on delete cascade,
 emoji text not null check(char_length(emoji) between 1 and 16),
 check((direct_message is null) <> (group_message is null))
);
create unique index korlix_social_reaction_direct on public.korlix_social_message_reactions(direct_message,reactor) where direct_message is not null;
create unique index korlix_social_reaction_group on public.korlix_social_message_reactions(group_message,reactor) where group_message is not null;
create index korlix_social_reaction_actor on public.korlix_social_message_reactions(reactor);
alter table public.korlix_social_message_reactions enable row level security;
revoke all on public.korlix_social_message_reactions from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_message_reactions to service_role;

-- Offsets are Unicode code points, not UTF-16 units or encoded bytes.
create function public.korlix_social_validate_formatting(body text, ranges jsonb) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
declare r jsonb; first_pos integer; last_pos integer;
begin
 if jsonb_typeof(ranges) is distinct from 'array' then raise exception 'Choose valid text formatting.'; end if;
 if jsonb_array_length(ranges)>100 then raise exception 'Use fewer than 101 text styles.'; end if;
 for r in select value from jsonb_array_elements(ranges) loop
  if jsonb_typeof(r) is distinct from 'object' or coalesce(r->>'style','') not in ('bold','italic','strike','highlight')
   or jsonb_typeof(r->'start') is distinct from 'number' or jsonb_typeof(r->'end') is distinct from 'number'
   or coalesce(r->>'start','') !~ '^[0-9]{1,4}$' or coalesce(r->>'end','') !~ '^[0-9]{1,4}$'
   then raise exception 'Choose valid text formatting.'; end if;
  first_pos:=(r->>'start')::integer; last_pos:=(r->>'end')::integer;
  if first_pos<0 or last_pos<=first_pos or last_pos>char_length(body) then raise exception 'Text formatting is outside the message.'; end if;
 end loop;
 return coalesce((select jsonb_agg(item order by item->>'style',(item->>'start')::integer,(item->>'end')::integer)
  from (select distinct jsonb_build_object('style',value->>'style','start',(value->>'start')::integer,'end',(value->>'end')::integer) item from jsonb_array_elements(ranges))x),'[]');
end $$;

create function public.korlix_social_interaction_card(card jsonb,is_group boolean,viewer uuid) returns jsonb
language plpgsql stable security invoker set search_path=public as $$
declare result jsonb; styles jsonb; reactions jsonb; mid uuid; gid uuid; message_seq bigint;
begin
 if card is null or card='null'::jsonb then return card; end if;
 if coalesce((card->>'deleted')::boolean,true) then return card||jsonb_build_object('formatting','[]'::jsonb,'reactions','[]'::jsonb); end if;
 mid:=(card->>'id')::uuid;
 if is_group then select formatting,group_id,seq into styles,gid,message_seq from korlix_social_group_messages where id=mid;
 else select formatting into styles from korlix_social_messages where id=mid; end if;
 select coalesce(jsonb_agg(jsonb_build_object('emoji',emoji,'count',n,'mine',mine) order by n desc,emoji),'[]') into reactions from (
  select r.emoji,count(*) n,bool_or(r.reactor=viewer) mine
  from korlix_social_message_reactions r join korlix_social_profiles p on p.id=r.reactor
  where (case when is_group then r.group_message else r.direct_message end)=mid
   and not p.suspended and not korlix_social_blocked(viewer,p.id)
   and (not is_group or exists(select 1 from korlix_social_group_members gm where gm.group_id=gid and gm.member=p.id and gm.state='accepted' and gm.joined_after<message_seq))
  group by r.emoji
 )x;
 result:=card||jsonb_build_object('formatting',coalesce(styles,'[]'),'reactions',reactions);
 if jsonb_typeof(card->'reply')='object' then result:=jsonb_set(result,'{reply}',korlix_social_interaction_card(card->'reply',is_group,viewer)); end if;
 return result;
end $$;

-- Keep the mature attachment, reply, block, membership and Auto Dump logic.
alter function public.korlix_social_media_chat_v1(uuid,text,jsonb) rename to korlix_social_media_before_interactions_v1;
create function public.korlix_social_media_chat_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare result jsonb; me uuid; styles jsonb; previous_styles jsonb;
 is_group boolean:=left(p_action,6)='group_'; mid uuid;
begin
 select id into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action in ('send','group_send') then
  perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
  styles:=korlix_social_validate_formatting(trim(coalesce(p_data->>'body','')),coalesce(p_data->'formatting','[]'));
  mid:=(p_data->>'id')::uuid;
  if is_group then select formatting into previous_styles from korlix_social_group_messages where id=mid;
  else select formatting into previous_styles from korlix_social_messages where id=mid; end if;
 end if;
 result:=korlix_social_media_before_interactions_v1(p_actor,p_action,p_data);
 if p_action in ('send','group_send') then
  if previous_styles is not null and previous_styles<>styles then raise exception 'This message request already has different formatting. Use a new message.' using errcode='23505'; end if;
  if is_group then update korlix_social_group_messages set formatting=styles where id=mid;
  else update korlix_social_messages set formatting=styles where id=mid; end if;
 elsif p_action in ('message','group_message') then
  result:=jsonb_set(result,'{message}',korlix_social_interaction_card(result->'message',is_group,me));
 elsif p_action in ('messages','group_messages') then
  result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(korlix_social_interaction_card(value,is_group,me) order by ord) from jsonb_array_elements(result->'items') with ordinality x(value,ord)),'[]'));
 end if;
 return result;
end $$;

create function public.korlix_social_react_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me uuid; result jsonb; card jsonb; mid uuid; gid uuid; target uuid; emoji_value text; removed boolean;
begin
 if p_action<>'react' then raise exception 'Reaction action not found.' using errcode='P0002'; end if;
 select id into me from korlix_social_profiles where user_id=p_actor and not suspended;
 if me is null then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 mid:=(p_data->>'id')::uuid; gid:=(p_data->>'group')::uuid; target:=(p_data->>'peer')::uuid;
 if mid is null or (gid is null)=(target is null) or not(p_data ? 'emoji') then raise exception 'Choose a message and reaction.'; end if;
 if jsonb_typeof(p_data->'emoji') not in ('string','null') then raise exception 'Choose a supported reaction.'; end if;
 emoji_value:=p_data->>'emoji';
 if emoji_value is not null and emoji_value<>all(array['👍','🙂','😂','😢','❤️','🎉','😀','😊','🤣','😭','😍','🥰','😘','😎','🤩','🤔','🙃','😉','😅','😮','😴','🥳','🤗','🫡','🤝','👎','👏','🙌','🙏','💪','👋','✌️','👌','🩵','💜','💚','💛','💯','🔥','✨','✅','😡','😱','🤯','🥹','👍🏻','👍🏼','👍🏽','👍🏾','👍🏿','👏🏻','👏🏼','👏🏽','👏🏾','👏🏿','🙏🏻','🙏🏼','🙏🏽','🙏🏾','🙏🏿']) then raise exception 'Choose a supported reaction.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('social-actor:'||p_actor::text,0));
 -- Exact-message lookup enforces current connection/group membership, join
 -- history, blocks, suspension, deletion and personal/everyone Auto Dump.
 result:=korlix_social_media_chat_v1(p_actor,case when gid is null then 'message' else 'group_message' end,p_data);
 card:=result->'message';
 if coalesce((card->>'deleted')::boolean,true) then raise exception 'This message is unavailable.' using errcode='P0002'; end if;
 if gid is null then select deleted into removed from korlix_social_messages where id=mid for update;
 else select deleted into removed from korlix_social_group_messages where id=mid for update; end if;
 if coalesce(removed,true) or korlix_social_dumped(me,case when gid is null then 'direct' else 'group' end,mid) then raise exception 'This message is unavailable.' using errcode='P0002'; end if;
 perform korlix_social_limit(p_actor,'reaction-minute',120,60);
 if gid is null then
  if emoji_value is null then delete from korlix_social_message_reactions where direct_message=mid and reactor=me;
  else insert into korlix_social_message_reactions(direct_message,reactor,emoji) values(mid,me,emoji_value)
   on conflict(direct_message,reactor) where direct_message is not null do update set emoji=excluded.emoji; end if;
 else
  if emoji_value is null then delete from korlix_social_message_reactions where group_message=mid and reactor=me;
  else insert into korlix_social_message_reactions(group_message,reactor,emoji) values(mid,me,emoji_value)
   on conflict(group_message,reactor) where group_message is not null do update set emoji=excluded.emoji; end if;
 end if;
 return jsonb_build_object('id',mid,'reactions',korlix_social_interaction_card(card,gid is not null,me)->'reactions');
end $$;

create function public.korlix_social_interactions_removed() returns trigger
language plpgsql security invoker set search_path=public as $$ begin
 if new.deleted then
  new.formatting:='[]';
  if tg_table_name='korlix_social_messages' then delete from korlix_social_message_reactions where direct_message=new.id;
  else delete from korlix_social_message_reactions where group_message=new.id; end if;
 end if;
 return new;
end $$;
create trigger korlix_social_direct_interactions_removed before update of deleted on public.korlix_social_messages for each row execute function public.korlix_social_interactions_removed();
create trigger korlix_social_group_interactions_removed before update of deleted on public.korlix_social_group_messages for each row execute function public.korlix_social_interactions_removed();
revoke all on function public.korlix_social_validate_formatting(text,jsonb),public.korlix_social_interaction_card(jsonb,boolean,uuid),public.korlix_social_media_chat_v1(uuid,text,jsonb),public.korlix_social_react_v1(uuid,text,jsonb),public.korlix_social_interactions_removed() from public,anon,authenticated;
grant execute on function public.korlix_social_validate_formatting(text,jsonb),public.korlix_social_interaction_card(jsonb,boolean,uuid),public.korlix_social_media_chat_v1(uuid,text,jsonb),public.korlix_social_react_v1(uuid,text,jsonb),public.korlix_social_interactions_removed() to service_role;
