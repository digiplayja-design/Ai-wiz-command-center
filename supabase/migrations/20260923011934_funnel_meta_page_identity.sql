begin;
-- Page identity only: no Page access tokens or ad-publishing authorization.
-- Existing private RLS/grants and encrypted user credentials are preserved.
alter table public.korlix_meta_connections
  add column pages jsonb not null default '[]' check(jsonb_typeof(pages)='array' and jsonb_array_length(pages)<=500),
  add column selected_page text check(selected_page is null or selected_page ~ '^[0-9]{1,40}$'),
  add column pages_refreshed_at timestamptz,
  add column pages_access_denied boolean not null default false;

create or replace function public.korlix_meta_v1(p_actor uuid,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_meta_oauth_attempts; c public.korlix_meta_connections; result jsonb; owner_id uuid;
begin
  if p_action='deauthorize' then
    -- The server verifies Meta's signature before this service-only command.
    delete from public.korlix_meta_connections where meta_user_id=p_data->>'meta_user_id' and connected_at<=to_timestamp((p_data->>'issued_at')::bigint);
    delete from public.korlix_meta_oauth_attempts where meta_user_id=p_data->>'meta_user_id' and created_at<=to_timestamp((p_data->>'issued_at')::bigint);
    return '{}'::jsonb;
  end if;
  if p_action='consume' then
    select user_id into owner_id from public.korlix_meta_oauth_attempts where id=(p_data->>'id')::uuid and state_hash=p_data->>'state_hash';
    if owner_id is null then raise exception 'This connection link is invalid or expired.' using errcode='P0002'; end if;
  else owner_id:=p_actor; end if;
  if owner_id is null or not exists(select 1 from public.user_profiles where id=owner_id and lower(trim(tier))='enterprise') then
    raise exception 'Meta connections require Enterprise.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('korlix-meta:'||owner_id::text,0));
  delete from public.korlix_meta_oauth_attempts where user_id=owner_id and expires_at<=now();
  select * into a from public.korlix_meta_oauth_attempts where user_id=owner_id for update;
  select * into c from public.korlix_meta_connections where user_id=owner_id for update;
  if p_action='status' then
    return jsonb_build_object('connection',case when c.user_id is null then null else (to_jsonb(c)-array['sealed','config_hash','meta_user_id','user_id','binding_id'])||jsonb_build_object('needs_reconnect',c.needs_reconnect or c.expires_at<=now()+interval '60 seconds' or c.config_hash is distinct from p_data->>'config_hash') end,'pending',case when a.user_id is null then null else jsonb_build_object('phase',a.phase,'expires_at',a.expires_at) end);
  elsif p_action='begin' then
    if a.user_id is not null and a.created_at>now()-interval '30 seconds' then raise exception 'Wait 30 seconds before starting another connection.' using errcode='54000'; end if;
    delete from public.korlix_meta_oauth_attempts where user_id=owner_id;
    insert into public.korlix_meta_oauth_attempts(user_id,id,state_hash,proof_hash,config_hash) values(owner_id,(p_data->>'id')::uuid,p_data->>'state_hash',p_data->>'proof_hash',p_data->>'config_hash');
    return '{}'::jsonb;
  elsif p_action='consume' then
    if a.id is distinct from (p_data->>'id')::uuid or a.state_hash is distinct from p_data->>'state_hash' or a.phase<>'waiting' or a.config_hash is distinct from p_data->>'config_hash' then raise exception 'This connection link is invalid, expired or already used.' using errcode='40001'; end if;
    update public.korlix_meta_oauth_attempts set phase='exchanging' where user_id=owner_id;
    return jsonb_build_object('user_id',owner_id,'id',a.id);
  elsif p_action in ('candidate','failed') then
    if a.id is distinct from (p_data->>'id')::uuid or a.phase<>'exchanging' then raise exception 'This connection attempt is no longer active.' using errcode='40001'; end if;
    if p_action='failed' then update public.korlix_meta_oauth_attempts set phase='failed',candidate=null where user_id=owner_id;
    else
      if (p_data->>'expires_at')::timestamptz<=now()+interval '60 seconds' then raise exception 'Reconnect to renew Meta access.'; end if;
      update public.korlix_meta_oauth_attempts set phase='ready',candidate=p_data->'sealed',meta_user_id=p_data->>'meta_user_id',token_expires_at=(p_data->>'expires_at')::timestamptz where user_id=owner_id;
    end if;
    return '{}'::jsonb;
  elsif p_action='finish' then
    if a.id is distinct from (p_data->>'id')::uuid or a.proof_hash is distinct from p_data->>'proof_hash' or a.config_hash is distinct from p_data->>'config_hash' then raise exception 'Start a new connection from this KORLIX window.' using errcode='40001'; end if;
    if a.phase='failed' then raise exception 'Meta authorization was not completed. Start again.'; end if;
    if a.phase<>'ready' then raise exception 'Complete the Meta sign-in first, then try Finish connection again.' using errcode='40900'; end if;
    if a.token_expires_at<=now()+interval '60 seconds' then raise exception 'Reconnect to renew Meta access.'; end if;
    insert into public.korlix_meta_connections(user_id,binding_id,config_hash,meta_user_id,sealed,expires_at,version)
      values(owner_id,a.id,a.config_hash,a.meta_user_id,a.candidate,a.token_expires_at,nextval('public.korlix_meta_version_seq'))
      on conflict(user_id) do update set binding_id=excluded.binding_id,config_hash=excluded.config_hash,meta_user_id=excluded.meta_user_id,sealed=excluded.sealed,expires_at=excluded.expires_at,version=excluded.version,accounts='[]',selected_account=null,connected_at=now(),refreshed_at=null,needs_reconnect=false,pages='[]',selected_page=null,pages_refreshed_at=null,pages_access_denied=false;
    delete from public.korlix_meta_oauth_attempts where user_id=owner_id;
    return '{}'::jsonb;
  elsif p_action='disconnect' then
    if c.user_id is not null and (p_data->>'version')::integer is distinct from c.version then raise exception 'The connection changed. Refresh before disconnecting.' using errcode='40001'; end if;
    delete from public.korlix_meta_connections where user_id=owner_id;
    delete from public.korlix_meta_oauth_attempts where user_id=owner_id;
    return '{}'::jsonb;
  elsif p_action='secret' then
    if c.user_id is null then raise exception 'Connect Meta first.' using errcode='P0002'; end if;
    return to_jsonb(c);
  elsif p_action in ('pages','pagesDenied','clearPage') then
    if c.user_id is null or (p_data->>'version')::integer is distinct from c.version or c.selected_account is null or c.selected_account is distinct from p_data->>'account_id' then raise exception 'The Meta connection or selected account changed. Check your connection.' using errcode='40001'; end if;
    if c.needs_reconnect or c.expires_at<=now()+interval '60 seconds' or c.config_hash is distinct from p_data->>'config_hash' then raise exception 'Reconnect Meta to renew access.' using errcode='40001'; end if;
    if p_action='pagesDenied' then
      update public.korlix_meta_connections set pages='[]',selected_page=null,pages_refreshed_at=null,pages_access_denied=true,version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    elsif p_action='clearPage' then
      update public.korlix_meta_connections set selected_page=null,version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    else
      if jsonb_typeof(p_data->'pages') is distinct from 'array' then raise exception 'Invalid Page list.'; end if;
      if jsonb_array_length(p_data->'pages')>500 or exists(select 1 from jsonb_array_elements(p_data->'pages') p where jsonb_typeof(p) is distinct from 'object' or not (p ?& array['id','name','category']) or p-array['id','name','category']<>'{}'::jsonb or jsonb_typeof(p->'id') is distinct from 'string' or (p->>'id') !~ '^[0-9]{1,40}$' or jsonb_typeof(p->'name') is distinct from 'string' or length(trim(p->>'name')) not between 1 and 200 or length(p->>'name')>200 or jsonb_typeof(p->'category') is distinct from 'string' or length(p->>'category')>200) or (select count(distinct p->>'id') from jsonb_array_elements(p_data->'pages') p)<>jsonb_array_length(p_data->'pages') then raise exception 'Invalid Page list.'; end if;
      if p_data ? 'page_id' and not exists(select 1 from jsonb_array_elements(p_data->'pages') p where p->>'id'=p_data->>'page_id') then raise exception 'Choose a Page currently shared with KORLIX.'; end if;
      update public.korlix_meta_connections set pages=p_data->'pages',selected_page=case when p_data ? 'page_id' then p_data->>'page_id' when exists(select 1 from jsonb_array_elements(p_data->'pages') p where p->>'id'=c.selected_page) then c.selected_page else null end,pages_refreshed_at=now(),pages_access_denied=false,version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    end if;
    return '{}'::jsonb;
  elsif p_action in ('accounts','select','invalid') then
    if c.user_id is null or (p_data->>'version')::integer is distinct from c.version then raise exception 'The connection changed. Refresh and try again.' using errcode='40001'; end if;
    if p_action='invalid' then
      update public.korlix_meta_connections set needs_reconnect=true,accounts='[]',selected_account=null,pages='[]',selected_page=null,pages_refreshed_at=null,pages_access_denied=false,version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    elsif p_action='accounts' then
      update public.korlix_meta_connections set pages=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.pages else '[]'::jsonb end,selected_page=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.selected_page else null end,pages_refreshed_at=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.pages_refreshed_at else null end,pages_access_denied=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.pages_access_denied else false end,accounts=p_data->'accounts',selected_account=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.selected_account else null end,refreshed_at=now(),version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    else
      if not exists(select 1 from jsonb_array_elements(c.accounts) x where x->>'id'=p_data->>'account_id') then raise exception 'Refresh your accounts and select an available account.'; end if;
      update public.korlix_meta_connections set pages='[]',selected_page=null,pages_refreshed_at=null,pages_access_denied=false,selected_account=p_data->>'account_id',version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    end if;
    return '{}'::jsonb;
  else raise exception 'Unknown Meta connection action.'; end if;
end $$;
revoke all on function public.korlix_meta_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_meta_v1(uuid,text,jsonb) to service_role;
commit;
