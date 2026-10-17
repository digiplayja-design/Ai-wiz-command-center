-- First-party onboarding events. Client reports are observations, never auth,
-- entitlement, billing, or advertising attribution evidence.
create table public.korlix_onboarding_events (
  id uuid primary key,
  recorded_at timestamptz not null default now(),
  installation_hash text not null check (installation_hash ~ '^[0-9a-f]{64}$'),
  platform text not null check (platform in ('android','ios','web','linux','macos','windows','unknown')),
  source text not null check (source in ('client','server')),
  event_name text not null,
  user_id uuid references auth.users(id) on delete cascade,
  new_setup boolean,
  error_code text check (error_code in ('required_fields','password_length','eligibility','network','response','server_error','rate_limited','auth_rejected')),
  check ((source = 'client' and user_id is null and event_name in (
    'app_open','registration_screen_viewed','registration_submit','registration_validation_error',
    'registration_transport_error','confirmation_screen_viewed','login_screen_viewed'))
    or (source = 'server' and event_name in (
      'signup_attempt','signup_accepted','signup_rejected','signin_attempt','signin_rejected','sign_in_succeeded'))),
  check (new_setup is null or event_name = 'app_open')
);
create index korlix_onboarding_time_idx on public.korlix_onboarding_events(recorded_at);
create index korlix_onboarding_install_idx on public.korlix_onboarding_events(installation_hash, recorded_at);
create index korlix_onboarding_user_idx on public.korlix_onboarding_events(user_id) where user_id is not null;
alter table public.korlix_onboarding_events enable row level security;
revoke all on public.korlix_onboarding_events from public, anon, authenticated;
grant select, insert, delete on public.korlix_onboarding_events to service_role;

create function public.korlix_prune_onboarding_events() returns void
language sql security invoker set search_path = '' as $$
  delete from public.korlix_onboarding_events where id in (
    select id from public.korlix_onboarding_events
    where recorded_at < now() - interval '90 days' order by recorded_at limit 10000
  );
$$;
revoke all on function public.korlix_prune_onboarding_events() from public, anon, authenticated;
grant execute on function public.korlix_prune_onboarding_events() to service_role;

create function public.korlix_onboarding_summary(p_start timestamptz, p_end timestamptz, p_platform text)
-- The service role cannot read auth.users directly in production. Only this
-- fixed aggregate query runs with its owner's rights; no raw account data or
-- dynamic SQL is exposed, and only service_role may execute the function.
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if p_start is null or p_end is null or p_end <= p_start or p_end - p_start > interval '31 days'
    or p_platform is null or p_platform not in ('android','ios','web','linux','macos','windows') then
    raise exception 'Invalid reporting window or platform';
  end if;
  with first_setups as (
    select installation_hash, min(recorded_at) as started_at
    from public.korlix_onboarding_events
    where platform = p_platform and event_name = 'app_open' and new_setup is true
    group by installation_hash
  ), cohort as (
    select * from first_setups where started_at >= p_start and started_at < p_end
  ), window_events as (
    select * from public.korlix_onboarding_events
    where platform = p_platform and recorded_at >= p_start and recorded_at < p_end
  ), stages as (
    select c.installation_hash,
      bool_or(e.event_name = 'registration_screen_viewed') as registration_screen,
      bool_or(e.event_name = 'registration_submit') as registration_submit,
      bool_or(e.event_name = 'confirmation_screen_viewed') as confirmation_screen,
      bool_or(e.event_name = 'sign_in_succeeded') as signed_in,
      bool_or(e.event_name = 'sign_in_succeeded' and exists (
        select 1 from public.generation_history g where g.user_id = e.user_id
          and g.created_at >= c.started_at and g.created_at < p_end
      )) as generated
    from cohort c left join window_events e using (installation_hash)
    group by c.installation_hash
  ), new_accounts as (
    select u.id, u.email_confirmed_at, u.last_sign_in_at
    from auth.users u where u.created_at >= p_start and u.created_at < p_end
      and u.deleted_at is null and coalesce(u.is_anonymous, false) is false
  )
  select jsonb_build_object(
    'coverage', 'All acquisition sources. New setup means fresh local app storage, not a verified Google Ads install. Events use server receipt time. Stage counts are distinct setups; returning customers may skip registration.',
    'first_client_event_at', (select min(recorded_at) from public.korlix_onboarding_events where source = 'client' and platform = p_platform),
    'last_client_event_at', (select max(recorded_at) from public.korlix_onboarding_events where source = 'client' and platform = p_platform),
    'opened_setups', (select count(distinct installation_hash) from window_events where event_name = 'app_open'),
    'new_setup_cohort', jsonb_build_object(
      'opened', (select count(*) from stages),
      'registration_screen', (select count(*) from stages where registration_screen),
      'registration_submitted', (select count(*) from stages where registration_submit),
      'confirmation_screen', (select count(*) from stages where confirmation_screen),
      'signed_in', (select count(*) from stages where signed_in),
      'completed_ai_generation', (select count(*) from stages where generated)
    ),
    'authentication_events', (select coalesce(jsonb_object_agg(event_name, n), '{}'::jsonb) from (
      select event_name, count(*) n from window_events where source = 'server' group by event_name
    ) q),
    'registration_errors', (select coalesce(jsonb_object_agg(error_code, n), '{}'::jsonb) from (
      select error_code, count(*) n from window_events
      where error_code is not null and event_name in ('signup_rejected','registration_validation_error','registration_transport_error')
      group by error_code
    ) q),
    'new_accounts_all_platforms', jsonb_build_object(
      'created', (select count(*) from new_accounts),
      'email_confirmed', (select count(*) from new_accounts where email_confirmed_at is not null and email_confirmed_at < p_end),
      'signed_in', (select count(*) from new_accounts where last_sign_in_at is not null and last_sign_in_at < p_end),
      'completed_ai_generation', (select count(*) from new_accounts u where exists (
        select 1 from public.generation_history g where g.user_id = u.id and g.created_at >= p_start and g.created_at < p_end
      ))
    )
  ) into result;
  return result;
end;
$$;
revoke all on function public.korlix_onboarding_summary(timestamptz,timestamptz,text) from public, anon, authenticated;
grant execute on function public.korlix_onboarding_summary(timestamptz,timestamptz,text) to service_role;
