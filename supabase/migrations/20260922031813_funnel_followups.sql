begin;
create table public.korlix_funnel_followup_settings (
  funnel_id uuid primary key references public.korlix_funnels(id) on delete cascade,
  enabled boolean not null default false,
  email_enabled boolean not null default true,
  call_enabled boolean not null default false,
  delay_minutes integer not null default 0 check(delay_minutes in (0,60,240,1440)),
  subject text not null default 'Your inquiry at {{brand}}' check(length(subject) between 1 and 160),
  body text not null default E'Hi {{name}},\n\nThank you for contacting {{brand}}. We received your inquiry and would be happy to discuss your needs. What would be a good next step for you?\n\n{{brand}}' check(length(body) between 1 and 4000),
  version integer not null default 1,
  updated_at timestamptz not null default now()
);
create table public.korlix_funnel_followup_tasks (
  id uuid primary key default gen_random_uuid(),
  funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
  lead_id uuid not null references public.korlix_funnel_leads(id) on delete cascade,
  channel text not null check(channel in ('email','call_review')),
  state text not null default 'review' check(state in ('review','processing','sent','done','dismissed','needs_review')),
  due_at timestamptz not null,
  subject text not null check(length(subject)<=400),
  body text not null check(length(body)<=6000),
  to_email text not null,
  message_id uuid,
  agent_id text,
  approval_nonce uuid not null default gen_random_uuid(),
  version integer not null default 1,
  note text not null default '' check(length(note)<=1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(lead_id,channel)
);
create index korlix_funnel_followup_queue on public.korlix_funnel_followup_tasks(funnel_id,state,due_at,id);
alter table public.korlix_funnel_followup_settings enable row level security;
alter table public.korlix_funnel_followup_tasks enable row level security;
revoke all on public.korlix_funnel_followup_settings,public.korlix_funnel_followup_tasks from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_followup_settings,public.korlix_funnel_followup_tasks to service_role;

create function public.korlix_funnel_followup_text_v1(template text,lead_name text,brand text,funnel_name text,booking text)
returns text language sql immutable security invoker set search_path=public,pg_temp as $$
  select replace(replace(replace(replace(template,'{{booking_url}}',coalesce(booking,'')),'{{funnel}}',funnel_name),'{{brand}}',brand),'{{name}}',lead_name)
$$;
create function public.korlix_funnel_followup_enqueue_v1(target uuid)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare l public.korlix_funnel_leads; f public.korlix_funnels; s public.korlix_funnel_followup_settings;
begin
  select * into l from public.korlix_funnel_leads where id=target;
  select * into f from public.korlix_funnels where id=l.funnel_id;
  select * into s from public.korlix_funnel_followup_settings where funnel_id=f.id;
  if not found or not s.enabled or f.state<>'published' or not exists(select 1 from public.user_profiles where id=f.user_id and lower(trim(tier))='enterprise') then return; end if;
  insert into public.korlix_funnel_followup_tasks(funnel_id,lead_id,channel,due_at,subject,body,to_email)
  select f.id,l.id,ch,now()+make_interval(mins=>s.delay_minutes),
    left(public.korlix_funnel_followup_text_v1(s.subject,l.name,f.published->>'brand',f.name,f.published->>'booking_url'),200),
    left(public.korlix_funnel_followup_text_v1(s.body,l.name,f.published->>'brand',f.name,f.published->>'booking_url'),6000),l.email
  from unnest(array[case when s.email_enabled then 'email' end,case when s.call_enabled then 'call_review' end]) ch
  where ch is not null on conflict(lead_id,channel) do nothing;
end $$;
create function public.korlix_funnel_followup_on_lead_v1() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin perform public.korlix_funnel_followup_enqueue_v1(new.id); return new; end $$;
create trigger korlix_funnel_followup_on_lead after insert on public.korlix_funnel_leads for each row execute function public.korlix_funnel_followup_on_lead_v1();

create function public.korlix_funnel_followup_v1(p_actor uuid,p_action text,p_id uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; s public.korlix_funnel_followup_settings; t public.korlix_funnel_followup_tasks; l public.korlix_funnel_leads; c public.korlix_contacts; off integer; filt text;
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
      'total',(select count(*) from public.korlix_funnel_followup_tasks x where x.funnel_id=f.id and (filt='all' or (filt='open' and x.state in ('review','processing','needs_review')) or (filt='completed' and x.state in ('sent','done','dismissed')))),
      'counts',jsonb_build_object('open',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state in ('review','processing','needs_review')),
      'sent',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state='sent'),'completed',(select count(*) from public.korlix_funnel_followup_tasks where funnel_id=f.id and state in ('done','dismissed'))),
      'tasks',coalesce((select jsonb_agg(x.data order by x.due_at,x.id) from (select t0.due_at,t0.id,
        (to_jsonb(t0)-'approval_nonce')||jsonb_build_object('lead_name',l0.name,'inquiry',l0.message,'contact_id',c0.id,'phone',c0.phone,'call_brief',c0.call_brief,
        'email_allowed',coalesce(c0.archived_at is null and not c0.do_not_contact and c0.email_permission in ('transactional','marketing') and c0.consent_at is not null and lower(c0.email)=lower(t0.to_email),false),
        'call_allowed',coalesce(c0.archived_at is null and not c0.do_not_contact and c0.call_permission='allowed' and regexp_replace(c0.phone,'[ ()-]','','g') ~ '^\+[1-9][0-9]{6,14}$',false)) data
        from public.korlix_funnel_followup_tasks t0 join public.korlix_funnel_leads l0 on l0.id=t0.lead_id left join public.korlix_contacts c0 on c0.id=l0.contact_id and c0.user_id=p_actor
        where t0.funnel_id=f.id and (filt='all' or (filt='open' and t0.state in ('review','processing','needs_review')) or (filt='completed' and t0.state in ('sent','done','dismissed')))
        order by t0.due_at,t0.id limit 25 offset off) x),'[]'::jsonb));
  end if;
  select * into t from public.korlix_funnel_followup_tasks where id=(p_data->>'task_id')::uuid and funnel_id=f.id for update;
  if not found then raise exception 'Follow-up not found.' using errcode='P0002'; end if;
  select * into l from public.korlix_funnel_leads where id=t.lead_id;
  select * into c from public.korlix_contacts where id=l.contact_id and user_id=p_actor;
  if p_action='get' then return jsonb_build_object('task',to_jsonb(t),'contact',to_jsonb(c)); end if;
  if p_action in ('edit','claim','resolve') and (p_data->>'version')::integer is distinct from t.version then raise exception 'This follow-up changed. Refresh before continuing.' using errcode='40001'; end if;
  if p_action in ('claim','check') then
    if not s.enabled or not s.email_enabled or f.state<>'published' then raise exception 'This workflow or page is paused. Resume email follow-ups before sending.' using errcode='40001'; end if;
    if t.channel<>'email' or c.id is null or c.archived_at is not null or c.do_not_contact or c.email_permission not in ('transactional','marketing') or c.consent_at is null or lower(c.email) is distinct from lower(t.to_email) then raise exception 'This contact does not currently permit this email. Review Contacts CRM.' using errcode='40001'; end if;
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
revoke all on function public.korlix_funnel_followup_text_v1(text,text,text,text,text),public.korlix_funnel_followup_enqueue_v1(uuid),public.korlix_funnel_followup_on_lead_v1(),public.korlix_funnel_followup_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_followup_text_v1(text,text,text,text,text),public.korlix_funnel_followup_enqueue_v1(uuid),public.korlix_funnel_followup_on_lead_v1(),public.korlix_funnel_followup_v1(uuid,text,uuid,jsonb) to service_role;
commit;
