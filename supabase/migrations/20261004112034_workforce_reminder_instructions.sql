-- Editable reminder instructions stay private under the existing owner-only RPC.
-- Saving an edit pauses that rule and invalidates unsent drafts for fresh approval.
alter table public.korlix_workforce_automations
 add column instructions text not null default '' check(length(instructions)<=1500);

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
   if r.org_id<>p_org or (to_jsonb(r)-array['org_id','enabled','version','email_rule_id','email_approval_version','created_at','enabled_at','last_checked_at','last_error','local_time','approved_owner','send_start','send_end','delivery_mode','instructions']) is distinct from (p-array['local_time','send_start','send_end','delivery_mode','instructions'])
     or r.instructions<>coalesce(p->>'instructions','') or r.local_time<>(p->>'local_time')::time or r.delivery_mode<>coalesce(p->>'delivery_mode','review') or r.send_start<>coalesce(p->>'send_start','08:00')::time or r.send_end<>coalesce(p->>'send_end','18:00')::time then raise exception 'WF409: This request was already used for different settings'; end if;
   return to_jsonb(r);
  end if;
  if (select count(*) from public.korlix_workforce_automations where org_id=p_org)>=25 then raise exception 'WF: Limit of 25 automations per workspace reached'; end if;
  if p->>'member_id' is not null and not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=(p->>'member_id')::uuid and active) then raise exception 'WF: Select an active workspace member'; end if;
  if exists(select 1 from jsonb_array_elements_text(p->'days') d where d::int not between 0 and 6) then raise exception 'WF: Choose valid weekdays'; end if;
  insert into public.korlix_workforce_automations(id,org_id,name,kind,channel,member_id,recipient_id,delay_minutes,local_time,days,daily_limit,delivery_mode,send_start,send_end,instructions)
   values((p->>'id')::uuid,p_org,p->>'name',p->>'kind',p->>'channel',(p->>'member_id')::uuid,(p->>'recipient_id')::uuid,(p->>'delay_minutes')::int,(p->>'local_time')::time,p->'days',(p->>'daily_limit')::int,coalesce(p->>'delivery_mode','review'),coalesce(p->>'send_start','08:00')::time,coalesce(p->>'send_end','18:00')::time,coalesce(p->>'instructions','')) returning * into r;
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
 if p_action='update' then
  if r.version is distinct from (p->>'version')::int then raise exception 'WF409: This reminder changed. Close and reopen it before saving'; end if;
  if r.channel<>'workspace_email' or p->>'channel' is distinct from r.channel or p->>'kind' is distinct from r.kind then raise exception 'WF: Edit the existing Workforce email reminder type'; end if;
  if p->>'member_id' is not null and not exists(select 1 from public.korlix_workforce_members where org_id=p_org and user_id=(p->>'member_id')::uuid and active) then raise exception 'WF: Select an active workspace member'; end if;
  if not exists(select 1 from public.korlix_workforce_email_recipients where id=(p->>'recipient_id')::uuid and org_id=p_org and active and approved_by=p_actor) then raise exception 'WF: Choose an approved email recipient'; end if;
  if jsonb_array_length(p->'days') not between 1 and 7 or exists(select 1 from jsonb_array_elements_text(p->'days') d where d::int not between 0 and 6) then raise exception 'WF: Choose valid weekdays'; end if;
  if r.kind='daily_summary' and ((p->>'local_time')::time<(p->>'send_start')::time or (p->>'local_time')::time>=(p->>'send_end')::time) then raise exception 'WF: Choose a summary time inside the sending window'; end if;
  update public.korlix_workforce_automations set
   name=p->>'name',instructions=coalesce(p->>'instructions',''),member_id=(p->>'member_id')::uuid,
   recipient_id=(p->>'recipient_id')::uuid,delay_minutes=(p->>'delay_minutes')::int,
   local_time=(p->>'local_time')::time,days=p->'days',daily_limit=(p->>'daily_limit')::int,
   delivery_mode=p->>'delivery_mode',send_start=(p->>'send_start')::time,send_end=(p->>'send_end')::time,
   enabled=false,approved_owner=null,version=version+1,last_error=null
   where id=r.id returning * into r;
  -- Never send an old draft after an edit. Already dispatched messages retain their receipts.
  update public.korlix_workforce_automation_jobs set status='cancelled',result_code='rule_updated',completed_at=t,
   lease_token=null,lease_until=null,email_payload=null,sender_fingerprint=null,approved_by=null,version=version+1
   where rule_id=r.id and status in ('pending','processing','draft') and dispatch_at is null;
  insert into public.korlix_workforce_audit(org_id,actor_id,action,details)
   values(p_org,p_actor,'automation_updated',jsonb_build_object('rule_id',r.id,'version',r.version));
  return to_jsonb(r);
 elsif p_action in ('enable','pause') then
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
  if not r.enabled or (p ? 'version' and r.version is distinct from (p->>'version')::int) then return '{}'; end if;
  if (p->>'expires_at')::timestamptz<=t then return '{}'; end if;
  insert into public.korlix_workforce_automation_jobs(org_id,rule_id,event_key,subject,body,member_id,expires_at)
   values(p_org,r.id,p->>'event_key',p->>'subject',p->>'body',(p->>'member_id')::uuid,(p->>'expires_at')::timestamptz)
   on conflict(rule_id,event_key) do update set
    subject=excluded.subject,body=excluded.body,member_id=excluded.member_id,expires_at=excluded.expires_at,
    status='pending',result_code=null,completed_at=null,next_attempt_at=t,attempts=0,
    email_payload=null,sender_fingerprint=null,recipient_version=null,rule_version=null,approved_by=null,
    lease_token=null,lease_until=null,version=korlix_workforce_automation_jobs.version+1
   where korlix_workforce_automation_jobs.status='cancelled'
    and korlix_workforce_automation_jobs.result_code='rule_updated'
    and korlix_workforce_automation_jobs.dispatch_at is null
    and (p->>'version')::int=r.version;
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
