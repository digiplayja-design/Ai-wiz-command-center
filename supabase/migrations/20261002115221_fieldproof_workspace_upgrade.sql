-- Retain the deployed ownership, revision, integrity, quota and replay controls.
-- The only RPC behavior change is the per-job photo limit: 8 -> 24.
do $guard$
begin
 if not exists (select 1 from pg_proc where oid='public.korlix_fieldproof_v1(uuid,text,uuid,jsonb)'::regprocedure and md5(prosrc) in ('bd164a67eb846c1fe03674d938c3261d','5ce8f1f47448c379fb32becef8ecf3d8')) then
  raise exception 'FieldProof storage changed; review this migration before applying.';
 end if;
end
$guard$;
create or replace function public.korlix_fieldproof_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public as $$
declare j public.korlix_fieldproof_jobs; a public.korlix_fieldproof_evidence; r public.korlix_fieldproof_reviews;
 v_job uuid; v_event text; v_detail jsonb:='{}'; v_result jsonb; v_total bigint;
begin
 if p_actor is null then raise exception 'Sign in to use FieldProof.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,224));
 update korlix_fieldproof_reviews set state='failed',error='This review was interrupted. No credit was charged. Start a new review.',completed_at=now()
 where user_id=p_actor and state='running' and created_at<now()-interval '8 minutes';
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (select id,data,version,state,approval,completion,created_at,updated_at,
   (select count(*) from korlix_fieldproof_evidence photo_row where photo_row.job_id=korlix_fieldproof_jobs.id and photo_row.state='ready') as photo_count,
   (select review_row.id from korlix_fieldproof_reviews review_row where review_row.job_id=korlix_fieldproof_jobs.id and review_row.state='running' limit 1) as running_review
   from korlix_fieldproof_jobs where user_id=p_actor order by updated_at desc limit 200) x),'[]'::jsonb);
 elsif p_action='job_create' then
  select * into j from korlix_fieldproof_jobs where id=p_id and user_id=p_actor;
  if found then
   if j.data is distinct from p_data then raise exception 'This job was already created. Return to your jobs and edit its saved record.' using errcode='40001';end if;
   return to_jsonb(j);
  end if;
  if (select count(*) from korlix_fieldproof_jobs where user_id=p_actor)>=200 then raise exception 'Your workspace has 200 jobs. Remove an old job to add another.' using errcode='54000';end if;
  insert into korlix_fieldproof_jobs(id,user_id,data) values(p_id,p_actor,p_data) returning * into j;
  v_job:=j.id;v_event:='job_created';v_result:=to_jsonb(j);
 elsif p_action='job_get' then
  select * into j from korlix_fieldproof_jobs where id=p_id and user_id=p_actor;
  if not found then raise exception 'This FieldProof job was not found.' using errcode='P0002';end if;
  return jsonb_build_object('job',to_jsonb(j),'evidence',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from korlix_fieldproof_evidence x where x.job_id=j.id and x.user_id=p_actor),'[]'::jsonb),
   'reviews',coalesce((select jsonb_agg(to_jsonb(x)-'input'-'usage_id'-'user_id' order by x.created_at desc) from (select * from korlix_fieldproof_reviews where job_id=j.id and user_id=p_actor order by created_at desc limit 20) x),'[]'::jsonb),
   'events',coalesce((select jsonb_agg(to_jsonb(x)-'user_id' order by x.id desc) from (select * from korlix_fieldproof_events where job_id=j.id and user_id=p_actor order by id desc limit 30) x),'[]'::jsonb));
 elsif p_action='asset_get' then
  select * into a from korlix_fieldproof_evidence where id=p_id and user_id=p_actor;
  if not found then raise exception 'This photo was not found.' using errcode='P0002';end if;return to_jsonb(a);
 elsif p_action='review_get' then
  select * into r from korlix_fieldproof_reviews where id=p_id and user_id=p_actor;
  if not found then raise exception 'This review was not found.' using errcode='P0002';end if;return to_jsonb(r);
 elsif p_action in ('review_finish','review_fail') then
  select * into r from korlix_fieldproof_reviews where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'This review was not found.' using errcode='P0002';end if;
  if r.state<>'running' then return to_jsonb(r);end if;
  v_job:=r.job_id;
  if p_action='review_fail' then
   update korlix_fieldproof_reviews set state='failed',error=left(p_data->>'error',300),completed_at=now() where id=r.id returning * into r;
   v_event:='review_failed';
  else
   if not exists(select 1 from korlix_fieldproof_jobs where id=r.job_id and user_id=p_actor and version=r.version and state='active') then raise exception 'The job changed before review completed. No credit was charged.' using errcode='40001';end if;
   update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=r.usage_id and user_id=p_actor;
   if not found then raise exception 'Usage is unavailable.' using errcode='40001';end if;
   update korlix_fieldproof_reviews set state='completed',charged=1,result=p_data->'result',completed_at=now() where id=r.id returning * into r;
   v_event:='review_completed';
  end if;v_result:=to_jsonb(r);
 else
  if p_action in ('asset_begin','review_begin') then v_job:=(p_data->>'job_id')::uuid;
  elsif p_action like 'asset_%' then
   select * into a from korlix_fieldproof_evidence where id=p_id and user_id=p_actor;
   if not found then raise exception 'This photo was not found.' using errcode='P0002';end if;v_job:=a.job_id;
  else v_job:=p_id;end if;
  select * into j from korlix_fieldproof_jobs where id=v_job and user_id=p_actor for update;
  if not found then raise exception 'This FieldProof job was not found.' using errcode='P0002';end if;
  -- Recover repeated requests before state/version gates; never repeat work.
  if p_action='asset_begin' then
   select * into a from korlix_fieldproof_evidence where id=p_id and user_id=p_actor;
   if found then
    if a.job_id<>j.id or a.sha256<>p_data->>'sha256' or a.tag<>p_data->>'tag' or a.name<>p_data->>'name' or a.note<>p_data->>'note' then raise exception 'Use a new upload request for a different photo or description.' using errcode='40001';end if;
    if a.state='ready' then return to_jsonb(a);end if;
    if a.state<>'uploading' or a.lease_until>now() then raise exception 'This upload is still finishing. Refresh or retry after three minutes.' using errcode='40001';end if;
   end if;
  elsif p_action='review_begin' then
   select * into r from korlix_fieldproof_reviews where id=p_id and user_id=p_actor;
   if found then
    if r.job_id<>j.id then raise exception 'Use a new request for this job.' using errcode='40001';end if;
    return to_jsonb(r)||jsonb_build_object('replayed',true);
   end if;
  end if;
  if p_action='job_delete_finish' then
   if j.state<>'deleting' then raise exception 'Confirm deletion first.' using errcode='40001';end if;
   delete from korlix_fieldproof_jobs where id=j.id and user_id=p_actor;return '{}'::jsonb;
  end if;
  if p_action='job_delete_begin' and j.state='deleting' then
   return coalesce((select jsonb_agg(to_jsonb(x)) from korlix_fieldproof_evidence x where job_id=j.id and user_id=p_actor),'[]'::jsonb);
  end if;
  if exists(select 1 from korlix_fieldproof_reviews where user_id=p_actor and job_id=j.id and state='running') then raise exception 'Wait for KORLIX to finish this job review.' using errcode='40001';end if;
  if exists(select 1 from korlix_fieldproof_evidence where job_id=j.id and state='uploading' and lease_until>now() and (p_action<>'asset_finish' or id<>p_id)) then raise exception 'Wait for the photo upload to finish before changing this job.' using errcode='40001';end if;
  if p_action not in ('job_reopen','job_delete_begin','asset_delete_finish') and j.state<>'active' then raise exception 'Reopen this completed job before changing it.' using errcode='40001';end if;
  if p_action in ('job_save','job_approve','job_complete','job_reopen','job_delete_begin','review_begin') and j.version is distinct from (p_data->>'version')::integer then raise exception 'This job changed on another screen. Refresh before saving.' using errcode='40001';end if;
  if p_action='job_save' then
   if j.data=p_data->'data' then return to_jsonb(j);end if;
   update korlix_fieldproof_jobs set data=p_data->'data',version=version+1,completion=null,updated_at=now() where id=j.id returning * into j;
   v_event:='job_updated';v_result:=to_jsonb(j);
  elsif p_action='job_approve' then
   update korlix_fieldproof_jobs set version=version+1,approval=jsonb_build_object('name',p_data->>'name','note',p_data->>'note','recordedAt',now(),'recordedBy',data->>'technician','version',version+1),updated_at=now() where id=j.id returning * into j;
   v_event:='customer_approval_recorded';v_result:=to_jsonb(j);
  elsif p_action='job_complete' then
   if p_data->>'ready'<>'true' or exists(select 1 from korlix_fieldproof_evidence where job_id=j.id and state<>'ready') then raise exception 'Complete the required records before closing the job.' using errcode='40001';end if;
   update korlix_fieldproof_jobs set state='completed',completion=jsonb_build_object('name',p_data->>'name','completedAt',now(),'version',version),updated_at=now() where id=j.id returning * into j;
   v_event:='job_closed';v_result:=to_jsonb(j);
  elsif p_action='job_reopen' then
   if j.state<>'completed' then raise exception 'Only completed jobs can be reopened.' using errcode='40001';end if;
   update korlix_fieldproof_jobs set state='active',version=version+1,completion=null,updated_at=now() where id=j.id returning * into j;
   v_event:='job_reopened';v_result:=to_jsonb(j);
  elsif p_action='job_delete_begin' then
   update korlix_fieldproof_jobs set state='deleting',updated_at=now() where id=j.id;
   update korlix_fieldproof_evidence set state='deleting' where job_id=j.id and user_id=p_actor;
   return coalesce((select jsonb_agg(to_jsonb(x)) from korlix_fieldproof_evidence x where job_id=j.id and user_id=p_actor),'[]'::jsonb);
  elsif p_action='asset_begin' then
   if a.id is null then
    if j.version is distinct from (p_data->>'version')::integer then raise exception 'Refresh this job before adding a photo.' using errcode='40001';end if;
    if (select count(*) from korlix_fieldproof_evidence where job_id=j.id)>=24 then raise exception 'This job has 24 photos. Remove one before adding another.' using errcode='54000';end if;
    select coalesce(sum(bytes+preview_bytes),0) into v_total from korlix_fieldproof_evidence where user_id=p_actor;
    if v_total+(p_data->>'bytes')::bigint+(p_data->>'preview_bytes')::bigint>524288000 then raise exception 'FieldProof storage is full. Remove old evidence to make space.' using errcode='54000';end if;
    insert into korlix_fieldproof_evidence(id,user_id,job_id,tag,name,note,mime,extension,path,preview_path,sha256,preview_sha256,bytes,preview_bytes,width,height,lease,lease_until)
    values(p_id,p_actor,j.id,p_data->>'tag',p_data->>'name',p_data->>'note',p_data->>'mime',p_data->>'extension',p_data->>'path',p_data->>'preview_path',p_data->>'sha256',p_data->>'preview_sha256',
     (p_data->>'bytes')::bigint,(p_data->>'preview_bytes')::bigint,(p_data->>'width')::integer,(p_data->>'height')::integer,(p_data->>'lease')::uuid,now()+interval '3 minutes') returning * into a;
    update korlix_fieldproof_jobs set version=version+1,updated_at=now() where id=j.id;
    v_event:='photo_upload_started';v_detail:=jsonb_build_object('photoId',a.id,'name',a.name,'sha256',a.sha256);
   else
    update korlix_fieldproof_evidence set lease=(p_data->>'lease')::uuid,lease_until=now()+interval '3 minutes' where id=a.id returning * into a;
   end if;v_result:=to_jsonb(a);
  elsif p_action='asset_finish' then
   update korlix_fieldproof_evidence set state='ready' where id=a.id and user_id=p_actor and state='uploading' and lease=(p_data->>'lease')::uuid and lease_until>now() returning * into a;
   if not found then raise exception 'The upload lease expired. Retry the same photo.' using errcode='40001';end if;
   update korlix_fieldproof_jobs set version=version+1,updated_at=now() where id=j.id;
   v_event:='photo_saved';v_detail:=jsonb_build_object('photoId',a.id,'name',a.name,'sha256',a.sha256);v_result:=to_jsonb(a);
  elsif p_action='asset_delete_begin' then
   if a.state='uploading' and a.lease_until>now() then raise exception 'Wait three minutes before removing an interrupted upload.' using errcode='40001';end if;
   if a.state<>'deleting' then
    update korlix_fieldproof_evidence set state='deleting' where id=a.id returning * into a;
    update korlix_fieldproof_jobs set version=version+1,updated_at=now() where id=j.id;
    v_event:='photo_removed';v_detail:=jsonb_build_object('photoId',a.id,'name',a.name,'sha256',a.sha256);
   end if;v_result:=to_jsonb(a);
  elsif p_action='asset_delete_finish' then
   delete from korlix_fieldproof_evidence where id=a.id and user_id=p_actor and state='deleting';v_result:='{}'::jsonb;
  elsif p_action='review_begin' then
   if exists(select 1 from korlix_fieldproof_reviews where user_id=p_actor and state='running') then raise exception 'KORLIX is already reviewing another job.' using errcode='40001';end if;
   if (select count(*) from korlix_fieldproof_reviews where user_id=p_actor and created_at>now()-interval '1 hour')>=12 then raise exception 'Please wait before requesting more reviews.' using errcode='54000';end if;
   if not exists(select 1 from korlix_fieldproof_evidence where job_id=j.id and state='ready') or exists(select 1 from korlix_fieldproof_evidence where job_id=j.id and state<>'ready') then raise exception 'Save at least one photo and finish all uploads before review.' using errcode='40001';end if;
   if not exists(select 1 from usage_counters where id=(p_data->>'usage_id')::uuid and user_id=p_actor) then raise exception 'Usage is unavailable.' using errcode='40001';end if;
   delete from korlix_fieldproof_reviews where job_id=j.id and id in (select id from korlix_fieldproof_reviews where job_id=j.id order by created_at desc offset 19);
   insert into korlix_fieldproof_reviews(id,user_id,job_id,version,input,usage_id)
   values(p_id,p_actor,j.id,j.version,jsonb_build_object('job',jsonb_build_object('data',j.data,'version',j.version,'approval',j.approval),
    'evidence',(select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from korlix_fieldproof_evidence x where job_id=j.id and user_id=p_actor)),(p_data->>'usage_id')::uuid) returning * into r;
   v_event:='review_started';v_result:=to_jsonb(r)||jsonb_build_object('replayed',false);
  else raise exception 'Unknown FieldProof operation.';end if;
 end if;
 if v_event is not null then
  insert into korlix_fieldproof_events(user_id,job_id,action,version,detail) select p_actor,v_job,v_event,version,v_detail from korlix_fieldproof_jobs where id=v_job and user_id=p_actor;
  delete from korlix_fieldproof_events where job_id=v_job and id in (select id from korlix_fieldproof_events where job_id=v_job order by id desc offset 200);
 end if;
 return v_result;
end $$;
revoke all on function public.korlix_fieldproof_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_fieldproof_v1(uuid,text,uuid,jsonb) to service_role;
