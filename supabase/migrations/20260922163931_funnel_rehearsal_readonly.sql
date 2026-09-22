begin;
-- A rehearsal must never initialize settings, reconcile tasks, or touch leads.
create function public.korlix_funnel_rehearsal_v1(p_actor uuid,p_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path=public,pg_temp as $$
declare f public.korlix_funnels; s public.korlix_funnel_followup_settings;
begin
  if p_actor is null or not exists(
    select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise'
  ) then
    raise exception 'Funnel Studio requires Enterprise.' using errcode='42501';
  end if;
  select * into f from public.korlix_funnels where id=p_id and user_id=p_actor;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  select * into s from public.korlix_funnel_followup_settings where funnel_id=f.id;
  return jsonb_build_object(
    'id',f.id,'name',f.name,'state',f.state,'version',f.version,
    'published_version',f.published_version,'draft',f.draft,'published',f.published,
    'workflow',case when s.funnel_id is null then null else jsonb_build_object(
      'enabled',s.enabled,'email_enabled',s.email_enabled,'call_enabled',s.call_enabled,
      'delay_minutes',s.delay_minutes,'subject',s.subject,'body',s.body,'version',s.version
    ) end
  );
end $$;
revoke all on function public.korlix_funnel_rehearsal_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.korlix_funnel_rehearsal_v1(uuid,uuid) to service_role;
comment on function public.korlix_funnel_rehearsal_v1(uuid,uuid) is
  'Read-only rehearsal snapshot. Checks fresh Enterprise membership and ownership; never initializes or modifies business data.';
commit;
