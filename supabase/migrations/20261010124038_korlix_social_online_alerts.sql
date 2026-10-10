-- Opt-in, accepted-connection online alerts. Browser roles have no direct access.
do $guard$ begin
 if (select md5(prosrc) from pg_proc where oid='public.korlix_social_push_allowed(public.korlix_social_push_outbox)'::regprocedure) is distinct from '39f5859c5066d8a041fd7d6e34e54df4'
 or (select md5(prosrc) from pg_proc where oid='public.korlix_social_push_v1(uuid,text,jsonb)'::regprocedure) is distinct from 'bde9785ee632dec881ab5a89c7672658' then
  raise exception 'Social push baseline changed; review before applying online alerts.';
 end if;
end $guard$;
alter table public.korlix_social_push_subscriptions add column online boolean not null default false;
alter table public.korlix_social_push_outbox drop constraint korlix_social_push_outbox_kind_check;
alter table public.korlix_social_push_outbox add constraint korlix_social_push_outbox_kind_check check(kind in('call','message','group_message','online'));
create table public.korlix_social_online_watches (
 watcher uuid not null references public.korlix_social_profiles(id) on delete cascade,
 target uuid not null references public.korlix_social_profiles(id) on delete cascade,
 sound text not null default 'bell' check(sound in('bell','ring','silent')),
 created_at timestamptz not null default now(), last_alert_at timestamptz,
 primary key(watcher,target), check(watcher<>target)
);
create index korlix_social_online_watches_target on public.korlix_social_online_watches(target);
-- Keep only the latest short-lived event per selected connection, not a presence history.
create table public.korlix_social_online_events (
 watcher uuid not null, target uuid not null, id uuid not null unique default gen_random_uuid(),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '90 seconds',
 primary key(watcher,target),
 foreign key(watcher,target) references public.korlix_social_online_watches(watcher,target) on delete cascade
);
create index korlix_social_online_events_target on public.korlix_social_online_events(target);
create index korlix_social_online_events_expiry on public.korlix_social_online_events(expires_at);
alter table public.korlix_social_online_watches enable row level security;
alter table public.korlix_social_online_events enable row level security;
revoke all on public.korlix_social_online_watches,public.korlix_social_online_events from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_online_watches,public.korlix_social_online_events to service_role;

create function public.korlix_social_online_connected(watcher uuid,target uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select $1<>$2 and not public.korlix_social_blocked($1,$2)
 and exists(select 1 from public.korlix_social_profiles where id=$1 and not suspended)
 and exists(select 1 from public.korlix_social_profiles where id=$2 and not suspended)
 and exists(select 1 from public.korlix_social_connections where state='accepted'
  and least(requester,recipient)=least($1,$2) and greatest(requester,recipient)=greatest($1,$2));
$$;

create function public.korlix_social_online_transition() returns trigger
language plpgsql security invoker set search_path=public as $$
begin
 -- Updating the profile serializes simultaneous heartbeats across devices.
 if new.suspended or not new.show_online or new.last_seen is null or new.last_seen<=now()-interval '90 seconds' then
  delete from korlix_social_online_events where target=new.id;
  return new;
 end if;
 if old.show_online and not old.suspended and old.last_seen>now()-interval '90 seconds' then return new; end if;
 with eligible as (
  update korlix_social_online_watches w set last_alert_at=now()
  where w.target=new.id and (w.last_alert_at is null or w.last_alert_at<=now()-interval '15 minutes')
   and korlix_social_online_connected(w.watcher,w.target)
  returning w.watcher,w.target
 ), events as (
  insert into korlix_social_online_events(watcher,target)
   select watcher,target from eligible
   on conflict(watcher,target) do update set id=gen_random_uuid(),created_at=now(),expires_at=now()+interval '90 seconds'
   returning *
 )
 insert into korlix_social_push_outbox(subscription_id,owner,sender,binding,subscription_revision,kind,event_id,expires_at)
  select s.id,e.watcher,e.target,s.binding,s.revision,'online',e.id,e.expires_at
  from events e join korlix_social_push_subscriptions s on s.owner=e.watcher
  where s.online and s.updated_at>now()-interval '90 days'
   and (select count(*) from korlix_social_push_outbox q where q.owner=e.watcher and q.status in('pending','retry'))<500
  on conflict do nothing;
 return new;
end $$;
create trigger korlix_social_online_transition after update of last_seen,show_online,suspended on public.korlix_social_profiles
 for each row execute function public.korlix_social_online_transition();

-- Removing a connection or blocking deletes both directions' selections. Reconnecting
-- never silently reenrolls either person in a previous online watch.
create function public.korlix_social_online_disconnect() returns trigger
language plpgsql security invoker set search_path=public as $$
declare a uuid; b uuid;
begin
 if tg_table_name='korlix_social_blocks' then a:=new.blocker;b:=new.blocked;
 else
  if tg_op='UPDATE' and new.state='accepted' then return new; end if;
  a:=old.requester;b:=old.recipient;
 end if;
 delete from korlix_social_online_watches where (watcher=a and target=b) or (watcher=b and target=a);
 return null;
end $$;
create trigger korlix_social_online_disconnect after delete or update of state on public.korlix_social_connections
 for each row execute function public.korlix_social_online_disconnect();
create trigger korlix_social_online_block after insert on public.korlix_social_blocks
 for each row execute function public.korlix_social_online_disconnect();

create function public.korlix_social_online_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; target_id uuid; sound_name text; items jsonb;
begin
 select * into me from korlix_social_profiles where user_id=p_actor;
 if me.id is null or me.suspended then raise exception 'An active Social profile is required.' using errcode='42501'; end if;
 if p_action='online_watches' then
  select coalesce(jsonb_agg(jsonb_build_object('peer',korlix_social_card(p,me.id),'sound',w.sound) order by p.name,p.id),'[]') into items
  from korlix_social_online_watches w join korlix_social_profiles p on p.id=w.target
  where w.watcher=me.id and korlix_social_online_connected(me.id,w.target);
  return jsonb_build_object('items',items,'limit',50);
 elsif p_action='online_events' then
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'peer',korlix_social_card(p,me.id),'sound',w.sound,'expires_at',e.expires_at) order by e.created_at,e.id),'[]') into items
  from korlix_social_online_events e join korlix_social_online_watches w using(watcher,target)
  join korlix_social_profiles p on p.id=e.target
  where e.watcher=me.id and e.expires_at>now() and p.show_online and p.last_seen>now()-interval '90 seconds'
   and korlix_social_online_connected(me.id,e.target);
  return jsonb_build_object('items',items);
 elsif p_action='online_watch_set' then
  target_id:=(p_data->>'peer')::uuid; sound_name:=p_data->>'sound';
  if target_id is null or target_id=me.id or jsonb_typeof(p_data->'enabled') is distinct from 'boolean'
   or sound_name is null or sound_name not in('bell','ring','silent') then raise exception 'Choose a connection and alert sound.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-online-watch:'||me.id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('social-pair:'||least(me.id,target_id)::text||greatest(me.id,target_id)::text,0));
  perform korlix_social_limit(p_actor,'online-watch',120,3600);
  if p_data->'enabled'='false'::jsonb then
   delete from korlix_social_online_watches where watcher=me.id and target=target_id;
   update korlix_social_push_outbox set status='cancelled',lease_until=null where owner=me.id and sender=target_id and kind='online' and status in('pending','retry','claimed');
   return jsonb_build_object('ok',true);
  end if;
  if not korlix_social_online_connected(me.id,target_id) then raise exception 'Choose an accepted connection.' using errcode='42501'; end if;
  if not exists(select 1 from korlix_social_online_watches where watcher=me.id and target=target_id)
   and (select count(*) from korlix_social_online_watches where watcher=me.id)>=50 then raise exception 'Choose up to 50 connections for online alerts.'; end if;
  insert into korlix_social_online_watches(watcher,target,sound) values(me.id,target_id,sound_name)
   on conflict(watcher,target) do update set sound=excluded.sound;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Online alert action unavailable.';
end $$;
revoke all on function public.korlix_social_online_connected(uuid,uuid),public.korlix_social_online_transition(),public.korlix_social_online_disconnect(),public.korlix_social_online_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_online_connected(uuid,uuid),public.korlix_social_online_transition(),public.korlix_social_online_disconnect(),public.korlix_social_online_v1(uuid,text,jsonb) to service_role;

create or replace function public.korlix_social_push_allowed(o public.korlix_social_push_outbox) returns boolean
language plpgsql volatile security invoker set search_path=public as $$
begin
 if o.expires_at<=clock_timestamp() or not exists(select 1 from korlix_social_push_subscriptions s where s.id=o.subscription_id and s.owner=o.owner and s.binding=o.binding and s.revision=o.subscription_revision
  and s.updated_at>now()-interval '90 days' and case when o.kind='call' then s.calls when o.kind='online' then s.online else s.messages end)
  or not exists(select 1 from korlix_social_profiles p where p.id=o.owner and not p.suspended)
  or not exists(select 1 from korlix_social_profiles p where p.id=o.sender and not p.suspended)
  or korlix_social_blocked(o.owner,o.sender) then return false; end if;
 if o.kind='online' then
  return exists(select 1 from korlix_social_online_events e
   join korlix_social_online_watches w using(watcher,target)
   join korlix_social_profiles p on p.id=e.target
   where e.id=o.event_id and e.watcher=o.owner and e.target=o.sender and e.expires_at>clock_timestamp()
    and p.show_online and p.last_seen>clock_timestamp()-interval '90 seconds'
    and korlix_social_online_connected(e.watcher,e.target));
 end if;
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

create or replace function public.korlix_social_push_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public as $$
declare me korlix_social_profiles; s korlix_social_push_subscriptions; o korlix_social_push_outbox;
 items jsonb; subscription_data jsonb; endpoint_text text; outcome text; device_id uuid;
begin
 if p_action in('claim','authorize','finish') then
  if p_actor is not null then raise exception 'Worker action unavailable.' using errcode='42501'; end if;
  if p_action='claim' then
   delete from korlix_social_online_events where expires_at<now();
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
   return jsonb_build_object('delivery',jsonb_build_object('subscription',s.subscription,'kind',o.kind,'event_id',o.event_id,'binding',o.binding,'expires_at',o.expires_at,'silent',case when o.kind='online' then coalesce((select sound='silent' from korlix_social_online_watches where watcher=o.owner and target=o.sender),true) else false end));
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
  select coalesce(jsonb_agg(jsonb_build_object('device',device,'messages',messages,'calls',calls,'online',online,'updated_at',updated_at)),'[]') into items from korlix_social_push_subscriptions where owner=me.id;
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
  if p_data?'online' and jsonb_typeof(p_data->'online') is distinct from 'boolean' then raise exception 'Choose your online notification preference.'; end if;
  select * into s from korlix_social_push_subscriptions where owner=me.id and device=device_id;
  if s.id is null and (select count(*) from korlix_social_push_subscriptions where owner=me.id)>=10 then raise exception 'Remove an old browser before adding another notification device.'; end if;
  -- A subscription cannot be moved between accounts. Logout unsubscribes in the
  -- browser, which obtains a fresh endpoint before enrolling another account.
  if exists(select 1 from korlix_social_push_subscriptions where endpoint=endpoint_text and (owner<>me.id or device<>device_id)) then raise exception 'Turn browser notifications off, then enable them again on this account.'; end if;
  delete from korlix_social_push_outbox where subscription_id=s.id and status in('pending','retry','claimed');
  insert into korlix_social_push_subscriptions(owner,device,binding,subscription,endpoint,messages,calls,online)
   values(me.id,device_id,(p_data->>'binding')::uuid,subscription_data,endpoint_text,(p_data->>'messages')::boolean,(p_data->>'calls')::boolean,coalesce((p_data->>'online')::boolean,s.online,false))
   on conflict(owner,device) do update set binding=excluded.binding,revision=korlix_social_push_subscriptions.revision+1,subscription=excluded.subscription,endpoint=excluded.endpoint,messages=excluded.messages,calls=excluded.calls,online=excluded.online,updated_at=now();
  return jsonb_build_object('ok',true,'device',device_id);
 end if;
 raise exception 'Notification action unavailable.';
end $$;
