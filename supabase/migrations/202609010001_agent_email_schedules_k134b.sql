-- KORLIX_AGENT_EMAIL_SCHEDULES_K134B_BEGIN
-- Additive schema for Nova one-time and weekly scheduled Agent Email rules.
-- Existing event-triggered rules remain schedule_type = 'event'.

alter table public.korlix_agent_email_rules
  add column if not exists schedule_type text not null default 'event',
  add column if not exists schedule_timezone text not null default 'UTC',
  add column if not exists schedule_local_time text,
  add column if not exists schedule_days smallint[] not null default '{}'::smallint[],
  add column if not exists scheduled_for timestamptz,
  add column if not exists next_run_at timestamptz,
  add column if not exists last_run_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists deleted_at timestamptz;

update public.korlix_agent_email_rules as rule
   set schedule_timezone = settings.timezone
  from public.korlix_agent_email_settings as settings
 where rule.user_id = settings.user_id
   and rule.agent_id = settings.agent_id
   and rule.schedule_type = 'event'
   and rule.schedule_timezone = 'UTC'
   and btrim(coalesce(settings.timezone, '')) <> '';

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'korlix_agent_email_rules_schedule_type_k134b_ck'
       and conrelid = 'public.korlix_agent_email_rules'::regclass
  ) then
    alter table public.korlix_agent_email_rules
      add constraint korlix_agent_email_rules_schedule_type_k134b_ck
      check (schedule_type in ('event', 'once', 'weekly'));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'korlix_agent_email_rules_schedule_time_k134b_ck'
       and conrelid = 'public.korlix_agent_email_rules'::regclass
  ) then
    alter table public.korlix_agent_email_rules
      add constraint korlix_agent_email_rules_schedule_time_k134b_ck
      check (
        schedule_local_time is null
        or schedule_local_time ~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
      );
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'korlix_agent_email_rules_schedule_days_k134b_ck'
       and conrelid = 'public.korlix_agent_email_rules'::regclass
  ) then
    alter table public.korlix_agent_email_rules
      add constraint korlix_agent_email_rules_schedule_days_k134b_ck
      check (
        schedule_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
      );
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'korlix_agent_email_rules_schedule_shape_k134b_ck'
       and conrelid = 'public.korlix_agent_email_rules'::regclass
  ) then
    alter table public.korlix_agent_email_rules
      add constraint korlix_agent_email_rules_schedule_shape_k134b_ck
      check (
        (
          schedule_type = 'event'
          and scheduled_for is null
          and schedule_local_time is null
          and cardinality(schedule_days) = 0
          and next_run_at is null
        )
        or
        (
          schedule_type = 'once'
          and send_mode = 'autopilot'
          and scheduled_for is not null
          and schedule_local_time is null
          and cardinality(schedule_days) = 0
        )
        or
        (
          schedule_type = 'weekly'
          and send_mode = 'autopilot'
          and schedule_local_time is not null
          and cardinality(schedule_days) between 1 and 7
          and scheduled_for is null
        )
      );
  end if;
end;
$$;

create index if not exists korlix_agent_email_rules_due_k134b_idx
  on public.korlix_agent_email_rules
  (user_id, agent_id, next_run_at, id)
  where enabled = true
    and deleted_at is null
    and send_mode = 'autopilot'
    and schedule_type in ('once', 'weekly')
    and next_run_at is not null;

create index if not exists korlix_agent_email_rules_visible_k134b_idx
  on public.korlix_agent_email_rules
  (user_id, agent_id, updated_at desc)
  where deleted_at is null;

comment on column public.korlix_agent_email_rules.schedule_type is
  'K134B schedule mode: event, once, or weekly.';
comment on column public.korlix_agent_email_rules.schedule_timezone is
  'IANA timezone used to calculate weekly local schedule occurrences.';
comment on column public.korlix_agent_email_rules.schedule_local_time is
  'Weekly local send time in 24-hour HH:MM format.';
comment on column public.korlix_agent_email_rules.schedule_days is
  'Weekly weekday numbers where Sunday is 0 and Saturday is 6.';
comment on column public.korlix_agent_email_rules.scheduled_for is
  'Immutable requested occurrence for a one-time scheduled rule.';
comment on column public.korlix_agent_email_rules.next_run_at is
  'Server-calculated UTC occurrence currently due or next due.';
comment on column public.korlix_agent_email_rules.deleted_at is
  'Soft deletion timestamp retained for audit and message foreign keys.';

-- KORLIX_AGENT_EMAIL_SCHEDULES_K134B_END
