begin;
-- Hosted default privileges can grant service_role ALL on new public tables.
-- Revoke explicitly before granting the intended append/read-only privileges.
revoke all on public.korlix_funnel_attribution_links,public.korlix_funnel_attribution_events from service_role;
grant select,insert on public.korlix_funnel_attribution_links,public.korlix_funnel_attribution_events to service_role;
commit;
