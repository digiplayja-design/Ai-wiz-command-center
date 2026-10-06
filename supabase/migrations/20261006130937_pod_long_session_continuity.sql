-- Give short, fluid turns enough room for a 15-minute episode. Existing
-- sessions retain their original allowance; monthly accounting is unchanged.
do $migration$
declare definition text;
begin
 definition := pg_get_functiondef('public.korlix_pod_v1(uuid,text,uuid,jsonb)'::regprocedure);
 if position('then 36 else 12 end' in definition)>0 then
  execute replace(definition,'then 36 else 12 end','then 90 else 12 end');
 elsif position('then 90 else 12 end' in definition)=0 then
  raise exception 'Unexpected pod operation budget; review before migration';
 end if;
 definition := pg_get_functiondef('public.korlix_pod_present_v1(uuid)'::regprocedure);
 if position('''hostTurnLimit''' in definition)=0 then
  if position('''usageLabel'',' in definition)=0 then
   raise exception 'Unexpected pod presentation function; review before migration';
  end if;
  execute replace(definition,'''usageLabel'',',
   '''hostTurnLimit'',(select least(90,greatest(2,q.max_response_count-1)) from public.korlix_live_convo_sessions q where q.id=korlix_pod_sessions.quota_session_id),''usageLabel'',');
 end if;
end $migration$;
revoke all on function public.korlix_pod_v1(uuid,text,uuid,jsonb),public.korlix_pod_present_v1(uuid) from public,anon,authenticated;
grant execute on function public.korlix_pod_v1(uuid,text,uuid,jsonb),public.korlix_pod_present_v1(uuid) to service_role;
