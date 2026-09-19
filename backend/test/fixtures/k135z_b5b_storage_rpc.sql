-- LOCAL TEST BOOTSTRAP ONLY. Never apply as a Supabase migration.
\set ON_ERROR_STOP on
begin;
do $$begin
  if current_database()<>'k135z_gate6a_local' or inet_server_addr() is not null or
    coalesce(current_setting('k135z.gate6a_instance',true),'') !~ '^[a-f0-9]{48}$' then
    raise exception 'GATE6A_ISOLATED_LOCAL_INSTANCE_REQUIRED';
  end if;
end$$;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role gate6a_untrusted nologin;
create schema auth;
create table auth.users(id uuid primary key);
insert into auth.users(id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');
commit;
