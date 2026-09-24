begin;
create function public.korlix_google_upload_sealed_valid(d jsonb)
returns boolean language sql immutable security invoker set search_path=public,pg_temp as $$
 select coalesce(jsonb_typeof(d)='object' and d ?& array['v','iv','tag','ciphertext'] and d-array['v','iv','tag','ciphertext']='{}'::jsonb and d->'v'='1'::jsonb
  and jsonb_typeof(d->'iv')='string' and d->>'iv' ~ '^[A-Za-z0-9_-]{16}$' and jsonb_typeof(d->'tag')='string' and d->>'tag' ~ '^[A-Za-z0-9_-]{22}$'
  and jsonb_typeof(d->'ciphertext')='string' and length(d->>'ciphertext') between 1 and 20000 and d->>'ciphertext' ~ '^[A-Za-z0-9_-]+$',false)
$$;
revoke all on function public.korlix_google_upload_sealed_valid(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_google_upload_sealed_valid(jsonb) to service_role;
create sequence public.korlix_google_upload_version_seq as integer;
revoke all on sequence public.korlix_google_upload_version_seq from public,anon,authenticated,service_role;
grant usage on sequence public.korlix_google_upload_version_seq to service_role;
create table public.korlix_google_upload_connections (
 user_id uuid primary key references public.korlix_google_ads_connections(user_id) on delete cascade,
 binding_id uuid not null,
 ads_binding_id uuid not null,
 config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb not null check(public.korlix_google_upload_sealed_valid(sealed)),
 scopes jsonb not null check(scopes='["https://www.googleapis.com/auth/adwords","https://www.googleapis.com/auth/datamanager"]'::jsonb),
 refresh_expires_at timestamptz check(isfinite(refresh_expires_at)),
 account jsonb not null check(jsonb_typeof(account)='object'),
 root_id text not null check(root_id ~ '^[0-9]{10}$'),
 login_customer_id text check(login_customer_id ~ '^[0-9]{10}$'),
 version integer not null default nextval('public.korlix_google_upload_version_seq'),
 connected_at timestamptz not null default now(),
 checked_at timestamptz not null check(isfinite(checked_at)),
 needs_reconnect boolean not null default false,
 check(coalesce((login_customer_id is null and root_id=account->>'id') or login_customer_id=root_id,false))
);
create table public.korlix_google_upload_oauth_attempts (
 user_id uuid primary key references public.korlix_google_ads_connections(user_id) on delete cascade,
 id uuid not null unique,
 funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
 campaign_id uuid not null references public.korlix_funnel_campaigns(id) on delete cascade,
 state_hash text not null check(state_hash ~ '^[a-f0-9]{64}$'),
 proof_hash text not null check(proof_hash ~ '^[a-f0-9]{64}$'),
 config_hash text not null check(config_hash ~ '^[a-f0-9]{64}$'),
 destination_fingerprint text not null check(destination_fingerprint ~ '^[a-f0-9]{64}$'),
 authorization_version integer not null check(authorization_version>=0),
 phase text not null default 'waiting' check(phase in ('waiting','exchanging','ready','verifying','failed')),
 verifier_sealed jsonb check(verifier_sealed is null or public.korlix_google_upload_sealed_valid(verifier_sealed)),
 candidate jsonb check(candidate is null or public.korlix_google_upload_sealed_valid(candidate)),
 refresh_expires_at timestamptz check(isfinite(refresh_expires_at)),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '10 minutes'
);
alter table public.korlix_google_upload_connections enable row level security;
alter table public.korlix_google_upload_oauth_attempts enable row level security;
revoke all on public.korlix_google_upload_connections,public.korlix_google_upload_oauth_attempts from public,anon,authenticated,service_role;
grant select,insert,update,delete on public.korlix_google_upload_connections,public.korlix_google_upload_oauth_attempts to service_role;
comment on table public.korlix_google_upload_connections is 'Separate encrypted OAuth grant for future Google conversion uploads; no upload dispatch, destination permission proof or visitor data. Deleting Ads connection cascades upload access.';

create function public.korlix_google_upload_access_v1(p_actor uuid,p_action text,p_funnel uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 a public.korlix_google_upload_oauth_attempts;u public.korlix_google_upload_connections;c public.korlix_google_ads_connections;
 owner_id uuid:=p_actor;funnel_id uuid:=p_funnel;campaign_id uuid;d jsonb;ctx jsonb;fp text;ready boolean;current_access boolean;current_attempt boolean;checked timestamptz;
 allowed text[]:=array['campaign_id','ads_configured','ads_config_hash','configured','config_hash'];
begin
 if p_action is null or p_action not in ('read','begin','consume','candidate','failed','claim','finish','disconnect') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Choose an upload authorization action.';end if;
 allowed:=allowed||case p_action when 'begin' then array['version','fingerprint','confirmed','id','state_hash','proof_hash','verifier_sealed'] when 'consume' then array['id','state_hash'] when 'candidate' then array['id','sealed','scopes','refresh_expires_at'] when 'failed' then array['id'] when 'claim' then array['id','proof_hash','confirmed'] when 'finish' then array['id','checked_at'] when 'disconnect' then array['version','fingerprint','confirmed'] else array[]::text[] end;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(allowed)) then raise exception 'Unexpected upload authorization fields.';end if;
 if p_action='consume' then
  select * into a from public.korlix_google_upload_oauth_attempts where id=(p_data->>'id')::uuid and state_hash=p_data->>'state_hash';
  if a.user_id is null then raise exception 'This Google upload authorization link is invalid or expired.' using errcode='P0002';end if;
  owner_id:=a.user_id;funnel_id:=a.funnel_id;campaign_id:=a.campaign_id;
 else campaign_id:=(p_data->>'campaign_id')::uuid;end if;
 -- Existing destination context authorizes Enterprise ownership and locks the
 -- funnel, campaign and Ads connection in their established order.
 d:=public.korlix_funnel_google_destination_v1(owner_id,'read',funnel_id,jsonb_build_object('campaign_id',campaign_id,'configured',p_data->'ads_configured','config_hash',p_data->'ads_config_hash'));
 ctx:=d->'context';
 select * into c from public.korlix_google_ads_connections where user_id=owner_id for update;
 perform pg_advisory_xact_lock(hashtextextended('korlix-google-upload:'||owner_id::text,0));
 delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id and expires_at<=now();
 select * into u from public.korlix_google_upload_connections where user_id=owner_id for update;
 select * into a from public.korlix_google_upload_oauth_attempts where user_id=owner_id for update;
 ready:=coalesce(p_data->'configured'='true'::jsonb and d->'selection_current'='true'::jsonb and c.user_id is not null,false);
 current_access:=coalesce(ready and not u.needs_reconnect and (u.refresh_expires_at is null or u.refresh_expires_at>now()+interval '60 seconds') and u.config_hash=p_data->>'config_hash' and u.ads_binding_id=c.binding_id and u.root_id=ctx->>'root_id' and (u.login_customer_id is not distinct from ctx->>'login_customer_id') and u.account=ctx->'account',false);
 current_attempt:=coalesce(ready and a.funnel_id=funnel_id and a.campaign_id=campaign_id and a.config_hash=p_data->>'config_hash' and a.destination_fingerprint=d->>'fingerprint' and a.authorization_version=coalesce(u.version,0),false);
 fp:=encode(sha256(convert_to(jsonb_build_object('contract','google_upload_access_v1','destination',d->'fingerprint','authorization_version',coalesce(u.version,0),'pending_id',a.id,'configured',p_data->'configured','config_hash',p_data->'config_hash')::text,'UTF8')),'hex');
 if p_action='read' then
  return jsonb_build_object('source','google_upload_access','funnel_id',funnel_id,'campaign_id',campaign_id,'campaign_name',d->'campaign_name','configured',p_data->'configured'='true'::jsonb,'destination_current',d->'selection_current','can_authorize',ready,'version',coalesce(u.version,0),'fingerprint',fp,
   'authorization',case when u.user_id is null then null else jsonb_build_object('account',u.account,'root_id',u.root_id,'login_customer_id',u.login_customer_id,'connected_at',u.connected_at,'checked_at',u.checked_at,'needs_reconnect',u.needs_reconnect or coalesce(u.refresh_expires_at<=now()+interval '60 seconds',false) or u.config_hash is distinct from p_data->>'config_hash','current',current_access) end,
   'pending',case when a.user_id is null or a.funnel_id<>funnel_id or a.campaign_id<>campaign_id then null else jsonb_build_object('id',a.id,'phase',a.phase,'expires_at',a.expires_at,'current',current_attempt) end,
   'scope_set','ads_datamanager_v1','delivery_state','not_implemented','send_ready',false,'provider_verified',false);
 end if;
 if p_action in ('begin','disconnect') then
  if p_data->>'fingerprint' is distinct from fp or jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,10}$' then raise exception 'Upload access or destination changed. Refresh before continuing.' using errcode='40001';end if;
  if (p_data->>'version')::bigint is distinct from coalesce(u.version,0) then raise exception 'Upload access changed. Refresh before continuing.' using errcode='40001';end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm the Google upload access change.';end if;
  if p_action='disconnect' then
   delete from public.korlix_google_upload_connections where user_id=owner_id;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
  else
   if not ready then raise exception 'Save a current Google conversion destination and finish platform setup first.' using errcode='40001';end if;
   if a.user_id is not null and a.created_at>now()-interval '30 seconds' then raise exception 'Wait 30 seconds before starting another Google upload authorization.' using errcode='54000';end if;
   if not public.korlix_google_upload_sealed_valid(p_data->'verifier_sealed') then raise exception 'Start a new Google upload authorization.';end if;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
   insert into public.korlix_google_upload_oauth_attempts(user_id,id,funnel_id,campaign_id,state_hash,proof_hash,config_hash,destination_fingerprint,authorization_version,verifier_sealed)
    values(owner_id,(p_data->>'id')::uuid,funnel_id,campaign_id,p_data->>'state_hash',p_data->>'proof_hash',p_data->>'config_hash',d->>'fingerprint',coalesce(u.version,0),p_data->'verifier_sealed');
  end if;
 elsif p_action='failed' then
  if a.id is distinct from (p_data->>'id')::uuid or a.funnel_id<>funnel_id or a.campaign_id<>campaign_id or a.phase not in ('exchanging','verifying') then raise exception 'This upload authorization is no longer active.' using errcode='40001';end if;
  update public.korlix_google_upload_oauth_attempts set phase='failed',candidate=null,verifier_sealed=null where user_id=owner_id;
 else
  if not current_attempt or a.id is distinct from (p_data->>'id')::uuid then raise exception 'The Google account, destination or upload authorization changed. Start again.' using errcode='40001';end if;
  if p_action='consume' then
   if a.state_hash is distinct from p_data->>'state_hash' or a.phase<>'waiting' or a.verifier_sealed is null then raise exception 'This upload authorization link expired or was already used.' using errcode='40001';end if;
   update public.korlix_google_upload_oauth_attempts set phase='exchanging',verifier_sealed=null where user_id=owner_id;
   return jsonb_build_object('user_id',owner_id,'funnel_id',funnel_id,'campaign_id',campaign_id,'id',a.id,'verifier_sealed',a.verifier_sealed);
  elsif p_action='candidate' then
   if a.phase<>'exchanging' or not public.korlix_google_upload_sealed_valid(p_data->'sealed') or p_data->'scopes' is distinct from '["https://www.googleapis.com/auth/adwords","https://www.googleapis.com/auth/datamanager"]'::jsonb then raise exception 'Google upload permissions could not be verified.' using errcode='40001';end if;
   if p_data->>'refresh_expires_at' is not null and (not isfinite((p_data->>'refresh_expires_at')::timestamptz) or (p_data->>'refresh_expires_at')::timestamptz<=now()+interval '60 seconds') then raise exception 'Google upload access is already expired.';end if;
   update public.korlix_google_upload_oauth_attempts set phase='ready',candidate=p_data->'sealed',refresh_expires_at=(p_data->>'refresh_expires_at')::timestamptz where user_id=owner_id;
  elsif p_action='claim' then
   if a.proof_hash is distinct from p_data->>'proof_hash' or p_data->'confirmed' is distinct from 'true'::jsonb or a.phase<>'ready' or a.candidate is null or a.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'Complete Google sign-in in this window, then finish upload authorization.' using errcode='40001';end if;
   update public.korlix_google_upload_oauth_attempts set phase='verifying' where user_id=owner_id;
   return jsonb_build_object('id',a.id,'candidate',a.candidate,'destination',d->'selection'->'destination','context',ctx);
  elsif p_action='finish' then
   if a.phase<>'verifying' or a.candidate is null or a.refresh_expires_at<=now()+interval '60 seconds' then raise exception 'This upload authorization is no longer ready. Start again.' using errcode='40001';end if;
   if jsonb_typeof(p_data->'checked_at') is distinct from 'string' then raise exception 'Repeat the Google access check.';end if;
   checked:=(p_data->>'checked_at')::timestamptz;
   if not isfinite(checked) or checked<now()-interval '5 minutes' or checked>now()+interval '1 minute' then raise exception 'The Google access check expired. Start again.' using errcode='40001';end if;
   insert into public.korlix_google_upload_connections(user_id,binding_id,ads_binding_id,config_hash,sealed,scopes,refresh_expires_at,account,root_id,login_customer_id,version,checked_at)
    values(owner_id,a.id,c.binding_id,a.config_hash,a.candidate,'["https://www.googleapis.com/auth/adwords","https://www.googleapis.com/auth/datamanager"]'::jsonb,a.refresh_expires_at,ctx->'account',ctx->>'root_id',ctx->>'login_customer_id',nextval('public.korlix_google_upload_version_seq'),checked)
    on conflict(user_id) do update set binding_id=excluded.binding_id,ads_binding_id=excluded.ads_binding_id,config_hash=excluded.config_hash,sealed=excluded.sealed,scopes=excluded.scopes,refresh_expires_at=excluded.refresh_expires_at,account=excluded.account,root_id=excluded.root_id,login_customer_id=excluded.login_customer_id,version=excluded.version,connected_at=now(),checked_at=excluded.checked_at,needs_reconnect=false;
   delete from public.korlix_google_upload_oauth_attempts where user_id=owner_id;
  end if;
 end if;
 return '{}'::jsonb;
end $$;
revoke all on function public.korlix_google_upload_access_v1(uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.korlix_google_upload_access_v1(uuid,text,uuid,jsonb) to service_role;
commit;
