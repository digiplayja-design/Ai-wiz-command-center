-- Private review metadata only. Original reports and report contents are not
-- modified by this migration; an authorized, guarded review transaction is a
-- separate operation. This is not a browser-accessible moderation endpoint.
create table public.korlix_legacy_report_reviews (
  report_id uuid primary key references public.reports(id) on delete cascade,
  reviewed_at timestamptz not null default now() check (isfinite(reviewed_at)),
  outcome text not null check (outcome in ('duplicate', 'no_action', 'needs_followup')),
  note text not null check (char_length(note) <= 1000 and char_length(btrim(note)) >= 1),
  duplicate_of uuid references public.reports(id) on delete set null,
  method text not null default 'codex_assisted_owner_requested'
    check (method = 'codex_assisted_owner_requested'),
  batch_id uuid not null,
  constraint legacy_report_review_no_self_link check (duplicate_of <> report_id),
  -- A deleted parent may null the link while retaining the historic outcome.
  constraint legacy_report_review_duplicate_link check (
    duplicate_of is null or outcome = 'duplicate'
  )
);
create index korlix_legacy_report_reviews_batch_idx
  on public.korlix_legacy_report_reviews(batch_id, reviewed_at);
create index korlix_legacy_report_reviews_duplicate_idx
  on public.korlix_legacy_report_reviews(duplicate_of) where duplicate_of is not null;
alter table public.korlix_legacy_report_reviews enable row level security;
revoke all on public.korlix_legacy_report_reviews from public, anon, authenticated, service_role;
grant select, insert, update on public.korlix_legacy_report_reviews to service_role;
create policy korlix_legacy_report_reviews_server_only
  on public.korlix_legacy_report_reviews as restrictive for all to anon, authenticated
  using (false) with check (false);
