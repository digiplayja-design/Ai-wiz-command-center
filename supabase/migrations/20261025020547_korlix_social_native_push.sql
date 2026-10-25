begin;
-- Opt-in native Social and independent Messenger notifications. Existing web subscriptions and RPCs stay unchanged.
-- Only the verified backend/service role can enroll a device or deliver a queued event.
create table public.korlix_social_native_push_subscriptions (
 id uuid primary key default gen_random_uuid(),
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 client_app text not null check(client_app in('korlix_ai','korlix_messenger')),
 session_id uuid references public.korlix_receipt_app_sessions(session_id) on delete cascade,
 check((client_app='korlix_messenger')=(session_id is not null)),
 check(app_id=case client_app when 'korlix_messenger' then 'com.korlixdeveloper.messenger' else 'com.korlixdeveloper.korlixai' end),
 device uuid not null, binding uuid not null, owner_key text not null check(octet_length(owner_key)<=2048),
 revision integer not null default 1 check(revision>0),
 provider text not null check(provider in('fcm','apns')),
 app_id text not null check(app_id ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{2,199}$'),
 environment text not null check(environment in('production','sandbox') and (provider<>'fcm' or environment='production')),
 token text not null check((provider='fcm' and length(token) between 20 and 2048 and token ~ '^[A-Za-z0-9_:.-]+$') or
  (provider='apns' and token ~ '^[a-f0-9]{64,200}$' and length(token)%2=0)),
 messages boolean not null default true, calls boolean not null default true, online boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(owner,client_app,device), unique(provider,app_id,environment,token)
);
create table public.korlix_social_native_push_outbox (
 id uuid primary key default gen_random_uuid(),
 subscription_id uuid not null references public.korlix_social_native_push_subscriptions(id) on delete cascade,
 owner uuid not null references public.korlix_social_profiles(id) on delete cascade,
 sender uuid not null references public.korlix_social_profiles(id) on delete cascade,
 binding uuid not null, subscription_revision integer not null check(subscription_revision>0),
 kind text not null check(kind in('call','message','group_message','online')),
 event_id uuid not null, conversation_id uuid not null,
 created_at timestamptz not null default now(), expires_at timestamptz not null,
 status text not null default 'pending' check(status in('pending','claimed','sending','retry','accepted','unknown','failed','cancelled')),
 attempts integer not null default 0, lease uuid, lease_until timestamptz, next_attempt timestamptz not null default now(),
 unique(subscription_id,kind,event_id)
);
create index korlix_social_native_push_session on public.korlix_social_native_push_subscriptions(session_id);
create index korlix_social_native_push_owner on public.korlix_social_native_push_outbox(owner,created_at);
create index korlix_social_native_push_sender on public.korlix_social_native_push_outbox(sender);
create index korlix_social_native_push_pending on public.korlix_social_native_push_outbox(owner,conversation_id,kind) where status in('pending','retry');
create index korlix_social_native_push_due on public.korlix_social_native_push_outbox(next_attempt) where status in('pending','retry');
create index korlix_social_native_push_expiry on public.korlix_social_native_push_outbox(expires_at);
create index korlix_social_native_push_age on public.korlix_social_native_push_subscriptions(updated_at);
alter table public.korlix_social_native_push_subscriptions enable row level security;
alter table public.korlix_social_native_push_outbox enable row level security;
revoke all on public.korlix_social_native_push_subscriptions,public.korlix_social_native_push_outbox from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_social_native_push_subscriptions,public.korlix_social_native_push_outbox to service_role;

create function public.korlix_social_native_push_enqueue() returns trigger
language plpgsql security invoker set search_path='' as $$
declare target uuid; source uuid; notification_kind text; expiry timestamptz;
begin
 if tg_table_name='korlix_social_online_events' then
  target:=new.watcher;source:=new.target;notification_kind:='online';expiry:=new.expires_at;
 elsif tg_table_name='korlix_social_calls' then
  target:=new.callee;source:=new.caller;notification_kind:='call';expiry:=new.created_at+interval '45 seconds';
 elsif tg_table_name='korlix_social_messages' then
  target:=new.recipient;source:=new.sender;notification_kind:='message';expiry:=new.created_at+interval '5 minutes';
 else
  -- Coalesce only within this group, never another conversation from the sender.
  delete from public.korlix_social_native_push_outbox where sender=new.sender and conversation_id=new.group_id
   and kind='group_message' and status in('pending','retry');
  insert into public.korlix_social_native_push_outbox(subscription_id,owner,sender,binding,subscription_revision,kind,event_id,conversation_id,expires_at)
   select s.id,s.owner,new.sender,s.binding,s.revision,'group_message',new.id,new.group_id,new.created_at+interval '5 minutes'
   from public.korlix_social_native_push_subscriptions s
   join public.korlix_social_group_members m on m.member=s.owner and m.group_id=new.group_id
   join public.korlix_social_profiles p on p.id=s.owner
   where s.messages and s.updated_at>now()-interval '90 days' and m.state='accepted' and m.member<>new.sender
    and not p.suspended and not public.korlix_social_blocked(s.owner,new.sender)
    and (select count(*) from public.korlix_social_native_push_outbox q where q.owner=s.owner and q.status in('pending','retry'))<500
   on conflict do nothing;
  return new;
 end if;
 if notification_kind in('message','online') then
  delete from public.korlix_social_native_push_outbox where owner=target and sender=source
   and kind=notification_kind and status in('pending','retry');
 end if;
 insert into public.korlix_social_native_push_outbox(subscription_id,owner,sender,binding,subscription_revision,kind,event_id,conversation_id,expires_at)
  select s.id,target,source,s.binding,s.revision,notification_kind,new.id,source,expiry
  from public.korlix_social_native_push_subscriptions s join public.korlix_social_profiles p on p.id=s.owner
  where s.owner=target and s.updated_at>now()-interval '90 days' and not p.suspended
   and case when notification_kind='call' then s.calls when notification_kind='online' then s.online else s.messages end
   and not public.korlix_social_blocked(target,source)
   and (select count(*) from public.korlix_social_native_push_outbox q where q.owner=target and q.status in('pending','retry'))<500
  on conflict do nothing;
 return new;
exception when foreign_key_violation then
 -- A concurrent device revocation/account handoff can remove the subscription
 -- between selection and the outbox FK check. Cancel this alert, never the chat.
 -- Other errors remain visible; do not mask schema or permission failures.
 return new;
end $$;
create trigger korlix_social_native_push_call after insert on public.korlix_social_calls for each row execute function public.korlix_social_native_push_enqueue();
create trigger korlix_social_native_push_message after insert on public.korlix_social_messages for each row execute function public.korlix_social_native_push_enqueue();
create trigger korlix_social_native_push_group after insert on public.korlix_social_group_messages for each row execute function public.korlix_social_native_push_enqueue();
-- The existing online transition upserts this row, including when a watch alerts again.
create trigger korlix_social_native_push_online after insert or update on public.korlix_social_online_events for each row execute function public.korlix_social_native_push_enqueue();

create function public.korlix_social_native_push_allowed(o public.korlix_social_native_push_outbox) returns boolean
language plpgsql volatile security invoker set search_path='' as $$
begin
 if o.expires_at<=clock_timestamp() or not exists(select 1 from public.korlix_social_native_push_subscriptions s
  where s.id=o.subscription_id and s.owner=o.owner and s.binding=o.binding and s.revision=o.subscription_revision
   and s.updated_at>now()-interval '90 days'
   and (s.client_app='korlix_ai' or exists(select 1 from public.korlix_receipt_app_sessions login
    join public.korlix_social_profiles account on account.user_id=login.user_id
    where login.session_id=s.session_id and login.status='active' and login.client_app=s.client_app and account.id=s.owner))
   and case when o.kind='call' then s.calls when o.kind='online' then s.online else s.messages end)
  or not exists(select 1 from public.korlix_social_profiles p where p.id=o.owner and not p.suspended)
  or not exists(select 1 from public.korlix_social_profiles p where p.id=o.sender and not p.suspended)
  or public.korlix_social_blocked(o.owner,o.sender) then return false; end if;
 if o.kind='online' then
  return exists(select 1 from public.korlix_social_online_events e
   join public.korlix_social_online_watches w using(watcher,target)
   join public.korlix_social_profiles p on p.id=e.target
   where e.id=o.event_id and e.watcher=o.owner and e.target=o.sender and e.expires_at>clock_timestamp()
    and p.show_online and p.last_seen>clock_timestamp()-interval '90 seconds'
    and public.korlix_social_online_connected(e.watcher,e.target));
 end if;
 if o.kind in('call','message') and not exists(select 1 from public.korlix_social_connections c where c.state='accepted'
  and least(c.requester,c.recipient)=least(o.owner,o.sender) and greatest(c.requester,c.recipient)=greatest(o.owner,o.sender)) then return false; end if;
 if o.kind='call' then
  return exists(select 1 from public.korlix_social_calls c where c.id=o.event_id and c.caller=o.sender and c.callee=o.owner
   and c.state='ringing' and c.created_at>clock_timestamp()-interval '45 seconds' and c.caller_seen>clock_timestamp()-interval '60 seconds');
 elsif o.kind='message' then
  return exists(select 1 from public.korlix_social_messages m where m.id=o.event_id and m.sender=o.sender and m.recipient=o.owner
   and not m.deleted and m.read_at is null and not public.korlix_social_dumped(o.owner,'direct',m.id));
 else
  return exists(select 1 from public.korlix_social_group_messages m
   join public.korlix_social_group_members g on g.group_id=m.group_id and g.member=o.owner
   join public.korlix_social_groups parent on parent.id=m.group_id
   where m.id=o.event_id and m.group_id=o.conversation_id and m.sender=o.sender and not m.deleted and not parent.archived
    and g.state='accepted' and m.seq>greatest(g.joined_after,g.last_read)
    and exists(select 1 from public.korlix_social_group_members sender_member where sender_member.group_id=m.group_id and sender_member.member=m.sender and sender_member.state='accepted')
    and not exists(select 1 from public.korlix_social_group_message_reads r where r.message_id=m.id and r.reader=o.owner)
    and not public.korlix_social_dumped(o.owner,'group',m.id));
 end if;
end $$;

create function public.korlix_social_native_push_v1(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare me public.korlix_social_profiles; s public.korlix_social_native_push_subscriptions; o public.korlix_social_native_push_outbox;
 items jsonb; subscription_data jsonb; owner_data jsonb; outcome text; device_id uuid; binding_id uuid;
 token_text text; provider_name text; app_name text; environment_name text; owner_text text; retry_seconds integer; client_name text; login_id uuid;
begin
 if p_action in('claim','authorize','finish') then
  if p_actor is not null then raise exception 'Worker action unavailable.' using errcode='42501'; end if;
  if p_action='claim' then
   -- Never replay an uncertain provider send. Only an unstarted claim can be reclaimed.
   update public.korlix_social_native_push_outbox set status='unknown',lease_until=null where status='sending' and lease_until<now();
   update public.korlix_social_native_push_outbox set status='pending',lease=null,lease_until=null where status='claimed' and lease_until<now();
   update public.korlix_social_native_push_outbox set status='cancelled',lease_until=null where status in('pending','retry','claimed') and expires_at<=now();
   delete from public.korlix_social_native_push_outbox where expires_at<now()-interval '7 days';
   delete from public.korlix_social_native_push_subscriptions expired_sub where expired_sub.updated_at<now()-interval '90 days'
    or (expired_sub.client_app='korlix_messenger' and not exists(select 1 from public.korlix_receipt_app_sessions login
     where login.session_id=expired_sub.session_id and login.status='active' and login.client_app=expired_sub.client_app));
   with due as(select id from public.korlix_social_native_push_outbox where status in('pending','retry') and next_attempt<=now() and expires_at>now()
    order by (kind='call') desc,expires_at,next_attempt,id limit 20 for update skip locked),
   claimed as(update public.korlix_social_native_push_outbox q set status='claimed',lease=gen_random_uuid(),lease_until=now()+interval '30 seconds'
    from due where q.id=due.id returning q.id,q.lease,q.kind,q.expires_at,q.next_attempt)
   select coalesce(jsonb_agg(jsonb_build_object('id',claimed.id,'lease',claimed.lease)
    order by (claimed.kind='call') desc,claimed.expires_at,claimed.next_attempt,claimed.id),'[]') into items from claimed;
   return jsonb_build_object('items',items);
  end if;
  select * into o from public.korlix_social_native_push_outbox where id=(p_data->>'id')::uuid and lease=(p_data->>'lease')::uuid for update;
  if o.id is null then return jsonb_build_object('delivery',null); end if;
  if p_action='authorize' then
   if o.status<>'claimed' or o.lease_until<=now() then return jsonb_build_object('delivery',null); end if;
   if not public.korlix_social_native_push_allowed(o) then
    update public.korlix_social_native_push_outbox set status='cancelled',lease_until=null where id=o.id;
    return jsonb_build_object('delivery',null);
   end if;
   select * into s from public.korlix_social_native_push_subscriptions where id=o.subscription_id;
   update public.korlix_social_native_push_outbox set status='sending',attempts=attempts+1 where id=o.id;
   return jsonb_build_object('delivery',jsonb_build_object(
    'client_app',s.client_app,'subscription',jsonb_build_object('provider',s.provider,'token',s.token,'app_id',s.app_id,'environment',s.environment),
    'owner',s.owner_key,'binding',o.binding,'kind',case when o.kind='group_message' then 'group' else 'peer' end,
    'id',o.conversation_id,'event_id',o.event_id,'type',case when o.kind='group_message' then 'message' else o.kind end,
    'expires_at',o.expires_at,'silent',case when o.kind='online' then
     coalesce((select sound='silent' from public.korlix_social_online_watches where watcher=o.owner and target=o.sender),true) else false end));
  end if;
  if o.status not in('sending','claimed') then return jsonb_build_object('ok',true); end if;
  outcome:=p_data->>'status';
  if outcome='expired' then
   delete from public.korlix_social_native_push_subscriptions where id=o.subscription_id and binding=o.binding and revision=o.subscription_revision;
   if not found then update public.korlix_social_native_push_outbox set status='cancelled',lease_until=null where id=o.id; end if;
   return jsonb_build_object('ok',true);
  end if;
  if outcome is null or outcome not in('accepted','unknown','retry','failed','cancelled') then raise exception 'Invalid notification outcome.'; end if;
  if outcome='retry' then
   -- Provider rate limits must never become a rapid retry loop. Respect a longer
   -- Retry-After while retaining bounded exponential backoff and event expiry.
   retry_seconds:=least(3600,60*power(2,least(6,greatest(0,o.attempts-1))))::integer;
   if p_data?'retry_after_seconds' then
    if jsonb_typeof(p_data->'retry_after_seconds') is distinct from 'number'
     or (p_data->>'retry_after_seconds') !~ '^[0-9]+$' then raise exception 'Invalid notification retry delay.'; end if;
    retry_seconds:=greatest(retry_seconds,least(86400,(p_data->>'retry_after_seconds')::numeric)::integer);
   end if;
   if o.attempts>=3 or o.expires_at<=now()+make_interval(secs=>retry_seconds) then outcome:='failed'; end if;
  end if;
  update public.korlix_social_native_push_outbox set status=outcome,lease_until=null,
   next_attempt=case when outcome='retry' then now()+make_interval(secs=>retry_seconds) else next_attempt end where id=o.id;
  return jsonb_build_object('ok',true);
 end if;
 client_name:=p_data->>'client_app';
 if client_name is null or client_name not in('korlix_ai','korlix_messenger') then
  raise exception 'Invalid notification app scope.' using errcode='42501';
 end if;
 select * into me from public.korlix_social_profiles where user_id=p_actor;
 if me.id is null then raise exception 'Create your Social profile before enabling notifications.' using errcode='42501'; end if;
 if me.suspended and p_action<>'unsubscribe' then raise exception 'Social notifications are unavailable for this account.' using errcode='42501'; end if;
 if p_action='state' then
  select coalesce(jsonb_agg(jsonb_build_object('device',device,'binding',binding,'provider',provider,'environment',environment,
   'messages',messages,'calls',calls,'online',online,'updated_at',updated_at) order by created_at,id),'[]') into items
   from public.korlix_social_native_push_subscriptions where owner=me.id and client_app=client_name;
  return jsonb_build_object('subscriptions',items);
 end if;
 device_id:=(p_data->>'device')::uuid;binding_id:=(p_data->>'binding')::uuid;
 if device_id is null or binding_id is null then raise exception 'Choose this app notification device and binding.'; end if;
 -- Short serialized enrollment prevents token handoff races between accounts.
 perform pg_advisory_xact_lock(hashtextextended('social-native-push-enrollment',0));
 if p_action='unsubscribe' then
  delete from public.korlix_social_native_push_subscriptions where owner=me.id and client_app=client_name and device=device_id and binding=binding_id;
  return jsonb_build_object('ok',true);
 elsif p_action='subscribe' then
  perform public.korlix_social_limit(p_actor,'native-push-subscribe:'||client_name,30,3600);
  login_id:=(p_data->>'session_id')::uuid;
  if (client_name='korlix_messenger' and (login_id is null or not exists(
   select 1 from public.korlix_receipt_app_sessions login where login.session_id=login_id
    and login.user_id=p_actor and login.client_app=client_name and login.status='active')))
   or (client_name='korlix_ai' and login_id is not null) then
   raise exception 'Sign in again to enable app notifications.' using errcode='42501';
  end if;
  subscription_data:=p_data->'subscription';provider_name:=subscription_data->>'provider';
  app_name:=subscription_data->>'app_id';environment_name:=subscription_data->>'environment';token_text:=subscription_data->>'token';
  owner_text:=p_data->>'owner_key';
  if jsonb_typeof(subscription_data) is distinct from 'object' or octet_length(subscription_data::text)>4096
   or provider_name is null or provider_name not in('fcm','apns')
   or app_name is distinct from (case client_name when 'korlix_messenger' then 'com.korlixdeveloper.messenger' else 'com.korlixdeveloper.korlixai' end)
   or environment_name is null or environment_name not in('production','sandbox')
   or (provider_name='fcm' and environment_name<>'production')
   or token_text is null or not ((provider_name='fcm' and length(token_text) between 20 and 2048 and token_text ~ '^[A-Za-z0-9_:.-]+$') or
    (provider_name='apns' and token_text ~ '^[A-Fa-f0-9]{64,200}$' and length(token_text)%2=0))
   or jsonb_typeof(p_data->'messages') is distinct from 'boolean' or jsonb_typeof(p_data->'calls') is distinct from 'boolean'
   or jsonb_typeof(p_data->'online') is distinct from 'boolean'
   or jsonb_typeof(p_data->'owner_key') is distinct from 'string' or octet_length(owner_text)>2048 then
   raise exception 'Invalid app notification settings.';
  end if;
  owner_data:=owner_text::jsonb;
  if jsonb_typeof(owner_data) is distinct from 'array' then raise exception 'Invalid notification account binding.'; end if;
  if jsonb_array_length(owner_data)<>2 or jsonb_typeof(owner_data->0) is distinct from 'string'
   or jsonb_typeof(owner_data->1) is distinct from 'string' or owner_data->>0 !~ '^https://[^[:space:]]+$'
   or (owner_data->>1) is distinct from p_actor::text then raise exception 'Invalid notification account binding.'; end if;
  if provider_name='apns' then token_text:=lower(token_text); end if;
  select * into s from public.korlix_social_native_push_subscriptions where owner=me.id and client_app=client_name and device=device_id;
  if s.id is null and (select count(*) from public.korlix_social_native_push_subscriptions where owner=me.id and client_app=client_name)>=10 then
   raise exception 'Remove an old notification device before adding another.';
  end if;
  -- APNs/FCM tokens can survive logout. Move their registration atomically;
  -- cascading deletion removes every old queued job and its account binding.
  delete from public.korlix_social_native_push_subscriptions where provider=provider_name and app_id=app_name and environment=environment_name
   and token=token_text and (owner<>me.id or client_app<>client_name or device<>device_id);
  delete from public.korlix_social_native_push_outbox where subscription_id=s.id;
  insert into public.korlix_social_native_push_subscriptions(owner,client_app,session_id,device,binding,owner_key,provider,app_id,environment,token,messages,calls,online)
   values(me.id,client_name,login_id,device_id,binding_id,owner_text,provider_name,app_name,environment_name,token_text,
    (p_data->>'messages')::boolean,(p_data->>'calls')::boolean,(p_data->>'online')::boolean)
   on conflict(owner,client_app,device) do update set session_id=excluded.session_id,binding=excluded.binding,owner_key=excluded.owner_key,
    revision=public.korlix_social_native_push_subscriptions.revision+1,provider=excluded.provider,app_id=excluded.app_id,
    environment=excluded.environment,token=excluded.token,messages=excluded.messages,calls=excluded.calls,online=excluded.online,updated_at=now();
  return jsonb_build_object('ok',true,'device',device_id,'binding',binding_id);
 end if;
 raise exception 'Notification action unavailable.';
end $$;
revoke all on function public.korlix_social_native_push_enqueue(),
 public.korlix_social_native_push_allowed(public.korlix_social_native_push_outbox),public.korlix_social_native_push_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_social_native_push_enqueue(),
 public.korlix_social_native_push_allowed(public.korlix_social_native_push_outbox),public.korlix_social_native_push_v1(uuid,text,jsonb) to service_role;


commit;
