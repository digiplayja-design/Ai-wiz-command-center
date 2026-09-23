begin;
-- Server-only Google credentials. Versions never repeat across reconnects.
create sequence public.korlix_google_ads_version_seq as integer;
revoke all on sequence public.korlix_google_ads_version_seq from public,anon,authenticated;
grant usage on sequence public.korlix_google_ads_version_seq to service_role;
create table public.korlix_google_ads_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  binding_id uuid not null,
  config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
  sealed jsonb not null,
  refresh_expires_at timestamptz,
  roots jsonb not null default '[]' check(jsonb_typeof(roots)='array' and jsonb_array_length(roots)<=500),
  root_id text check(root_id ~ '^[0-9]{10}$'),
  root_name text,
  login_customer_id text check(login_customer_id ~ '^[0-9]{10}$'),
  accounts jsonb not null default '[]' check(jsonb_typeof(accounts)='array' and jsonb_array_length(accounts)<=500),
  selected_account text check(selected_account ~ '^[0-9]{10}$'),
  version integer not null default nextval('public.korlix_google_ads_version_seq'),
  connected_at timestamptz not null default now(),
  refreshed_at timestamptz,
  needs_reconnect boolean not null default false,
  check(coalesce(sealed ?& array['v','iv','tag','ciphertext'] and sealed-array['v','iv','tag','ciphertext']='{}'::jsonb and sealed->>'v'='1' and sealed->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and sealed->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(sealed->>'ciphertext') between 1 and 20000,false))
);
create table public.korlix_google_ads_oauth_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  id uuid not null unique,
  state_hash text not null check(state_hash ~ '^[a-f0-9]{64}$'),
  proof_hash text not null check(proof_hash ~ '^[a-f0-9]{64}$'),
  config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
  phase text not null default 'waiting' check(phase in ('waiting','exchanging','ready','failed')),
  verifier_sealed jsonb,
  candidate jsonb,
  refresh_expires_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '10 minutes',
  check(verifier_sealed is null or coalesce(verifier_sealed ?& array['v','iv','tag','ciphertext'] and verifier_sealed-array['v','iv','tag','ciphertext']='{}'::jsonb and verifier_sealed->>'v'='1' and verifier_sealed->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and verifier_sealed->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(verifier_sealed->>'ciphertext') between 1 and 20000,false)),
  check(candidate is null or coalesce(candidate ?& array['v','iv','tag','ciphertext'] and candidate-array['v','iv','tag','ciphertext']='{}'::jsonb and candidate->>'v'='1' and candidate->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and candidate->>'tag' ~ '^[A-Za-z0-9_-]{22}$' and length(candidate->>'ciphertext') between 1 and 20000,false))
);
alter table public.korlix_google_ads_connections enable row level security;
alter table public.korlix_google_ads_oauth_attempts enable row level security;
revoke all on public.korlix_google_ads_connections,public.korlix_google_ads_oauth_attempts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_google_ads_connections,public.korlix_google_ads_oauth_attempts to service_role;

create function public.korlix_google_ads_v1(p_actor uuid,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.korlix_google_ads_oauth_attempts; c public.korlix_google_ads_connections; owner_id uuid; selected jsonb;
begin
  if p_action='consume' then
    select user_id into owner_id from public.korlix_google_ads_oauth_attempts where id=(p_data->>'id')::uuid and state_hash=p_data->>'state_hash';
    if owner_id is null then raise exception 'This Google connection link is invalid or expired.' using errcode='P0002'; end if;
  else owner_id:=p_actor; end if;
  if owner_id is null or not exists(select 1 from public.user_profiles where id=owner_id and lower(trim(tier))='enterprise') then
    raise exception 'Google Ads connections require Enterprise.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('korlix-google-ads:'||owner_id::text,0));
  delete from public.korlix_google_ads_oauth_attempts where user_id=owner_id and expires_at<=now();
  select * into a from public.korlix_google_ads_oauth_attempts where user_id=owner_id for update;
  select * into c from public.korlix_google_ads_connections where user_id=owner_id for update;
  if p_action='status' then
    -- Explicit projection: new private columns can never accidentally reach UI.
    return jsonb_build_object('connection',case when c.user_id is null then null else jsonb_build_object(
      'version',c.version,'roots',c.roots,'root_id',c.root_id,'root_name',c.root_name,'login_customer_id',c.login_customer_id,
      'accounts',c.accounts,'selected_account',c.selected_account,'connected_at',c.connected_at,'refreshed_at',c.refreshed_at,
      'needs_reconnect',c.needs_reconnect or coalesce(c.refresh_expires_at<=now()+interval '60 seconds',false) or c.config_hash is distinct from p_data->>'config_hash') end,
      'pending',case when a.user_id is null then null else jsonb_build_object('phase',a.phase,'expires_at',a.expires_at) end);
  elsif p_action='begin' then
    if a.user_id is not null and a.created_at>now()-interval '30 seconds' then raise exception 'Wait 30 seconds before starting another Google connection.' using errcode='54000'; end if;
    if p_data->'verifier_sealed' is null or p_data->'verifier_sealed'='null'::jsonb then raise exception 'Start a new Google connection.'; end if;
    delete from public.korlix_google_ads_oauth_attempts where user_id=owner_id;
    insert into public.korlix_google_ads_oauth_attempts(user_id,id,state_hash,proof_hash,config_hash,verifier_sealed)
      values(owner_id,(p_data->>'id')::uuid,p_data->>'state_hash',p_data->>'proof_hash',p_data->>'config_hash',p_data->'verifier_sealed');
  elsif p_action='consume' then
    if a.id is distinct from (p_data->>'id')::uuid or a.state_hash is distinct from p_data->>'state_hash' or a.phase<>'waiting' or a.config_hash is distinct from p_data->>'config_hash' or a.verifier_sealed is null then raise exception 'This Google connection link is invalid, expired or already used.' using errcode='40001'; end if;
    update public.korlix_google_ads_oauth_attempts set phase='exchanging',verifier_sealed=null where user_id=owner_id;
    return jsonb_build_object('user_id',owner_id,'id',a.id,'verifier_sealed',a.verifier_sealed);
  elsif p_action in ('candidate','failed') then
    if a.id is distinct from (p_data->>'id')::uuid or a.phase<>'exchanging' then raise exception 'This Google connection attempt is no longer active.' using errcode='40001'; end if;
    if p_action='failed' then update public.korlix_google_ads_oauth_attempts set phase='failed',candidate=null,verifier_sealed=null where user_id=owner_id;
    else
      if p_data->'sealed' is null or p_data->'sealed'='null'::jsonb or (p_data->>'refresh_expires_at')::timestamptz<=now()+interval '60 seconds' then raise exception 'Reconnect to renew Google access.'; end if;
      update public.korlix_google_ads_oauth_attempts set phase='ready',candidate=p_data->'sealed',refresh_expires_at=(p_data->>'refresh_expires_at')::timestamptz where user_id=owner_id;
    end if;
  elsif p_action='finish' then
    if a.id is distinct from (p_data->>'id')::uuid or a.proof_hash is distinct from p_data->>'proof_hash' or a.config_hash is distinct from p_data->>'config_hash' then raise exception 'Start a new Google connection from this KORLIX window.' using errcode='40001'; end if;
    if a.phase='failed' then raise exception 'Google authorization was not completed. Start again.'; end if;
    if a.phase<>'ready' then raise exception 'Complete Google sign-in first, then try Finish Google connection again.' using errcode='40001'; end if;
    if a.candidate is null or a.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'Reconnect to renew Google access.'; end if;
    insert into public.korlix_google_ads_connections(user_id,binding_id,config_hash,sealed,refresh_expires_at,version)
      values(owner_id,a.id,a.config_hash,a.candidate,a.refresh_expires_at,nextval('public.korlix_google_ads_version_seq'))
      on conflict(user_id) do update set binding_id=excluded.binding_id,config_hash=excluded.config_hash,sealed=excluded.sealed,refresh_expires_at=excluded.refresh_expires_at,version=excluded.version,roots='[]',root_id=null,root_name=null,login_customer_id=null,accounts='[]',selected_account=null,connected_at=now(),refreshed_at=null,needs_reconnect=false;
    delete from public.korlix_google_ads_oauth_attempts where user_id=owner_id;
  elsif p_action='disconnect' then
    if c.user_id is not null and (p_data->>'version')::integer is distinct from c.version then raise exception 'The Google connection changed. Refresh before disconnecting.' using errcode='40001'; end if;
    delete from public.korlix_google_ads_connections where user_id=owner_id;
    delete from public.korlix_google_ads_oauth_attempts where user_id=owner_id;
  elsif p_action='secret' then
    if c.user_id is null then raise exception 'Connect Google Ads first.' using errcode='P0002'; end if;
    return to_jsonb(c);
  elsif p_action in ('roots','accounts','select','invalid') then
    if c.user_id is null or (p_data->>'version')::integer is distinct from c.version then raise exception 'The Google connection changed. Refresh and try again.' using errcode='40001'; end if;
    if p_action='invalid' then
      update public.korlix_google_ads_connections set needs_reconnect=true,roots='[]',root_id=null,root_name=null,login_customer_id=null,accounts='[]',selected_account=null,version=nextval('public.korlix_google_ads_version_seq') where user_id=owner_id;
    else
      if c.needs_reconnect or c.config_hash is distinct from p_data->>'config_hash' or c.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'Reconnect to renew Google access.' using errcode='40001'; end if;
      if p_action='roots' then
        if jsonb_typeof(p_data->'roots') is distinct from 'array' or exists(select 1 from jsonb_array_elements_text(p_data->'roots') x where x !~ '^[0-9]{10}$') then raise exception 'Invalid Google access accounts.'; end if;
        update public.korlix_google_ads_connections set roots=p_data->'roots',root_id=null,root_name=null,login_customer_id=null,accounts='[]',selected_account=null,refreshed_at=now(),version=nextval('public.korlix_google_ads_version_seq') where user_id=owner_id;
      elsif p_action='accounts' then
        if not c.roots ? (p_data->>'root_id') or p_data->>'root_id' is null or (p_data->>'login_customer_id' is not null and p_data->>'login_customer_id' is distinct from p_data->>'root_id') then raise exception 'Choose a current Google access account.'; end if;
        if jsonb_typeof(p_data->'accounts') is distinct from 'array' or exists(select 1 from jsonb_array_elements(p_data->'accounts') x where coalesce(x->>'id' ~ '^[0-9]{10}$' and x->>'manager'='false' and x->>'status'='ENABLED',false)=false) then raise exception 'Invalid Google advertising accounts.'; end if;
        update public.korlix_google_ads_connections set root_id=p_data->>'root_id',root_name=p_data->>'root_name',login_customer_id=p_data->>'login_customer_id',accounts=p_data->'accounts',
          selected_account=case when c.root_id=p_data->>'root_id' and exists(select 1 from jsonb_array_elements(p_data->'accounts') x where x->>'id'=c.selected_account) then c.selected_account else null end,
          refreshed_at=now(),version=nextval('public.korlix_google_ads_version_seq') where user_id=owner_id;
      else
        if c.root_id is distinct from p_data->>'root_id' or c.root_id is null then raise exception 'The Google access account changed.' using errcode='40001'; end if;
        select x into selected from jsonb_array_elements(c.accounts) x where x->>'id'=p_data->>'account_id' and x->>'manager'='false' and x->>'status'='ENABLED';
        if selected is null then raise exception 'Load your Google accounts and choose an active advertising account.'; end if;
        update public.korlix_google_ads_connections set selected_account=p_data->>'account_id',version=nextval('public.korlix_google_ads_version_seq') where user_id=owner_id;
      end if;
    end if;
  else raise exception 'Unknown Google connection action.'; end if;
  return '{}'::jsonb;
end $$;
revoke all on function public.korlix_google_ads_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_google_ads_v1(uuid,text,jsonb) to service_role;
commit;
