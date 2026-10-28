-- Service-only, one submission per source draft. No job runs automatically.
alter table public.korlix_auto_email_mailboxes add column dispatch_lease uuid, add column dispatch_lease_until timestamptz;
create table public.korlix_auto_email_outbox (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 agent_id text not null,
 draft_id uuid not null unique references public.korlix_agent_email_messages(id) on delete cascade,
 mailbox_id uuid not null references public.korlix_auto_email_mailboxes(id) on delete cascade,
 mailbox_generation bigint not null,
 provider text not null check(provider in ('google','microsoft')),
 snapshot jsonb not null,
 status text not null default 'preparing' check(status in ('preparing','submitting','accepted','not_sent','uncertain')),
 provider_message_id text,
 result_code text,
 confirmed_at timestamptz not null default now(),
 submitted_at timestamptz,
 finished_at timestamptz
);
create index korlix_auto_email_outbox_owner on public.korlix_auto_email_outbox(user_id,agent_id,confirmed_at desc);
alter table public.korlix_auto_email_outbox enable row level security;
revoke all on public.korlix_auto_email_outbox from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_auto_email_outbox to service_role;

-- Freeze the retired source, including edits/approvals that raced the handoff.
create function public.korlix_auto_email_retired_draft_guard() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if old.metadata ? 'autoEmailOutboxId' then raise exception 'draft_moved_to_outbox'; end if;
 return new;
end $$;
create trigger korlix_auto_email_retired_draft_guard before update on public.korlix_agent_email_messages
for each row execute function public.korlix_auto_email_retired_draft_guard();

create function public.korlix_auto_email_outbox_claim(p_user uuid,p_agent text,p_job uuid,p_draft uuid,p_provider text,p_generation bigint,p_snapshot jsonb,p_daily_cap integer) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare m public.korlix_auto_email_mailboxes; d public.korlix_agent_email_messages; s public.korlix_agent_email_settings; r public.korlix_agent_email_recipients; j public.korlix_auto_email_outbox; n integer;
begin
 select * into m from public.korlix_auto_email_mailboxes where user_id=p_user and agent_id=p_agent and provider=p_provider for update;
 if not found then raise exception 'mailbox_unavailable'; end if;
 select * into s from public.korlix_agent_email_settings where user_id=p_user and agent_id=p_agent for update;
 if not found or not s.enabled or s.emergency_paused or s.operating_mode='draft_only' then raise exception 'workspace_paused'; end if;
 select * into j from public.korlix_auto_email_outbox where user_id=p_user and agent_id=p_agent and draft_id=p_draft;
 if found then return jsonb_build_object('claimed',false,'job',to_jsonb(j)); end if;
 if m.status<>'connected' or m.generation is distinct from p_generation or (m.identity->>'email') is distinct from (p_snapshot->>'from') then raise exception 'mailbox_changed'; end if;
 if m.dispatch_lease_until>now() then raise exception 'mailbox_busy'; end if;
 select * into d from public.korlix_agent_email_messages where id=p_draft and user_id=p_user and agent_id=p_agent for update;
 if not found or d.status not in ('draft','pending_approval') or d.message_kind<>'transactional' or d.rule_id is not null or d.scheduled_at is not null or d.authorization_type<>'none' or d.attempt_count<>0 or d.provider_message_id is not null or d.sent_at is not null then raise exception 'draft_not_eligible'; end if;
 if d.subject is distinct from (p_snapshot->>'subject') or d.text_body is distinct from (p_snapshot->>'textBody') or d.to_email is distinct from (p_snapshot->>'to') or d.recipient_id::text is distinct from (p_snapshot->>'recipientId') or d.updated_at is distinct from (p_snapshot->>'updatedAt')::timestamptz then raise exception 'draft_changed'; end if;
 select * into r from public.korlix_agent_email_recipients where id=d.recipient_id and user_id=p_user and agent_id=p_agent for update;
 if not found or not r.active or r.consent_status not in ('transactional_only','marketing_opt_in') or r.suppressed_at is not null or r.unsubscribed_at is not null or lower(r.email)<>lower(d.to_email) then raise exception 'recipient_unavailable'; end if;
 select count(*) into n from public.korlix_auto_email_outbox where user_id=p_user and agent_id=p_agent and confirmed_at>=now()-interval '24 hours';
 if n>=least(greatest(coalesce(p_daily_cap,5),1),20,s.daily_send_cap) then raise exception 'daily_limit'; end if;
 update public.korlix_auto_email_mailboxes set dispatch_lease=p_job,dispatch_lease_until=now()+interval '2 minutes' where id=m.id;
 insert into public.korlix_auto_email_outbox(id,user_id,agent_id,draft_id,mailbox_id,mailbox_generation,provider,snapshot)
 values(p_job,p_user,p_agent,p_draft,m.id,m.generation,p_provider,p_snapshot) returning * into j;
 update public.korlix_agent_email_messages set status='cancelled',confirmation_nonce_hash=null,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('autoEmailOutboxId',p_job),updated_at=now() where id=d.id;
 return jsonb_build_object('claimed',true,'job',to_jsonb(j));
end $$;

create function public.korlix_auto_email_outbox_submit(p_user uuid,p_agent text,p_job uuid) returns boolean
language plpgsql security invoker set search_path=public,pg_temp as $$
declare j public.korlix_auto_email_outbox; m public.korlix_auto_email_mailboxes; s public.korlix_agent_email_settings; r public.korlix_agent_email_recipients;
begin
 select * into j from public.korlix_auto_email_outbox where id=p_job and user_id=p_user and agent_id=p_agent;
 if not found then return false; end if;
 select * into m from public.korlix_auto_email_mailboxes where id=j.mailbox_id for update;
 select * into s from public.korlix_agent_email_settings where user_id=p_user and agent_id=p_agent for update;
 select * into j from public.korlix_auto_email_outbox where id=p_job for update;
 select * into r from public.korlix_agent_email_recipients where id=(j.snapshot->>'recipientId')::uuid and user_id=p_user and agent_id=p_agent;
 if j.status<>'preparing' or m.status<>'connected' or m.generation<>j.mailbox_generation or m.dispatch_lease is distinct from p_job or m.dispatch_lease_until<=now() or m.identity->>'email'<>j.snapshot->>'from' then return false; end if;
 if s.id is null or not s.enabled or s.emergency_paused or s.operating_mode='draft_only' or r.id is null or not r.active or r.consent_status not in ('transactional_only','marketing_opt_in') or r.suppressed_at is not null or r.unsubscribed_at is not null or lower(r.email)<>lower(j.snapshot->>'to') then return false; end if;
 update public.korlix_auto_email_outbox set status='submitting',submitted_at=now() where id=p_job;
 return true;
end $$;

create function public.korlix_auto_email_outbox_finish(p_user uuid,p_agent text,p_job uuid,p_status text,p_code text,p_provider_id text) returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if p_status not in ('accepted','not_sent','uncertain') then raise exception 'invalid_result'; end if;
 perform 1 from public.korlix_auto_email_mailboxes where user_id=p_user and agent_id=p_agent and dispatch_lease=p_job for update;
 update public.korlix_auto_email_outbox set status=p_status,result_code=p_code,provider_message_id=p_provider_id,finished_at=now()
 where id=p_job and user_id=p_user and agent_id=p_agent and (status='submitting' or (status='preparing' and p_status='not_sent'));
 update public.korlix_auto_email_mailboxes set dispatch_lease=null,dispatch_lease_until=null where user_id=p_user and agent_id=p_agent and dispatch_lease=p_job;
end $$;
create function public.korlix_auto_email_outbox_cleanup() returns void
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 update public.korlix_auto_email_outbox set status=case when status='preparing' then 'not_sent' else 'uncertain' end,result_code='interrupted',finished_at=now()
 where status in ('preparing','submitting') and confirmed_at<now()-interval '2 minutes';
end $$;
revoke all on function public.korlix_auto_email_retired_draft_guard(),public.korlix_auto_email_outbox_claim(uuid,text,uuid,uuid,text,bigint,jsonb,integer),public.korlix_auto_email_outbox_submit(uuid,text,uuid),public.korlix_auto_email_outbox_finish(uuid,text,uuid,text,text,text),public.korlix_auto_email_outbox_cleanup() from public,anon,authenticated;
grant execute on function public.korlix_auto_email_retired_draft_guard(),public.korlix_auto_email_outbox_claim(uuid,text,uuid,uuid,text,bigint,jsonb,integer),public.korlix_auto_email_outbox_submit(uuid,text,uuid),public.korlix_auto_email_outbox_finish(uuid,text,uuid,text,text,text),public.korlix_auto_email_outbox_cleanup() to service_role;
