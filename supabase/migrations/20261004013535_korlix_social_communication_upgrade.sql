-- Additive call recovery/history and opt-in browser push. No account is enrolled.
alter table public.korlix_social_calls add column caller_protocol integer not null default 1 check(caller_protocol in(1,2));
alter table public.korlix_social_calls add column callee_protocol integer not null default 1 check(callee_protocol in(1,2));
alter table public.korlix_social_calls add column generation integer not null default 0 check(generation between 0 and 20);
alter table public.korlix_social_call_signals add column generation integer not null default 0 check(generation between 0 and 20);
alter table public.korlix_social_call_signals drop constraint korlix_social_call_signals_kind_check;
alter table public.korlix_social_call_signals add constraint korlix_social_call_signals_kind_check check(kind in('offer','answer','candidate','media','restart_request'));
drop index public.korlix_social_call_description;
create unique index korlix_social_call_description on public.korlix_social_call_signals(call_id,generation,kind) where kind in('offer','answer','restart_request');
create or replace function public.korlix_social_call_view(c public.korlix_social_calls,me uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 select jsonb_build_object('id',c.id,'mode',c.mode,'state',c.state,'incoming',c.callee=me,
  'generation',c.generation,'recovery_supported',c.caller_protocol=2 and c.callee_protocol=2,'created_at',c.created_at,'accepted_at',c.accepted_at,'ended_at',c.ended_at,
  'peer',case when p.suspended or korlix_social_blocked(me,p.id) then jsonb_build_object('id',null,'name','Unavailable member') else korlix_social_card(p) end,
  'can_call',not p.suspended and not korlix_social_blocked(me,p.id) and exists(select 1 from korlix_social_connections n where n.state='accepted' and least(n.requester,n.recipient)=least(me,p.id) and greatest(n.requester,n.recipient)=greatest(me,p.id)))
 from korlix_social_profiles p where p.id=case when c.caller=me then c.callee else c.caller end;
$$;
create function public.korlix_social_call_signal_cleanup() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if new.state not in('ringing','accepted') then delete from korlix_social_call_signals where call_id=new.id; end if;
 return new;
end $$;
create trigger korlix_social_call_signal_cleanup after update of state on public.korlix_social_calls for each row execute function public.korlix_social_call_signal_cleanup();
revoke all on function public.korlix_social_call_signal_cleanup() from public,anon,authenticated;
grant execute on function public.korlix_social_call_signal_cleanup() to service_role;

create or replace function public.korlix_social_calls_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; peer korlix_social_profiles; c korlix_social_calls; existing korlix_social_call_signals;
 device uuid:=(p_data->>'device')::uuid; target uuid; signal_id uuid; signal_kind text; payload jsonb; items jsonb; gen integer; skip integer:=greatest(0,least(5000,coalesce((p_data->>'offset')::integer,0)));
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required to call.' using errcode='42501'; end if;
 if device is null then raise exception 'Reopen Social before calling.'; end if;
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
  if p_action='call_history' then
   select coalesce(jsonb_agg(x.card order by x.created_at desc,x.id),'[]') into items from(
    select korlix_social_call_view(h,me.id) card,h.created_at,h.id from korlix_social_calls h
     where h.caller=me.id or h.callee=me.id order by h.created_at desc,h.id limit 50 offset skip)x;
   return jsonb_build_object('items',items,'offset',skip,'has_more',(select count(*)>skip+50 from korlix_social_calls h where h.caller=me.id or h.callee=me.id));
  end if;
 end if;
 if p_action='call_inbox' then
  select * into c from korlix_social_calls where callee=me.id and state='ringing' and created_at>now()-interval '45 seconds' and caller_seen>now()-interval '60 seconds' order by created_at desc limit 1 for update;
  if c.id is null then return jsonb_build_object('call',null); end if;
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
 if p_action='call_inbox' then return jsonb_build_object('call',case when c.state='ringing' then korlix_social_call_view(c,me.id) else null end); end if;
 if (c.caller=me.id and c.caller_device<>device) or(c.callee=me.id and c.callee_device is not null and c.callee_device<>device) then raise exception 'This call is open on another device or tab.' using errcode='42501'; end if;
 if p_action='call_accept' then
  if c.callee<>me.id then raise exception 'Only the recipient can answer.' using errcode='42501'; end if;
  if c.state='ringing' then update korlix_social_calls set state='accepted',callee_device=device,callee_seen=now(),accepted_at=now(),callee_protocol=coalesce((p_data->>'protocol')::integer,1) where id=c.id returning * into c; end if;
 elsif p_action='call_end' then
  if c.state in ('ringing','accepted') then update korlix_social_calls set state=case when c.state='ringing' and c.callee=me.id then 'declined' else 'ended' end,ended_at=now() where id=c.id returning * into c; end if;
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
revoke all on function public.korlix_social_call_view(public.korlix_social_calls,uuid),public.korlix_social_calls_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_call_view(public.korlix_social_calls,uuid),public.korlix_social_calls_v1(uuid,text,jsonb) to service_role;

-- Subscription secrets and outbox rows are service-only. Payloads never contain
-- message text, contact names, auth identities, or SDP/ICE network information.
create table public.korlix_social_push_subscriptions (
 id uuid primary key default gen_random_uuid(),
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 device uuid not null, binding uuid not null, revision integer not null default 1 check(revision>0), provider text not null default 'web' check(provider='web'),
 subscription jsonb not null check(octet_length(subscription::text)<=4096),
 endpoint text not null unique check(char_length(endpoint)<=2048),
 messages boolean not null default true, calls boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(owner,device)
);
create table public.korlix_social_push_outbox (
 id uuid primary key default gen_random_uuid(),
 subscription_id uuid not null references public.korlix_social_push_subscriptions(id) on delete cascade,
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 binding uuid not null, subscription_revision integer not null check(subscription_revision>0), kind text not null check(kind in('call','message','group_message')),
 event_id uuid not null, created_at timestamptz not null default now(), expires_at timestamptz not null,
 status text not null default 'pending' check(status in('pending','claimed','sending','retry','accepted','unknown','failed','cancelled')),
 attempts integer not null default 0, lease uuid, lease_until timestamptz, next_attempt timestamptz not null default now(),
 unique(subscription_id,kind,event_id)
);
create index korlix_social_push_owner on public.korlix_social_push_outbox(owner,created_at);
create index korlix_social_push_sender on public.korlix_social_push_outbox(sender);
create index korlix_social_push_pending_owner on public.korlix_social_push_outbox(owner,sender,kind) where status in('pending','retry');
create index korlix_social_push_due on public.korlix_social_push_outbox(next_attempt) where status in('pending','retry');
create index korlix_social_push_expiry on public.korlix_social_push_outbox(expires_at);
create index korlix_social_push_subscription_age on public.korlix_social_push_subscriptions(updated_at);
alter table public.korlix_social_push_subscriptions enable row level security;
alter table public.korlix_social_push_outbox enable row level security;
revoke all on public.korlix_social_push_subscriptions,public.korlix_social_push_outbox from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_push_subscriptions,public.korlix_social_push_outbox to service_role;

create function public.korlix_social_push_enqueue() returns trigger language plpgsql security invoker set search_path=public as $$
declare target uuid; source uuid; notification_kind text; expiry timestamptz;
begin
 if tg_table_name='korlix_social_calls' then
  target:=new.callee; source:=new.caller; notification_kind:='call'; expiry:=new.created_at+interval '45 seconds';
 elsif tg_table_name='korlix_social_messages' then
  target:=new.recipient; source:=new.sender; notification_kind:='message'; expiry:=new.created_at+interval '5 minutes';
 else
  -- Generic message alerts coalesce unsent bursts from the same sender; message
  -- history remains authoritative. Queue saturation never rejects chat writes.
  delete from korlix_social_push_outbox where sender=new.sender and kind='group_message' and status in('pending','retry')
   and owner in(select member from korlix_social_group_members where group_id=new.group_id and state='accepted');
  insert into korlix_social_push_outbox(subscription_id,owner,sender,binding,subscription_revision,kind,event_id,expires_at)
   select s.id,s.owner,new.sender,s.binding,s.revision,'group_message',new.id,new.created_at+interval '5 minutes'
   from korlix_social_push_subscriptions s join korlix_social_group_members m on m.member=s.owner and m.group_id=new.group_id
   join korlix_social_profiles p on p.id=s.owner
   where s.messages and s.updated_at>now()-interval '90 days' and m.state='accepted' and m.member<>new.sender
    and not p.suspended and not korlix_social_blocked(s.owner,new.sender)
    and (select count(*) from korlix_social_push_outbox q where q.owner=s.owner and q.status in('pending','retry'))<500
   on conflict do nothing;
  return new;
 end if;
 if notification_kind='message' then
  delete from korlix_social_push_outbox where owner=target and sender=source and kind='message' and status in('pending','retry');
 end if;
 insert into korlix_social_push_outbox(subscription_id,owner,sender,binding,subscription_revision,kind,event_id,expires_at)
  select s.id,s.owner,source,s.binding,s.revision,notification_kind,new.id,expiry from korlix_social_push_subscriptions s
  join korlix_social_profiles p on p.id=s.owner
  where s.owner=target and not p.suspended and s.updated_at>now()-interval '90 days'
   and case when notification_kind='call' then s.calls else s.messages end
   and not korlix_social_blocked(target,source)
   and (notification_kind='call' or (select count(*) from korlix_social_push_outbox q where q.owner=target and q.status in('pending','retry'))<500)
  on conflict do nothing;
 return new;
end $$;
create trigger korlix_social_push_call after insert on public.korlix_social_calls for each row execute function public.korlix_social_push_enqueue();
create trigger korlix_social_push_message after insert on public.korlix_social_messages for each row execute function public.korlix_social_push_enqueue();
create trigger korlix_social_push_group after insert on public.korlix_social_group_messages for each row execute function public.korlix_social_push_enqueue();

create function public.korlix_social_push_allowed(o public.korlix_social_push_outbox) returns boolean
language plpgsql volatile security invoker set search_path=public as $$
begin
 if o.expires_at<=clock_timestamp() or not exists(select 1 from korlix_social_push_subscriptions s where s.id=o.subscription_id and s.owner=o.owner and s.binding=o.binding and s.revision=o.subscription_revision
  and s.updated_at>now()-interval '90 days' and case when o.kind='call' then s.calls else s.messages end)
  or not exists(select 1 from korlix_social_profiles p where p.id=o.owner and not p.suspended)
  or not exists(select 1 from korlix_social_profiles p where p.id=o.sender and not p.suspended)
  or korlix_social_blocked(o.owner,o.sender) then return false; end if;
 if o.kind in('call','message') and not exists(select 1 from korlix_social_connections c where c.state='accepted' and least(c.requester,c.recipient)=least(o.owner,o.sender) and greatest(c.requester,c.recipient)=greatest(o.owner,o.sender)) then return false; end if;
 if o.kind='call' then
  return exists(select 1 from korlix_social_calls c where c.id=o.event_id and c.caller=o.sender and c.callee=o.owner and c.state='ringing' and c.created_at>clock_timestamp()-interval '45 seconds');
 elsif o.kind='message' then
  return exists(select 1 from korlix_social_messages m where m.id=o.event_id and m.sender=o.sender and m.recipient=o.owner and not m.deleted and m.read_at is null and not korlix_social_dumped(o.owner,'direct',m.id));
 else
  return exists(select 1 from korlix_social_group_messages m join korlix_social_group_members g on g.group_id=m.group_id and g.member=o.owner
   join korlix_social_groups parent on parent.id=m.group_id
   where m.id=o.event_id and m.sender=o.sender and not m.deleted and not parent.archived and g.state='accepted' and m.seq>greatest(g.joined_after,g.last_read) and not korlix_social_dumped(o.owner,'group',m.id));
 end if;
end $$;

create function public.korlix_social_push_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; s korlix_social_push_subscriptions; o korlix_social_push_outbox;
 items jsonb; subscription_data jsonb; endpoint_text text; outcome text; device_id uuid;
begin
 if p_action in('claim','authorize','finish') then
  if p_actor is not null then raise exception 'Worker action unavailable.' using errcode='42501'; end if;
  if p_action='claim' then
   -- A crashed sender is never replayed because Web Push has no idempotency key.
   update korlix_social_push_outbox set status='unknown',lease_until=null where status='sending' and lease_until<now();
   update korlix_social_push_outbox set status='pending',lease=null,lease_until=null where status='claimed' and lease_until<now();
   update korlix_social_push_outbox set status='cancelled',lease_until=null where status in('pending','retry','claimed') and expires_at<=now();
   delete from korlix_social_push_outbox where expires_at<now()-interval '7 days';
   delete from korlix_social_push_subscriptions where updated_at<now()-interval '90 days';
   -- Retain call metadata for 30 days, but discard SDP/ICE immediately on end.
   update korlix_social_calls set state=case when state='ringing' then 'missed' else 'ended' end,ended_at=now()
    where state in('ringing','accepted') and ((state='ringing' and created_at<now()-interval '45 seconds') or caller_seen<now()-interval '60 seconds' or (state='accepted' and callee_seen<now()-interval '60 seconds') or created_at<now()-interval '4 hours');
   delete from korlix_social_calls where created_at<now()-interval '30 days';
   with due as(select id from korlix_social_push_outbox where status in('pending','retry') and next_attempt<=now() and expires_at>now() order by (kind='call') desc,expires_at,next_attempt,id limit 20 for update skip locked),
   claimed as(update korlix_social_push_outbox q set status='claimed',lease=gen_random_uuid(),lease_until=now()+interval '30 seconds' from due where q.id=due.id returning q.id,q.lease,q.kind,q.expires_at,q.next_attempt)
   select coalesce(jsonb_agg(jsonb_build_object('id',claimed.id,'lease',claimed.lease) order by (claimed.kind='call') desc,claimed.expires_at,claimed.next_attempt,claimed.id),'[]') into items from claimed;
   return jsonb_build_object('items',items);
  end if;
  select * into o from korlix_social_push_outbox where id=(p_data->>'id')::uuid and lease=(p_data->>'lease')::uuid for update;
  if o.id is null then return jsonb_build_object('delivery',null); end if;
  if p_action='authorize' then
   if o.status<>'claimed' or o.lease_until<=now() then return jsonb_build_object('delivery',null); end if;
   if not korlix_social_push_allowed(o) then
    update korlix_social_push_outbox set status='cancelled',lease_until=null where id=o.id;
    return jsonb_build_object('delivery',null);
   end if;
   select * into s from korlix_social_push_subscriptions where id=o.subscription_id;
   update korlix_social_push_outbox set status='sending',attempts=attempts+1 where id=o.id;
   return jsonb_build_object('delivery',jsonb_build_object('subscription',s.subscription,'kind',o.kind,'event_id',o.event_id,'binding',o.binding,'expires_at',o.expires_at));
  end if;
  if o.status not in('sending','claimed') then return jsonb_build_object('ok',true); end if;
  outcome:=p_data->>'status';
  if outcome='expired' then
   delete from korlix_social_push_subscriptions where id=o.subscription_id and binding=o.binding and revision=o.subscription_revision;
   if not found then update korlix_social_push_outbox set status='cancelled',lease_until=null where id=o.id; end if;
   return jsonb_build_object('ok',true);
  end if;
  if outcome not in('accepted','unknown','retry','failed','cancelled') then raise exception 'Invalid notification outcome.'; end if;
  if outcome='retry' and (o.attempts>=3 or o.expires_at<now()+interval '15 seconds') then outcome:='failed'; end if;
  update korlix_social_push_outbox set status=outcome,lease_until=null,next_attempt=now()+interval '15 seconds' where id=o.id;
  return jsonb_build_object('ok',true);
 end if;
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null then raise exception 'Create your Social profile before enabling notifications.' using errcode='42501'; end if;
 -- Unsubscribe remains available after suspension, so users can revoke devices.
 if me.suspended and p_action<>'unsubscribe' then raise exception 'Social notifications are unavailable for this account.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('social-push:'||me.id::text,0));
 if p_action='state' then
  select coalesce(jsonb_agg(jsonb_build_object('device',device,'messages',messages,'calls',calls,'updated_at',updated_at)),'[]') into items from korlix_social_push_subscriptions where owner=me.id;
  return jsonb_build_object('subscriptions',items);
 end if;
 device_id:=(p_data->>'device')::uuid;
 if device_id is null then raise exception 'Choose this browser notification device.'; end if;
 if p_action='unsubscribe' then
  delete from korlix_social_push_subscriptions where owner=me.id and device=device_id;
  return jsonb_build_object('ok',true);
 elsif p_action='subscribe' then
  perform korlix_social_limit(p_actor,'push-subscribe',30,3600);
  subscription_data:=p_data->'subscription'; endpoint_text:=subscription_data->>'endpoint';
  if jsonb_typeof(subscription_data) is distinct from 'object' or endpoint_text is null or endpoint_text!~'^https://' or octet_length(subscription_data::text)>4096 or p_data->>'binding' is null
   or jsonb_typeof(p_data->'messages') is distinct from 'boolean' or jsonb_typeof(p_data->'calls') is distinct from 'boolean' then raise exception 'Invalid browser notification settings.'; end if;
  select * into s from korlix_social_push_subscriptions where owner=me.id and device=device_id;
  if s.id is null and (select count(*) from korlix_social_push_subscriptions where owner=me.id)>=10 then raise exception 'Remove an old browser before adding another notification device.'; end if;
  -- A subscription cannot be moved between accounts. Logout unsubscribes in the
  -- browser, which obtains a fresh endpoint before enrolling another account.
  if exists(select 1 from korlix_social_push_subscriptions where endpoint=endpoint_text and (owner<>me.id or device<>device_id)) then raise exception 'Turn browser notifications off, then enable them again on this account.'; end if;
  delete from korlix_social_push_outbox where subscription_id=s.id and status in('pending','retry','claimed');
  insert into korlix_social_push_subscriptions(owner,device,binding,subscription,endpoint,messages,calls)
   values(me.id,device_id,(p_data->>'binding')::uuid,subscription_data,endpoint_text,(p_data->>'messages')::boolean,(p_data->>'calls')::boolean)
   on conflict(owner,device) do update set binding=excluded.binding,revision=korlix_social_push_subscriptions.revision+1,subscription=excluded.subscription,endpoint=excluded.endpoint,messages=excluded.messages,calls=excluded.calls,updated_at=now();
  return jsonb_build_object('ok',true,'device',device_id);
 end if;
 raise exception 'Notification action unavailable.';
end $$;
revoke all on function public.korlix_social_push_enqueue(),public.korlix_social_push_allowed(public.korlix_social_push_outbox),public.korlix_social_push_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_push_enqueue(),public.korlix_social_push_allowed(public.korlix_social_push_outbox),public.korlix_social_push_v1(uuid,text,jsonb) to service_role;
