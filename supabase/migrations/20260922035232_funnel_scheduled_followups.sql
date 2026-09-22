begin;
alter table public.korlix_funnel_followup_tasks
  add column scheduled_for timestamptz,
  add column scheduled_approved_at timestamptz,
  add column schedule_agent_id text;
alter table public.korlix_funnel_followup_tasks drop constraint korlix_funnel_followup_tasks_state_check;
alter table public.korlix_funnel_followup_tasks add constraint korlix_funnel_followup_tasks_state_check
  check(state in ('review','scheduled','processing','sent','done','dismissed','needs_review'));
alter table public.korlix_funnel_followup_tasks add constraint korlix_funnel_schedule_approval_check
  check(state<>'scheduled' or (scheduled_for is not null and scheduled_approved_at is not null and schedule_agent_id is not null));
create index korlix_funnel_scheduled_due on public.korlix_funnel_followup_tasks(scheduled_for,id) where state='scheduled';
create or replace function public.korlix_funnel_followup_v1(p_actor uuid,p_action text,p_id uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; s public.korlix_funnel_followup_settings; t public.korlix_funnel_followup_tasks; l public.korlix_funnel_leads; c public.korlix_contacts; off integer; filt text; send_at timestamptz;
begin
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Funnel Studio requires Enterprise.' using errcode='42501'; end if;
  select * into f from public.korlix_funnels where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  insert into public.korlix_funnel_followup_settings(funnel_id) values(f.id) on conflict do nothing;
  select * into s from public.korlix_funnel_followup_settings where funnel_id=f.id for update;
  if p_action='settings' then
    if (p_data->>'version')::integer is distinct from s.version then raise exception 'Follow-up settings changed. Refresh first.' using errcode='40001'; end if;
    if p_data->>'enabled'='true' and p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm this workflow before enabling it.'; end if;
    if p_data->>'email_enabled' is distinct from 'true' and p_data->>'call_enabled' is distinct from 'true' then raise exception 'Choose at least one follow-up channel.'; end if;
    update public.korlix_funnel_followup_settings set enabled=(p_data->>'enabled')::boolean,email_enabled=(p_data->>'email_enabled')::boolean,
      call_enabled=(p_data->>'call_enabled')::boolean,delay_minutes=(p_data->>'delay_minutes')::integer,subject=p_data->>'subject',body=p_data->>'body',version=version+1,updated_at=now() where funnel_id=f.id returning * into s;
    if not s.enabled or not s.email_enabled then
      update public.korlix_funnel_followup_tasks set state='review',scheduled_for=null,scheduled_approved_at=null,schedule_agent_id=null,
        note='Schedule cancelled because this workflow was paused. Review again before scheduling.',version=version+1,updated_at=now()
        where funnel_id=f.id and state='scheduled';
    end if;
    return to_jsonb(s);
  elsif p_action='enqueue' then
    if not s.enabled or f.state<>'published' then raise exception 'Enable the workflow on a published funnel first.' using errcode='40001'; end if;
    if not exists(select 1 from public.korlix_funnel_leads where id=(p_data->>'lead_id')::uuid and funnel_id=f.id) then raise exception 'Inquiry not found.' using errcode='P0002'; end if;
    perform public.korlix_funnel_followup_enqueue_v1((p_data->>'lead_id')::uuid);return jsonb_build_object('queued',true);
  elsif p_action='state' then
    -- Never retry a potentially accepted email because a browser or server disappeared.
    update public.korlix_funnel_followup_tasks set state='needs_review',note='Sending was interrupted. Check delivery before taking another action.',updated_at=now(),version=version+1 where funnel_id=f.id and state='processing' and updated_at<now()-interval '5 minutes';
    off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));filt:=coalesce(p_data->>'filter','open');
    if filt not in ('open','completed','all') then raise exception 'Invalid task filter.'; end if;
    return jsonb_build_object('settings',to_jsonb(s),'page_state',f.state,'offset',off,
      'total',(select count(*) from public.korlix_funnel_followup_tasks x where x.funnel_id=f.id and (filt='all' or (filt='open' and x.state in ('review','scheduled','processing','needs_review')) or (filt='completed' and x.state in ('sent','done','dismissed')))),
      'counts',jsonb_build_object('open',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state in ('review','scheduled','processing','needs_review')),
      'scheduled',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state='scheduled'),
      'sent',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state='sent'),'completed',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state in ('done','dismissed'))),
      'tasks',coalesce((select jsonb_agg(x.data order by x.due_at,x.id) from (select t0.due_at,t0.id,
        (to_jsonb(t0)-'approval_nonce')||jsonb_build_object('lead_name',l0.name,'inquiry',l0.message,'contact_id',c0.id,'phone',c0.phone,'call_brief',c0.call_brief,
        'email_allowed',coalesce(c0.archived_at is null and not c0.do_not_contact and c0.email_permission in ('transactional','marketing') and c0.consent_at is not null and lower(c0.email)=lower(t0.to_email),false),
        'call_allowed',coalesce(c0.archived_at is null and not c0.do_not_contact and c0.call_permission='allowed' and regexp_replace(c0.phone,'[ ()-]','','g') ~ '^\+[1-9][0-9]{6,14}$',false)) data
        from public.korlix_funnel_followup_tasks t0 join public.korlix_funnel_leads l0 on l0.id=t0.lead_id left join public.korlix_contacts c0 on c0.id=l0.contact_id and c0.user_id=p_actor
        where t0.funnel_id=f.id and (filt='all' or (filt='open' and t0.state in ('review','scheduled','processing','needs_review')) or (filt='completed' and t0.state in ('sent','done','dismissed')))
        order by t0.due_at,t0.id limit 25 offset off) x),'[]'::jsonb));
  end if;
  select * into t from public.korlix_funnel_followup_tasks where id=(p_data->>'task_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Follow-up not found.' using errcode='P0002'; end if;
  select * into l from public.korlix_funnel_leads where id=t.lead_id;
  select * into c from public.korlix_contacts where id=l.contact_id and user_id=p_actor;
  if p_action='get' then return jsonb_build_object('task',to_jsonb(t),'contact',to_jsonb(c)); end if;
  if p_action in ('edit','claim','resolve','schedule','cancel_schedule','claim_scheduled') and (p_data->>'version')::integer is distinct from t.version then raise exception 'This follow-up changed. Refresh before continuing.' using errcode='40001'; end if;
  if p_action='cancel_schedule' then
    if t.state<>'scheduled' then raise exception 'This schedule already changed or sending has started. Refresh its status.' using errcode='40001'; end if;
    update public.korlix_funnel_followup_tasks set state='review',scheduled_for=null,scheduled_approved_at=null,schedule_agent_id=null,
      note=left(coalesce(p_data->>'note','Schedule cancelled by owner. No new send was started.'),1000),version=version+1,updated_at=now() where id=t.id returning * into t;
    return to_jsonb(t);
  end if;
  if p_action in ('claim','check','schedule','claim_scheduled') then
    if not s.enabled or not s.email_enabled or f.state<>'published' then raise exception 'This workflow or page is paused. Resume email follow-ups before sending.' using errcode='40001'; end if;
    if t.channel<>'email' or c.id is null or c.archived_at is not null or c.do_not_contact or c.email_permission not in ('transactional','marketing') or c.consent_at is null or lower(c.email) is distinct from lower(t.to_email) then raise exception 'This contact does not currently permit this email. Review Contacts CRM.' using errcode='40001'; end if;
    if p_action='schedule' then
      if t.state<>'review' or t.message_id is not null then raise exception 'Only an unprepared email can be scheduled. Check existing delivery first.' using errcode='40001'; end if;
      if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and approve this exact scheduled email.'; end if;
      if coalesce(p_data->>'agent_id','') !~ '^[a-z][a-z0-9_]{0,95}$' then raise exception 'An approved NOVA agent is required.'; end if;
      send_at:=(p_data->>'scheduled_for')::timestamptz;
      if send_at is null or send_at<now()+interval '2 minutes' or send_at>now()+interval '30 days' or send_at<t.due_at then
        raise exception 'Choose a send time at least two minutes from now, after the task is due, and within 30 days.' using errcode='40001';
      end if;
      update public.korlix_funnel_followup_tasks set state='scheduled',scheduled_for=send_at,scheduled_approved_at=now(),schedule_agent_id=p_data->>'agent_id',
        version=version+1,updated_at=now(),note='Owner approved this exact reply for scheduled sending.' where id=t.id returning * into t;
      return to_jsonb(t);
    end if;
    if p_action='claim_scheduled' then
      if t.state<>'scheduled' or t.scheduled_approved_at is null or t.schedule_agent_id is distinct from p_data->>'agent_id'
         or t.scheduled_for>now() or t.scheduled_for<now()-interval '24 hours' then
        raise exception 'This schedule changed, is not due, or needs renewed approval.' using errcode='40001';
      end if;
      update public.korlix_funnel_followup_tasks set state='processing',version=version+1,updated_at=now(),note='Sending the owner-approved scheduled email.' where id=t.id returning * into t;
    end if;
    if t.due_at>now() then raise exception 'This follow-up is not due yet.' using errcode='40001'; end if;
    if (p_action='claim' and t.state<>'review') or (p_action='check' and t.state<>'processing') then raise exception 'This email needs a delivery check or has already been handled.' using errcode='40001'; end if;
    if p_action='claim' then
      if p_data->>'confirmed' is distinct from 'true' then raise exception 'Review and confirm sending this exact email.'; end if;
      update public.korlix_funnel_followup_tasks set state='processing',version=version+1,updated_at=now(),note='Sending the owner-approved email.' where id=t.id returning * into t;
    end if;
  elsif p_action='edit' then
    if t.state<>'review' or t.message_id is not null or t.channel<>'email' then raise exception 'Only an unsent, unprepared email can be edited.' using errcode='40001'; end if;
    update public.korlix_funnel_followup_tasks set subject=p_data->>'subject',body=p_data->>'body',version=version+1,updated_at=now() where id=t.id returning * into t;
  elsif p_action='attach' then
    if t.state<>'processing' or (t.message_id is not null and t.message_id is distinct from (p_data->>'message_id')::uuid) then raise exception 'Email preparation changed.' using errcode='40001'; end if;
    update public.korlix_funnel_followup_tasks set message_id=(p_data->>'message_id')::uuid,agent_id=p_data->>'agent_id',updated_at=now() where id=t.id returning * into t;
  elsif p_action='finish' then
    if t.state not in ('processing','needs_review','review') then return to_jsonb(t); end if;
    if p_data->>'state' not in ('sent','needs_review','review') then raise exception 'Invalid email outcome.'; end if;
    update public.korlix_funnel_followup_tasks set state=p_data->>'state',note=left(coalesce(p_data->>'note',''),1000),version=version+1,updated_at=now() where id=t.id returning * into t;
  elsif p_action='resolve' then
    if t.state<>'review' then raise exception 'This task has already been handled or needs a delivery check.' using errcode='40001'; end if;
    if p_data->>'state'='done' and t.channel<>'call_review' then raise exception 'Only call review tasks can be marked reviewed.'; end if;
    if p_data->>'state' not in ('done','dismissed') then raise exception 'Invalid task outcome.'; end if;
    update public.korlix_funnel_followup_tasks set state=p_data->>'state',note=left(coalesce(p_data->>'note',''),1000),version=version+1,updated_at=now() where id=t.id returning * into t;
  else raise exception 'Unsupported follow-up action.';
  end if;
  return to_jsonb(t);
end $$;

-- A page pause cancels pending schedules in the same transaction. Resuming does not re-authorize them.
create function public.korlix_funnel_schedule_page_pause_v1() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if new.state is distinct from 'published' then
    update public.korlix_funnel_followup_tasks set state='review',scheduled_for=null,scheduled_approved_at=null,schedule_agent_id=null,
      note='Schedule cancelled because the funnel was paused. Review again before scheduling.',version=version+1,updated_at=now()
      where funnel_id=new.id and state='scheduled';
  end if;
  return new;
end $$;
create trigger korlix_funnel_schedule_page_pause after update of state on public.korlix_funnels
for each row execute function public.korlix_funnel_schedule_page_pause_v1();

-- Only the server-bound owner is scanned; locks/versions are claimed by the sending command.
create function public.korlix_funnel_scheduled_due_v1(p_owner uuid) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  update public.korlix_funnel_followup_tasks t set state='needs_review',note='Scheduled sending was interrupted. Check delivery; automatic retry is disabled.',version=t.version+1,updated_at=now()
    from public.korlix_funnels f where t.funnel_id=f.id and f.user_id=p_owner and t.state='processing' and t.updated_at<now()-interval '5 minutes';
  update public.korlix_funnel_followup_tasks t set state='review',scheduled_for=null,scheduled_approved_at=null,schedule_agent_id=null,
    note='Schedule held: timing, page, workflow, Enterprise access, or contact permission changed. Review again before sending.',version=t.version+1,updated_at=now()
    from public.korlix_funnels f where t.funnel_id=f.id and f.user_id=p_owner and t.state='scheduled' and t.scheduled_for<=now()
    and (t.scheduled_for<now()-interval '24 hours' or f.state<>'published'
      or not exists(select 1 from public.user_profiles where id=p_owner and lower(trim(tier))='enterprise')
      or not exists(select 1 from public.korlix_funnel_followup_settings s where s.funnel_id=f.id and s.enabled and s.email_enabled)
      or not exists(select 1 from public.korlix_funnel_leads l join public.korlix_contacts c on c.id=l.contact_id and c.user_id=p_owner
        where l.id=t.lead_id and c.archived_at is null and not c.do_not_contact and c.email_permission in ('transactional','marketing')
        and c.consent_at is not null and lower(c.email)=lower(t.to_email)));
  return coalesce((select jsonb_agg(to_jsonb(q)) from (
    select t.id,t.funnel_id,t.version from public.korlix_funnel_followup_tasks t join public.korlix_funnels f on f.id=t.funnel_id
    where f.user_id=p_owner and t.state='scheduled' and t.scheduled_for<=now() order by t.scheduled_for,t.id limit 5
  ) q),'[]'::jsonb);
end $$;
revoke all on function public.korlix_funnel_followup_v1(uuid,text,uuid,jsonb),public.korlix_funnel_schedule_page_pause_v1(),public.korlix_funnel_scheduled_due_v1(uuid) from public,anon,authenticated;
grant execute on function public.korlix_funnel_followup_v1(uuid,text,uuid,jsonb),public.korlix_funnel_schedule_page_pause_v1(),public.korlix_funnel_scheduled_due_v1(uuid) to service_role;
commit;
