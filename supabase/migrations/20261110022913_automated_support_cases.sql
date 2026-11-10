-- Server-only support cases. Installing this migration does not enable sending.
begin;

create table public.korlix_support_profiles (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  owner_uid uuid not null references auth.users(id) on delete cascade,
  fingerprint text not null check (length(fingerprint) = 64),
  mode text not null default 'paused' check (mode in ('paused','draft','automatic')),
  automatic_since timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_uid)
);
create index korlix_support_profiles_owner on public.korlix_support_profiles(owner_uid);

create table public.korlix_support_intake (
  report_id text primary key references public.korlix_ai_output_reports(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','processed')),
  claim_token uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index korlix_support_intake_pending on public.korlix_support_intake(next_attempt_at,created_at) where status <> 'processed';

create table public.korlix_support_cases (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null,
  owner_uid uuid not null,
  report_id text not null unique references public.korlix_ai_output_reports(id) on delete cascade,
  reporter_uid uuid not null references auth.users(id) on delete cascade,
  reporter_email text not null check (length(reporter_email) <= 254),
  reporter_verified boolean not null default false,
  app_key text not null,
  subject text not null check (length(subject) <= 200),
  details text not null default '' check (length(details) <= 20000),
  app_area text not null default '', app_version text not null default '', platform text not null default '',
  state text not null default 'new' check (state in ('new','waiting_for_customer','needs_review','resolved')),
  automation_paused boolean not null default false,
  resolution_note text not null default '' check (length(resolution_note) <= 2000),
  conversation_version integer not null default 0,
  report_created_at timestamptz not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key (profile_id,owner_uid) references public.korlix_support_profiles(id,owner_uid) on delete cascade,
  unique(id,profile_id,owner_uid)
);
create index korlix_support_cases_owner_profile on public.korlix_support_cases(owner_uid,profile_id,updated_at desc,id);
create index korlix_support_cases_owner_state on public.korlix_support_cases(owner_uid,state,updated_at desc);
create index korlix_support_cases_reporter on public.korlix_support_cases(reporter_uid);

create table public.korlix_support_messages (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null, profile_id text not null, owner_uid uuid not null,
  direction text not null check (direction in ('inbound','outbound')),
  kind text not null check (kind in ('acknowledgment','owner_reply','customer_reply')),
  action_key text not null check (length(action_key) <= 300),
  subject text not null check (length(subject) <= 200),
  text text not null check (length(text) <= 20000),
  status text not null default 'pending' check (status in ('pending','sending','sent','failed','uncertain','received')),
  profile_fingerprint text not null,
  conversation_version integer not null default 0,
  claim_token uuid, claimed_at timestamptz,
  provider_message_id text, internet_message_id text,
  in_reply_to text,
  error_code text,
  attachments jsonb not null default '[]'::jsonb check (jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=10),
  authentication text not null default 'unknown',
  created_at timestamptz not null default now(), sent_at timestamptz,
  foreign key (case_id,profile_id,owner_uid) references public.korlix_support_cases(id,profile_id,owner_uid) on delete cascade,
  unique(case_id,action_key)
);
create index korlix_support_messages_case on public.korlix_support_messages(owner_uid,case_id,created_at,id);
create index korlix_support_messages_pending on public.korlix_support_messages(owner_uid,profile_id,created_at) where status='pending';
create index korlix_support_messages_quota on public.korlix_support_messages(owner_uid,profile_id,claimed_at) where claimed_at is not null;
create unique index korlix_support_messages_inbound_once on public.korlix_support_messages(profile_id,provider_message_id) where direction='inbound';
create index korlix_support_messages_thread on public.korlix_support_messages(owner_uid,profile_id,internet_message_id) where direction='outbound' and status='sent';

alter table public.korlix_support_profiles enable row level security;
alter table public.korlix_support_intake enable row level security;
alter table public.korlix_support_cases enable row level security;
alter table public.korlix_support_messages enable row level security;
revoke all on public.korlix_support_profiles,public.korlix_support_intake,public.korlix_support_cases,public.korlix_support_messages from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_support_profiles,public.korlix_support_intake,public.korlix_support_cases,public.korlix_support_messages to service_role;

create function public.korlix_support_enqueue_report() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
  insert into public.korlix_support_intake(report_id) values(new.id) on conflict do nothing;
  return new;
end; $$;
create trigger korlix_support_report_intake after insert on public.korlix_ai_output_reports
for each row execute function public.korlix_support_enqueue_report();
-- No backfill: historical reports must never silently start emailing customers.

create function public.korlix_support_sync_profile(p_id text,p_owner uuid,p_fingerprint text,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare r public.korlix_support_profiles;
begin
  insert into public.korlix_support_profiles(id,owner_uid,fingerprint,created_at,updated_at)
  values(p_id,p_owner,p_fingerprint,p_now,p_now) on conflict do nothing;
  select * into r from public.korlix_support_profiles where id=p_id for update;
  if r.owner_uid is distinct from p_owner then raise exception 'SUPPORT_OWNER_CHANGED'; end if;
  if r.fingerprint<>p_fingerprint then
    update public.korlix_support_profiles set fingerprint=p_fingerprint,mode='paused',automatic_since=null,updated_at=p_now where id=p_id returning * into r;
    update public.korlix_support_messages set status='failed',error_code='support_sender_configuration_changed' where profile_id=p_id and status='pending';
  end if;
  return to_jsonb(r);
end; $$;

create function public.korlix_support_set_mode(p_id text,p_owner uuid,p_fingerprint text,p_mode text,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare r public.korlix_support_profiles;
begin
  select * into r from public.korlix_support_profiles where id=p_id and owner_uid=p_owner for update;
  if not found then raise exception 'SUPPORT_PROFILE_NOT_FOUND'; end if;
  if r.fingerprint<>p_fingerprint then raise exception 'SUPPORT_FINGERPRINT_CHANGED'; end if;
  update public.korlix_support_profiles set mode=p_mode,
    automatic_since=case when p_mode='automatic' then case when r.mode='automatic' then r.automatic_since else p_now end else null end,
    updated_at=p_now where id=p_id returning * into r;
  if p_mode='automatic' then
    update public.korlix_support_messages m set status='failed',error_code='report_predates_automatic_mode'
      from public.korlix_support_cases c where m.case_id=c.id and m.profile_id=p_id and m.status='pending' and m.kind='acknowledgment' and c.report_created_at<r.automatic_since;
  end if;
  return to_jsonb(r);
end; $$;

create function public.korlix_support_claim_intake(p_token uuid,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare r public.korlix_support_intake; payload jsonb;
begin
  select * into r from public.korlix_support_intake
    where (status='pending' or (status='processing' and lease_until<p_now)) and next_attempt_at<=p_now
    order by created_at,report_id for update skip locked limit 1;
  if not found then return null; end if;
  update public.korlix_support_intake set status='processing',claim_token=p_token,lease_until=p_now+interval '2 minutes',attempts=attempts+1 where report_id=r.report_id;
  select report into payload from public.korlix_ai_output_reports where id=r.report_id;
  return jsonb_build_object('report_id',r.report_id,'report',payload);
end; $$;

create function public.korlix_support_release_intake(p_report text,p_token uuid,p_now timestamptz) returns boolean
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
  update public.korlix_support_intake set status='pending',claim_token=null,lease_until=null,next_attempt_at=p_now+interval '1 minute'
    where report_id=p_report and claim_token=p_token and status='processing';
  return found;
end; $$;

create function public.korlix_support_complete_intake(p_report text,p_token uuid,p_profile text,p_owner uuid,p_case jsonb,p_message jsonb,p_fingerprint text,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare q public.korlix_support_intake; c public.korlix_support_cases; p public.korlix_support_profiles; source jsonb; source_user uuid;
begin
  select * into p from public.korlix_support_profiles where id=p_profile and owner_uid=p_owner for update;
  if not found or p.fingerprint<>p_fingerprint then raise exception 'SUPPORT_PROFILE_CHANGED'; end if;
  select * into q from public.korlix_support_intake where report_id=p_report for update;
  if not found or q.status<>'processing' or q.claim_token is distinct from p_token then return null; end if;
  select report,user_id into source,source_user from public.korlix_ai_output_reports where id=p_report;
  if p_case->>'reportId'<>p_report or (p_case->>'reporterUid')::uuid<>source_user or lower(p_case->>'reporterEmail')<>lower(source->>'userEmail') then raise exception 'SUPPORT_RECIPIENT_MISMATCH'; end if;
  insert into public.korlix_support_cases(id,profile_id,owner_uid,report_id,reporter_uid,reporter_email,reporter_verified,app_key,subject,details,app_area,app_version,platform,state,report_created_at,created_at,updated_at)
  values((p_case->>'id')::uuid,p_profile,p_owner,p_report,source_user,lower(source->>'userEmail'),coalesce((p_case->>'reporterVerified')::boolean,false),'korlix_ai',p_case->>'subject',coalesce(p_case->>'details',''),coalesce(p_case->>'appArea',''),coalesce(p_case->>'appVersion',''),coalesce(p_case->>'platform',''),p_case->>'state',(p_case->>'reportCreatedAt')::timestamptz,p_now,p_now)
  on conflict(report_id) do nothing;
  select * into c from public.korlix_support_cases where report_id=p_report;
  if c.owner_uid<>p_owner or c.profile_id<>p_profile then raise exception 'SUPPORT_OWNER_CHANGED'; end if;
  insert into public.korlix_support_messages(id,case_id,profile_id,owner_uid,direction,kind,action_key,subject,text,status,profile_fingerprint,created_at)
  values((p_message->>'id')::uuid,c.id,p_profile,p_owner,'outbound','acknowledgment','acknowledgment',p_message->>'subject',p_message->>'text','pending',p_fingerprint,p_now)
  on conflict(case_id,action_key) do nothing;
  update public.korlix_support_intake set status='processed',claim_token=null,lease_until=null,processed_at=p_now where report_id=p_report;
  return to_jsonb(c);
end; $$;

create function public.korlix_support_update_case(p_owner uuid,p_case uuid,p_patch jsonb,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare c public.korlix_support_cases;
begin
  select * into c from public.korlix_support_cases where id=p_case and owner_uid=p_owner for update;
  if not found then raise exception 'SUPPORT_CASE_NOT_FOUND'; end if;
  if p_patch->>'state'='resolved' and length(trim(coalesce(p_patch->>'resolutionNote','')))=0 then raise exception 'SUPPORT_CASE_RESOLUTION_REQUIRED'; end if;
  update public.korlix_support_cases set state=coalesce(p_patch->>'state',state),
    automation_paused=case when p_patch ? 'automationPaused' then (p_patch->>'automationPaused')::boolean else automation_paused end,
    resolution_note=coalesce(p_patch->>'resolutionNote',resolution_note),updated_at=p_now
    where id=p_case returning * into c;
  if c.state='resolved' then
    update public.korlix_support_messages set status='failed',error_code='case_resolved_before_send' where case_id=p_case and status='pending';
  end if;
  return to_jsonb(c);
end; $$;

create function public.korlix_support_queue_reply(p_owner uuid,p_case uuid,p_text text,p_fingerprint text,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare c public.korlix_support_cases; m public.korlix_support_messages; p public.korlix_support_profiles; action text; reply_id text;
begin
  select * into c from public.korlix_support_cases where id=p_case and owner_uid=p_owner;
  if not found then raise exception 'SUPPORT_CASE_NOT_FOUND'; end if;
  select * into p from public.korlix_support_profiles where id=c.profile_id and owner_uid=p_owner for update;
  select * into c from public.korlix_support_cases where id=p_case and owner_uid=p_owner for update;
  if p.fingerprint<>p_fingerprint then raise exception 'SUPPORT_FINGERPRINT_CHANGED'; end if;
  if c.state='resolved' or not c.reporter_verified then raise exception 'SUPPORT_CASE_CANNOT_REPLY'; end if;
  if length(trim(p_text))=0 or length(p_text)>12000 then raise exception 'SUPPORT_CASE_REPLY_INVALID'; end if;
  action='owner_reply:'||c.conversation_version::text||':'||md5(p_text);
  select internet_message_id into reply_id from public.korlix_support_messages
    where case_id=p_case and owner_uid=p_owner and internet_message_id is not null and status in ('received','sent')
    order by case when direction='inbound' then 0 else 1 end,created_at desc,id desc limit 1;
  insert into public.korlix_support_messages(case_id,profile_id,owner_uid,direction,kind,action_key,subject,text,profile_fingerprint,conversation_version,in_reply_to,created_at)
  values(c.id,c.profile_id,c.owner_uid,'outbound','owner_reply',action,'Re: '||left(c.subject,196),p_text,p_fingerprint,c.conversation_version,reply_id,p_now)
  on conflict(case_id,action_key) do nothing;
  select * into m from public.korlix_support_messages where case_id=p_case and action_key=action;
  update public.korlix_support_messages set status='failed',error_code='owner_reply_superseded_acknowledgment' where case_id=p_case and kind='acknowledgment' and status='pending';
  return to_jsonb(m);
end; $$;

create function public.korlix_support_claim_message(p_owner uuid,p_profile text,p_case uuid,p_fingerprint text,p_daily_cap integer,p_token uuid,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare p public.korlix_support_profiles; c public.korlix_support_cases; m public.korlix_support_messages; used integer;
begin
  select * into p from public.korlix_support_profiles where id=p_profile and owner_uid=p_owner for update;
  if not found or p.mode='paused' or p.fingerprint<>p_fingerprint then return null; end if;
  select * into c from public.korlix_support_cases where id=p_case and owner_uid=p_owner and profile_id=p_profile for update;
  if not found or c.state='resolved' or not c.reporter_verified then return null; end if;
  -- Serialize on profile before counting so concurrent workers cannot exceed quota.
  select count(*) into used from public.korlix_support_messages where profile_id=p_profile and owner_uid=p_owner and claimed_at>=p_now-interval '24 hours';
  if used>=greatest(1,least(100,p_daily_cap)) then return null; end if;
  if exists(select 1 from public.korlix_support_messages where case_id=p_case and status='sending') then return null; end if;
  select * into m from public.korlix_support_messages where case_id=p_case and owner_uid=p_owner and status='pending'
    and direction='outbound' and profile_fingerprint=p_fingerprint and conversation_version=c.conversation_version
    and (kind='owner_reply' or (kind='acknowledgment' and p.mode='automatic' and not c.automation_paused and c.report_created_at>=p.automatic_since))
    order by case when kind='owner_reply' then 0 else 1 end,created_at,id for update skip locked limit 1;
  if not found then return null; end if;
  update public.korlix_support_messages set status='sending',claim_token=p_token,claimed_at=p_now where id=m.id returning * into m;
  return jsonb_build_object('case',to_jsonb(c),'message',to_jsonb(m));
end; $$;

create function public.korlix_support_pending_cases(p_owner uuid,p_profile text,p_limit integer) returns jsonb
language sql security invoker set search_path=pg_catalog,public as $$
  select coalesce(jsonb_agg(candidate.case_id),'[]'::jsonb) from (
    select m.case_id,min(m.created_at) as first_message
    from public.korlix_support_messages m
    join public.korlix_support_cases c on c.id=m.case_id and c.owner_uid=m.owner_uid
    join public.korlix_support_profiles p on p.id=m.profile_id and p.owner_uid=m.owner_uid
    where m.owner_uid=p_owner and m.profile_id=p_profile and m.status='pending' and m.direction='outbound'
      and m.profile_fingerprint=p.fingerprint and m.conversation_version=c.conversation_version and p.mode<>'paused'
      and c.state<>'resolved' and c.reporter_verified
      and (m.kind='owner_reply' or (m.kind='acknowledgment' and p.mode='automatic' and not c.automation_paused and c.report_created_at>=p.automatic_since))
    group by m.case_id order by first_message,m.case_id limit greatest(1,least(50,p_limit))
  ) candidate;
$$;

create function public.korlix_support_finish_message(p_owner uuid,p_message uuid,p_token uuid,p_status text,p_error text,p_provider_id text,p_internet_id text,p_now timestamptz) returns boolean
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare m public.korlix_support_messages;
begin
  if p_status not in ('sent','failed','uncertain') then raise exception 'SUPPORT_CASE_DELIVERY_INVALID'; end if;
  if p_status='sent' and coalesce(p_provider_id,'')='' then raise exception 'SUPPORT_CASE_DELIVERY_UNCONFIRMED'; end if;
  update public.korlix_support_messages set status=p_status,error_code=p_error,provider_message_id=p_provider_id,internet_message_id=p_internet_id,
    sent_at=case when p_status='sent' then p_now else null end,claim_token=null
    where id=p_message and owner_uid=p_owner and status='sending' and claim_token=p_token returning * into m;
  if not found then return false; end if;
  update public.korlix_support_cases set state=case when p_status<>'sent' then 'needs_review' when conversation_version=m.conversation_version and (state='new' or m.kind='owner_reply') then 'waiting_for_customer' else state end,updated_at=p_now
    where id=m.case_id and owner_uid=p_owner and state<>'resolved';
  return true;
end; $$;

create function public.korlix_support_settle_stale(p_now timestamptz) returns integer
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare count_updated integer;
begin
  with settled as (
    update public.korlix_support_messages set status='uncertain',claim_token=null,error_code='support_interrupted_handoff'
      where status='sending' and claimed_at<p_now-interval '2 minutes' returning case_id
  ) update public.korlix_support_cases set state='needs_review',updated_at=p_now where id in (select case_id from settled) and state<>'resolved';
  get diagnostics count_updated=row_count;
  return count_updated;
end; $$;

create function public.korlix_support_receive_reply(p_owner uuid,p_profile text,p_case uuid,p_from text,p_text text,p_provider_id text,p_internet_id text,p_in_reply_to text,p_attachments jsonb,p_authentication text,p_now timestamptz) returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare c public.korlix_support_cases; existing public.korlix_support_messages;
begin
  select * into c from public.korlix_support_cases where id=p_case and owner_uid=p_owner and profile_id=p_profile for update;
  if not found or not c.reporter_verified or c.reporter_email<>lower(p_from) then raise exception 'SUPPORT_RECIPIENT_MISMATCH'; end if;
  select * into existing from public.korlix_support_messages where profile_id=p_profile and provider_message_id=p_provider_id and direction='inbound';
  if found then
    if existing.case_id<>p_case then raise exception 'SUPPORT_CASE_REPLY_MISMATCH'; end if;
    return jsonb_build_object('duplicate',true);
  end if;
  insert into public.korlix_support_messages(case_id,profile_id,owner_uid,direction,kind,action_key,subject,text,status,profile_fingerprint,provider_message_id,internet_message_id,in_reply_to,attachments,authentication,conversation_version,created_at)
  values(c.id,p_profile,p_owner,'inbound','customer_reply','received:'||p_provider_id,c.subject,p_text,'received','',p_provider_id,p_internet_id,p_in_reply_to,p_attachments,p_authentication,c.conversation_version+1,p_now);
  update public.korlix_support_messages set status='failed',error_code='customer_replied_before_send' where case_id=p_case and status='pending';
  update public.korlix_support_cases set state='needs_review',conversation_version=conversation_version+1,resolution_note='',updated_at=p_now where id=p_case;
  return jsonb_build_object('duplicate',false);
end; $$;

-- Every function above is service-only and uses caller permissions, not definer privileges.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'korlix_support_%' loop
    execute format('revoke all on function %s from public,anon,authenticated', f.signature);
    execute format('grant execute on function %s to service_role', f.signature);
  end loop;
end; $$;
commit;
