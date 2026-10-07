-- The previous report intake stored content only in process memory / local disk.
-- A report is acknowledged only after this server-only queue accepts it.
create table public.korlix_ai_output_reports (
  id text primary key check (id ~ '^korlix_report_[0-9a-f-]{36}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  report jsonb not null check (
    jsonb_typeof(report) = 'object'
    and octet_length(report::text) <= 49152
    and report ? 'id' and report ? 'userId'
    and jsonb_typeof(report->'id') = 'string'
    and jsonb_typeof(report->'userId') = 'string'
    and report->>'id' = id
    and report->>'userId' = user_id::text
  ),
  state text not null default 'open' check (state in ('open','reviewing','resolved')),
  notification_state text not null default 'queued' check (notification_state in ('queued','delivered','failed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution_note text check (char_length(resolution_note) <= 2000),
  check ((state = 'resolved') = (resolved_at is not null))
);
create index korlix_ai_output_reports_review_queue
  on public.korlix_ai_output_reports(state, created_at, id);
create index korlix_ai_output_reports_actor
  on public.korlix_ai_output_reports(user_id, created_at);
create index korlix_ai_output_reports_reviewer
  on public.korlix_ai_output_reports(resolved_by) where resolved_by is not null;
alter table public.korlix_ai_output_reports enable row level security;
revoke all on public.korlix_ai_output_reports from public, anon, authenticated;
grant select, insert, update, delete on public.korlix_ai_output_reports to service_role;
create policy korlix_ai_output_reports_server_only
  on public.korlix_ai_output_reports as restrictive for all
  to anon, authenticated using (false) with check (false);
comment on table public.korlix_ai_output_reports is
  'Private AI safety intake. Reviewed by authorized staff only; report content must not enter ordinary logs or aggregate readiness exports.';
