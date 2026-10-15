-- Per-account developer entitlement. Empty by default; grants are separate
-- administrative data, never inferred from user-editable metadata or email.
create table public.korlix_developer_access (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  enabled boolean not null default false,
  granted_at timestamptz not null default now(),
  reason text not null default ''
);
alter table public.korlix_developer_access enable row level security;
revoke all on public.korlix_developer_access from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_developer_access to service_role;

create function public.korlix_has_unlimited_access(p_user_id uuid)
returns boolean language sql stable security invoker set search_path=pg_catalog,public as $$
  select exists(select 1 from public.korlix_developer_access d
    join public.user_profiles p on p.id=d.user_id
    where d.user_id=p_user_id and d.enabled and p.is_disabled is not true);
$$;
revoke all on function public.korlix_has_unlimited_access(uuid) from public,anon,authenticated;
grant execute on function public.korlix_has_unlimited_access(uuid) to service_role;

-- Patch only the reviewed quota predicates. Abort on schema drift instead of
-- replacing whole feature implementations or weakening their ownership rules.
-- CREATE OR REPLACE retains each existing function's execution grants.
do $migration$
declare change jsonb; definition text; occurrences integer;
begin
  for change in select value from jsonb_array_elements($patches$
[
  {
    "signature": "public.korlix_web_billing_profile(uuid,boolean)",
    "before": "return to_jsonb(pr);",
    "after": "return to_jsonb(pr)||jsonb_build_object('developer_unlimited',public.korlix_has_unlimited_access(p_user_id));",
    "count": 2
  },
  {
    "signature": "public.korlix_agent_workflow_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)<(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)<(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer));",
    "count": 1
  },
  {
    "signature": "public.korlix_app_studio_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer\n    and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer\n    and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer));",
    "count": 1
  },
  {
    "signature": "public.korlix_cyber_defender_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer));",
    "count": 1
  },
  {
    "signature": "public.korlix_inventory_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)<(p_data->>'credit_limit')::int and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::int;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)<(p_data->>'credit_limit')::int and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::int));",
    "count": 1
  },
  {
    "signature": "public.korlix_seo_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)+3<=(p_data->>'credit_limit')::integer\n   and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)+1<=(p_data->>'request_limit')::integer;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)+3<=(p_data->>'credit_limit')::integer\n   and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)+1<=(p_data->>'request_limit')::integer));",
    "count": 1
  },
  {
    "signature": "public.korlix_study_studio_v1(uuid,text,uuid,jsonb)",
    "before": "where id=uid and user_id=p_actor and coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer;",
    "after": "where id=uid and user_id=p_actor and (public.korlix_has_unlimited_access(p_actor) or (coalesce(credits_used,0)+1<=(p_data->>'credit_limit')::integer and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::integer));",
    "count": 1
  },
  {
    "signature": "public.korlix_video_credit_summary(uuid)",
    "before": "credit_balance bigint; override_text text;",
    "after": "credit_balance bigint; override_text text; unlimited boolean := public.korlix_has_unlimited_access(p_user_id);",
    "count": 1
  },
  {
    "signature": "public.korlix_video_credit_summary(uuid)",
    "before": "  select count(*) into used_count",
    "after": "  if unlimited then monthly_limit:=2147483647; end if;\n  select count(*) into used_count",
    "count": 1
  },
  {
    "signature": "public.korlix_video_credit_summary(uuid)",
    "before": "'tier',plan,'monthlyLimit'",
    "after": "'unlimited',unlimited,'developerAccess',unlimited,'tier',plan,'monthlyLimit'",
    "count": 1
  },
  {
    "signature": "public.korlix_video_credit_summary(uuid)",
    "before": "'includedRemaining',greatest(monthly_limit-used_count,0)",
    "after": "'includedRemaining',case when unlimited then 2147483647 else greatest(monthly_limit-used_count,0) end",
    "count": 1
  },
  {
    "signature": "public.korlix_video_credit_summary(uuid)",
    "before": "'canGenerateVideo',used_count<monthly_limit or credit_balance>0",
    "after": "'canGenerateVideo',unlimited or used_count<monthly_limit or credit_balance>0",
    "count": 1
  },
  {
    "signature": "public.korlix_video_reserve(uuid,text,text)",
    "before": "spend := (summary->>'includedRemaining')::bigint<=0;",
    "after": "spend := summary->'unlimited' is distinct from 'true'::jsonb and (summary->>'includedRemaining')::bigint<=0;",
    "count": 1
  },
  {
    "signature": "public.korlix_claim_monthly_video_generation(uuid,text,text)",
    "before": "  v_used integer;",
    "after": "  v_used integer;\n  v_unlimited boolean := public.korlix_has_unlimited_access(p_user_id);",
    "count": 1
  },
  {
    "signature": "public.korlix_claim_monthly_video_generation(uuid,text,text)",
    "before": "    v_limit := 1;\n  end if;",
    "after": "    v_limit := 1;\n  end if;\n  if v_unlimited then v_limit:=2147483647; end if;",
    "count": 1
  },
  {
    "signature": "public.korlix_claim_monthly_video_generation(uuid,text,text)",
    "before": "    'ok', true,",
    "after": "    'ok', true,\n    'unlimited', v_unlimited,",
    "count": 1
  },
  {
    "signature": "public.korlix_get_monthly_video_generation_usage(uuid,text)",
    "before": "  v_used integer;",
    "after": "  v_used integer;\n  v_unlimited boolean := public.korlix_has_unlimited_access(p_user_id);",
    "count": 1
  },
  {
    "signature": "public.korlix_get_monthly_video_generation_usage(uuid,text)",
    "before": "    v_limit := 1;\n  end if;",
    "after": "    v_limit := 1;\n  end if;\n  if v_unlimited then v_limit:=2147483647; end if;",
    "count": 1
  },
  {
    "signature": "public.korlix_get_monthly_video_generation_usage(uuid,text)",
    "before": "    'ok', true,",
    "after": "    'ok', true,\n    'unlimited', v_unlimited,",
    "count": 1
  },
  {
    "signature": "public.korlix_claim_monthly_video_generation(uuid,text,text)",
    "before": "if coalesce(v_used, 0) >= v_limit then",
    "after": "if not v_unlimited and coalesce(v_used, 0) >= v_limit then",
    "count": 1
  },
  {
    "signature": "public.korlix_claim_monthly_video_generation(uuid,text,text)",
    "before": "v_remaining := greatest(v_limit - v_used, 0);",
    "after": "v_remaining := case when v_unlimited then 2147483647 else greatest(v_limit - v_used, 0) end;",
    "count": 1
  },
  {
    "signature": "public.korlix_get_monthly_video_generation_usage(uuid,text)",
    "before": "'remaining', greatest(v_limit - coalesce(v_used, 0), 0)",
    "after": "'remaining', case when v_unlimited then 2147483647 else greatest(v_limit - coalesce(v_used, 0), 0) end",
    "count": 1
  },
  {
    "signature": "public.korlix_music_v2(uuid,text,uuid,jsonb)",
    "before": "if lim is null or lim<1 or lim>10000 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (lim is null or lim<1 or lim>10000) then",
    "count": 1
  },
  {
    "signature": "public.korlix_music_v2(uuid,text,uuid,jsonb)",
    "before": "if (select count(*) from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held)>=lim then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and ((select count(*) from public.korlix_music_jobs where owner_id=p_actor and cycle=cy and quota_held)>=lim) then",
    "count": 1
  },
  {
    "signature": "public.korlix_music_v2(uuid,text,uuid,jsonb)",
    "before": "if (select count(*) from public.korlix_music_jobs where owner_id=p_actor and not hidden)>=2000 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and ((select count(*) from public.korlix_music_jobs where owner_id=p_actor and not hidden)>=2000) then",
    "count": 1
  },
  {
    "signature": "public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb)",
    "before": "if coalesce((p_data->>'daily_limit')::integer,0) not between 1 and 250 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (coalesce((p_data->>'daily_limit')::integer,0) not between 1 and 250) then",
    "count": 1
  },
  {
    "signature": "public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb)",
    "before": "if total_n>=(p_data->>'daily_limit')::integer then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (total_n>=(p_data->>'daily_limit')::integer) then",
    "count": 1
  },
  {
    "signature": "public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb)",
    "before": "if used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000 or total_n>=1000 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000 or total_n>=1000) then",
    "count": 1
  },
  {
    "signature": "public.korlix_receipt_wiz_v1(uuid,text,uuid,jsonb)",
    "before": "if total_n>=1000 or used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (total_n>=1000 or used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000) then",
    "count": 1
  },
  {
    "signature": "public.korlix_radar_monitor_v1(uuid,text,uuid,jsonb)",
    "before": "if n>20 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (n>20) then",
    "count": 1
  },
  {
    "signature": "public.korlix_radar_monitor_v1(uuid,text,uuid,jsonb)",
    "before": "if n>40 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (n>40) then",
    "count": 1
  },
  {
    "signature": "public.korlix_schedule_ai_v2(uuid,text,uuid,jsonb)",
    "before": "if (select count(*) from public.korlix_schedule_ai_plans where owner_id=p_actor and created_at>now()-interval '1 day')>=10 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and ((select count(*) from public.korlix_schedule_ai_plans where owner_id=p_actor and created_at>now()-interval '1 day')>=10) then",
    "count": 1
  },
  {
    "signature": "public.korlix_funnel_v1(uuid,text,uuid,jsonb)",
    "before": "if n>10 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (n>10) then",
    "count": 1
  },
  {
    "signature": "public.korlix_funnel_v1(uuid,text,uuid,jsonb)",
    "before": "if (select count(*) from public.korlix_funnels where user_id=p_actor)>=50 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and ((select count(*) from public.korlix_funnels where user_id=p_actor)>=50) then",
    "count": 1
  },
  {
    "signature": "public.korlix_funnel_v1(uuid,text,uuid,jsonb)",
    "before": "jsonb_build_object('funnels',",
    "after": "jsonb_build_object('unlimited',public.korlix_has_unlimited_access(p_actor),'funnels',",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "g.period_start>t or g.period_end<=t or r.released_at",
    "after": "((g.period_start>t or g.period_end<=t) and not public.korlix_has_unlimited_access(s.owner_id)) or r.released_at",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "not g.enabled or g.period_start>t or g.period_end<=t or not korlix_live_private.account_available(p_actor)",
    "after": "not g.enabled or ((g.period_start>t or g.period_end<=t) and not public.korlix_has_unlimited_access(p_actor)) or not korlix_live_private.account_available(p_actor)",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "not g.enabled or g.period_start>t or g.period_end<=t or r.grant_period_start",
    "after": "not g.enabled or ((g.period_start>t or g.period_end<=t) and not public.korlix_has_unlimited_access(p_actor)) or r.grant_period_start",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "g.enabled and g.period_start<=t and g.period_end>t and korlix_live_private.account_available(p_actor)",
    "after": "g.enabled and (public.korlix_has_unlimited_access(p_actor) or (g.period_start<=t and g.period_end>t)) and korlix_live_private.account_available(p_actor)",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "'entitlement',jsonb_build_object('enabled',is_enabled",
    "after": "'entitlement',jsonb_build_object('unlimited',public.korlix_has_unlimited_access(p_actor),'enabled',is_enabled",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "'label',coalesce(g.label,'Access not enabled')",
    "after": "'label',case when public.korlix_has_unlimited_access(p_actor) then 'Developer Unlimited' else coalesce(g.label,'Access not enabled') end",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "coalesce(g.max_daily_starts,0)",
    "after": "(case when public.korlix_has_unlimited_access(p_actor) then 2147483647 else coalesce(g.max_daily_starts,0) end)",
    "count": 2
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "coalesce(g.rehearsal_limit,0)",
    "after": "(case when public.korlix_has_unlimited_access(p_actor) then 2147483647 else coalesce(g.rehearsal_limit,0) end)",
    "count": 2
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "coalesce(g.broadcast_seconds_limit,0)",
    "after": "(case when public.korlix_has_unlimited_access(p_actor) then 2147483647 else coalesce(g.broadcast_seconds_limit,0) end)",
    "count": 2
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "coalesce(g.generation_limit,0)",
    "after": "(case when public.korlix_has_unlimited_access(p_actor) then 2147483647 else coalesce(g.generation_limit,0) end)",
    "count": 2
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "if due_at>=g.period_end or due_at>t+",
    "after": "if (due_at>=g.period_end and not public.korlix_has_unlimited_access(p_actor)) or due_at>t+",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "if daily_starts>=g.max_daily_starts then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (daily_starts>=g.max_daily_starts) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "if reserved_rehearsals+wanted_rehearsals>g.rehearsal_limit or reserved_seconds+wanted_seconds>g.broadcast_seconds_limit or reserved_generations+wanted_generations>g.generation_limit then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and (reserved_rehearsals+wanted_rehearsals>g.rehearsal_limit or reserved_seconds+wanted_seconds>g.broadcast_seconds_limit or reserved_generations+wanted_generations>g.generation_limit) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_studio_v2(uuid,text,uuid,jsonb)",
    "before": "if (select count(*) from public.korlix_live_studio_shows where owner_id=p_actor)>=30 then",
    "after": "if not public.korlix_has_unlimited_access(p_actor) and ((select count(*) from public.korlix_live_studio_shows where owner_id=p_actor)>=30) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_get_usage(uuid,text,integer,integer,bigint)",
    "before": "\nbegin\n",
    "after": "\nbegin\n  if public.korlix_has_unlimited_access(p_user_id) then v_session_limit:=2147483647; v_duration_limit:=2147483647; v_token_limit:=9007199254740991; end if;\n",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_reserve_session(uuid,uuid,text,integer,integer,bigint,integer,integer)",
    "before": "\nbegin\n",
    "after": "\nbegin\n  if public.korlix_has_unlimited_access(p_user_id) then v_session_limit:=2147483647; v_duration_limit:=2147483647; v_token_limit:=9007199254740991; end if;\n",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_report_usage(uuid,uuid,integer,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint,integer,bigint,boolean,text)",
    "before": "\nbegin\n",
    "after": "\nbegin\n  if public.korlix_has_unlimited_access(p_user_id) then v_duration_limit:=2147483647; v_token_limit:=9007199254740991; end if;\n",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_reserve_session(uuid,uuid,text,integer,integer,bigint,integer,integer)",
    "before": "if v_usage.session_count >= v_session_limit then",
    "after": "if not public.korlix_has_unlimited_access(p_user_id) and (v_usage.session_count >= v_session_limit) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_reserve_session(uuid,uuid,text,integer,integer,bigint,integer,integer)",
    "before": "if v_usage.duration_seconds >= v_duration_limit then",
    "after": "if not public.korlix_has_unlimited_access(p_user_id) and (v_usage.duration_seconds >= v_duration_limit) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_reserve_session(uuid,uuid,text,integer,integer,bigint,integer,integer)",
    "before": "if v_used_tokens >= v_token_limit then",
    "after": "if not public.korlix_has_unlimited_access(p_user_id) and (v_used_tokens >= v_token_limit) then",
    "count": 1
  },
  {
    "signature": "public.korlix_live_convo_report_usage(uuid,uuid,integer,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint,integer,bigint,boolean,text)",
    "before": "v_monthly_limit_reached :=\n    v_usage.duration_seconds >= v_duration_limit\n    or (v_usage.total_tokens + v_usage.transcription_tokens) >= v_token_limit;",
    "after": "v_monthly_limit_reached := not public.korlix_has_unlimited_access(p_user_id) and (\n    v_usage.duration_seconds >= v_duration_limit\n    or (v_usage.total_tokens + v_usage.transcription_tokens) >= v_token_limit);",
    "count": 1
  },
  {
    "signature": "public.korlix_payroll_addon_active_v1(uuid)",
    "before": " select exists(select 1 from public.korlix_payroll_addons",
    "after": " select exists(select 1 from public.korlix_payroll_accounts a where a.id=p_account and public.korlix_has_unlimited_access(a.owner_id))\n or exists(select 1 from public.korlix_payroll_addons",
    "count": 1
  },
  {
    "signature": "public.korlix_payroll_addon_public_v1(uuid)",
    "before": "'status',coalesce((select case when state='active' and paid_through<=now() then 'expired'\n   when state='active' and (access_starts_at>now() or billing_verified_at>now()) then 'scheduled' else state end\n   from public.korlix_payroll_addons where account_id=p_account),'inactive'),",
    "after": "'status',case when exists(select 1 from public.korlix_payroll_accounts a where a.id=p_account and public.korlix_has_unlimited_access(a.owner_id)) then 'developer_unlimited' else coalesce((select case when state='active' and paid_through<=now() then 'expired'\n   when state='active' and (access_starts_at>now() or billing_verified_at>now()) then 'scheduled' else state end\n   from public.korlix_payroll_addons where account_id=p_account),'inactive') end,",
    "count": 1
  }
]
$patches$::jsonb) loop
    definition:=replace(pg_get_functiondef((change->>'signature')::regprocedure),E'\r\n',E'\n');
    occurrences:=(length(definition)-length(replace(definition,change->>'before','')))/length(change->>'before');
    if occurrences<>(change->>'count')::integer then
      raise exception 'Developer entitlement migration requires review: % (% matches)',change->>'signature',occurrences;
    end if;
    execute replace(definition,change->>'before',change->>'after');
  end loop;
end $migration$;
notify pgrst, 'reload schema';
