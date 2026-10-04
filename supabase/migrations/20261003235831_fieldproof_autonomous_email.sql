-- Account-private FieldProof email automation. No existing job is backfilled.
create table public.korlix_fieldproof_email_settings (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 version integer not null default 1 check(version>0),
 business_name text not null default '' check(length(business_name)<=120),
 customer_mode text not null default 'off' check(customer_mode in ('off','draft','automatic')),
 followup_mode text not null default 'off' check(followup_mode in ('off','draft','automatic')),
 followup_days integer not null default 3 check(followup_days between 1 and 30),
 supervisor_mode text not null default 'off' check(supervisor_mode in ('off','draft','automatic')),
 supervisor_emails text[] not null default '{}' check(cardinality(supervisor_emails)<=5),
 timezone text not null default 'America/New_York', summary_time time not null default '17:00',
 summary_days integer[] not null default '{1,2,3,4,5}' check(cardinality(summary_days) between 1 and 7 and summary_days <@ array[0,1,2,3,4,5,6]),
 include_photos boolean not null default false, daily_limit integer not null default 25 check(daily_limit between 1 and 100),
 paused boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 last_scanned_at timestamptz, last_queue_code text
);
create index korlix_fieldproof_email_scan on public.korlix_fieldproof_email_settings(last_scanned_at nulls first,owner_id)
 where not paused and supervisor_mode<>'off';
create table public.korlix_fieldproof_email_job_settings (
 job_id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 foreign key(job_id,owner_id) references public.korlix_fieldproof_jobs(id,user_id) on delete cascade,
 version integer not null default 1 check(version>0), customer_email text not null default '' check(length(customer_email)<=254),
 enabled boolean not null default false, updated_at timestamptz not null default now(),
 check(not enabled or customer_email ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}$')
);
create index korlix_fieldproof_email_job_owner on public.korlix_fieldproof_email_job_settings(owner_id);
create table public.korlix_fieldproof_email_recipients (
 owner_id uuid not null references auth.users(id) on delete cascade, recipient text not null check(length(recipient) between 3 and 254),
 suppressed_at timestamptz, reason text, created_at timestamptz not null default now(), primary key(owner_id,recipient)
);
create table public.korlix_fieldproof_email_deliveries (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 job_id uuid, job_version integer, settings_version integer not null, job_settings_version integer,
 kind text not null check(kind in ('customer_report','customer_followup','supervisor_summary')),
 event_key text not null check(length(event_key) between 1 and 200), recipient text not null check(length(recipient) between 3 and 254),
 delivery_mode text not null check(delivery_mode in ('draft','automatic')),
 version integer not null default 1 check(version>0),
 state text not null default 'pending' check(state in ('pending','preparing','draft','ready','sending','retry','accepted','failed','unknown','cancelled')),
 subject text not null default '' check(length(subject)<=240), payload jsonb check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=200000),
 attachment_path text, attachment_sha256 text check(attachment_sha256 ~ '^[0-9a-f]{64}$'), attachment_bytes integer check(attachment_bytes between 1 and 5242880),
 period_start timestamptz, period_end timestamptz, report_date date,
 scheduled_at timestamptz not null default now(), expires_at timestamptz not null,
 lease_token uuid, lease_until timestamptz, first_attempt_at timestamptz, attempt_count integer not null default 0,
 prepared_at timestamptz, accepted_at timestamptz, provider_id text check(length(provider_id)<=200), code text check(length(code)<=100),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), redacted_at timestamptz,
 unique(owner_id,event_key,recipient),
 check(attachment_path is null or attachment_path=owner_id::text || '/' || id::text || '/report.pdf'),
 check((kind='supervisor_summary' and job_id is null and report_date is not null) or (kind<>'supervisor_summary' and job_id is not null))
);
-- Job IDs are deliberately retained as audit references after job deletion; trigger cancels waiting work.
create index korlix_fieldproof_email_owner on public.korlix_fieldproof_email_deliveries(owner_id,created_at desc);
create index korlix_fieldproof_email_job on public.korlix_fieldproof_email_deliveries(job_id,owner_id);
create index korlix_fieldproof_email_due on public.korlix_fieldproof_email_deliveries(scheduled_at,id) where state in ('pending','ready','retry','preparing','sending');
create index korlix_fieldproof_email_provider on public.korlix_fieldproof_email_deliveries(provider_id) where provider_id is not null;
-- A compact event tombstone outlives pruned report/history rows. Hashes are
-- deduplication keys, not credentials; no message body or recipient is retained.
create table public.korlix_fieldproof_email_events (
 owner_id uuid not null references auth.users(id) on delete cascade,event_key text not null check(length(event_key)<=200),
 recipient_key text not null check(length(recipient_key)=32),delivery_id uuid not null,created_at timestamptz not null default now(),
 primary key(owner_id,event_key,recipient_key)
);
-- No account FK: deletion must leave a durable storage cleanup instruction.
create table public.korlix_fieldproof_email_gc (
 id uuid primary key default gen_random_uuid(), attachment_path text not null unique,
 not_before timestamptz not null default now()+interval '10 minutes', created_at timestamptz not null default now(),
 check(attachment_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/report\.pdf$')
);
create index korlix_fieldproof_email_gc_due on public.korlix_fieldproof_email_gc(not_before,id);
create table public.korlix_fieldproof_email_recipient_tokens (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'), owner_id uuid not null, recipient text not null,
 delivery_id uuid not null, created_at timestamptz not null default now(),
 foreign key(owner_id,recipient) references public.korlix_fieldproof_email_recipients(owner_id,recipient) on delete cascade
);
create index korlix_fieldproof_email_tokens_owner on public.korlix_fieldproof_email_recipient_tokens(owner_id,recipient);
create index korlix_fieldproof_email_tokens_delivery on public.korlix_fieldproof_email_recipient_tokens(delivery_id);
create table public.korlix_fieldproof_email_daily_usage (
 owner_id uuid not null references auth.users(id) on delete cascade, usage_date date not null,
 reserved integer not null default 0 check(reserved between 0 and 100), primary key(owner_id,usage_date)
);
alter table public.korlix_fieldproof_email_settings enable row level security;
alter table public.korlix_fieldproof_email_job_settings enable row level security;
alter table public.korlix_fieldproof_email_recipients enable row level security;
alter table public.korlix_fieldproof_email_deliveries enable row level security;
alter table public.korlix_fieldproof_email_recipient_tokens enable row level security;
alter table public.korlix_fieldproof_email_daily_usage enable row level security;
alter table public.korlix_fieldproof_email_gc enable row level security;
alter table public.korlix_fieldproof_email_events enable row level security;
revoke all on public.korlix_fieldproof_email_settings,public.korlix_fieldproof_email_job_settings,public.korlix_fieldproof_email_recipients,
 public.korlix_fieldproof_email_deliveries,public.korlix_fieldproof_email_recipient_tokens,public.korlix_fieldproof_email_daily_usage,public.korlix_fieldproof_email_gc,public.korlix_fieldproof_email_events from public,anon,authenticated;
grant all on public.korlix_fieldproof_email_settings,public.korlix_fieldproof_email_job_settings,public.korlix_fieldproof_email_recipients,
 public.korlix_fieldproof_email_deliveries,public.korlix_fieldproof_email_recipient_tokens,public.korlix_fieldproof_email_daily_usage,public.korlix_fieldproof_email_gc,public.korlix_fieldproof_email_events to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-fieldproof-mail','korlix-fieldproof-mail',false,5242880,array['application/pdf']) on conflict(id) do nothing;
create policy korlix_fieldproof_mail_server_only on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'korlix-fieldproof-mail') with check(bucket_id<>'korlix-fieldproof-mail');

create function public.korlix_fieldproof_email_gc_trigger()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if old.kind='customer_report' then
  insert into korlix_fieldproof_email_gc(attachment_path) values(old.owner_id::text||'/'||old.id::text||'/report.pdf')
   on conflict(attachment_path) do update set not_before=greatest(korlix_fieldproof_email_gc.not_before,excluded.not_before);
 end if;return old;
end $$;
create trigger korlix_fieldproof_email_gc_delete before delete on public.korlix_fieldproof_email_deliveries
 for each row execute function public.korlix_fieldproof_email_gc_trigger();

create function public.korlix_fieldproof_email_event_trigger()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
 insert into korlix_fieldproof_email_events(owner_id,event_key,recipient_key,delivery_id)
  values(new.owner_id,new.event_key,md5(new.recipient),new.id) on conflict do nothing;
 if not found then return null;end if;return new;
end $$;
create trigger korlix_fieldproof_email_event_once before insert on public.korlix_fieldproof_email_deliveries
 for each row execute function public.korlix_fieldproof_email_event_trigger();

-- Keep up to 500 recent records without making ordinary job closeout fail.
-- Pruned reports use the durable GC queue; unsubscribe tokens remain valid.
create function public.korlix_fieldproof_email_room(p_owner uuid,p_needed integer)
returns integer language plpgsql security invoker set search_path=public as $$
declare total integer;
begin
 select count(*) into total from korlix_fieldproof_email_deliveries where owner_id=p_owner;
 if total+p_needed>500 then
  delete from korlix_fieldproof_email_deliveries where id in (
   select id from korlix_fieldproof_email_deliveries where owner_id=p_owner and
    (state in ('accepted','failed','cancelled') or (state='unknown' and first_attempt_at<now()-interval '23 hours'))
    order by created_at,id limit greatest(0,total+p_needed-500));
 end if;
 return greatest(0,500-(select count(*) from korlix_fieldproof_email_deliveries where owner_id=p_owner));
end $$;

-- Match the UI scheduler across DST: first repeated minute; first real minute
-- after a spring gap. Calendar boundaries may be 23 or 25 hours apart.
create function public.korlix_fieldproof_email_summary_window(s public.korlix_fieldproof_email_settings,p_now timestamptz)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare local_now timestamp; local_day date; day_start timestamptz; day_end timestamptz; due_at timestamptz;
begin
 local_now:=p_now at time zone s.timezone;local_day:=local_now::date;
 if s.paused or s.supervisor_mode='off' or not(extract(dow from local_now)::integer=any(s.summary_days)) or local_now::time<s.summary_time then return null;end if;
 day_start:=(local_day::timestamp) at time zone s.timezone;day_end:=((local_day+1)::timestamp) at time zone s.timezone;
 select min(t) into due_at from generate_series(day_start,day_end-interval '1 minute',interval '1 minute') t
  where (t at time zone s.timezone)::time>=s.summary_time;
 day_end:=least(day_end,due_at+interval '6 hours');
 if due_at is null or p_now<due_at or p_now>=day_end then return null;end if;
 return jsonb_build_object('event_key','supervisor:'||local_day::text,'report_date',local_day-1,
  'period_start',((local_day-1)::timestamp) at time zone s.timezone,'period_end',day_start,'scheduled_at',due_at,'expires_at',day_end);
end $$;

-- Called under the same account advisory lock as the existing FieldProof job RPC.
create function public.korlix_fieldproof_email_stale(d public.korlix_fieldproof_email_deliveries)
returns text language plpgsql security invoker set search_path=public as $$
declare s korlix_fieldproof_email_settings; js korlix_fieldproof_email_job_settings; j korlix_fieldproof_jobs;
begin
 select * into s from korlix_fieldproof_email_settings where owner_id=d.owner_id;
 if not found or s.paused then return 'automation_paused';end if;
 if s.version<>d.settings_version then return 'settings_changed';end if;
 if exists(select 1 from korlix_fieldproof_email_recipients where owner_id=d.owner_id and recipient=d.recipient and suppressed_at is not null) then return 'recipient_suppressed';end if;
 if d.expires_at<=now() then return 'expired';end if;
 if d.kind='supervisor_summary' then
  if s.supervisor_mode='off' or not(d.recipient=any(s.supervisor_emails)) then return 'recipient_changed';end if;
 else
  select * into js from korlix_fieldproof_email_job_settings where job_id=d.job_id and owner_id=d.owner_id;
  if not found or not js.enabled or js.version<>d.job_settings_version or js.customer_email<>d.recipient then return 'recipient_changed';end if;
  select * into j from korlix_fieldproof_jobs where id=d.job_id and user_id=d.owner_id;
  if not found or j.state<>'completed' or j.version<>d.job_version then return 'job_changed';end if;
  if (d.kind='customer_report' and s.customer_mode='off') or (d.kind='customer_followup' and s.followup_mode='off') then return 'automation_off';end if;
 end if;
 return null;
end $$;

create function public.korlix_fieldproof_email_job_trigger()
returns trigger language plpgsql security invoker set search_path=public as $$
declare s korlix_fieldproof_email_settings; js korlix_fieldproof_email_job_settings; oid uuid; jid uuid; remaining integer;
begin
 oid:=coalesce(new.user_id,old.user_id);jid:=coalesce(new.id,old.id);
 perform pg_advisory_xact_lock(hashtextextended(oid::text,224));
 if tg_op='DELETE' or (tg_op='UPDATE' and (new.state<>'completed' or new.version<>old.version)) then
  update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='job_changed',version=version+1,lease_token=null,lease_until=null,updated_at=now()
   where owner_id=oid and job_id=jid and state in ('pending','preparing','draft','ready','retry');
 end if;
 if tg_op='DELETE' or (tg_op='UPDATE' and new.state='deleting') then
  insert into korlix_fieldproof_email_gc(attachment_path)
   select owner_id::text||'/'||id::text||'/report.pdf' from korlix_fieldproof_email_deliveries where owner_id=oid and job_id=jid and kind='customer_report'
   on conflict(attachment_path) do update set not_before=greatest(korlix_fieldproof_email_gc.not_before,excluded.not_before);
  update korlix_fieldproof_email_deliveries set payload=null,attachment_path=null,attachment_sha256=null,attachment_bytes=null,subject='',redacted_at=now()
   where owner_id=oid and job_id=jid;
 end if;
 if tg_op='UPDATE' and old.state<>'completed' and new.state='completed' then
  select * into s from korlix_fieldproof_email_settings where owner_id=oid;
  select * into js from korlix_fieldproof_email_job_settings where job_id=jid and owner_id=oid;
  if s.owner_id is not null and not s.paused and js.enabled and
   not exists(select 1 from korlix_fieldproof_email_recipients where owner_id=oid and recipient=js.customer_email and suppressed_at is not null) then
   remaining:=korlix_fieldproof_email_room(oid,(case when s.customer_mode<>'off' then 1 else 0 end)+(case when s.followup_mode<>'off' then 1 else 0 end));
   update korlix_fieldproof_email_settings set last_queue_code=case when remaining<(case when s.customer_mode<>'off' then 1 else 0 end)+(case when s.followup_mode<>'off' then 1 else 0 end) then 'queue_full' else null end where owner_id=oid;
   if s.customer_mode<>'off' and remaining>0 then
    insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,expires_at)
     values(oid,jid,new.version,s.version,js.version,'customer_report','closeout:'||jid||':'||new.version,js.customer_email,s.customer_mode,now()+interval '7 days')
     on conflict(owner_id,event_key,recipient) do nothing;
    remaining:=remaining-1;
   end if;
   if s.followup_mode<>'off' and remaining>0 then
    insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,scheduled_at,expires_at)
     values(oid,jid,new.version,s.version,js.version,'customer_followup','followup:'||jid||':'||new.version,js.customer_email,s.followup_mode,
      now()+make_interval(days=>s.followup_days),now()+make_interval(days=>s.followup_days+7)) on conflict(owner_id,event_key,recipient) do nothing;
   end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger korlix_fieldproof_email_closeout after update or delete on public.korlix_fieldproof_jobs
 for each row execute function public.korlix_fieldproof_email_job_trigger();

create function public.korlix_fieldproof_email_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public as $$
declare s korlix_fieldproof_email_settings; js korlix_fieldproof_email_job_settings; j korlix_fieldproof_jobs; d korlix_fieldproof_email_deliveries;
 candidate record; body jsonb; result jsonb; emails text[]; days integer[]; code_value text; selected_mode text; recipient_value text;
 local_now timestamp; local_day date; period_begin timestamptz; period_finish timestamptz; due_time timestamptz;
 lease uuid; total integer; id_value uuid;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>210000 then raise exception 'Invalid email operation.' using errcode='22023';end if;
 if p_action not in ('claim','due_accounts','cleanup','cleanup_done','unsubscribe','suppress') and p_actor is null then
  raise exception 'Sign in to use FieldProof email.' using errcode='42501';end if;
 if p_actor is not null then perform pg_advisory_xact_lock(hashtextextended(p_actor::text,224));end if;

 if p_action='due_accounts' then
  with picked as (select owner_id from korlix_fieldproof_email_settings where not paused and supervisor_mode<>'off'
   order by last_scanned_at nulls first,owner_id limit 50 for update skip locked), updated as (
   update korlix_fieldproof_email_settings s1 set last_scanned_at=now() from picked where s1.owner_id=picked.owner_id returning s1.*)
  select coalesce(jsonb_agg(to_jsonb(updated)),'[]') into result from updated;return result;
 elsif p_action='claim' then
  lease:=(p_data->>'lease_token')::uuid;if lease is null then raise exception 'A worker lease is required.' using errcode='22023';end if;
  for candidate in select id,owner_id from korlix_fieldproof_email_deliveries
   where ((state in ('pending','ready','retry') and scheduled_at<=now()) or (state in ('preparing','sending') and lease_until<=now()))
   order by scheduled_at,id limit 40 loop
   if not pg_try_advisory_xact_lock(hashtextextended(candidate.owner_id::text,224)) then continue;end if;
   select * into d from korlix_fieldproof_email_deliveries where id=candidate.id for update skip locked;
   if not found or not((d.state in ('pending','ready','retry') and d.scheduled_at<=now()) or (d.state in ('preparing','sending') and d.lease_until<=now())) then continue;end if;
   if d.state='sending' and d.first_attempt_at is not null then
    update korlix_fieldproof_email_deliveries set state='unknown',code='send_interrupted',lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id;continue;
   end if;
   code_value:=korlix_fieldproof_email_stale(d);
   if code_value is not null then
    update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code=code_value,lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id;continue;
   end if;
   if d.first_attempt_at is not null and (d.first_attempt_at<=now()-interval '23 hours' or d.attempt_count>=8) then
    update korlix_fieldproof_email_deliveries set state='unknown',code='retry_window_closed',lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id;continue;
   end if;
   update korlix_fieldproof_email_deliveries set state=case when payload is null then 'preparing' else 'sending' end,
    lease_token=lease,lease_until=now()+interval '5 minutes',version=version+1,updated_at=now() where id=d.id returning * into d;
   return to_jsonb(d);
  end loop;return null;
 elsif p_action='unsubscribe' then
  if coalesce(p_data->>'token_hash','')!~'^[0-9a-f]{64}$' then return jsonb_build_object('ok',true);end if;
  select owner_id,recipient into candidate from korlix_fieldproof_email_recipient_tokens where token_hash=p_data->>'token_hash';
  if found then
   perform pg_advisory_xact_lock(hashtextextended(candidate.owner_id::text,224));
   update korlix_fieldproof_email_recipients set suppressed_at=coalesce(suppressed_at,now()),reason='unsubscribed' where owner_id=candidate.owner_id and recipient=candidate.recipient;
   update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='recipient_suppressed',version=version+1,lease_token=null,lease_until=null,updated_at=now()
    where owner_id=candidate.owner_id and recipient=candidate.recipient and state in ('pending','preparing','draft','ready','retry');
  end if;return jsonb_build_object('ok',true);
 elsif p_action='suppress' then
  code_value:=replace(p_data->>'reason','email.','');
  if coalesce(code_value,'') not in ('bounced','complained','suppressed') or coalesce(p_data->>'provider_id','')='' then raise exception 'Invalid suppression reason.' using errcode='22023';end if;
  for candidate in select id,owner_id,recipient from korlix_fieldproof_email_deliveries
   where first_attempt_at is not null and ((coalesce(p_id,(p_data->>'delivery_id')::uuid) is not null and id=coalesce(p_id,(p_data->>'delivery_id')::uuid))
     or (coalesce(p_id,(p_data->>'delivery_id')::uuid) is null and provider_id=p_data->>'provider_id'))
    and (provider_id is null or provider_id=p_data->>'provider_id') loop
   perform pg_advisory_xact_lock(hashtextextended(candidate.owner_id::text,224));
   insert into korlix_fieldproof_email_recipients(owner_id,recipient,suppressed_at,reason) values(candidate.owner_id,candidate.recipient,now(),code_value)
    on conflict(owner_id,recipient) do update set suppressed_at=excluded.suppressed_at,reason=excluded.reason;
   update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='recipient_suppressed',version=version+1,lease_token=null,lease_until=null,updated_at=now()
    where owner_id=candidate.owner_id and recipient=candidate.recipient and state in ('pending','preparing','draft','ready','retry');
   update korlix_fieldproof_email_deliveries set provider_id=p_data->>'provider_id',code=code_value,updated_at=now() where id=candidate.id;
  end loop;return jsonb_build_object('ok',true);
 elsif p_action='cleanup' then
  -- Do not hold row locks across storage calls. cleanup_done verifies eligibility again.
  update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='expired',lease_token=null,lease_until=null,version=version+1,updated_at=now()
   where expires_at<=now() and state in ('pending','preparing','draft','ready','retry');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
   (select id,case when kind='customer_report' then owner_id::text||'/'||id::text||'/report.pdf' else null end as attachment_path,false as gc
    from korlix_fieldproof_email_deliveries where redacted_at is null and state in ('accepted','failed','unknown','cancelled')
    and coalesce(prepared_at,created_at)<now()-interval '30 days' order by created_at limit 50)
   union all (select id,attachment_path,true as gc from korlix_fieldproof_email_gc where not_before<=now() order by not_before limit 50)) x;return result;
 elsif p_action='cleanup_done' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>100 then raise exception 'Invalid cleanup confirmation.' using errcode='22023';end if;
  update korlix_fieldproof_email_deliveries set payload=null,attachment_path=null,attachment_sha256=null,attachment_bytes=null,subject='',redacted_at=now()
   where id in (select value::uuid from jsonb_array_elements_text(p_data->'ids')) and redacted_at is null
    and state in ('accepted','failed','unknown','cancelled') and coalesce(prepared_at,created_at)<now()-interval '30 days';
  delete from korlix_fieldproof_email_deliveries where redacted_at<now()-interval '30 days';
  delete from korlix_fieldproof_email_daily_usage where usage_date<current_date-60;
  if jsonb_typeof(p_data->'gc_ids')='array' and jsonb_array_length(p_data->'gc_ids')<=100 then
   delete from korlix_fieldproof_email_gc where id in(select value::uuid from jsonb_array_elements_text(p_data->'gc_ids')) and not_before<=now();
  end if;
  delete from korlix_fieldproof_email_recipient_tokens where created_at<now()-interval '365 days';
  return jsonb_build_object('ok',true);
 end if;

 select * into s from korlix_fieldproof_email_settings where owner_id=p_actor;
 if p_action='save_settings' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm these email settings.' using errcode='22023';end if;
  if coalesce(s.version,0) is distinct from (p_data->>'version')::integer then raise exception 'Email settings changed. Refresh before saving.' using errcode='40001';end if;
  body:=p_data->'settings';
  if jsonb_typeof(body)<>'object' or body is null or octet_length(body::text)>6000 then raise exception 'Invalid email settings.' using errcode='22023';end if;
  if coalesce(body->>'customer_mode','') not in ('off','draft','automatic') or coalesce(body->>'followup_mode','') not in ('off','draft','automatic')
   or coalesce(body->>'supervisor_mode','') not in ('off','draft','automatic') or not exists(select 1 from pg_timezone_names where name=body->>'timezone')
   or coalesce(body->>'summary_time','')!~'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$' or jsonb_typeof(body->'supervisor_emails') is distinct from 'array'
   or jsonb_typeof(body->'summary_days') is distinct from 'array' or jsonb_typeof(body->'paused') is distinct from 'boolean'
   or jsonb_typeof(body->'include_photos') is distinct from 'boolean' then raise exception 'Invalid email settings.' using errcode='22023';end if;
  select coalesce(array_agg(distinct lower(trim(value))),'{}') into emails from jsonb_array_elements_text(body->'supervisor_emails');
  if cardinality(emails)>5 or exists(select 1 from unnest(emails) e where length(e)>254 or e!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}$') then raise exception 'Use up to five valid supervisor email addresses.' using errcode='22023';end if;
  if body->>'supervisor_mode'<>'off' and cardinality(emails)=0 then raise exception 'Add a supervisor email address.' using errcode='22023';end if;
  select array_agg(distinct value::integer) into days from jsonb_array_elements_text(body->'summary_days');
  if days is null or not(days <@ array[0,1,2,3,4,5,6]) then raise exception 'Choose one or more summary days.' using errcode='22023';end if;
  insert into korlix_fieldproof_email_settings(owner_id,business_name,customer_mode,followup_mode,followup_days,supervisor_mode,supervisor_emails,timezone,summary_time,summary_days,include_photos,daily_limit,paused)
   values(p_actor,trim(coalesce(body->>'business_name','')),body->>'customer_mode',body->>'followup_mode',(body->>'followup_days')::integer,body->>'supervisor_mode',emails,
    body->>'timezone',(body->>'summary_time')::time,days,(body->>'include_photos')::boolean,(body->>'daily_limit')::integer,(body->>'paused')::boolean)
   on conflict(owner_id) do update set version=korlix_fieldproof_email_settings.version+1,business_name=excluded.business_name,customer_mode=excluded.customer_mode,
    followup_mode=excluded.followup_mode,followup_days=excluded.followup_days,supervisor_mode=excluded.supervisor_mode,supervisor_emails=excluded.supervisor_emails,
    timezone=excluded.timezone,summary_time=excluded.summary_time,summary_days=excluded.summary_days,include_photos=excluded.include_photos,daily_limit=excluded.daily_limit,
    paused=excluded.paused,updated_at=now() returning * into s;
  update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='settings_changed',version=version+1,lease_token=null,lease_until=null,updated_at=now()
   where owner_id=p_actor and state in ('pending','preparing','draft','ready','retry');
  p_action:='state';
 end if;
 if p_action='state' then
  body:=coalesce((case when s.owner_id is not null then to_jsonb(s)-'owner_id'-'last_scanned_at'-'created_at'-'updated_at'-'last_queue_code' end)||jsonb_build_object('summary_time',to_char(s.summary_time,'HH24:MI')),jsonb_build_object('version',0,'business_name','','customer_mode','off','followup_mode','off','followup_days',3,
   'supervisor_mode','off','supervisor_emails','[]'::jsonb,'timezone','America/New_York','summary_time','17:00','summary_days','[1,2,3,4,5]'::jsonb,'include_photos',false,'daily_limit',25,'paused',false));
  return jsonb_build_object('settings',body,'queue_notice',s.last_queue_code,'deliveries',coalesce((select jsonb_agg(to_jsonb(x)) from
   (select * from korlix_fieldproof_email_deliveries where owner_id=p_actor order by created_at desc limit 100) x),'[]'::jsonb),
   'suppressions',coalesce((select jsonb_agg(jsonb_build_object('recipient',recipient,'reason',reason)) from korlix_fieldproof_email_recipients where owner_id=p_actor and suppressed_at is not null),'[]'::jsonb));
 end if;

 if p_action in ('job_state','save_job','prepare_job') then
  select * into j from korlix_fieldproof_jobs where id=p_id and user_id=p_actor;
  if not found or j.state='deleting' then raise exception 'This FieldProof job was not found.' using errcode='P0002';end if;
  select * into js from korlix_fieldproof_email_job_settings where job_id=p_id and owner_id=p_actor;
  if p_action='save_job' then
   if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm this customer recipient.' using errcode='22023';end if;
   if coalesce(js.version,0) is distinct from (p_data->>'version')::integer then raise exception 'Customer email settings changed. Refresh before saving.' using errcode='40001';end if;
   body:=p_data->'job_settings';recipient_value:=lower(trim(coalesce(body->>'customer_email','')));
   if jsonb_typeof(body)<>'object' or jsonb_typeof(body->'enabled') is distinct from 'boolean' or length(recipient_value)>254
    or (recipient_value<>'' and recipient_value!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}$') then raise exception 'Use a valid customer email address.' using errcode='22023';end if;
   insert into korlix_fieldproof_email_job_settings(job_id,owner_id,customer_email,enabled) values(p_id,p_actor,recipient_value,(body->>'enabled')::boolean)
    on conflict(job_id) do update set version=korlix_fieldproof_email_job_settings.version+1,customer_email=excluded.customer_email,enabled=excluded.enabled,updated_at=now() returning * into js;
   update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='recipient_changed',version=version+1,lease_token=null,lease_until=null,updated_at=now()
    where owner_id=p_actor and job_id=p_id and state in ('pending','preparing','draft','ready','retry');p_action:='job_state';
  end if;
  if p_action='job_state' then
   return jsonb_build_object('job_settings',coalesce(case when js.job_id is not null then to_jsonb(js)-'owner_id' end,jsonb_build_object('version',0,'customer_email','','enabled',false)),
    'deliveries',coalesce((select jsonb_agg(to_jsonb(x)) from
     (select * from korlix_fieldproof_email_deliveries where owner_id=p_actor and job_id=p_id order by created_at desc limit 100) x),'[]'::jsonb));
  end if;
  if p_data->'confirmed' is distinct from 'true'::jsonb or s.owner_id is null or s.paused or s.customer_mode='off' or not coalesce(js.enabled,false) or j.state<>'completed' then raise exception 'Enable customer email for this completed job before preparing a draft.' using errcode='22023';end if;
  id_value:=(p_data->>'request_key')::uuid;if id_value is null then raise exception 'Use a valid preparation request.' using errcode='22023';end if;
  if exists(select 1 from korlix_fieldproof_email_recipients where owner_id=p_actor and recipient=js.customer_email and suppressed_at is not null) then raise exception 'This recipient has opted out.' using errcode='22023';end if;
  if korlix_fieldproof_email_room(p_actor,1)<1 then raise exception 'Email queue is full. Review or cancel waiting messages first.' using errcode='54000';end if;
  insert into korlix_fieldproof_email_deliveries(owner_id,job_id,job_version,settings_version,job_settings_version,kind,event_key,recipient,delivery_mode,expires_at)
   values(p_actor,p_id,j.version,s.version,js.version,'customer_report','manual:'||id_value,js.customer_email,'draft',now()+interval '7 days')
   on conflict(owner_id,event_key,recipient) do nothing;
  select * into d from korlix_fieldproof_email_deliveries where owner_id=p_actor and event_key='manual:'||id_value and recipient=js.customer_email;
  if not found then raise exception 'This request was already processed and its report has expired. Use a new request to prepare another draft.' using errcode='40001';end if;
  if d.job_id<>p_id or d.job_version<>j.version then raise exception 'Use a new request for this job revision.' using errcode='40001';end if;return to_jsonb(d);
 elsif p_action='enqueue_summary' then
  if s.owner_id is null or s.paused or s.supervisor_mode='off' then return '[]'::jsonb;end if;
  body:=korlix_fieldproof_email_summary_window(s,now());if body is null then return '[]'::jsonb;end if;
  local_now:=now() at time zone s.timezone;local_day:=local_now::date;
  due_time:=(body->>'scheduled_at')::timestamptz;
  period_begin:=((local_day-1)::timestamp) at time zone s.timezone;period_finish:=(local_day::timestamp) at time zone s.timezone;
  if not(extract(dow from local_now)::integer=any(s.summary_days)) or now()<due_time or due_time<s.updated_at then return '[]'::jsonb;end if;
  if p_data->>'event_key' is distinct from 'supervisor:'||local_day::text or (p_data->>'report_date')::date is distinct from local_day-1
   or (p_data->>'period_start')::timestamptz is distinct from period_begin or (p_data->>'period_end')::timestamptz is distinct from period_finish then
   raise exception 'Summary period must be the previous local calendar day.' using errcode='22023';end if;
  foreach recipient_value in array s.supervisor_emails loop
   if korlix_fieldproof_email_room(p_actor,1)<1 then
    update korlix_fieldproof_email_settings set last_queue_code='queue_full' where owner_id=p_actor;exit;
   end if;
   if exists(select 1 from korlix_fieldproof_email_recipients where owner_id=p_actor and recipient=recipient_value and suppressed_at is not null) then continue;end if;
   insert into korlix_fieldproof_email_deliveries(owner_id,settings_version,kind,event_key,recipient,delivery_mode,period_start,period_end,report_date,scheduled_at,expires_at)
    values(p_actor,s.version,'supervisor_summary',p_data->>'event_key',recipient_value,s.supervisor_mode,period_begin,period_finish,local_day-1,due_time,
     (body->>'expires_at')::timestamptz) on conflict(owner_id,event_key,recipient) do nothing;
  end loop;
  return coalesce((select jsonb_agg(to_jsonb(x)) from korlix_fieldproof_email_deliveries x where owner_id=p_actor and event_key=p_data->>'event_key'),'[]'::jsonb);
 end if;

 select * into d from korlix_fieldproof_email_deliveries where id=p_id and owner_id=p_actor for update;
 if not found then raise exception 'This email was not found.' using errcode='P0002';end if;
 if p_action='delivery' then return to_jsonb(d);end if;
 if p_action='recipient_token' then
  if d.state<>'preparing' or d.lease_until<=now() or p_data->>'recipient' is distinct from d.recipient
   or coalesce(p_data->>'token_hash','')!~'^[0-9a-f]{64}$' then raise exception 'Invalid unsubscribe token preparation.' using errcode='22023';end if;
  insert into korlix_fieldproof_email_recipients(owner_id,recipient) values(p_actor,d.recipient) on conflict do nothing;
  if exists(select 1 from korlix_fieldproof_email_recipients where owner_id=p_actor and recipient=d.recipient and suppressed_at is not null) then return jsonb_build_object('created',false,'suppressed',true);end if;
  if (select count(*) from korlix_fieldproof_email_recipient_tokens where delivery_id=d.id)>=8 then raise exception 'This preparation needs review.' using errcode='54000';end if;
  insert into korlix_fieldproof_email_recipient_tokens(token_hash,owner_id,recipient,delivery_id) values(p_data->>'token_hash',p_actor,d.recipient,d.id) on conflict do nothing;
  return jsonb_build_object('created',true,'suppressed',false);
 end if;
 if p_action in ('approve','cancel','retry') then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm this email action.' using errcode='22023';end if;
  if d.version is distinct from (p_data->>'version')::integer then raise exception 'This email changed. Refresh before continuing.' using errcode='40001';end if;
  if p_action='cancel' then
   if d.state not in ('pending','preparing','draft','ready','retry') then raise exception 'This email can no longer be cancelled.' using errcode='40001';end if;
   update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code='owner_cancelled',lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
  end if;
  code_value:=korlix_fieldproof_email_stale(d);
  if code_value is not null then raise exception 'This email is no longer current: %',code_value using errcode='40001';end if;
  if p_action='approve' then
   if d.state<>'draft' or d.payload is null then raise exception 'Wait for this draft to finish preparing.' using errcode='40001';end if;
   update korlix_fieldproof_email_deliveries set state='ready',scheduled_at=now(),version=version+1,updated_at=now() where id=d.id returning * into d;
  else
   if d.state not in ('unknown','retry') or d.payload is null or d.first_attempt_at is null or d.first_attempt_at<=now()-interval '23 hours' or d.attempt_count>=8 then raise exception 'This email cannot be safely retried.' using errcode='40001';end if;
   update korlix_fieldproof_email_deliveries set state='retry',scheduled_at=now(),code=null,version=version+1,updated_at=now() where id=d.id returning * into d;
  end if;return to_jsonb(d);
 end if;
 lease:=(p_data->>'lease_token')::uuid;
 if lease is null or d.lease_token is distinct from lease or d.lease_until<=now() then raise exception 'The email worker lease expired.' using errcode='40001';end if;
 if p_action in ('prepare','authorize') then
  code_value:=korlix_fieldproof_email_stale(d);
  if code_value is not null then
   update korlix_fieldproof_email_deliveries set state=case when first_attempt_at is null then 'cancelled' else 'unknown' end,code=code_value,lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
  end if;
 end if;
 if p_action='prepare' then
  body:=p_data->'payload';
  if d.state<>'preparing' or d.payload is not null or body is null or jsonb_typeof(body)<>'object' or body->>'to' is distinct from d.recipient
   or coalesce(body->>'subject','')='' or length(body->>'subject')>240 or body->>'subject' ~ '[\r\n]' or body->>'subject' is distinct from p_data->>'subject'
   or coalesce(body->>'replyTo','')!~'^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$' or length(body->>'replyTo')>254
   or jsonb_typeof(body->'text') is distinct from 'string' or jsonb_typeof(body->'html') is distinct from 'string'
   or octet_length(body::text)>200000 or body-array['to','subject','text','html','replyTo','attachment','senderFingerprint']<>'{}'::jsonb then raise exception 'Invalid immutable email payload.' using errcode='22023';end if;
  if d.kind='customer_report' then
   if p_data->>'attachment_path' is distinct from p_actor::text||'/'||d.id::text||'/report.pdf' or coalesce(p_data->>'attachment_sha256','')!~'^[0-9a-f]{64}$'
    or p_data->>'attachment_bytes' is null or (p_data->>'attachment_bytes')::integer not between 1 and 5242880 or body->'attachment'->>'path' is distinct from p_data->>'attachment_path'
    or body->'attachment'->>'sha256' is distinct from p_data->>'attachment_sha256' or (body->'attachment'->>'bytes')::integer is distinct from (p_data->>'attachment_bytes')::integer
    or coalesce(body->'attachment'->>'filename','')!~'^[A-Za-z0-9._ -]{1,120}\.pdf$'
    or (body->'attachment')-array['filename','path','sha256','bytes']<>'{}'::jsonb then raise exception 'A private verified report is required.' using errcode='22023';end if;
  elsif p_data->>'attachment_path' is not null or body->'attachment' is not null and body->'attachment'<>'null'::jsonb then raise exception 'This email does not use attachments.' using errcode='22023';end if;
  update korlix_fieldproof_email_deliveries set payload=body,subject=p_data->>'subject',attachment_path=p_data->>'attachment_path',attachment_sha256=p_data->>'attachment_sha256',
   attachment_bytes=(p_data->>'attachment_bytes')::integer,prepared_at=now(),state=case when delivery_mode='draft' then 'draft' else 'ready' end,
   lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
 elsif p_action='authorize' then
  if d.state<>'sending' or d.payload is null then raise exception 'This email is not ready to send.' using errcode='40001';end if;
  if d.first_attempt_at is not null and (d.first_attempt_at<=now()-interval '23 hours' or d.attempt_count>=8) then
   update korlix_fieldproof_email_deliveries set state='unknown',code='retry_window_closed',lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
  end if;
  if d.first_attempt_at is null then
   local_day:=(now() at time zone s.timezone)::date;
   insert into korlix_fieldproof_email_daily_usage(owner_id,usage_date) values(p_actor,local_day) on conflict do nothing;
   update korlix_fieldproof_email_daily_usage set reserved=reserved+1 where owner_id=p_actor and usage_date=local_day and reserved<least(s.daily_limit,100);
   if not found then
    update korlix_fieldproof_email_deliveries set state='retry',code='daily_limit',scheduled_at=((local_day+1)::timestamp) at time zone s.timezone,
     lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
   end if;
  end if;
  update korlix_fieldproof_email_deliveries set first_attempt_at=coalesce(first_attempt_at,now()),attempt_count=attempt_count+1,version=version+1,updated_at=now()
   where id=d.id returning * into d;return to_jsonb(d);
 elsif p_action='finish' then
  if d.state not in ('preparing','sending') or p_data->>'state' not in ('accepted','failed','retry','unknown','cancelled') then raise exception 'Invalid email outcome.' using errcode='22023';end if;
  if p_data->>'state'='cancelled' and d.first_attempt_at is not null then raise exception 'An attempted delivery requires a provider outcome.' using errcode='40001';end if;
  if p_data->>'state'='accepted' and (d.state<>'sending' or d.first_attempt_at is null or coalesce(p_data->>'provider_id','')='') then raise exception 'A provider receipt is required.' using errcode='22023';end if;
  if p_data->>'state' in ('retry','unknown') and d.state='sending' and d.first_attempt_at is null then raise exception 'This send was not authorized.' using errcode='40001';end if;
  update korlix_fieldproof_email_deliveries set state=p_data->>'state',code=case when code in ('bounced','complained','suppressed') then code else left(p_data->>'code',100) end,provider_id=coalesce(provider_id,left(p_data->>'provider_id',200)),
   accepted_at=case when p_data->>'state'='accepted' then now() else accepted_at end,
   scheduled_at=case when p_data->>'state'='retry' then greatest(now()+interval '30 seconds',least(coalesce((p_data->>'retry_at')::timestamptz,now()+interval '5 minutes'),now()+interval '1 day')) else scheduled_at end,
   lease_token=null,lease_until=null,version=version+1,updated_at=now() where id=d.id returning * into d;return to_jsonb(d);
 end if;
 raise exception 'Unknown FieldProof email operation.' using errcode='22023';
end $$;
revoke all on function public.korlix_fieldproof_email_stale(public.korlix_fieldproof_email_deliveries),public.korlix_fieldproof_email_job_trigger(),public.korlix_fieldproof_email_gc_trigger(),public.korlix_fieldproof_email_event_trigger(),public.korlix_fieldproof_email_room(uuid,integer),public.korlix_fieldproof_email_summary_window(public.korlix_fieldproof_email_settings,timestamptz),public.korlix_fieldproof_email_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_fieldproof_email_stale(public.korlix_fieldproof_email_deliveries),public.korlix_fieldproof_email_job_trigger(),public.korlix_fieldproof_email_gc_trigger(),public.korlix_fieldproof_email_event_trigger(),public.korlix_fieldproof_email_room(uuid,integer),public.korlix_fieldproof_email_summary_window(public.korlix_fieldproof_email_settings,timestamptz),public.korlix_fieldproof_email_v1(uuid,text,uuid,jsonb) to service_role;
