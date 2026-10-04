-- CRM follow-up mail. All access is through the authenticated server; no browser grants.
create table public.korlix_crm_email_rules (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 contact_id uuid not null unique references public.korlix_contacts(id) on delete cascade,
 subject text not null check(length(subject) between 1 and 200 and subject !~ '[\r\n]'),
 body text not null check(length(body) between 1 and 6000),
 timezone text not null default 'UTC', send_hour integer not null default 9 check(send_hour between 0 and 20),
 delivery_mode text not null default 'review' check(delivery_mode in ('review','automatic')),
 enabled boolean not null default false, version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index korlix_crm_email_rules_owner on public.korlix_crm_email_rules(user_id);
create index korlix_crm_email_rules_enabled on public.korlix_crm_email_rules(updated_at) where enabled;
create table public.korlix_crm_email_jobs (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 rule_id uuid not null references public.korlix_crm_email_rules(id) on delete cascade,
 contact_id uuid not null references public.korlix_contacts(id) on delete cascade, follow_up_on date not null,
 rule_version integer not null, contact_version integer not null, recipient text not null,
 subject text not null, body text not null, status text not null default 'draft'
 check(status in ('draft','queued','preparing','sending','sent','delivered','blocked','cancelled','unknown')),
 version integer not null default 1, lease_token uuid, lease_until timestamptz,
 email_payload jsonb, sender_fingerprint text, token_hash text unique,
 dispatched_at timestamptz, provider_id uuid unique, code text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(contact_id,follow_up_on)
);
create index korlix_crm_email_jobs_owner on public.korlix_crm_email_jobs(user_id,created_at desc);
create index korlix_crm_email_jobs_queue on public.korlix_crm_email_jobs(created_at) where status in ('queued','preparing','sending');
create table public.korlix_crm_email_suppressions (
 user_id uuid not null references auth.users(id) on delete cascade, email text not null, reason text not null,
 created_at timestamptz not null default now(), primary key(user_id,email)
);
alter table public.korlix_crm_email_rules enable row level security;
alter table public.korlix_crm_email_jobs enable row level security;
alter table public.korlix_crm_email_suppressions enable row level security;
revoke all on public.korlix_crm_email_rules, public.korlix_crm_email_jobs, public.korlix_crm_email_suppressions from public,anon,authenticated;
grant all on public.korlix_crm_email_rules, public.korlix_crm_email_jobs, public.korlix_crm_email_suppressions to service_role;

create function public.korlix_crm_email_v1(p_actor uuid,p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
#variable_conflict use_column
declare r public.korlix_crm_email_rules; j public.korlix_crm_email_jobs; c public.korlix_contacts;
 v_now timestamptz:=clock_timestamp(); v_local timestamp; v_rules jsonb; v_jobs jsonb; v_email text;
begin
 if p_action not in ('tick','claim','prepare','authorize','finish','provider_event','unsubscribe') then
  if p_actor is null or not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'CRM403: Enterprise required.'; end if;
 end if;
 if p_actor is not null then perform pg_advisory_xact_lock(hashtextextended('crm-email:'||p_actor::text,0)); end if;
 if p_action='state' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]') into v_rules from
   (select r.*,c.name contact_name,c.email,c.follow_up_on,c.email_permission,c.do_not_contact,
    exists(select 1 from korlix_crm_email_suppressions s where s.user_id=r.user_id and s.email=lower(c.email)) suppressed
    from korlix_crm_email_rules r join korlix_contacts c on c.id=r.contact_id where r.user_id=p_actor and c.archived_at is null limit 500) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into v_jobs from
   (select id,rule_id,contact_id,follow_up_on,recipient,subject,body,status,version,code,created_at,updated_at from korlix_crm_email_jobs where user_id=p_actor order by created_at desc limit 60) x;
  return jsonb_build_object('rules',v_rules,'jobs',v_jobs,'daily_limit',100);
 elsif p_action='save' then
  select * into c from korlix_contacts where id=(p->>'contact_id')::uuid and user_id=p_actor and archived_at is null for update;
  if not found then raise exception 'CRM404: Contact not found.'; end if;
  if not exists(select 1 from pg_timezone_names where name=p->>'timezone') then raise exception 'CRM: Choose a valid timezone.'; end if;
  select * into r from korlix_crm_email_rules where contact_id=c.id for update;
  if found and r.version<>coalesce((p->>'version')::integer,0) then raise exception 'CRM409: This email rule changed. Refresh before saving.'; end if;
  if r.id is null and (select count(*) from korlix_crm_email_rules where user_id=p_actor)>=500 then raise exception 'CRM409: The workspace supports up to 500 follow-up rules.'; end if;
  insert into korlix_crm_email_rules(user_id,contact_id,subject,body,timezone,send_hour,delivery_mode)
   values(p_actor,c.id,p->>'subject',p->>'body',p->>'timezone',(p->>'send_hour')::integer,p->>'delivery_mode')
   on conflict(contact_id) do update set subject=excluded.subject,body=excluded.body,timezone=excluded.timezone,send_hour=excluded.send_hour,delivery_mode=excluded.delivery_mode,enabled=false,version=korlix_crm_email_rules.version+1,updated_at=v_now returning * into r;
  update korlix_crm_email_jobs set status='cancelled',code='rule_changed',version=version+1,lease_token=null,lease_until=null,updated_at=v_now where rule_id=r.id and dispatched_at is null and status not in ('sent','delivered','unknown');
  return jsonb_build_object('rule',to_jsonb(r),'saved',true,'enabled',false);
 elsif p_action in ('toggle','pause_all') then
  if p_action='pause_all' then
   update korlix_crm_email_rules set enabled=false,version=version+1,updated_at=v_now where user_id=p_actor;
   update korlix_crm_email_jobs set status='cancelled',code='paused',version=version+1,lease_token=null,updated_at=v_now where user_id=p_actor and dispatched_at is null and status in ('draft','queued','preparing');
   return jsonb_build_object('paused',true);
  end if;
  select * into r from korlix_crm_email_rules where id=(p->>'id')::uuid and user_id=p_actor for update;
  if not found then raise exception 'CRM404: Email rule not found.'; end if;
  if r.version<>coalesce((p->>'version')::integer,0) then raise exception 'CRM409: Refresh this email rule first.'; end if;
  if (p->>'enabled')::boolean then
   select * into c from korlix_contacts where id=r.contact_id and user_id=p_actor for update;
   if p->>'confirmed'<>'true' or c.archived_at is not null or c.email is null or c.do_not_contact or c.email_permission not in ('transactional','marketing') or c.follow_up_on is null then raise exception 'CRM409: Review the contact, email permission and follow-up date before enabling.'; end if;
   if exists(select 1 from korlix_crm_email_suppressions where user_id=p_actor and email=lower(c.email)) then raise exception 'CRM409: This address has stopped CRM emails.'; end if;
  else
   update korlix_crm_email_jobs set status='cancelled',code='paused',version=version+1,lease_token=null,updated_at=v_now where rule_id=r.id and dispatched_at is null and status in ('draft','queued','preparing');
  end if;
  update korlix_crm_email_rules set enabled=(p->>'enabled')::boolean,version=version+1,updated_at=v_now where id=r.id returning * into r;
  return jsonb_build_object('rule',to_jsonb(r));
 elsif p_action in ('approve','cancel') then
  select * into j from korlix_crm_email_jobs where id=(p->>'id')::uuid and user_id=p_actor for update;
  if not found then raise exception 'CRM404: Email draft not found.'; end if;
  if j.version<>coalesce((p->>'version')::integer,0) or j.status<>'draft' then raise exception 'CRM409: This draft changed. Refresh before reviewing.'; end if;
  if p_action='approve' and p->>'confirmed'<>'true' then raise exception 'CRM: Review the exact recipient and message first.'; end if;
  update korlix_crm_email_jobs set status=case when p_action='approve' then 'queued' else 'cancelled' end,code=case when p_action='approve' then 'approved' else 'skipped' end,version=version+1,updated_at=v_now where id=j.id;
  return jsonb_build_object('saved',true);
 elsif p_action='tick' then
  -- A stale request may already have reached the provider. Never resend it.
  update korlix_crm_email_jobs set status='unknown',code='dispatch_receipt_missing',updated_at=v_now where status='sending' and lease_until<v_now;
  update korlix_crm_email_jobs set status='queued',lease_token=null,updated_at=v_now where status='preparing' and lease_until<v_now and dispatched_at is null;
  insert into korlix_crm_email_jobs(user_id,rule_id,contact_id,follow_up_on,rule_version,contact_version,recipient,subject,body,status)
  select r.user_id,r.id,c.id,c.follow_up_on,r.version,c.version,c.email,r.subject,r.body,case when r.delivery_mode='review' then 'draft' else 'queued' end
  from korlix_crm_email_rules r join korlix_contacts c on c.id=r.contact_id and c.user_id=r.user_id join user_profiles u on u.id=r.user_id
  where r.enabled and lower(trim(u.tier))='enterprise' and c.archived_at is null and not c.do_not_contact and c.email_permission in ('transactional','marketing') and c.email is not null
   and c.follow_up_on between (v_now at time zone r.timezone)::date-7 and (v_now at time zone r.timezone)::date
   and not exists(select 1 from korlix_crm_email_suppressions s where s.user_id=r.user_id and s.email=lower(c.email))
   and not exists(select 1 from korlix_crm_email_jobs old where old.contact_id=c.id and old.follow_up_on=c.follow_up_on and not (old.dispatched_at is null and old.status='cancelled' and old.code in ('paused','rule_changed') and old.rule_version<>r.version))
  order by r.updated_at limit 500
  on conflict(contact_id,follow_up_on) do update set rule_version=excluded.rule_version,contact_version=excluded.contact_version,recipient=excluded.recipient,subject=excluded.subject,body=excluded.body,status=excluded.status,version=korlix_crm_email_jobs.version+1,email_payload=null,token_hash=null,code=null,updated_at=v_now
  where korlix_crm_email_jobs.dispatched_at is null and korlix_crm_email_jobs.status='cancelled' and korlix_crm_email_jobs.code in ('paused','rule_changed') and korlix_crm_email_jobs.rule_version<>excluded.rule_version;
  return jsonb_build_object('ok',true);
 elsif p_action='claim' then
  select x.* into j from korlix_crm_email_jobs x join korlix_crm_email_rules r on r.id=x.rule_id
   where x.status='queued' and (extract(hour from v_now at time zone r.timezone) between r.send_hour and r.send_hour+3)
   order by x.updated_at,x.id for update of x skip locked limit 1;
  if not found then return null; end if;
  update korlix_crm_email_jobs set status='preparing',lease_token=gen_random_uuid(),lease_until=v_now+interval '2 minutes',updated_at=v_now where id=j.id returning * into j;
  return to_jsonb(j);
 elsif p_action in ('prepare','authorize') then
  select * into j from korlix_crm_email_jobs where id=(p->>'id')::uuid and user_id=p_actor for update;
  if not found or j.status<>'preparing' or j.lease_token is distinct from (p->>'lease_token')::uuid or j.lease_until<v_now then raise exception 'CRM409: Delivery claim expired.'; end if;
  select * into r from korlix_crm_email_rules where id=j.rule_id for update;
  select * into c from korlix_contacts where id=j.contact_id and user_id=p_actor for update;
  if not r.enabled or r.version<>j.rule_version or c.version<>j.contact_version or c.archived_at is not null or c.email is distinct from j.recipient or c.follow_up_on is distinct from j.follow_up_on or c.do_not_contact or c.email_permission not in ('transactional','marketing')
   or c.follow_up_on not between (v_now at time zone r.timezone)::date-7 and (v_now at time zone r.timezone)::date
   or not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier))='enterprise')
   or exists(select 1 from korlix_crm_email_suppressions where user_id=p_actor and email=lower(j.recipient)) then
   update korlix_crm_email_jobs set status='blocked',code='contact_rule_or_access_changed',updated_at=v_now where id=j.id; return jsonb_build_object('blocked',true);
  end if;
  if p_action='prepare' then
   if p->>'token_hash' !~ '^[a-f0-9]{64}$' or p->>'unsubscribe_url' !~ '^https://' or coalesce(p->>'reply_to','')='' then raise exception 'CRM: Invalid email identity.'; end if;
   update korlix_crm_email_jobs set token_hash=p->>'token_hash',sender_fingerprint=p->>'sender_fingerprint',email_payload=jsonb_build_object('id',j.id,'to',j.recipient,'subject',j.subject,'text',j.body||E'\n\nSent via KORLIX CRM. Reply to this email to reach the sender.\nStop these follow-ups: '||(p->>'unsubscribe_url'),'replyTo',p->>'reply_to') where id=j.id;
   return jsonb_build_object('prepared',true);
  end if;
  v_local:=v_now at time zone r.timezone;
  if extract(hour from v_local) not between r.send_hour and r.send_hour+3 or (select count(*) from korlix_crm_email_jobs where user_id=p_actor and dispatched_at>v_now-interval '24 hours')>=100 then
   update korlix_crm_email_jobs set status='queued',lease_token=null,updated_at=v_now where id=j.id; return jsonb_build_object('deferred',true);
  end if;
  if j.email_payload is null or j.email_payload->>'replyTo' is distinct from p->>'reply_to' or j.sender_fingerprint is distinct from p->>'sender_fingerprint' then raise exception 'CRM409: Sender identity changed.'; end if;
  update korlix_crm_email_jobs set status='sending',dispatched_at=v_now,lease_until=v_now+interval '2 minutes',updated_at=v_now where id=j.id;
  return jsonb_build_object('email_payload',j.email_payload);
 elsif p_action='finish' then
  update korlix_crm_email_jobs set status=p->>'status',provider_id=coalesce((p->>'provider_id')::uuid,provider_id),code=p->>'code',updated_at=v_now
   where id=(p->>'id')::uuid and user_id=p_actor and lease_token=(p->>'lease_token')::uuid and status='sending' and p->>'status' in ('sent','unknown','blocked');
  return jsonb_build_object('ok',true);
 elsif p_action in ('unsubscribe','provider_event') then
  if p_action='unsubscribe' then select * into j from korlix_crm_email_jobs where token_hash=p->>'token_hash';
  else select * into j from korlix_crm_email_jobs where dispatched_at is not null and (provider_id=(p->>'provider_id')::uuid or (id=(p->>'id')::uuid and (provider_id is null or provider_id=(p->>'provider_id')::uuid)));
  end if;
  if not found then return jsonb_build_object('ok',true); end if;
  perform pg_advisory_xact_lock(hashtextextended('crm-email:'||j.user_id::text,0));
  if p_action='provider_event' and p->>'event'='email.delivered' then
   update korlix_crm_email_jobs set status='delivered',provider_id=(p->>'provider_id')::uuid,updated_at=v_now where id=j.id and status in ('sending','sent','unknown');
  elsif p_action='unsubscribe' or p->>'event' in ('email.bounced','email.complained','email.suppressed') then
   insert into korlix_crm_email_suppressions(user_id,email,reason) values(j.user_id,lower(j.recipient),case when p_action='unsubscribe' then 'unsubscribed' else p->>'event' end) on conflict do nothing;
   update korlix_crm_email_rules set enabled=false,version=version+1,updated_at=v_now where user_id=j.user_id and contact_id in (select id from korlix_contacts where user_id=j.user_id and lower(email)=lower(j.recipient));
   update korlix_crm_email_jobs set status='blocked',code='recipient_stopped',updated_at=v_now where user_id=j.user_id and lower(recipient)=lower(j.recipient) and status in ('draft','queued','preparing');
   if p_action='provider_event' then update korlix_crm_email_jobs set status='blocked',provider_id=(p->>'provider_id')::uuid,code=p->>'event',updated_at=v_now where id=j.id; end if;
  end if;
  return jsonb_build_object('ok',true);
 else raise exception 'CRM: Unknown email action.';
 end if;
end $$;
revoke all on function public.korlix_crm_email_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_crm_email_v1(uuid,text,jsonb) to service_role;
