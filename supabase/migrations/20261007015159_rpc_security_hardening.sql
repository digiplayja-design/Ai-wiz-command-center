-- Keep privileged issuance, entitlement and usage RPCs behind the verified backend.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.korlix_claim_monthly_video_generation(uuid,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.korlix_get_monthly_video_generation_usage(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.korlix_get_custom_access(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.korlix_create_custom_access_code_for_email(text,integer,text[],timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.korlix_redeem_custom_access_code(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user(),
 public.korlix_claim_monthly_video_generation(uuid,text,text),
 public.korlix_get_monthly_video_generation_usage(uuid,text),
 public.korlix_get_custom_access(uuid,text),
 public.korlix_create_custom_access_code_for_email(text,integer,text[],timestamptz),
 public.korlix_redeem_custom_access_code(uuid,text,text) TO service_role;

-- Helpers use only built-ins; remove dependence on the caller's search path.
ALTER FUNCTION public.set_updated_at() SET search_path = pg_catalog;
ALTER FUNCTION public.korlix_normalize_video_tier(text) SET search_path = pg_catalog;
ALTER FUNCTION public.korlix_video_month_key(timestamptz) SET search_path = pg_catalog;
ALTER FUNCTION public.korlix_custom_access_email_norm(text) SET search_path = pg_catalog;
ALTER FUNCTION public.korlix_custom_access_code_norm(text) SET search_path = pg_catalog;

-- Browser roles never require table-wide destructive or schema-building privileges.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
