-- Minimal external companion-session dependency for isolated Social fixtures.
-- The full session schema and authorization are tested by receipt_app_sessions.
create table public.korlix_receipt_app_sessions (
 session_id uuid primary key,
 user_id uuid not null references auth.users(id),
 client_app text not null,
 status text not null
);
grant select on public.korlix_receipt_app_sessions to service_role;
