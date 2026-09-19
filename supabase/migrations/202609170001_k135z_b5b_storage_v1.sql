begin;
-- K135Z Gate6A: additive B5B storage. B1 consent/session tables remain untouched.
-- Backend-only RPC; metadata does not authorize media capture or speech.
-- Deliberately fail on a pre-existing B5B schema/function, rather than adopt it.
create schema k135z_b5b_private;
revoke all on schema k135z_b5b_private from public, anon, authenticated, service_role;

create function k135z_b5b_private.need(ok boolean, code text)
returns void language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
begin
  if ok is distinct from true then raise exception using errcode='22023', message=code; end if;
end $$;

create function k135z_b5b_private.fields(v jsonb, expected text[])
returns void language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
begin
  perform k135z_b5b_private.need(jsonb_typeof(v)='object','ZOOM_RECORD_INVALID');
  perform k135z_b5b_private.need(v ?& expected and
    not exists(select 1 from jsonb_object_keys(v) as names(key) where not (key=any(expected))),
    'ZOOM_RECORD_FIELDS_INVALID');
end $$;

create function k135z_b5b_private.txt(v jsonb, maximum integer default 256)
returns text language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare s text;
begin
  perform k135z_b5b_private.need(jsonb_typeof(v)='string','ZOOM_TEXT_INVALID');
  s=v#>>'{}';
  perform k135z_b5b_private.need(length(s)>0 and length(s)<=maximum and
    s !~ '[[:cntrl:]]' and s !~ '^[[:space:]]|[[:space:]]$','ZOOM_TEXT_INVALID');
  return s;
end $$;

create function k135z_b5b_private.ms(v jsonb)
returns bigint language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare n numeric;
begin
  perform k135z_b5b_private.need(jsonb_typeof(v)='number','ZOOM_TIME_INVALID');
  n=(v#>>'{}')::numeric;
  perform k135z_b5b_private.need(n>=0 and n<=8640000000000000 and trunc(n)=n,'ZOOM_TIME_INVALID');
  return n::bigint;
end $$;

create function k135z_b5b_private.hash(v jsonb)
returns text language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare s text;
begin
  s=k135z_b5b_private.txt(v,64);
  perform k135z_b5b_private.need(s ~ '^[a-f0-9]{64}$','ZOOM_HASH_INVALID'); return s;
end $$;

create function k135z_b5b_private.identity_key(v jsonb)
returns text language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare t text; u text; a text;
begin
  t=k135z_b5b_private.txt(v->'tenantId',128);
  u=k135z_b5b_private.txt(v->'userId',36);
  a=k135z_b5b_private.txt(v->'agentId',128);
  perform k135z_b5b_private.need(t ~ '^[A-Za-z0-9_-]{1,128}$' and
    a ~ '^[A-Za-z0-9_-]{1,128}$' and
    u ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' and
    u<>'00000000-0000-0000-0000-000000000000','ZOOM_IDENTITY_INVALID');
  return '['||to_jsonb(t)::text||','||to_jsonb(u)::text||','||to_jsonb(a)::text||']';
end $$;

create function k135z_b5b_private.key_identity(k text)
returns jsonb language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare a jsonb; v jsonb;
begin
  begin a=k::jsonb; exception when others then
    raise exception using errcode='22023',message='ZOOM_IDENTITY_KEY_INVALID'; end;
  perform k135z_b5b_private.need(jsonb_typeof(a)='array','ZOOM_IDENTITY_KEY_INVALID');
  perform k135z_b5b_private.need(jsonb_array_length(a)=3,'ZOOM_IDENTITY_KEY_INVALID');
  v=jsonb_build_object('tenantId',a->0,'userId',a->1,'agentId',a->2);
  perform k135z_b5b_private.need(k135z_b5b_private.identity_key(v)=k,'ZOOM_IDENTITY_KEY_INVALID');
  return v;
end $$;

create function k135z_b5b_private.envelope(v jsonb)
returns void language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare k text; s text; b bytea;
begin
  perform k135z_b5b_private.fields(v,array['version','algorithm','iv','tag','ciphertext']);
  perform k135z_b5b_private.need(v->'version'='2'::jsonb and
    v->'algorithm'='"aes-256-gcm"'::jsonb,'ZOOM_TOKEN_ENVELOPE_INVALID');
  foreach k in array array['iv','tag','ciphertext'] loop
    perform k135z_b5b_private.need(jsonb_typeof(v->k)='string','ZOOM_TOKEN_ENVELOPE_INVALID');
    s=v->>k;
    perform k135z_b5b_private.need(s ~ '^[A-Za-z0-9_-]+$' and length(s)<=43691,
      'ZOOM_TOKEN_ENVELOPE_INVALID');
    begin b=decode(translate(s,'-_','+/')||repeat('=',(4-length(s)%4)%4),'base64');
    exception when others then raise exception using errcode='22023',message='ZOOM_TOKEN_ENVELOPE_INVALID'; end;
    perform k135z_b5b_private.need(
      translate(rtrim(replace(encode(b,'base64'),E'\n',''),'='),'+/','-_')=s and
      case k when 'iv' then octet_length(b)=12 when 'tag' then octet_length(b)=16
        else octet_length(b) between 1 and 32768 end,'ZOOM_TOKEN_ENVELOPE_INVALID');
  end loop;
end $$;

create function k135z_b5b_private.record(kind text, v jsonb, k text default null)
returns boolean language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare created bigint; expires bigint; s text; expected text;
begin
  if kind='state' then
    perform k135z_b5b_private.fields(v,array['tenantId','userId','agentId','returnTo','createdAtMs','expiresAtMs']);
    perform k135z_b5b_private.identity_key(v);
    created=k135z_b5b_private.ms(v->'createdAtMs'); expires=k135z_b5b_private.ms(v->'expiresAtMs');
    perform k135z_b5b_private.need(expires>created and expires-created<=600000,'ZOOM_STATE_TTL_INVALID');
    if v->'returnTo'<>'null'::jsonb then
      s=k135z_b5b_private.txt(v->'returnTo',2048);
      -- Origin allowlisting is performed by the backend before this service-only RPC.
      perform k135z_b5b_private.need(s ~ '^https://[^/?#@[:space:]]+([/?#]|$)' and
        position(E'\\' in s)=0 and s !~ '[[:space:]]' and
        s !~* '%(0[0-9a-f]|1[0-9a-f]|7f|5c)','ZOOM_RETURN_URL_INVALID');
    end if;
  elsif kind='connection' then
    perform k135z_b5b_private.fields(v,array['key','tenantId','userId','agentId','zoomAccountId','zoomUserId',
      'scope','expiresAtMs','connectedAtMs','updatedAtMs','encryptedTokens']);
    perform k135z_b5b_private.key_identity(k);
    perform k135z_b5b_private.need(v->>'key'=k and k135z_b5b_private.identity_key(v)=k,'ZOOM_CONNECTION_BINDING_INVALID');
    perform k135z_b5b_private.txt(v->'zoomAccountId'); perform k135z_b5b_private.txt(v->'zoomUserId');
    perform k135z_b5b_private.need(jsonb_typeof(v->'scope')='string' and length(v->>'scope')<=4096 and
      (v->>'scope') !~ '[\x01-\x1f]','ZOOM_SCOPE_INVALID');
    perform k135z_b5b_private.ms(v->'expiresAtMs'); perform k135z_b5b_private.ms(v->'connectedAtMs');
    perform k135z_b5b_private.ms(v->'updatedAtMs'); perform k135z_b5b_private.envelope(v->'encryptedTokens');
  elsif kind='session' then
    perform k135z_b5b_private.fields(v,array['sessionKey','zoomAccountId','meetingUuid','streamId','eventTs','status',
      'mediaConnected','transcriptCollected','audioInjected']);
    perform k135z_b5b_private.hash(to_jsonb(k));
    perform k135z_b5b_private.txt(v->'zoomAccountId'); perform k135z_b5b_private.txt(v->'meetingUuid',512);
    perform k135z_b5b_private.txt(v->'streamId',512); perform k135z_b5b_private.ms(v->'eventTs');
    expected=encode(sha256(convert_to('['||(v->'zoomAccountId')::text||','||
      (v->'meetingUuid')::text||','||(v->'streamId')::text||']','UTF8')),'hex');
    perform k135z_b5b_private.need(v->>'sessionKey'=k and expected=k,'ZOOM_SESSION_BINDING_INVALID');
    perform k135z_b5b_private.need(v->>'status'=any(array['started','stopped','interrupted']) and
      v->'mediaConnected'='false'::jsonb and v->'transcriptCollected'='false'::jsonb and
      v->'audioInjected'='false'::jsonb,'ZOOM_MEDIA_DISABLED');
  else raise exception using errcode='22023',message='ZOOM_RECORD_KIND_INVALID'; end if;
  return true;
end $$;

create table k135z_b5b_private.oauth_states (
  state_hash text primary key check(state_hash ~ '^[a-f0-9]{64}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  record jsonb not null check(k135z_b5b_private.record('state',record)),
  consumed_at_ms bigint,
  check(user_id::text=record->>'userId'),
  check(consumed_at_ms is null or consumed_at_ms between 0 and 8640000000000000)
);
create table k135z_b5b_private.connections (
  identity_key text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  record jsonb not null check(k135z_b5b_private.record('connection',record,identity_key)),
  check(user_id::text=record->>'userId')
);
create index b5b_provider_identity_idx on k135z_b5b_private.connections
  ((record->>'zoomAccountId'),(record->>'zoomUserId'));
create table k135z_b5b_private.sessions (
  session_key text primary key,
  record jsonb not null check(k135z_b5b_private.record('session',record,session_key))
);
-- Accountless provider terminal events bind the exact meeting/stream pair.
create index b5b_stream_identity_idx on k135z_b5b_private.sessions
  ((record->>'meetingUuid'),(record->>'streamId'));
create table k135z_b5b_private.stream_terminals (
  meeting_uuid text not null,
  stream_id text not null,
  status text not null check(status in ('stopped','interrupted')),
  event_ts bigint not null check(event_ts between 0 and 8640000000000000),
  primary key(meeting_uuid,stream_id)
);
alter table k135z_b5b_private.stream_terminals enable row level security;
create table k135z_b5b_private.capture_sources (
  session_key text primary key references k135z_b5b_private.sessions(session_key) on delete cascade,
  event_ts bigint not null check(event_ts between 0 and 8640000000000000),
  operator_id text not null,
  original_host boolean not null,
  server_urls text not null check(length(server_urls) between 1 and 4096)
);
alter table k135z_b5b_private.capture_sources enable row level security;
create table k135z_b5b_private.events (
  event_id text primary key check(event_id ~ '^[a-f0-9]{64}$'),
  payload_hash text not null check(payload_hash ~ '^[a-f0-9]{64}$'),
  event_name text not null,
  event_ts bigint not null check(event_ts between 0 and 8640000000000000)
);
alter table k135z_b5b_private.oauth_states enable row level security;
alter table k135z_b5b_private.connections enable row level security;
alter table k135z_b5b_private.sessions enable row level security;
alter table k135z_b5b_private.events enable row level security;

create function k135z_b5b_private.session_upsert(k text, v jsonb)
returns jsonb language plpgsql set search_path=pg_catalog,pg_temp as $$
declare result jsonb; terminal k135z_b5b_private.stream_terminals%rowtype;
begin
  perform k135z_b5b_private.record('session',v,k);
  -- Same transaction lock for Starts and accountless terminal events.
  perform pg_advisory_xact_lock(hashtextextended(jsonb_build_array(v->>'meetingUuid',v->>'streamId')::text,13526));
  select * into terminal from k135z_b5b_private.stream_terminals
    where meeting_uuid=v->>'meetingUuid' and stream_id=v->>'streamId';
  if found then
    v=v||jsonb_build_object('status',case when v->>'status'='stopped' then 'stopped' else terminal.status end,
      'eventTs',greatest((v->>'eventTs')::bigint,terminal.event_ts));
  end if;
  insert into k135z_b5b_private.sessions as existing(session_key,record) values(k,v)
    on conflict(session_key) do update set record=excluded.record
    where existing.record->>'status'<>'stopped' and
      (excluded.record->>'eventTs')::bigint >= (existing.record->>'eventTs')::bigint
    returning record into result;
  if result is null then select record into result from k135z_b5b_private.sessions where session_key=k; end if;
  return result;
end $$;

create function public.k135z_b5b_storage_v1(operation text, payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare k text; v jsonb; existing jsonb; used bigint; n bigint; now_ms bigint;
        m jsonb; kind text; event_hash text; stored_hash text; inserted boolean;
begin
  perform k135z_b5b_private.need(operation=any(array['state_create','state_consume','connection_save',
    'connection_get','connection_delete','connection_deauthorize','session_upsert','session_get','event_apply','capture_source']),
    'ZOOM_OPERATION_INVALID');
  perform k135z_b5b_private.need(jsonb_typeof(payload)='object' and
    octet_length(payload::text)<=131072,'ZOOM_PAYLOAD_INVALID');
  if operation='state_create' then
    perform k135z_b5b_private.fields(payload,array['stateHash','record']);
    k=k135z_b5b_private.hash(payload->'stateHash'); v=payload->'record';
    perform k135z_b5b_private.record('state',v);
    insert into k135z_b5b_private.oauth_states(state_hash,user_id,record)
      values(k,(v->>'userId')::uuid,v) on conflict(state_hash) do nothing;
    perform k135z_b5b_private.need(found,'ZOOM_STATE_EXISTS'); return 'true'::jsonb;
  elsif operation='state_consume' then
    perform k135z_b5b_private.fields(payload,array['stateHash','nowMs']);
    k=k135z_b5b_private.hash(payload->'stateHash'); now_ms=k135z_b5b_private.ms(payload->'nowMs');
    select record,consumed_at_ms into v,used from k135z_b5b_private.oauth_states where state_hash=k for update;
    if not found then return '{"outcome":"invalid"}'::jsonb; end if;
    if used is not null then return '{"outcome":"replayed"}'::jsonb; end if;
    update k135z_b5b_private.oauth_states set consumed_at_ms=now_ms where state_hash=k;
    if now_ms<(v->>'createdAtMs')::bigint or now_ms>=(v->>'expiresAtMs')::bigint then
      return '{"outcome":"expired"}'::jsonb; end if;
    return jsonb_build_object('outcome','ok','record',v);
  elsif operation='connection_save' then
    perform k135z_b5b_private.fields(payload,array['key','record']);
    k=k135z_b5b_private.txt(payload->'key',400);v=payload->'record';
    perform k135z_b5b_private.record('connection',v,k);
    insert into k135z_b5b_private.connections(identity_key,user_id,record) values(k,(v->>'userId')::uuid,v)
      on conflict(identity_key) do update set record=excluded.record;
    return 'true'::jsonb;
  elsif operation in ('connection_get','connection_delete') then
    perform k135z_b5b_private.fields(payload,array['key']); k=k135z_b5b_private.txt(payload->'key',400);
    perform k135z_b5b_private.key_identity(k);
    if operation='connection_get' then
      select record into v from k135z_b5b_private.connections where identity_key=k;
      return coalesce(v,'null'::jsonb);
    end if;
    delete from k135z_b5b_private.connections where identity_key=k; return to_jsonb(found);
  elsif operation='connection_deauthorize' then
    perform k135z_b5b_private.fields(payload,array['zoomAccountId','zoomUserId']);
    perform k135z_b5b_private.txt(payload->'zoomAccountId'); perform k135z_b5b_private.txt(payload->'zoomUserId');
    delete from k135z_b5b_private.connections where record->>'zoomAccountId'=payload->>'zoomAccountId'
      and record->>'zoomUserId'=payload->>'zoomUserId'; get diagnostics n=row_count; return to_jsonb(n);
  elsif operation='capture_source' then
    perform k135z_b5b_private.fields(payload,array['key','meetingUuid','streamId']);
    k=k135z_b5b_private.txt(payload->'key',400);perform k135z_b5b_private.key_identity(k);
    perform k135z_b5b_private.txt(payload->'meetingUuid',512);
    if payload->'streamId'<>'null'::jsonb then perform k135z_b5b_private.txt(payload->'streamId',512);end if;
    select record into v from k135z_b5b_private.connections where identity_key=k for share;
    if not found or not ('meeting:read:meeting_transcripts'=any(regexp_split_to_array(v->>'scope',' +')))
      then return 'null'::jsonb;end if;
    select jsonb_agg(candidate) into existing from (
      select jsonb_build_object('meetingUuid',s.record->'meetingUuid','streamId',s.record->'streamId',
        'serverUrls',c.server_urls) as candidate
      from k135z_b5b_private.sessions s join k135z_b5b_private.capture_sources c using(session_key)
      where s.record->>'zoomAccountId'=v->>'zoomAccountId' and c.operator_id=v->>'zoomUserId' and c.original_host
        and s.record->>'status'='started' and s.record->'meetingUuid'=payload->'meetingUuid'
        and (payload->'streamId'='null'::jsonb or s.record->'streamId'=payload->'streamId')
        and (s.record->>'eventTs')::bigint=c.event_ts and c.event_ts>=(v->>'connectedAtMs')::bigint
      limit 2
    ) candidates;
    if jsonb_array_length(existing)=1 then return existing->0;end if;return 'null'::jsonb;
  elsif operation='session_get' then
    perform k135z_b5b_private.fields(payload,array['key']); k=k135z_b5b_private.hash(payload->'key');
    select record into v from k135z_b5b_private.sessions where session_key=k; return coalesce(v,'null'::jsonb);
  elsif operation='session_upsert' then
    perform k135z_b5b_private.fields(payload,array['key','record']); k=k135z_b5b_private.hash(payload->'key');
    v=k135z_b5b_private.session_upsert(k,payload->'record');
    delete from k135z_b5b_private.capture_sources where session_key=k;
    return v;
  end if;
  -- event_apply: validate the entire plan BEFORE any persistence or effect.
  perform k135z_b5b_private.fields(payload,array['eventId','payloadHash','event','eventTs','mutation']);
  k=k135z_b5b_private.hash(payload->'eventId');event_hash=k135z_b5b_private.hash(payload->'payloadHash');
  perform k135z_b5b_private.txt(payload->'event',128);perform k135z_b5b_private.ms(payload->'eventTs');
  m=payload->'mutation';kind=k135z_b5b_private.txt(m->'kind',16);
  if kind='none' then perform k135z_b5b_private.fields(m,array['kind']);
  elsif kind='deauthorize' then
    perform k135z_b5b_private.fields(m,array['kind','zoomAccountId','zoomUserId']);
    perform k135z_b5b_private.txt(m->'zoomAccountId');perform k135z_b5b_private.txt(m->'zoomUserId');
    perform k135z_b5b_private.need(payload->>'event'='app_deauthorized','ZOOM_EVENT_MUTATION_INVALID');
  elsif kind='terminal' then
    perform k135z_b5b_private.fields(m,array['kind','meetingUuid','streamId','status']);
    perform k135z_b5b_private.txt(m->'meetingUuid',512);perform k135z_b5b_private.txt(m->'streamId',512);
    perform k135z_b5b_private.need(m->>'status'=any(array['stopped','interrupted']) and
      payload->>'event'='meeting.rtms_'||(m->>'status'),'ZOOM_EVENT_MUTATION_INVALID');
  elsif kind='session' then
    perform k135z_b5b_private.fields(m,case when m?'source' then array['kind','key','record','source'] else array['kind','key','record'] end);
    if m?'source' then
      perform k135z_b5b_private.fields(m->'source',array['operatorId','originalHost','serverUrls']);
      perform k135z_b5b_private.txt(m->'source'->'operatorId');
      perform k135z_b5b_private.txt(m->'source'->'serverUrls',4096);
      perform k135z_b5b_private.need(m->'record'->>'status'='started' and
        jsonb_typeof(m->'source'->'originalHost')='boolean','ZOOM_EVENT_MUTATION_INVALID');
    end if;
    perform k135z_b5b_private.record('session',m->'record',m->>'key');
    perform k135z_b5b_private.need(payload->>'event'='meeting.rtms_'||(m->'record'->>'status') and
      payload->'eventTs'=m->'record'->'eventTs','ZOOM_EVENT_MUTATION_INVALID');
  else raise exception using errcode='22023',message='ZOOM_EVENT_MUTATION_INVALID';end if;
  insert into k135z_b5b_private.events(event_id,payload_hash,event_name,event_ts)
    values(k,event_hash,payload->>'event',k135z_b5b_private.ms(payload->'eventTs'))
    on conflict(event_id) do nothing;
  inserted=found;
  if not inserted then
    select payload_hash into stored_hash from k135z_b5b_private.events where event_id=k;
    perform k135z_b5b_private.need(stored_hash=event_hash,'ZOOM_EVENT_ID_CONFLICT');
    return '{"accepted":false,"duplicate":true,"deletedConnections":0}'::jsonb;
  end if;
  n=0;
  if kind='terminal' then
    perform pg_advisory_xact_lock(hashtextextended(jsonb_build_array(m->>'meetingUuid',m->>'streamId')::text,13526));
    insert into k135z_b5b_private.stream_terminals as old(meeting_uuid,stream_id,status,event_ts)
      values(m->>'meetingUuid',m->>'streamId',m->>'status',k135z_b5b_private.ms(payload->'eventTs'))
      on conflict(meeting_uuid,stream_id) do update set
        status=case when old.status='stopped' then 'stopped' else excluded.status end,
        event_ts=greatest(old.event_ts,excluded.event_ts);
    update k135z_b5b_private.sessions s set record=s.record||jsonb_build_object(
      'status',case when s.record->>'status'='stopped' then 'stopped' else t.status end,
      'eventTs',greatest((s.record->>'eventTs')::bigint,t.event_ts))
      from k135z_b5b_private.stream_terminals t
      where t.meeting_uuid=m->>'meetingUuid' and t.stream_id=m->>'streamId'
        and s.record->>'meetingUuid'=t.meeting_uuid and s.record->>'streamId'=t.stream_id;
  elsif kind='session' then
    v=k135z_b5b_private.session_upsert(m->>'key',m->'record');
    if v->>'status'='started' and v->'eventTs'=payload->'eventTs' then
      if m?'source' then
        insert into k135z_b5b_private.capture_sources(session_key,event_ts,operator_id,original_host,server_urls)
          values(m->>'key',(payload->>'eventTs')::bigint,m->'source'->>'operatorId',
            (m->'source'->>'originalHost')::boolean,m->'source'->>'serverUrls')
          on conflict(session_key) do update set event_ts=excluded.event_ts,operator_id=excluded.operator_id,
            original_host=excluded.original_host,server_urls=excluded.server_urls;
      else delete from k135z_b5b_private.capture_sources where session_key=m->>'key';end if;
    end if;
  elsif kind='deauthorize' then
    delete from k135z_b5b_private.connections where record->>'zoomAccountId'=m->>'zoomAccountId'
      and record->>'zoomUserId'=m->>'zoomUserId'; get diagnostics n=row_count;
  end if;
  return jsonb_build_object('accepted',true,'duplicate',false,'deletedConnections',n);
end $$;

-- No direct service-role table/helper access. The one RPC is the only granted entry.
revoke all on all tables in schema k135z_b5b_private from public, anon, authenticated, service_role;
revoke all on all functions in schema k135z_b5b_private from public, anon, authenticated, service_role;
revoke all on function public.k135z_b5b_storage_v1(text,jsonb) from public, anon, authenticated;
grant execute on function public.k135z_b5b_storage_v1(text,jsonb) to service_role;
commit;
