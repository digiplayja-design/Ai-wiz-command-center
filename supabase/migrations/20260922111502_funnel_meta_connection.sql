begin;
-- Never reuse versions after disconnect/reconnect; reject late responses from prior credentials.
create sequence public.korlix_meta_version_seq as integer;
revoke all on sequence public.korlix_meta_version_seq from public,anon,authenticated;
grant usage on sequence public.korlix_meta_version_seq to service_role;
create table public.korlix_meta_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  binding_id uuid not null,
  config_hash text not null,
  meta_user_id text not null check(meta_user_id ~ '^[0-9]{1,40}$'),
  sealed jsonb not null,
  expires_at timestamptz not null,
  accounts jsonb not null default '[]' check(jsonb_typeof(accounts)='array' and jsonb_array_length(accounts)<=500),
  selected_account text,
  version integer not null default nextval('public.korlix_meta_version_seq'),
  connected_at timestamptz not null default now(),
  refreshed_at timestamptz,
  needs_reconnect boolean not null default false,
  check(sealed ?& array['v','iv','tag','ciphertext'] and sealed-array['v','iv','tag','ciphertext']='{}'::jsonb and sealed->>'v'='1' and sealed->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and sealed->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(sealed->>'ciphertext') between 1 and 20000)
);
create table public.korlix_meta_oauth_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  id uuid not null unique,
  state_hash text not null check(state_hash ~ '^[a-f0-9]{64}$'),
  proof_hash text not null check(proof_hash ~ '^[a-f0-9]{64}$'),
  config_hash text not null,
  phase text not null default 'waiting' check(phase in ('waiting','exchanging','ready','failed')),
  candidate jsonb,
  meta_user_id text,
  token_expires_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '10 minutes',
  check(candidate is null or (candidate ?& array['v','iv','tag','ciphertext'] and candidate-array['v','iv','tag','ciphertext']='{}'::jsonb and candidate->>'v'='1' and candidate->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and candidate->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(candidate->>'ciphertext') between 1 and 20000))
);
alter table public.korlix_meta_connections enable row level security;
alter table public.korlix_meta_oauth_attempts enable row level security;
revoke all on public.korlix_meta_connections,public.korlix_meta_oauth_attempts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_meta_connections,public.korlix_meta_oauth_attempts to service_role;

create function public.korlix_meta_v1(p_actor uuid,p_action text,p_data jsonb default '{}')
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
      on conflict(user_id) do update set binding_id=excluded.binding_id,config_hash=excluded.config_hash,meta_user_id=excluded.meta_user_id,sealed=excluded.sealed,expires_at=excluded.expires_at,version=excluded.version,accounts='[]',selected_account=null,connected_at=now(),refreshed_at=null,needs_reconnect=false;
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
  elsif p_action in ('accounts','select','invalid') then
    if c.user_id is null or (p_data->>'version')::integer is distinct from c.version then raise exception 'The connection changed. Refresh and try again.' using errcode='40001'; end if;
    if p_action='invalid' then
      update public.korlix_meta_connections set needs_reconnect=true,accounts='[]',selected_account=null,version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    elsif p_action='accounts' then
      update public.korlix_meta_connections set accounts=p_data->'accounts',selected_account=case when exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.selected_account else null end,refreshed_at=now(),version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    else
      if not exists(select 1 from jsonb_array_elements(c.accounts) x where x->>'id'=p_data->>'account_id') then raise exception 'Refresh your accounts and select an available account.'; end if;
      update public.korlix_meta_connections set selected_account=p_data->>'account_id',version=nextval('public.korlix_meta_version_seq') where user_id=owner_id;
    end if;
    return '{}'::jsonb;
  else raise exception 'Unknown Meta connection action.'; end if;
end $$;
revoke all on function public.korlix_meta_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_meta_v1(uuid,text,jsonb) to service_role;
commit;
