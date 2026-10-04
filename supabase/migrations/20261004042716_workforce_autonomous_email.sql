-- Workspace email is independent of the single-owner NOVA Email Center.
-- Service-only RPCs derive authorization from fresh workspace ownership.
alter table public.korlix_workforce_automations drop constraint korlix_workforce_automations_channel_check;
alter table public.korlix_workforce_automations add constraint korlix_workforce_automations_channel_check check(channel in ('email','call_review','workspace_email'));
alter table public.korlix_workforce_automations add column delivery_mode text not null default 'review' check(delivery_mode in ('review','automatic')),
 add column send_start time not null default '08:00', add column send_end time not null default '18:00',
 add column approved_owner uuid references auth.users;
alter table public.korlix_workforce_automations add constraint workforce_email_window check(send_start<send_end);
alter table public.korlix_workforce_automations add constraint workforce_email_recipient_required check(channel<>'workspace_email' or recipient_id is not null);
create table public.korlix_workforce_email_recipients(
 id uuid primary key, org_id uuid not null references public.korlix_workforce_orgs on delete cascade,
 email text not null check(length(email) between 3 and 254), name text not null check(length(name) between 1 and 100),
 active boolean not null default true, version int not null default 1,
 approved_by uuid not null references auth.users, approved_at timestamptz not null default now(),
 stopped_reason text, unique(org_id,email)
);
create table public.korlix_workforce_email_tokens(
 token_hash text primary key check(length(token_hash)=64), recipient_id uuid not null references public.korlix_workforce_email_recipients on delete cascade,
 expires_at timestamptz not null default now()+interval '1 year'
);
alter table public.korlix_workforce_email_recipients enable row level security;
alter table public.korlix_workforce_email_tokens enable row level security;
revoke all on public.korlix_workforce_email_recipients,public.korlix_workforce_email_tokens from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_workforce_email_recipients,public.korlix_workforce_email_tokens to service_role;
alter table public.korlix_workforce_automation_jobs drop constraint korlix_workforce_automation_jobs_status_check;
alter table public.korlix_workforce_automation_jobs add constraint korlix_workforce_automation_jobs_status_check check(status in ('pending','processing','sent','review','reviewed','expired','cancelled','blocked','draft','sending','unknown','delivered','bounced','complained'));
alter table public.korlix_workforce_automation_jobs add column email_payload jsonb, add column sender_fingerprint text,
 add column recipient_version int, add column rule_version int, add column approved_by uuid references auth.users,
 add column provider_id uuid, add column dispatch_at timestamptz, add column version int not null default 1;
create unique index workforce_email_provider on public.korlix_workforce_automation_jobs(provider_id) where provider_id is not null;
create index workforce_email_token_expiry on public.korlix_workforce_email_tokens(expires_at);

create or replace function public.korlix_workforce_automation_v1(p_actor uuid,p_action text,p_org uuid default null,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 o public.korlix_workforce_orgs; r public.korlix_workforce_automations; j public.korlix_workforce_automation_jobs;
 t timestamptz:=clock_timestamp(); ent boolean; result jsonb; n int;
begin
 -- Worker-only entry; execute privilege is reserved to service_role.
 if p_action='due_rules' then
  -- An interrupted provider call is never automatically retried.
  update public.korlix_workforce_automation_jobs set status='unknown',result_code='provider_outcome_unknown',version=version+1
   where status='sending' and lease_until<t;
  update public.korlix_workforce_automation_jobs set status='expired',result_code='event_expired',version=version+1 where status='draft' and expires_at<=t;
  -- Preserve event tombstones while removing old message content.
  update public.korlix_workforce_automation_jobs set email_payload=null,body='',subject='Archived Workforce activity'
   where created_at<t-interval '90 days' and body<>'' and status not in ('sending','processing','pending');
  delete from public.korlix_workforce_email_tokens where expires_at<t;
  return coalesce((select jsonb_agg(x) from (
   select a.*,w.owner_id,m.email as owner_email from public.korlix_workforce_automations a
   join public.korlix_workforce_orgs w on w.id=a.org_id
   join public.korlix_workforce_members m on m.org_id=w.id and m.user_id=w.owner_id and m.role='owner' and m.active
   join public.user_profiles u on u.id=w.owner_id and lower(trim(u.tier))='enterprise'
   where a.enabled order by a.last_checked_at nulls first,a.id limit 50
  ) x),'[]'::jsonb);
 end if;
 select * into o from public.korlix_workforce_orgs where id=p_org;
 if p_actor is null or o.owner_id is distinct from p_actor or not exists(
  select 1 from public.korlix_workforce_members where org_id=p_org and user_id=p_actor and role='owner' and active
 ) then raise exception 'WF403: Workspace owner access required'; end if;
 ent:=exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise');
 if p_action='state' then
  return jsonb_build_object('active_plan',ent,
   'rules',coalesce((select jsonb_agg(x order by x.created_at desc) from public.korlix_workforce_automations x where org_id=p_org),'[]'::jsonb),
   'jobs',coalesce((select jsonb_agg((to_jsonb(x)-'email_payload'-'sender_fingerprint'-'lease_token') || jsonb_build_object('recipient_email',x.email_payload->>'to') order by x.created_at desc) from (select * from public.korlix_workforce_automation_jobs where org_id=p_org order by created_at desc limit 100) x),'[]'::jsonb));
 end if;
 -- Stop and review stay available if the plan expires.
 if not ent and p_action not in ('pause','pause_all','resolve','finish','checked') then raise exception 'WF403: An active Enterprise plan is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text,140));
 if p_action='create' then
  select * into r from public.korlix_workforce_automations where id=(p->>'id')::uuid;
  if r.id is not null then
   if r.org_id<>p_org or (to_jsonb(r)-array['org_id','enabled','version','email_rule_id','email_approval_version','created_at','enabled_at','last_checked_at','last_error','local_time','approved_owner','send_start','send_end','delivery_mode']) is distinct from (p-array['local_time','send_start','send_end','delivery_mode'])
     or r.local_time<>(p->>'local_time')::time or r.delivery_mode<>coalesce(p->>'delivery_mode','review') or r.send_start<>coalesce(p->>'send_start','08:00')::time or r.send_end<>coalesce(p->>'send_end','18:00')::time then raise exception 'WF409: This request was already used for different settings'; end if;
   return to_jsonb(r);
  end if;
  if (select count(*) from public.korlix_workforce_automations where org_id=p_org)>=25 then raise exception 'WF: Limit of 25 automations per workspace reached'; end if;
  if p->>'member_id' is not null and not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=(p->>'member_id')::uuid and active) then raise exception 'WF: Select an active workspace member'; end if;
  if exists(select 1 from jsonb_array_elements_text(p->'days') d where d::int not between 0 and 6) then raise exception 'WF: Choose valid weekdays'; end if;
  insert into public.korlix_workforce_automations(id,org_id,name,kind,channel,member_id,recipient_id,delay_minutes,local_time,days,daily_limit,delivery_mode,send_start,send_end)
   values((p->>'id')::uuid,p_org,p->>'name',p->>'kind',p->>'channel',(p->>'member_id')::uuid,(p->>'recipient_id')::uuid,(p->>'delay_minutes')::int,(p->>'local_time')::time,p->'days',(p->>'daily_limit')::int,coalesce(p->>'delivery_mode','review'),coalesce(p->>'send_start','08:00')::time,coalesce(p->>'send_end','18:00')::time) returning * into r;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'automation_created',jsonb_build_object('rule_id',r.id,'kind',r.kind,'channel',r.channel));
  return to_jsonb(r);
 elsif p_action='pause_all' then
  update public.korlix_workforce_automations set enabled=false,version=version+1 where org_id=p_org and enabled;
  update public.korlix_workforce_automation_jobs set status='cancelled',result_code='owner_paused',completed_at=t,lease_token=null where org_id=p_org and status in ('pending','processing','draft');
  insert into public.korlix_workforce_audit(org_id,actor_id,action) values(p_org,p_actor,'automations_paused');
  return jsonb_build_object('paused',true);
 elsif p_action='resolve' then
  update public.korlix_workforce_automation_jobs set status='reviewed',reviewed_by=p_actor where org_id=p_org and id=(p->>'id')::uuid and status='review';
  if not found then raise exception 'WF409: Refresh this review item'; end if;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'call_escalation_reviewed',jsonb_build_object('job_id',p->>'id','call_placed',false));
  return jsonb_build_object('reviewed',true,'call_placed',false);
 end if;
 select * into r from public.korlix_workforce_automations where org_id=p_org and id=(p->>'rule_id')::uuid for update;
 if r.id is null then raise exception 'WF404: Automation not found'; end if;
 if p_action in ('enable','pause') then
  if r.version<>(p->>'version')::int then raise exception 'WF409: Automation changed; refresh before saving'; end if;
  if p_action='enable' and (p->>'confirmed')::boolean is distinct from true then raise exception 'WF: Review and approve this automation first'; end if;
  if p_action='enable' and r.channel='email' and (p->>'email_rule_id' is null or p->>'email_approval_version' is null) then raise exception 'WF: Approve the NOVA email rule first'; end if;
  if p_action='enable' and r.channel='workspace_email' and not exists(select 1 from public.korlix_workforce_email_recipients where id=r.recipient_id and org_id=p_org and active and approved_by=p_actor) then raise exception 'WF: Approve an active workspace email recipient first'; end if;
  update public.korlix_workforce_automations set enabled=p_action='enable',version=version+1,approved_owner=case when p_action='enable' then p_actor else approved_owner end,
   enabled_at=case when p_action='enable' then t else enabled_at end,
   email_rule_id=coalesce((p->>'email_rule_id')::uuid,email_rule_id),email_approval_version=coalesce((p->>'email_approval_version')::int,email_approval_version),last_error=null where id=r.id returning * into r;
  if p_action='pause' then
   update public.korlix_workforce_automation_jobs set status='cancelled',result_code='owner_paused',completed_at=t,lease_token=null where rule_id=r.id and status in ('pending','processing','draft');
  end if;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'automation_'||p_action,jsonb_build_object('rule_id',r.id,'version',r.version));
  return to_jsonb(r);
 elsif p_action='checked' then
  update public.korlix_workforce_automations set last_checked_at=t,last_error=left(p->>'error',180) where id=r.id;
  return '{}';
 elsif p_action='enqueue' then
  if not r.enabled then return '{}'; end if;
  if (p->>'expires_at')::timestamptz<=t then return '{}'; end if;
  insert into public.korlix_workforce_automation_jobs(org_id,rule_id,event_key,subject,body,member_id,expires_at)
   values(p_org,r.id,p->>'event_key',p->>'subject',p->>'body',(p->>'member_id')::uuid,(p->>'expires_at')::timestamptz)
   on conflict(rule_id,event_key) do nothing;
  return '{}';
 elsif p_action='claim' then
  if not r.enabled then return 'null'; end if;
  update public.korlix_workforce_automation_jobs set status='expired',result_code='event_expired',completed_at=t where rule_id=r.id and expires_at<=t and status in ('pending','processing') and (lease_until is null or lease_until<t);
  -- A crash gets a fresh lease but retains the same event/provider idempotency key.
  select * into j from public.korlix_workforce_automation_jobs where rule_id=r.id and expires_at>t and next_attempt_at<=t
   and (status='pending' or (status='processing' and lease_until<t)) order by created_at,id for update skip locked limit 1;
  if j.id is null then return 'null'; end if;
  select count(*) into n from public.korlix_workforce_automation_jobs where rule_id=r.id and
    (((completed_at at time zone o.timezone)::date=(t at time zone o.timezone)::date and status in ('sent','review','reviewed','draft','delivered','bounced','complained','unknown','sending')) or (status in ('processing','sending') and lease_until>t));
  if n>=r.daily_limit then return 'null'; end if;
  update public.korlix_workforce_automation_jobs set status='processing',lease_token=gen_random_uuid(),lease_until=t+interval '5 minutes',attempts=attempts+1 where id=j.id returning * into j;
  return to_jsonb(j);
 elsif p_action='finish' then
  if p->>'status' not in ('pending','sent','review','blocked','cancelled') then raise exception 'WF: Invalid delivery result'; end if;
  update public.korlix_workforce_automation_jobs set status=p->>'status',result_code=left(p->>'code',180),message_id=coalesce((p->>'message_id')::uuid,message_id),
   lease_token=null,lease_until=null,next_attempt_at=t+make_interval(secs=>least(1800,greatest(60,coalesce((p->>'retry_seconds')::int,300)))),
   completed_at=case when p->>'status'='pending' then null else t end
   where id=(p->>'job_id')::uuid and rule_id=r.id and status='processing' and lease_token=(p->>'lease_token')::uuid and lease_until>t;
  return jsonb_build_object('saved',found);
 end if;
 raise exception 'WF: Unsupported automation action';
end $$;
revoke all on function public.korlix_workforce_automation_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_workforce_automation_v1(uuid,text,uuid,jsonb) to service_role;

create function public.korlix_workforce_email_v1(p_actor uuid,p_action text,p_org uuid default null,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 o public.korlix_workforce_orgs; r public.korlix_workforce_automations; j public.korlix_workforce_automation_jobs;
 c public.korlix_workforce_email_recipients; t timestamptz:=clock_timestamp(); n int; ent boolean;
begin
 -- Signed webhooks supply only a known provider ID or our server-owned tag.
 if p_action='provider_event' then
  select * into j from public.korlix_workforce_automation_jobs where
   (provider_id=(p->>'provider_id')::uuid or id=(p->>'job_id')::uuid) and dispatch_at is not null
   and (provider_id is null or provider_id=(p->>'provider_id')::uuid) for update;
  if j.id is null then return '{}'; end if;
  if p->>'event' not in ('email.delivered','email.bounced','email.complained','email.suppressed') then return '{}'; end if;
  select * into r from public.korlix_workforce_automations where id=j.rule_id and channel='workspace_email';
  if r.id is null then return '{}'; end if;
  update public.korlix_workforce_automation_jobs set provider_id=(p->>'provider_id')::uuid,
   status=case when p->>'event'='email.complained' then 'complained' when p->>'event' in ('email.bounced','email.suppressed') then 'bounced'
    when status in ('bounced','complained') then status else 'delivered' end,
   result_code=p->>'event',completed_at=t,version=version+1 where id=j.id;
  if p->>'event'<>'email.delivered' then
   update public.korlix_workforce_email_recipients set active=false,version=version+1,stopped_reason=p->>'event' where id=r.recipient_id and active;
   update public.korlix_workforce_automations set enabled=false,version=version+1 where recipient_id=r.recipient_id and channel='workspace_email' and enabled;
   update public.korlix_workforce_automation_jobs set status='cancelled',result_code='recipient_suppressed',version=version+1 where status in ('pending','processing','draft')
    and rule_id in (select id from public.korlix_workforce_automations where recipient_id=r.recipient_id and channel='workspace_email');
  end if;
  return '{}';
 elsif p_action='unsubscribe' then
  select rc.* into c from public.korlix_workforce_email_recipients rc join public.korlix_workforce_email_tokens k on k.recipient_id=rc.id
   where k.token_hash=p->>'token_hash' and k.expires_at>t;
  if c.id is null then return '{}'; end if;
  p_org:=c.org_id;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text,140));
  update public.korlix_workforce_email_recipients set active=false,version=version+1,stopped_reason='unsubscribed' where id=c.id and active;
  update public.korlix_workforce_automations set enabled=false,version=version+1 where recipient_id=c.id and channel='workspace_email' and enabled;
  update public.korlix_workforce_automation_jobs set status='cancelled',result_code='unsubscribed',version=version+1 where status in ('pending','processing','draft')
   and rule_id in (select id from public.korlix_workforce_automations where recipient_id=c.id and channel='workspace_email');
  return '{}';
 end if;
 select * into o from public.korlix_workforce_orgs where id=p_org;
 if p_actor is null or o.owner_id is distinct from p_actor or not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=p_actor and role='owner' and active)
  then raise exception 'WF403: Workspace owner access required'; end if;
 ent:=exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise');
 perform pg_advisory_xact_lock(hashtextextended(p_org::text,140));
 if p_action='recipients' then
  return jsonb_build_object('recipients',coalesce((select jsonb_agg(x order by x.approved_at desc) from public.korlix_workforce_email_recipients x where org_id=p_org),'[]'::jsonb));
 end if;
 if not ent and p_action not in ('revoke','cancel','finish') then raise exception 'WF403: An active Enterprise plan is required'; end if;
 if p_action='add' then
  if (p->>'confirmed')::boolean is distinct from true then raise exception 'WF: Confirm permission to email this recipient'; end if;
  if (select count(*) from public.korlix_workforce_email_recipients where org_id=p_org)>=100 then raise exception 'WF: Limit of 100 recipients reached'; end if;
  select * into c from public.korlix_workforce_email_recipients where id=(p->>'id')::uuid;
  if c.id is not null then
   if c.org_id<>p_org or c.email<>p->>'email' or c.name<>p->>'name' then raise exception 'WF409: Request already used for another recipient'; end if;
   return to_jsonb(c);
  end if;
  if exists(select 1 from public.korlix_workforce_email_recipients where org_id=p_org and email=p->>'email') then raise exception 'WF409: This address is already listed; stopped recipients cannot be reactivated here'; end if;
  insert into public.korlix_workforce_email_recipients(id,org_id,email,name,approved_by) values((p->>'id')::uuid,p_org,p->>'email',p->>'name',p_actor) returning * into c;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'email_recipient_approved',jsonb_build_object('recipient_id',c.id));
  return to_jsonb(c);
 elsif p_action='revoke' then
  update public.korlix_workforce_email_recipients set active=false,version=version+1,stopped_reason='owner_revoked' where org_id=p_org and id=(p->>'id')::uuid;
  update public.korlix_workforce_automations set enabled=false,version=version+1 where org_id=p_org and recipient_id=(p->>'id')::uuid and channel='workspace_email' and enabled;
  update public.korlix_workforce_automation_jobs set status='cancelled',result_code='recipient_revoked',version=version+1 where org_id=p_org and status in ('pending','processing','draft')
   and rule_id in (select id from public.korlix_workforce_automations where org_id=p_org and recipient_id=(p->>'id')::uuid and channel='workspace_email');
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'email_recipient_revoked',jsonb_build_object('recipient_id',p->>'id'));
  return '{}';
 end if;
 select * into j from public.korlix_workforce_automation_jobs where org_id=p_org and id=(p->>'job_id')::uuid for update;
 select * into r from public.korlix_workforce_automations where id=j.rule_id and org_id=p_org and channel='workspace_email';
 if j.id is null or r.id is null then raise exception 'WF404: Workforce email not found'; end if;
 if p_action='finish' then
  if j.status not in ('sending','unknown') or j.lease_token is distinct from (p->>'lease_token')::uuid then return jsonb_build_object('saved',false); end if;
  if p->>'status' not in ('sent','blocked','unknown','pending') then raise exception 'WF: Invalid delivery result'; end if;
  update public.korlix_workforce_automation_jobs set status=p->>'status',result_code=left(p->>'code',180),
   provider_id=coalesce((p->>'provider_id')::uuid,provider_id),completed_at=t,version=version+1,
   dispatch_at=case when p->>'status'='pending' then null else dispatch_at end,
   next_attempt_at=t+make_interval(secs=>least(3600,greatest(60,coalesce((p->>'retry_seconds')::int,300)))) where id=j.id;
  return jsonb_build_object('saved',true);
 elsif p_action='cancel' then
  update public.korlix_workforce_automation_jobs set status='cancelled',result_code='owner_cancelled',version=version+1 where id=j.id and version=(p->>'version')::int and status in ('draft','pending','processing');
  if not found then raise exception 'WF409: This email changed; refresh before continuing'; end if;
  return '{}';
 end if;
 select * into c from public.korlix_workforce_email_recipients where id=r.recipient_id and org_id=p_org;
 if not r.enabled or r.approved_owner is distinct from p_actor or c.id is null or not c.active or c.approved_by<>p_actor or j.expires_at<=t then raise exception 'WF409: This email is no longer authorized or has expired'; end if;
 if p_action='approve' then
  if (p->>'confirmed')::boolean is distinct from true then raise exception 'WF: Review and approve this exact message first'; end if;
  if j.status<>'draft' or j.version<>(p->>'version')::int or j.rule_version<>r.version or j.recipient_version<>c.version then raise exception 'WF409: This draft changed; refresh before continuing'; end if;
  update public.korlix_workforce_automation_jobs set status='pending',approved_by=p_actor,next_attempt_at=t,version=version+1 where id=j.id;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details) values(p_org,p_actor,'email_draft_approved',jsonb_build_object('job_id',j.id,'version',j.version));
  return '{}';
 end if;
 if j.status<>'processing' or j.lease_token is distinct from (p->>'lease_token')::uuid or j.lease_until<=t then raise exception 'WF409: This email claim expired'; end if;
 if p_action='prepare' then
  if j.email_payload is null then
   if p->>'reply_to' is null or p->>'sender_fingerprint' is null or p->>'unsubscribe_url' is null then raise exception 'WF: Email sender is unavailable'; end if;
   insert into public.korlix_workforce_email_tokens(token_hash,recipient_id) values(p->>'token_hash',c.id);
   update public.korlix_workforce_automation_jobs set email_payload=jsonb_build_object('id',j.id,'to',c.email,'replyTo',p->>'reply_to','subject',left('Workforce · '||j.subject,200),
    'text',j.body||E'\n\nSent by KORLIX for your approved Workforce automation. Open KORLIX Workforce to review the records.\nStop these workspace emails: '||(p->>'unsubscribe_url')),
    sender_fingerprint=p->>'sender_fingerprint',recipient_version=c.version,rule_version=r.version,version=version+1 where id=j.id returning * into j;
  end if;
  if j.rule_version<>r.version or j.recipient_version<>c.version then raise exception 'WF409: Email approval changed'; end if;
  if r.delivery_mode='review' and j.approved_by is null then
   update public.korlix_workforce_automation_jobs set status='draft',completed_at=t,lease_token=null,lease_until=null,version=version+1 where id=j.id returning * into j;
  end if;
  return to_jsonb(j);
 elsif p_action='authorize' then
  if j.email_payload is null or j.rule_version<>r.version or j.recipient_version<>c.version or j.sender_fingerprint is distinct from p->>'sender_fingerprint'
   or j.email_payload->>'replyTo' is distinct from p->>'reply_to' or (r.delivery_mode='review' and j.approved_by is distinct from p_actor) then raise exception 'WF409: Email sender or approval changed'; end if;
  if (t at time zone o.timezone)::time<r.send_start or (t at time zone o.timezone)::time>=r.send_end
   or not (r.days @> to_jsonb(array[extract(dow from t at time zone o.timezone)::int])) then return jsonb_build_object('deferred',true); end if;
  -- Serialize across every workspace of this owner for the account-wide cap.
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,141));
  select count(*) into n from public.korlix_workforce_automation_jobs x join public.korlix_workforce_orgs w on w.id=x.org_id
   where w.owner_id=p_actor and x.dispatch_at>t-interval '24 hours';
  if n>=100 then return jsonb_build_object('deferred',true); end if;
  select count(*) into n from public.korlix_workforce_automation_jobs where rule_id=r.id and dispatch_at>t-interval '24 hours';
  if n>=r.daily_limit then return jsonb_build_object('deferred',true); end if;
  update public.korlix_workforce_automation_jobs set status='sending',dispatch_at=t,version=version+1 where id=j.id returning * into j;
  return to_jsonb(j);
 end if;
 raise exception 'WF: Unsupported email action';
end $$;
revoke all on function public.korlix_workforce_email_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_workforce_email_v1(uuid,text,uuid,jsonb) to service_role;
