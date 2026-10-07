-- Run this view with the caller's privileges so the existing ownership policies
-- on user_profiles, generation_history, and device_sessions apply to its joins.
-- Preserve the view definition and grants. The backend service role retains
-- its intentional administrative access; authenticated callers see their own rows.
ALTER VIEW public.crm_user_dashboard SET (security_invoker = true);
