-- Persist recipient acknowledgment across devices; existing call history retains
-- its 30-day limit and remains inaccessible to browser database roles.
alter table public.korlix_social_calls add column missed_seen_at timestamptz;
create index korlix_social_calls_missed on public.korlix_social_calls(callee,created_at desc)
 include(caller,missed_seen_at) where state='missed';

-- An unanswered attempt is missed even when the caller hangs up before timeout.
-- Repair retained legacy attempts without changing answered or declined calls.
update public.korlix_social_calls set state='missed'
 where state='ended' and accepted_at is null and ended_at is not null
  and created_at>=now()-interval '30 days';

create or replace function public.korlix_social_calls_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; peer korlix_social_profiles; c korlix_social_calls; existing korlix_social_call_signals;
 device uuid:=(p_data->>'device')::uuid; target uuid; signal_id uuid; signal_kind text; payload jsonb; items jsonb; gen integer; missed_count integer:=0; missed_total integer:=0; through_at timestamptz; skip integer:=greatest(0,least(5000,coalesce((p_data->>'offset')::integer,0)));
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required to call.' using errcode='42501'; end if;
 if device is null then raise exception 'Reopen Social before calling.'; end if;
 if p_action='call_history_read' then
  begin through_at:=least(now(),(p_data->>'through')::timestamptz);
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'Refresh call history before marking it seen.'; end;
  if nullif(p_data->>'through','') is null then raise exception 'Refresh call history before marking it seen.'; end if;
  -- Acknowledge the displayed snapshot only. An incoming attempt that ends later
  -- remains new, including calls arriving during the read/acknowledgment roundtrip.
  update korlix_social_calls set missed_seen_at=now()
   where callee=me.id and state='missed' and missed_seen_at is null
    and ended_at<=through_at and created_at>=now()-interval '30 days';
  return jsonb_build_object('missed_count',(select count(*) from korlix_social_calls
   where callee=me.id and state='missed' and missed_seen_at is null and created_at>=now()-interval '30 days'));
 end if;
 -- Deterministic participant locks prevent simultaneous/crossed calls across tabs.
 -- Mutations on an existing call serialize on its row. Calls never auto-answer.
 if p_action='call_start' then
  target:=(p_data->>'peer')::uuid;
  if target is null or target=me.id then raise exception 'Choose another connection.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-call-member:'||least(me.id,target)::text,0));
  perform pg_advisory_xact_lock(hashtextextended('social-call-member:'||greatest(me.id,target)::text,0));
  perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target)::text||greatest(me.id,target)::text,0));
  select * into peer from korlix_social_profiles where id=target;
  if peer.id is null or peer.suspended or korlix_social_blocked(me.id,target) or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target)) then raise exception 'An accepted connection is needed to call.' using errcode='42501'; end if;
  select * into c from korlix_social_calls where id=(p_data->>'id')::uuid;
  if c.id is not null then
   if c.caller<>me.id or c.callee<>target or c.caller_device<>device then raise exception 'Call ID unavailable.' using errcode='42501'; end if;
   return jsonb_build_object('call',korlix_social_call_view(c,me.id));
  end if;
  update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now()
   where (caller in(me.id,target) or callee in(me.id,target)) and state in ('ringing','accepted')
    and ((state='ringing' and created_at<now()-interval '45 seconds') or caller_seen<now()-interval '60 seconds' or (state='accepted' and callee_seen<now()-interval '60 seconds') or created_at<now()-interval '4 hours');
  if exists(select 1 from korlix_social_calls where (caller in(me.id,target) or callee in(me.id,target)) and state in ('ringing','accepted')) then raise exception 'You or this connection are already in a call.'; end if;
  perform korlix_social_limit(p_actor,'call',10,600);
  insert into korlix_social_calls(id,caller,callee,caller_device,mode,caller_protocol) values((p_data->>'id')::uuid,me.id,target,device,p_data->>'mode',coalesce((p_data->>'protocol')::integer,1)) returning * into c;
  return jsonb_build_object('call',korlix_social_call_view(c,me.id));
 end if;
 if p_action in ('call_inbox','call_history') then
  update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now()
   where (caller=me.id or callee=me.id) and state in ('ringing','accepted') and
    ((state='ringing' and created_at<now()-interval '45 seconds') or caller_seen<now()-interval '60 seconds'
     or (state='accepted' and callee_seen<now()-interval '60 seconds') or created_at<now()-interval '4 hours'
     or korlix_social_blocked(caller,callee)
     or exists(select 1 from korlix_social_profiles p where p.id in(caller,callee) and p.suspended)
     or not exists(select 1 from korlix_social_connections n where n.state='accepted' and least(n.requester,n.recipient)=least(caller,callee) and greatest(n.requester,n.recipient)=greatest(caller,callee)));
  delete from korlix_social_calls where created_at<now()-interval '30 days' and (caller=me.id or callee=me.id);
  select count(*) filter(where missed_seen_at is null),count(*) into missed_count,missed_total
   from korlix_social_calls where callee=me.id and state='missed' and created_at>=now()-interval '30 days';
  if p_action='call_history' then
   select coalesce(jsonb_agg(x.card order by x.created_at desc,x.id),'[]') into items from(
    select korlix_social_call_view(h,me.id)||jsonb_build_object(
      'peer_missed_count',count(*) filter(where h.callee=me.id and h.state='missed') over(partition by h.caller)) card,
      h.created_at,h.id from korlix_social_calls h
     where h.caller=me.id or h.callee=me.id order by h.created_at desc,h.id limit 50 offset skip)x;
   return jsonb_build_object('items',items,'missed_total',missed_total,'missed_count',missed_count,'missed_as_of',now(),'offset',skip,'has_more',(select count(*)>skip+50 from korlix_social_calls h where h.caller=me.id or h.callee=me.id));
  end if;
 end if;
 if p_action='call_inbox' then
  select * into c from korlix_social_calls where callee=me.id and state='ringing' and created_at>now()-interval '45 seconds' and caller_seen>now()-interval '60 seconds' order by created_at desc limit 1 for update;
  if c.id is null then return jsonb_build_object('call',null,'missed_count',missed_count); end if;
 else
  select * into c from korlix_social_calls where id=(p_data->>'id')::uuid and (caller=me.id or callee=me.id) for update;
  if c.id is null then raise exception 'Call not found.' using errcode='P0002'; end if;
 end if;
 target:=case when c.caller=me.id then c.callee else c.caller end;
 if c.state in ('ringing','accepted') and
  (korlix_social_blocked(me.id,target) or exists(select 1 from korlix_social_profiles where id=target and suspended)
   or not exists(select 1 from korlix_social_connections where state='accepted' and least(requester,recipient)=least(me.id,target) and greatest(requester,recipient)=greatest(me.id,target))
   or (c.state='ringing' and c.created_at<now()-interval '45 seconds') or c.caller_seen<now()-interval '60 seconds'
   or(c.state='accepted' and c.callee_seen<now()-interval '60 seconds') or c.created_at<now()-interval '4 hours') then
  update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now() where id=c.id returning * into c;
 end if;
 if p_action='call_inbox' then return jsonb_build_object('call',case when c.state='ringing' then korlix_social_call_view(c,me.id) else null end,'missed_count',missed_count); end if;
 if (c.caller=me.id and c.caller_device<>device) or(c.callee=me.id and c.callee_device is not null and c.callee_device<>device) then raise exception 'This call is open on another device or tab.' using errcode='42501'; end if;
 if p_action='call_accept' then
  if c.callee<>me.id then raise exception 'Only the recipient can answer.' using errcode='42501'; end if;
  if c.state='ringing' then update korlix_social_calls set state='accepted',callee_device=device,callee_seen=now(),accepted_at=now(),callee_protocol=coalesce((p_data->>'protocol')::integer,1) where id=c.id returning * into c; end if;
 elsif p_action='call_end' then
  if c.state in ('ringing','accepted') then update korlix_social_calls set state=case when c.state='ringing' and c.callee=me.id then 'declined' when c.state='ringing' then 'missed' else 'ended' end,ended_at=now() where id=c.id returning * into c; end if;
 elsif p_action='call_restart' then
  if c.caller_protocol<>2 or c.callee_protocol<>2 then raise exception 'Both callers need the latest KORLIX version to reconnect.' using errcode='42501'; end if;
  if c.state<>'accepted' then raise exception 'This call is not connected.' using errcode='42501'; end if;
  if c.caller<>me.id then raise exception 'Only the caller can restart the connection.' using errcode='42501'; end if;
  gen:=(p_data->>'generation')::integer;
  if gen is null or gen<0 or gen>c.generation then raise exception 'Refresh this call before reconnecting.'; end if;
  if gen=c.generation then
   if c.generation>=20 then raise exception 'Please end this call and start a new one.'; end if;
   if not exists(select 1 from korlix_social_call_signals where call_id=c.id and generation=c.generation and kind='answer') then
    raise exception 'Wait for the current connection attempt to finish.';
   end if;
   perform korlix_social_limit(p_actor,'call-restart',6,60);
   update korlix_social_calls set generation=generation+1 where id=c.id returning * into c;
  end if;
 elsif p_action='call_signal' then
  if c.state<>'accepted' then raise exception 'This call is not connected.' using errcode='42501'; end if;
  signal_id:=(p_data->>'signal_id')::uuid; signal_kind:=p_data->>'kind'; payload:=p_data->'payload';
  if signal_id is null or jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>200000 then raise exception 'Invalid call signal.'; end if;
  gen:=coalesce((payload->>'generation')::integer,0);
  if signal_kind<>'media' and gen<>c.generation then raise exception 'This connection attempt has expired.' using errcode='40001'; end if;
  if signal_kind='media' then gen:=c.generation; end if;
  if signal_kind in ('offer','answer') then
   if (signal_kind='offer' and c.caller<>me.id) or(signal_kind='answer' and c.callee<>me.id) then raise exception 'Signal sender unavailable.' using errcode='42501'; end if;
   if jsonb_typeof(payload->'sdp') is distinct from 'string' or char_length(payload->>'sdp') not between 1 and 190000 then raise exception 'Invalid call description.'; end if;
   if signal_kind='answer' and not exists(select 1 from korlix_social_call_signals where call_id=c.id and generation=gen and kind='offer') then raise exception 'Wait for the caller connection offer.'; end if;
  elsif signal_kind='restart_request' then
   if c.caller_protocol<>2 or c.callee_protocol<>2 then raise exception 'Both callers need the latest KORLIX version to reconnect.' using errcode='42501'; end if;
   if c.callee<>me.id then raise exception 'Only the recipient requests a reconnect.' using errcode='42501'; end if;
   if exists(select 1 from korlix_social_call_signals where call_id=c.id and generation=gen and kind='restart_request' and id<>signal_id) then
    return jsonb_build_object('call',korlix_social_call_view(c,me.id),'signals','[]'::jsonb);
   end if;
  elsif signal_kind='candidate' then
   if jsonb_typeof(payload->'candidate') is distinct from 'string' or char_length(payload->>'candidate')>4000 then raise exception 'Invalid network candidate.'; end if;
  elsif signal_kind='media' then
   if jsonb_typeof(payload->'camera') is distinct from 'boolean' or jsonb_typeof(payload->'microphone') is distinct from 'boolean' then raise exception 'Invalid media state.'; end if;
  else raise exception 'Signal unavailable.'; end if;
  select * into existing from korlix_social_call_signals where id=signal_id;
  if existing.id is not null then
   if existing.call_id<>c.id or existing.sender<>me.id or existing.kind<>signal_kind or existing.payload<>payload then raise exception 'Signal ID unavailable.' using errcode='42501'; end if;
  else
   perform korlix_social_limit(p_actor,'call-signal',300,60);
   insert into korlix_social_call_signals(id,call_id,sender,kind,payload,generation) values(signal_id,c.id,me.id,signal_kind,payload,gen);
  end if;
 elsif p_action<>'call_poll' then raise exception 'Call action unavailable.'; end if;
 if c.state in ('ringing','accepted') then
  update korlix_social_calls set caller_seen=case when caller=me.id then now() else caller_seen end,
   callee_seen=case when callee=me.id and state='accepted' then now() else callee_seen end where id=c.id returning * into c;
 else
  delete from korlix_social_call_signals where call_id=c.id;
 end if;
 if p_action='call_poll' and c.state='accepted' then
  select coalesce(jsonb_agg(x.item order by x.seq),'[]') into items from(
   select s.seq,jsonb_build_object('seq',s.seq,'kind',s.kind,'payload',s.payload,'generation',s.generation) item from korlix_social_call_signals s
   where s.call_id=c.id and s.sender<>me.id and s.seq>greatest(0,coalesce((p_data->>'after')::bigint,0)) order by s.seq limit 100)x;
 end if;
 return jsonb_build_object('call',korlix_social_call_view(c,me.id),'signals',coalesce(items,'[]'));
end $$;
revoke all on function public.korlix_social_calls_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_calls_v1(uuid,text,jsonb) to service_role;
