begin;
-- A durable command can outlive its Render process. Recovery closes a generation;
-- it never grants consent, reconnects media, or replays the abandoned command.
alter table k135z_workspace_private.bindings
 add column record_touched_at timestamptz not null default clock_timestamp();

create function k135z_workspace_private.touch_record() returns trigger
language plpgsql security invoker set search_path=pg_catalog,pg_temp as $$
begin
 if new.record is distinct from old.record then
  new.record_touched_at=clock_timestamp();
 end if;
 return new;
end $$;
revoke all on function k135z_workspace_private.touch_record() from public,anon,authenticated;
grant execute on function k135z_workspace_private.touch_record() to service_role;
create trigger touch_workspace_record before update of record
 on k135z_workspace_private.bindings for each row
 execute function k135z_workspace_private.touch_record();

-- Extend the installed RPC without replacing its entitlement/ownership checks,
-- row locks, consent logic, or compare-and-save fences.
do $migration$
declare source text; anchor text; recovery text;
begin
 source=pg_get_functiondef('public.k135z_workspace_commands_v1(text,jsonb)'::regprocedure);
 anchor=E' perform k135z_workspace_private.record(r.record);\n ctx=r.record#>''{snapshot,context}'';';
 recovery=$recovery$
 perform k135z_workspace_private.record(r.record);
 -- Only reconcile after the existing principal checks and binding row lock.
 if operation in ('read','capture_lease')
  and r.record#>>'{snapshot,state}'<>'stopped'
  and (r.record->'pending'<>'null'::jsonb or r.record#>>'{snapshot,state}' in ('listening','paused'))
  and r.authority_until<clock_timestamp()-interval '60 seconds'
  and r.record_touched_at<clock_timestamp()-interval '60 seconds' then
  perform k135z_workspace_private.need(r.authority_revision<9007199254740991
   and k135z_workspace_private.uint(r.record->'version')<9007199254740991
   and k135z_workspace_private.uint(r.record#>'{snapshot,revision}')<9007199254740991);
  next_record=r.record||jsonb_build_object('version',k135z_workspace_private.uint(r.record->'version')+1,
   'pending',null,'uncertain',false,'snapshot',(r.record->'snapshot')||jsonb_build_object(
    'revision',k135z_workspace_private.uint(r.record#>'{snapshot,revision}')+1,
    'state','stopped','hostAuthorized',false,'listeningAuthorized',false));
  perform k135z_workspace_private.record(next_record);
  update k135z_workspace_private.bindings set record=next_record,
   authority_revision=authority_revision+1,host_authorized=false,listening_authorized=false,
   authority_until='-infinity' where user_id=u and agent_id=ag returning * into r;
 end if;
 ctx=r.record#>'{snapshot,context}';$recovery$;
 if position(anchor in source)=0 or position('record_touched_at' in source)>0 then
  raise exception 'K135Z_RECOVERY_UNEXPECTED_RPC';
 end if;
 execute replace(source,anchor,recovery);
end $migration$;
commit;
