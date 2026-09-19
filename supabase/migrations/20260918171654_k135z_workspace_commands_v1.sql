begin;
-- Gate6G: backend-only workspace state. No live meeting or provider credentials.
create schema k135z_workspace_private;
revoke all on schema k135z_workspace_private from public,anon,authenticated;
grant usage on schema k135z_workspace_private to service_role;

create function k135z_workspace_private.need(ok boolean) returns void
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
begin
 if ok is distinct from true then raise exception 'K135Z_WORKSPACE_INVALID' using errcode='22023'; end if;
end $$;
create function k135z_workspace_private.fields(v jsonb,expected text[]) returns void
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
begin
 perform k135z_workspace_private.need(jsonb_typeof(v)='object');
 perform k135z_workspace_private.need(v ?& expected and not exists
  (select 1 from jsonb_object_keys(v) k where not(k=any(expected))));
end $$;
create function k135z_workspace_private.uint(v jsonb) returns bigint
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
declare n numeric;
begin
 perform k135z_workspace_private.need(jsonb_typeof(v)='number'); n=(v#>>'{}')::numeric;
 perform k135z_workspace_private.need(n>=0 and n<=9007199254740991 and trunc(n)=n);
 return n::bigint;
end $$;
create function k135z_workspace_private.txt(v jsonb) returns text
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
declare s text;
begin
 perform k135z_workspace_private.need(jsonb_typeof(v)='string'); s=v#>>'{}';
 perform k135z_workspace_private.need(octet_length(s) between 1 and 256 and s!~'^[[:space:]]*$'); return s;
end $$;
create function k135z_workspace_private.context(v jsonb) returns void
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
declare k text;
begin
 perform k135z_workspace_private.fields(v,array['tenantId','userId','agentId','sessionId','meetingUuid','streamId','generation']);
 foreach k in array array['tenantId','userId','agentId','sessionId','meetingUuid'] loop
  perform k135z_workspace_private.txt(v->k);
 end loop;
 if v->'streamId'<>'null'::jsonb then perform k135z_workspace_private.txt(v->'streamId'); end if;
 perform k135z_workspace_private.uint(v->'generation');
end $$;
create function k135z_workspace_private.record(v jsonb) returns void
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
declare s jsonb; p jsonb; q jsonb; o jsonb;
begin
 perform k135z_workspace_private.fields(v,array['snapshot','version','pending','uncertain']);
 perform k135z_workspace_private.need(octet_length(v::text)<=66560 and jsonb_typeof(v->'uncertain')='boolean');
 perform k135z_workspace_private.uint(v->'version'); s=v->'snapshot';
 perform k135z_workspace_private.fields(s,array['schemaVersion','context','revision','state','hostAuthorized','listeningAuthorized','activeSeconds','capabilities']);
 perform k135z_workspace_private.need(s->'schemaVersion'='1'::jsonb and s->>'state'=any(array['ready','listening','paused','stopped','error'])
  and jsonb_typeof(s->'hostAuthorized')='boolean' and jsonb_typeof(s->'listeningAuthorized')='boolean'
  and s->'capabilities'='{"canSpeak":false}'::jsonb);
 perform k135z_workspace_private.context(s->'context');
 perform k135z_workspace_private.uint(s->'revision'); perform k135z_workspace_private.uint(s->'activeSeconds');
 if s->>'state' in ('listening','paused') then perform k135z_workspace_private.need(s#>'{context,streamId}'<>'null'::jsonb); end if;
 p=v->'pending';
 if p<>'null'::jsonb then
  perform k135z_workspace_private.fields(p,array['request','ticketVersion','phase']);
  perform k135z_workspace_private.need(p->>'phase' in ('prepared','dispatched')
   and k135z_workspace_private.uint(p->'ticketVersion')<=k135z_workspace_private.uint(v->'version'));
  q=p->'request';
  perform k135z_workspace_private.fields(q,array['schemaVersion','operation','action','expectedContext','expectedSnapshotRevision']);
  perform k135z_workspace_private.need(q->'schemaVersion'='1'::jsonb and q->>'action' in ('start','pause','stop')
   and q->'expectedContext'=s->'context' and q->'expectedSnapshotRevision'=s->'revision');
  o=q->'operation'; perform k135z_workspace_private.fields(o,array['requestId','localEpoch','operationNumber']);
  perform k135z_workspace_private.txt(o->'requestId'); perform k135z_workspace_private.uint(o->'localEpoch');
  perform k135z_workspace_private.uint(o->'operationNumber');
 end if;
 perform k135z_workspace_private.need(v->'uncertain'='false'::jsonb or p->>'phase'='dispatched');
end $$;

create table k135z_workspace_private.bindings(
 user_id uuid not null references auth.users(id) on delete cascade,
 agent_id text not null check(agent_id~'^[A-Za-z0-9_-]{1,128}$'),
 binding_revision bigint not null check(binding_revision between 1 and 9007199254740991),
 authority_revision bigint not null check(authority_revision between 0 and 9007199254740991),
 record jsonb not null,
 host_authorized boolean not null default false,
 listening_authorized boolean not null default false,
 authority_until timestamptz not null default '-infinity',
 primary key(user_id,agent_id)
);
alter table k135z_workspace_private.bindings enable row level security;
revoke all on k135z_workspace_private.bindings from public,anon,authenticated,service_role;
grant select,insert,update on k135z_workspace_private.bindings to service_role;
create policy backend_workspace on k135z_workspace_private.bindings for all to service_role using(true) with check(true);

create function k135z_workspace_private.transition(old jsonb,new jsonb,a jsonb) returns void
language plpgsql immutable set search_path=pg_catalog,pg_temp as $$
declare p jsonb; q jsonb; s jsonb; t jsonb; action text; adopted boolean;
begin
 perform k135z_workspace_private.record(new);
 if old=new then return; end if;
 perform k135z_workspace_private.need(k135z_workspace_private.uint(new->'version')=k135z_workspace_private.uint(old->'version')+1
  and old->'uncertain'='false'::jsonb and old#>>'{snapshot,state}'<>'stopped');
 p=old->'pending'; q=new->'pending'; s=old->'snapshot'; t=new->'snapshot';
 if p='null'::jsonb then
  action=q#>>'{request,action}';
  perform k135z_workspace_private.need(q->>'phase'='prepared' and q->'ticketVersion'=new->'version'
   and s=t and new->'uncertain'='false'::jsonb and
   (action='stop' or action='pause' and s->>'state'='listening' or action='start' and s->>'state' in ('ready','paused')
    and a->'hostAuthorized'='true'::jsonb and a->'listeningAuthorized'='true'::jsonb));
 elsif p->>'phase'='prepared' then
  perform k135z_workspace_private.need(s=t and new->'uncertain'='false'::jsonb and
   (q='null'::jsonb or q=jsonb_set(p,'{phase}','"dispatched"'::jsonb) and
    (p#>>'{request,action}'<>'start' or a->'hostAuthorized'='true'::jsonb and a->'listeningAuthorized'='true'::jsonb)));
 else
  if q=p then
   perform k135z_workspace_private.need(s=t and new->'uncertain'='true'::jsonb);
  else
   perform k135z_workspace_private.need(q='null'::jsonb and new->'uncertain'='false'::jsonb);
   if s=t then return; end if;
   action=p#>>'{request,action}';
   adopted=action='start' and s#>'{context,streamId}'='null'::jsonb and t#>'{context,streamId}'<>'null'::jsonb
    and (s->'context')- 'streamId'=(t->'context')- 'streamId';
   perform k135z_workspace_private.need((s->'context'=t->'context' or adopted)
    and k135z_workspace_private.uint(t->'revision')=k135z_workspace_private.uint(s->'revision')+1
    and k135z_workspace_private.uint(t->'activeSeconds')>=k135z_workspace_private.uint(s->'activeSeconds')
    and t->>'state'=case action when 'start' then 'listening' when 'pause' then 'paused' when 'stop' then 'stopped' end
    and t->'hostAuthorized'=a->'hostAuthorized' and t->'listeningAuthorized'=a->'listeningAuthorized'
    and (action<>'start' or a->'hostAuthorized'='true'::jsonb and a->'listeningAuthorized'='true'::jsonb));
  end if;
 end if;
end $$;

create function public.k135z_workspace_commands_v1(operation text,payload jsonb) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,pg_temp as $$
declare u uuid; ag text; p jsonb; r k135z_workspace_private.bindings; found_binding boolean;
 ctx jsonb; a jsonb; expected jsonb; next_record jsonb; tier text; active boolean; deleted timestamptz;
 lease bigint; fresh boolean;
begin
 if current_user<>'service_role' then raise exception 'K135Z_WORKSPACE_DENIED' using errcode='42501'; end if;
 perform k135z_workspace_private.need(operation in ('bind','authorize','read','compare_save','capture_lease','consent','renew','revoke') and octet_length(payload::text)<=196608);
 perform k135z_workspace_private.fields(payload,case operation
  when 'capture_lease' then array['principal'] when 'read' then array['principal'] when 'bind' then array['principal','meetingUuid','expectedBindingRevision']
  when 'authorize' then array['principal','context','bindingRevision','authorityRevision','hostAuthorized','listeningAuthorized','leaseSeconds']
  when 'consent' then array['principal','context','bindingRevision','authorityRevision','listeningConsent']
  when 'renew' then array['principal','context','bindingRevision','authorityRevision']
  when 'revoke' then array['principal','context','bindingRevision','authorityRevision']
  else array['principal','context','expected','record'] end);
 p=payload->'principal'; perform k135z_workspace_private.fields(p,array['tenantId','userId','agentId']);
 perform k135z_workspace_private.txt(p->'agentId');
 perform k135z_workspace_private.need(p->>'userId'~'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
  and p->>'userId'<>'00000000-0000-0000-0000-000000000000' and p->>'tenantId'=p->>'userId'
  and p->>'agentId'~'^[A-Za-z0-9_-]{1,128}$');
 u=(p->>'userId')::uuid; ag=p->>'agentId';
 -- Stable lock order: current entitlement, current agent ownership, then binding.
 select up.tier into tier from public.user_profiles up where up.id=u for share;
 if not found or lower(btrim(tier))<>'enterprise' then return '{"status":"denied"}'::jsonb; end if;
 select ap.active,ap.deleted_at into active,deleted from public.korlix_live_convo_agent_profiles ap
  where ap.user_id=u and ap.agent_id=ag for share;
 if not found or active is not true or deleted is not null then return '{"status":"denied"}'::jsonb; end if;
 select * into r from k135z_workspace_private.bindings where user_id=u and agent_id=ag for update;
 found_binding=found;
 if operation='bind' then
  perform k135z_workspace_private.txt(payload->'meetingUuid');
  perform k135z_workspace_private.uint(payload->'expectedBindingRevision');
  if (not found_binding and payload->'expectedBindingRevision'<>'0'::jsonb) or
   (found_binding and (payload->'expectedBindingRevision'<>to_jsonb(r.binding_revision)
    or r.record#>>'{snapshot,state}'<>'stopped' or r.record->'pending'<>'null'::jsonb or r.record->'uncertain'<>'false'::jsonb))
   then return '{"status":"conflict"}'::jsonb; end if;
  perform k135z_workspace_private.need(not found_binding or r.binding_revision<9007199254740991);
  ctx=p||jsonb_build_object('sessionId',gen_random_uuid()::text,'meetingUuid',payload->'meetingUuid','streamId',null,
   'generation',case when found_binding then r.binding_revision+1 else 1 end);
  next_record=jsonb_build_object('version',0,'pending',null,'uncertain',false,'snapshot',jsonb_build_object(
   'schemaVersion',1,'context',ctx,'revision',0,'state','ready','hostAuthorized',false,'listeningAuthorized',false,
   'activeSeconds',0,'capabilities',jsonb_build_object('canSpeak',false)));
  if found_binding then
   update k135z_workspace_private.bindings set binding_revision=binding_revision+1,authority_revision=0,
    record=next_record,host_authorized=false,listening_authorized=false,authority_until='-infinity'
    where user_id=u and agent_id=ag returning * into r;
  else
   insert into k135z_workspace_private.bindings(user_id,agent_id,binding_revision,authority_revision,record)
    values(u,ag,1,0,next_record) on conflict do nothing returning * into r;
   if not found then return '{"status":"conflict"}'::jsonb; end if;
  end if;
 elsif not found_binding then return '{"status":"not_found"}'::jsonb;
 end if;
 perform k135z_workspace_private.record(r.record);
 ctx=r.record#>'{snapshot,context}';
 perform k135z_workspace_private.need(ctx->>'tenantId'=u::text and ctx->>'userId'=u::text and ctx->>'agentId'=ag
  and ctx->'generation'=to_jsonb(r.binding_revision));
 if operation='authorize' then
  perform k135z_workspace_private.context(payload->'context');
  perform k135z_workspace_private.uint(payload->'bindingRevision');perform k135z_workspace_private.uint(payload->'authorityRevision');
  lease=k135z_workspace_private.uint(payload->'leaseSeconds');
  perform k135z_workspace_private.need(lease between 1 and 60 and jsonb_typeof(payload->'hostAuthorized')='boolean'
   and jsonb_typeof(payload->'listeningAuthorized')='boolean' and r.authority_revision<9007199254740991);
  if payload->'context'<>ctx or payload->'bindingRevision'<>to_jsonb(r.binding_revision)
   or payload->'authorityRevision'<>to_jsonb(r.authority_revision) then return '{"status":"conflict"}'::jsonb; end if;
  update k135z_workspace_private.bindings set authority_revision=authority_revision+1,
   host_authorized=(payload->>'hostAuthorized')::boolean,listening_authorized=(payload->>'listeningAuthorized')::boolean,
   authority_until=clock_timestamp()+make_interval(secs=>lease::integer)
   where user_id=u and agent_id=ag returning * into r;
 end if;
 -- Gate6M: only an explicit app request can issue or extend listening consent.
 if operation in ('consent','renew','revoke') then
  perform k135z_workspace_private.context(payload->'context');
  perform k135z_workspace_private.uint(payload->'bindingRevision');
  perform k135z_workspace_private.uint(payload->'authorityRevision');
  if payload->'context'<>ctx or payload->'bindingRevision'<>to_jsonb(r.binding_revision)
   or payload->'authorityRevision'<>to_jsonb(r.authority_revision) then return '{"status":"conflict"}'::jsonb; end if;
  if operation='revoke' then
   perform k135z_workspace_private.need(r.authority_revision<9007199254740991);
   update k135z_workspace_private.bindings set authority_revision=authority_revision+1,
    host_authorized=false,listening_authorized=false,authority_until='-infinity'
    where user_id=u and agent_id=ag returning * into r;
  else
   if r.record->'uncertain'<>'false'::jsonb or r.record->'pending'<>'null'::jsonb
    or r.record#>>'{snapshot,state}' not in ('ready','listening','paused') then return '{"status":"conflict"}'::jsonb; end if;
   if operation='consent' then
    perform k135z_workspace_private.need(payload->'listeningConsent'='true'::jsonb and r.authority_revision<9007199254740991);
    if r.record#>>'{snapshot,state}'='listening' then return '{"status":"conflict"}'::jsonb; end if;
   elsif not(r.host_authorized and r.listening_authorized and clock_timestamp()<r.authority_until) then
    return '{"status":"denied"}'::jsonb;
   end if;
   -- The provider lookup independently checks the owned OAuth account, original
   -- host, transcript scope, signed event and exact active meeting/stream.
   if coalesce(public.k135z_b5b_storage_v1('capture_source',jsonb_build_object(
    'key','['||to_jsonb(p->>'tenantId')::text||','||to_jsonb(p->>'userId')::text||','||to_jsonb(p->>'agentId')::text||']',
    'meetingUuid',ctx->'meetingUuid','streamId',ctx->'streamId')),'null'::jsonb)='null'::jsonb then
    return '{"status":"denied"}'::jsonb;
   end if;
   -- Lock waits and provider lookup time cannot revive an expired lease.
   if operation='renew' and clock_timestamp()>=r.authority_until then return '{"status":"denied"}'::jsonb; end if;
   update k135z_workspace_private.bindings set
    authority_revision=authority_revision+case when operation='consent' then 1 else 0 end,
    host_authorized=true,listening_authorized=true,authority_until=clock_timestamp()+interval '30 seconds'
    where user_id=u and agent_id=ag returning * into r;
  end if;
 end if;
 fresh=clock_timestamp()<r.authority_until;
 a=jsonb_build_object('context',ctx,'viewerAuthorized',true,'hostAuthorized',r.host_authorized and fresh,
  'listeningAuthorized',r.listening_authorized and fresh);
 if operation='compare_save' then
  perform k135z_workspace_private.context(payload->'context');
  expected=payload->'expected'; perform k135z_workspace_private.fields(expected,array['bindingRevision','authorityRevision','record','authority']);
  if payload->'context'<>ctx or expected<>jsonb_build_object('bindingRevision',r.binding_revision,
   'authorityRevision',r.authority_revision,'record',r.record,'authority',a) then return '{"status":"conflict"}'::jsonb; end if;
  next_record=payload->'record'; perform k135z_workspace_private.transition(r.record,next_record,a);
  update k135z_workspace_private.bindings set record=next_record where user_id=u and agent_id=ag returning * into r;
  a=jsonb_set(a,'{context}',r.record#>'{snapshot,context}');
 end if;
 if operation in ('capture_lease','consent','renew','revoke') then
  lease=case when fresh then greatest(0,least(60000,floor(extract(epoch from (r.authority_until-clock_timestamp()))*1000)))::bigint else 0 end;
  return jsonb_build_object('status','ok','bindingRevision',r.binding_revision,'authorityRevision',r.authority_revision,
   'record',r.record,'authority',a,'validForMs',lease);
 end if;
 return jsonb_build_object('status','ok','bindingRevision',r.binding_revision,'authorityRevision',r.authority_revision,
  'record',r.record,'authority',a);
end $$;
revoke all on all functions in schema k135z_workspace_private from public,anon,authenticated;
grant execute on all functions in schema k135z_workspace_private to service_role;
revoke all on function public.k135z_workspace_commands_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.k135z_workspace_commands_v1(text,jsonb) to service_role;
commit;
