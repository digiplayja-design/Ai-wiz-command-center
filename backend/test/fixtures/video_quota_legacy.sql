-- Exact production claim RPC inspected 2026-10-07; synthetic tests only.
CREATE OR REPLACE FUNCTION public.korlix_claim_monthly_video_generation(p_user_id uuid, p_tier text DEFAULT 'basic'::text, p_job_kind text DEFAULT 'image_to_video'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tier text := public.korlix_normalize_video_tier(p_tier);
  v_month text := public.korlix_video_month_key(now());
  v_limit integer;
  v_used integer;
  v_remaining integer;
begin
  if p_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'missing_user_id',
      'message', 'Please sign in to use Create a Video.'
    );
  end if;

  select monthly_limit
    into v_limit
  from public.korlix_video_generation_limits
  where tier_key = v_tier
    and enabled = true;

  if v_limit is null then
    v_limit := 1;
  end if;

  insert into public.korlix_monthly_video_usage
    (user_id, month_key, tier_key, used_count, last_job_kind, created_at, updated_at)
  values
    (p_user_id, v_month, v_tier, 0, p_job_kind, now(), now())
  on conflict (user_id, month_key) do nothing;

  select used_count
    into v_used
  from public.korlix_monthly_video_usage
  where user_id = p_user_id
    and month_key = v_month
  for update;

  if coalesce(v_used, 0) >= v_limit then
    return jsonb_build_object(
      'ok', false,
      'code', 'monthly_video_limit_reached',
      'tier', v_tier,
      'monthKey', v_month,
      'monthlyLimit', v_limit,
      'usedThisMonth', coalesce(v_used, 0),
      'remaining', 0,
      'message', 'You have reached your monthly Create a Video limit for your plan.'
    );
  end if;

  update public.korlix_monthly_video_usage
  set
    used_count = used_count + 1,
    tier_key = v_tier,
    last_job_kind = p_job_kind,
    updated_at = now()
  where user_id = p_user_id
    and month_key = v_month
  returning used_count into v_used;

  v_remaining := greatest(v_limit - v_used, 0);

  return jsonb_build_object(
    'ok', true,
    'code', 'video_usage_claimed',
    'tier', v_tier,
    'monthKey', v_month,
    'monthlyLimit', v_limit,
    'usedThisMonth', v_used,
    'remaining', v_remaining
  );
end;
$function$
