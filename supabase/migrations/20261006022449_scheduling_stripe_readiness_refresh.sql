-- Apply before the merchant-readiness backend release. Existing callers remain compatible.
begin;
create or replace function public.korlix_schedule_connections_v2(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare c public.korlix_schedule_connections; a public.korlix_schedule_oauth; ids text[];
begin
 if not public.korlix_schedule_active_v1(p_actor) or not exists(select 1 from public.korlix_schedule_profiles where owner_id=p_actor) then raise exception using errcode='42501',message='Save your verified host profile first.';end if;
 if p_action='list' then return jsonb_build_object('connections',coalesce((select jsonb_agg(to_jsonb(q)-'owner_id'-'sealed_grant'-'config_hash'-'lease_id'-'lease_until' order by q.created_at) from public.korlix_schedule_connections q where owner_id=p_actor),'[]'),'pending',coalesce((select jsonb_agg(jsonb_build_object('id',id,'provider',provider,'status',status,'identity',identity,'expires_at',expires_at)) from public.korlix_schedule_oauth where owner_id=p_actor and expires_at>now() and status in ('pending','launched','exchanging','ready')),'[]'));end if;
 perform 1 from public.user_profiles where id=p_actor for update;
 if p_action='start' then
  if (select count(*) from public.korlix_schedule_oauth where owner_id=p_actor and created_at>now()-interval '1 hour')>=20 then raise exception using errcode='54000',message='Too many connection attempts. Try again later.';end if;
  update public.korlix_schedule_oauth set status='failed',sealed_secrets='',sealed_grant=null where owner_id=p_actor and provider=p_data->>'provider' and status in ('pending','launched','exchanging','ready');
  insert into public.korlix_schedule_oauth(id,owner_id,provider,ticket_hash,state_hash,sealed_secrets,config_hash)values(p_id,p_actor,p_data->>'provider',p_data->>'ticket_hash',p_data->>'state_hash',p_data->>'sealed_secrets',p_data->>'config_hash');
  return jsonb_build_object('started',true);
 elsif p_action in ('ready','finish') then
  select * into a from public.korlix_schedule_oauth where id=p_id and owner_id=p_actor and expires_at>now() and status='ready' for update;
  if a.id is null then raise exception 'This connection attempt expired. Start again.';end if;
  if p_action='ready' then return to_jsonb(a);end if;
  if p_data->>'confirmed' is distinct from 'true' or a.config_hash<>p_data->>'config_hash' then raise exception 'Review the connected account again.';end if;
  -- Fresh provider identity is supplied only by the authenticated server.
  -- Older deployed callers omit it and retain the existing behavior.
  if p_data ? 'identity' then
   if jsonb_typeof(p_data->'identity') is distinct from 'object'
      or p_data->'identity'->>'id' is distinct from a.identity->>'id'
      or (a.provider='stripe' and (p_data->'identity'->'livemode' is distinct from a.identity->'livemode'
          or jsonb_typeof(p_data->'identity'->'charges_enabled') is distinct from 'boolean')) then
    raise exception using errcode='40001',message='The connected account changed. Start again.';
   end if;
   a.identity:=p_data->'identity';
  end if;
  if a.provider='stripe' then
   perform pg_advisory_xact_lock(hashtextextended('schedule-stripe:'||(a.identity->>'id'),0));
   if exists(select 1 from public.korlix_schedule_connections where provider='stripe' and remote_id=a.identity->>'id' and owner_id<>p_actor) then raise exception 'This merchant account is linked to another KORLIX host.';end if;
   update public.korlix_schedule_connections set enabled=false,revision=revision+1 where owner_id=p_actor and provider='stripe';
  end if;
  if (select count(*) from public.korlix_schedule_connections where owner_id=p_actor and provider<>'stripe' and state<>'disconnected')>=5 and not exists(select 1 from public.korlix_schedule_connections where owner_id=p_actor and provider=a.provider and remote_id=a.identity->>'id') then raise exception 'Disconnect an account before adding more than five calendar accounts.';end if;
  insert into public.korlix_schedule_connections(owner_id,provider,remote_id,label,sealed_grant,config_hash,charges_enabled,livemode,enabled)
   values(p_actor,a.provider,a.identity->>'id',a.identity->>'label',p_data->>'sealed_grant',a.config_hash,coalesce((a.identity->>'charges_enabled')::boolean,false),(a.identity->>'livemode')::boolean,a.provider='stripe')
   on conflict(owner_id,provider,remote_id)do update set sealed_grant=excluded.sealed_grant,config_hash=excluded.config_hash,state='connected',charges_enabled=excluded.charges_enabled,livemode=excluded.livemode,label=excluded.label,enabled=case when excluded.provider='stripe' then true else korlix_schedule_connections.enabled end,revision=korlix_schedule_connections.revision+1,last_error=null,updated_at=now() returning * into c;
  update public.korlix_schedule_oauth set status='finished',sealed_secrets='',sealed_grant=null where id=a.id;
  insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,a.provider||'_connected');
  return jsonb_build_object('id',c.id,'saved',true);
 end if;
 select * into c from public.korlix_schedule_connections where id=p_id and owner_id=p_actor for update;
 if c.id is null then raise exception using errcode='P0002',message='Connection not found.';end if;
 if p_action='private' then return to_jsonb(c);end if;
 if p_action='stripe_readiness' then
  if c.provider<>'stripe' or c.state<>'connected' or not c.enabled
     or c.revision is distinct from (p_data->>'revision')::int
     or c.config_hash is distinct from p_data->>'config_hash'
     or c.remote_id is distinct from p_data->'identity'->>'id'
     or to_jsonb(c.livemode) is distinct from p_data->'identity'->'livemode'
     or jsonb_typeof(p_data->'identity'->'charges_enabled') is distinct from 'boolean' then
   raise exception using errcode='40001',message='The merchant connection changed. Refresh again.';
  end if;
  if p_data->'identity'->>'charges_enabled'='true' and (
     p_data->'identity'->>'readiness_source' is distinct from 'accounts_v2'
     or p_data->'identity'->>'card_payments_status' is distinct from 'active'
     or p_data->'identity'->>'payouts_status' is distinct from 'active') then
   raise exception 'Merchant capabilities could not be verified.';
  end if;
  update public.korlix_schedule_connections
   set charges_enabled=(p_data->'identity'->>'charges_enabled')::boolean,
       label=p_data->'identity'->>'label',revision=revision+1,updated_at=now()
   where id=c.id and (charges_enabled is distinct from (p_data->'identity'->>'charges_enabled')::boolean
                     or label is distinct from p_data->'identity'->>'label');
  return jsonb_build_object('saved',true);
 elsif p_action='calendar_list' then
  if c.revision<>(p_data->>'revision')::int then raise exception using errcode='40001',message='The connection changed. Refresh again.';end if;
  update public.korlix_schedule_connections set calendars=p_data->'calendars' where id=c.id;
 elsif p_action='settings' then
  if p_data->>'confirmed' is distinct from 'true' or c.revision<>(p_data->>'revision')::int or c.provider='stripe' then raise exception using errcode='40001',message='Review the latest calendar settings.';end if;
  ids:=array(select distinct jsonb_array_elements_text(p_data->'busy_ids'));
  if cardinality(ids) not between 1 and 5 or exists(select 1 from unnest(ids)x where not exists(select 1 from jsonb_array_elements(c.calendars)y where y->>'id'=x)) then raise exception 'Choose one to five calendars from this account.';end if;
  if nullif(p_data->>'write_id','') is not null and not exists(select 1 from jsonb_array_elements(c.calendars)y where y->>'id'=p_data->>'write_id' and y->>'writable'='true') then raise exception 'Choose a calendar you can edit.';end if;
  if nullif(p_data->>'write_id','') is not null then update public.korlix_schedule_connections set write_id=null,revision=revision+1 where owner_id=p_actor and id<>c.id and write_id is not null;end if;
  update public.korlix_schedule_connections set busy_ids=ids,write_id=nullif(p_data->>'write_id',''),enabled=true,revision=revision+1,lease_until=null,last_error=null where id=c.id;
 elsif p_action='disconnect' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'Confirm disconnection.';end if;
  if c.provider='stripe' and exists(select 1 from public.korlix_schedule_payments p join public.korlix_schedule_bookings b on b.id=p.booking_id where p.connection_id=c.id and (b.state='awaiting_payment' and b.hold_expires_at>now() or p.payment_state='unpaid' and p.checkout_wire is not null and not p.checkout_closed or p.refund_state in ('required','sending','pending'))) then raise exception 'Complete open payments and refunds before disconnecting.';end if;
  update public.korlix_schedule_connections set state='disconnected',sealed_grant=null,enabled=false,revision=revision+1,write_id=null,busy_ids='{}' where id=c.id;
  update public.korlix_schedule_calendar_links set state='failed',last_error='Calendar disconnected. Existing external entries must be managed in the calendar.' where connection_id=c.id and state='pending';
 else raise exception 'Unsupported connection action.';end if;
 insert into public.korlix_schedule_audit(owner_id,action)values(p_actor,'connection_'||p_action);
 return jsonb_build_object('saved',true);
end;
$$;
revoke all on function public.korlix_schedule_connections_v2(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_schedule_connections_v2(uuid,text,uuid,jsonb) to service_role;
commit;
