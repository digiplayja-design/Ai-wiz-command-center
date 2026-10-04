-- Import the first directory batch atomically when Auto Pull is enabled.
-- Existing enabled accounts retain their hourly schedule and permissions.
create or replace function public.korlix_crm_directory_v1(p_actor uuid,p_action text,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
#variable_conflict use_column
declare s public.korlix_crm_directory_sync; f jsonb; item jsonb; candidates jsonb; result jsonb; who uuid;
 v_now timestamptz:=clock_timestamp(); imported integer:=0; skipped integer:=0; processed integer:=0;
begin
 if p_action='tick' then
  -- Take the same per-user lock as manual controls, before touching the row.
  for who in select user_id from korlix_crm_directory_sync where enabled and next_run_at<=v_now order by next_run_at,user_id limit 10 loop
   if pg_try_advisory_xact_lock(hashtextextended('crm-directory:'||who::text,0)) then
    if not exists(select 1 from user_profiles where id=who and lower(trim(tier))='enterprise') then
     update korlix_crm_directory_sync set enabled=false,version=version+1,next_run_at=null,last_result='{"reason":"Enterprise access required"}',updated_at=v_now where user_id=who;
    else perform public.korlix_crm_directory_v1(who,'run','{"automatic":true}'); processed:=processed+1; end if;
   end if;
  end loop;
  return jsonb_build_object('processed',processed);
 end if;
 if p_actor is null or not exists(select 1 from user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'CRM403: Enterprise required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('crm-directory:'||p_actor::text,0));
 select * into s from korlix_crm_directory_sync where user_id=p_actor for update;
 if p_action='state' then
  return jsonb_build_object('settings',case when s.user_id is null then jsonb_build_object('enabled',false,'version',0,'filters',jsonb_build_object('q','','category','','city','','country','','verified_only',false),'imported_total',0) else to_jsonb(s)-'user_id' end,'interval_minutes',60,'batch_limit',100);
 end if;
 if p_action in ('save','preview') then
  f:=p->'filters';
  if jsonb_typeof(f) is distinct from 'object' or length(coalesce(f->>'q',''))>120 or length(coalesce(f->>'category',''))>80 or length(coalesce(f->>'city',''))>100 or length(coalesce(f->>'country',''))>100 or jsonb_typeof(f->'verified_only') is distinct from 'boolean' then raise exception 'CRM: Choose valid directory filters.'; end if;
  f:=jsonb_build_object('q',trim(coalesce(f->>'q','')),'category',trim(coalesce(f->>'category','')),'city',trim(coalesce(f->>'city','')),'country',trim(coalesce(f->>'country','')),'verified_only',(f->>'verified_only')::boolean);
  if p_action='preview' then
   select coalesce(jsonb_agg(x),'[]') into candidates from public.korlix_crm_directory_matches_v1(p_actor,f) x;
   return jsonb_build_object('businesses',(select coalesce(jsonb_agg(value),'[]') from (select value from jsonb_array_elements(candidates) limit 25) t),'available_in_batch',least(100,jsonb_array_length(candidates)),'more_available',jsonb_array_length(candidates)>100,'preview_only',true);
  end if;
  if coalesce(s.version,0)<>coalesce((p->>'version')::integer,-1) then raise exception 'CRM409: Directory settings changed. Refresh before saving.'; end if;
  insert into korlix_crm_directory_sync(user_id,filters) values(p_actor,f) on conflict(user_id) do update set filters=excluded.filters,enabled=false,next_run_at=null,version=korlix_crm_directory_sync.version+1,updated_at=v_now returning * into s;
  return jsonb_build_object('settings',to_jsonb(s)-'user_id','saved',true);
 end if;
 if s.user_id is null then raise exception 'CRM409: Save your directory filters first.'; end if;
 if p_action='toggle' then
  if s.version<>coalesce((p->>'version')::integer,-1) then raise exception 'CRM409: Directory settings changed. Refresh first.'; end if;
  if jsonb_typeof(p->'enabled') is distinct from 'boolean' or ((p->>'enabled')::boolean and p->>'confirmed' is distinct from 'true') then raise exception 'CRM: Review and confirm automatic imports first.'; end if;
  -- Enabling and the first import commit together. A failed first import cannot
  -- leave a misleading enabled state. Repeated enable requests keep the schedule.
  update korlix_crm_directory_sync
   set enabled=(p->>'enabled')::boolean,
       next_run_at=case when (p->>'enabled')::boolean
         then case when s.enabled then coalesce(s.next_run_at,v_now) else v_now end
         else null end,
       version=version+1,updated_at=v_now
   where user_id=p_actor returning * into s;
  if s.enabled then
   result:=public.korlix_crm_directory_v1(p_actor,'run','{"automatic":true}');
   select * into s from korlix_crm_directory_sync where user_id=p_actor;
  end if;
  return jsonb_build_object('settings',to_jsonb(s)-'user_id','initial_result',result);
 elsif p_action='run' then
  if coalesce((p->>'automatic')::boolean,false) then
   if not s.enabled or s.next_run_at is null or s.next_run_at>v_now then return jsonb_build_object('skipped',true); end if;
  else
   if p->>'confirmed' is distinct from 'true' then raise exception 'CRM: Confirm importing these business listings.'; end if;
   if s.version<>coalesce((p->>'version')::integer,-1) then raise exception 'CRM409: Directory settings changed. Review the current filters first.'; end if;
   if s.last_run_at>v_now-interval '10 seconds' then raise exception 'CRM409: Please wait a few seconds before pulling again.'; end if;
  end if;
  for item in select x from public.korlix_crm_directory_matches_v1(p_actor,s.filters) x limit 100 loop
   -- Serialize with listing withdrawal/moderation; never import a stale private draft.
   perform 1 from korlix_directory_businesses where id=(item->>'id')::uuid and version=(item->>'source_version')::integer and published is not null and state<>'hidden' for share;
   if not found then skipped:=skipped+1;continue;end if;
   begin
    insert into korlix_contacts(user_id,directory_business_id,name,company,email,phone,phone_key,category,source,notes,tags,email_permission,call_permission)
    values(p_actor,(item->>'id')::uuid,item->>'name',item->>'name',item->>'email',item->>'phone',item->>'phone_key','lead','directory',
     left(concat_ws(E'\n','Imported from KORLIX Business Directory.',nullif(item->>'description',''),
      case when coalesce(item->>'public_contact_name','')<>'' then 'Public contact: '||(item->>'public_contact_name') end,
      case when coalesce(item->>'website','')<>'' then 'Website: '||(item->>'website') end,
      'Location: '||concat_ws(', ',nullif(item->>'address',''),nullif(item->>'city',''),nullif(item->>'country','')),
      case when coalesce(item->>'service_area','')<>'' then 'Service area: '||(item->>'service_area') end),4000),
     array_remove(array['Business Directory',nullif(left(item->>'category',32),'')],null),'none','none');
    imported:=imported+1;
   exception when unique_violation then skipped:=skipped+1;
   end;
  end loop;
  result:=jsonb_build_object('imported',imported,'skipped',skipped,'completed_at',v_now,'automatic',coalesce((p->>'automatic')::boolean,false));
  update korlix_crm_directory_sync set last_run_at=v_now,last_result=result,imported_total=imported_total+imported,next_run_at=case when enabled then v_now+interval '1 hour' else null end,updated_at=v_now where user_id=p_actor;
  return result;
 end if;
 raise exception 'CRM: Unknown directory action.';
end $$;
revoke all on function public.korlix_crm_directory_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_crm_directory_v1(uuid,text,jsonb) to service_role;
