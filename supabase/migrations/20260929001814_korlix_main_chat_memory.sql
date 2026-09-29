-- Private main-chat notes. Backend verifies the caller with auth.getUser;
-- browser roles have no direct table or RPC privileges.
create table public.korlix_main_chat_memory_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
create table public.korlix_main_chat_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  category text not null default 'general' check (category in ('general','personal','preferences','work','goals')),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index korlix_main_chat_memories_owner on public.korlix_main_chat_memories(user_id, updated_at desc);
create unique index korlix_main_chat_memories_unique_note on public.korlix_main_chat_memories(user_id, lower(btrim(body)));
alter table public.korlix_main_chat_memory_settings enable row level security;
alter table public.korlix_main_chat_memories enable row level security;
revoke all on public.korlix_main_chat_memory_settings, public.korlix_main_chat_memories from public, anon, authenticated;
grant select, insert, update, delete on public.korlix_main_chat_memory_settings, public.korlix_main_chat_memories to service_role;

create function public.korlix_main_chat_memory_v1(p_actor uuid, p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_enabled boolean;
  v_id uuid;
  v_body text;
  v_category text;
  v_version integer;
  v_existing public.korlix_main_chat_memories%rowtype;
begin
  if p_actor is null then raise exception 'Sign in to use long-term memory.' using errcode='42501'; end if;
  if p_action not in ('list','save','delete','clear','settings') then raise exception 'Memory action not found.' using errcode='P0002'; end if;
  if p_action <> 'list' then
    insert into public.korlix_main_chat_memory_settings(user_id) values(p_actor) on conflict do nothing;
    select enabled into v_enabled from public.korlix_main_chat_memory_settings where user_id=p_actor for update;
  else
    select enabled into v_enabled from public.korlix_main_chat_memory_settings where user_id=p_actor;
  end if;
  v_enabled := coalesce(v_enabled, true);
  if p_action = 'settings' then
    if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'Choose whether memory is on or paused.'; end if;
    v_enabled := (p_data->>'enabled')::boolean;
    update public.korlix_main_chat_memory_settings set enabled=v_enabled, updated_at=now() where user_id=p_actor;
  elsif p_action = 'save' then
    if p_data->>'source' = 'chat' and not v_enabled then raise exception 'Memory is paused. Turn it on before saving from chat.'; end if;
    v_body := btrim(p_data->>'body');
    v_category := coalesce(p_data->>'category','general');
    if v_body is null or char_length(v_body) not between 1 and 500 then raise exception 'Write a memory between 1 and 500 characters.'; end if;
    if v_category not in ('general','personal','preferences','work','goals') then raise exception 'Choose a memory category.'; end if;
    v_id := (p_data->>'id')::uuid;
    if v_id is null then raise exception 'A memory ID is required.'; end if;
    if p_data ? 'version' then
      v_version := (p_data->>'version')::integer;
      if v_version is null or v_version < 1 then raise exception 'Refresh the memory before editing.'; end if;
      select * into v_existing from public.korlix_main_chat_memories where user_id=p_actor and id=v_id;
      if not found then raise exception 'Memory not found. Refresh the list.' using errcode='P0002'; end if;
      if v_existing.version <> v_version then raise exception 'This memory changed on another device. Refresh before editing.' using errcode='40001'; end if;
      update public.korlix_main_chat_memories set body=v_body,category=v_category,version=version+1,updated_at=now() where user_id=p_actor and id=v_id;
    else
      select * into v_existing from public.korlix_main_chat_memories where id=v_id;
      if found and (v_existing.user_id<>p_actor or v_existing.body<>v_body or v_existing.category<>v_category) then raise exception 'Use a new memory ID.' using errcode='42501'; end if;
      if not exists(select 1 from public.korlix_main_chat_memories where user_id=p_actor and lower(btrim(body))=lower(v_body)) then
        if (select count(*) from public.korlix_main_chat_memories where user_id=p_actor)>=100 then raise exception 'Your 100 memories are full. Edit or remove one before adding more.' using errcode='54000'; end if;
        insert into public.korlix_main_chat_memories(id,user_id,body,category) values(v_id,p_actor,v_body,v_category);
      end if;
    end if;
  elsif p_action = 'delete' then
    delete from public.korlix_main_chat_memories where user_id=p_actor and id=(p_data->>'id')::uuid;
  elsif p_action = 'clear' then
    if p_data->'confirm' is distinct from 'true'::jsonb then raise exception 'Confirm before forgetting all memories.'; end if;
    delete from public.korlix_main_chat_memories where user_id=p_actor;
  end if;
  return jsonb_build_object('enabled',v_enabled,'limit',100,'items',coalesce((
    select jsonb_agg(jsonb_build_object('id',id,'body',body,'category',category,'version',version,'created_at',created_at,'updated_at',updated_at) order by updated_at desc,id)
    from public.korlix_main_chat_memories where user_id=p_actor
  ),'[]'::jsonb));
end;
$$;
revoke all on function public.korlix_main_chat_memory_v1(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.korlix_main_chat_memory_v1(uuid,text,jsonb) to service_role;
