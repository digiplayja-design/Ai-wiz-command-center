-- Keep at most one paid next voice private until the listener reaches the handoff.
-- Audio bytes remain bounded in server memory; only validated text and accounting live in the database.
-- An ordinary pause preserves a completed preparation; contributions/end discard it without refunding real usage.
alter table public.korlix_pod_sessions add column preparation_error text;
alter table public.korlix_pod_sessions add column preparation_uncertain boolean not null default false;
alter table public.korlix_pod_operations drop constraint korlix_pod_operations_kind_check;
alter table public.korlix_pod_operations add constraint korlix_pod_operations_kind_check check(kind in('next','prepare','transcribe','contribute'));
alter table public.korlix_pod_operations drop constraint korlix_pod_operations_state_check;
alter table public.korlix_pod_operations add constraint korlix_pod_operations_state_check check(state in('claimed','prepared','completed','failed','interrupted','expired'));
create unique index korlix_pod_one_buffer on public.korlix_pod_operations(episode_id) where state in('claimed','prepared');

create or replace function public.korlix_pod_present_v1(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object(
  'id',id,'category',input->>'category','topic',input->>'topic',
  'durationSeconds',duration_seconds,'hostCount',(input->>'hostCount')::integer,'style',input->>'style',
  'state',state,'phase',phase,'version',version,'createdAt',created_at,'startedAt',started_at,'deadlineAt',deadline_at,
  'serverNow',clock_timestamp(),'turns',turns,'sources',sources,'checkedAt',checked_at,'summary',summary,
  'endReason',end_reason,'error',error,'preparationError',preparation_error,
  'preparedId',(select request_id from public.korlix_pod_operations where episode_id=p_id and state='prepared' limit 1),'activeSeconds',floor(active_millis/1000.0)::integer,
  'usageLabel','Personal beta · uses your LIVE CONVO session and time allowance. AI usage limits also apply.'
 ) from public.korlix_pod_sessions where id=p_id;
$$;

create or replace function public.korlix_pod_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 s public.korlix_pod_sessions; o public.korlix_pod_operations; old record;
 v_now timestamptz:=clock_timestamp(); until_at timestamptz; elapsed bigint;
 h text; rq uuid; k text; a text; q jsonb; u jsonb; e jsonb; v_result jsonb; turn_data jsonb; public_episode jsonb;
 incoming_version integer; max_seconds integer; max_responses integer; n integer; any_steps boolean; expected_welcome text; prep_uncertain boolean;
begin
 if p_action='sweep' then
  n:=0;
  for old in select owner_id,id from public.korlix_pod_sessions s1 where state in('ready','active','paused') or exists(select 1 from public.korlix_pod_operations o1 where o1.episode_id=s1.id and o1.state='claimed') order by owner_id,id limit 100 loop
   perform public.korlix_pod_v1(old.owner_id,'get',old.id,'{}');n:=n+1;
  end loop;
  return jsonb_build_object('checked',n);
 end if;
 if p_actor is null then raise exception 'Sign in to use your pod.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('pod:'||p_actor::text,0));
 if p_action='quota_lookup' then return jsonb_build_object('isPod',exists(select 1 from public.korlix_pod_sessions where owner_id=p_actor and quota_session_id=p_id));end if;
 if p_action in('list','create') then
  for old in select id from public.korlix_pod_sessions s1 where owner_id=p_actor and (state in('ready','active','paused') or exists(select 1 from public.korlix_pod_operations o1 where o1.episode_id=s1.id and o1.state='claimed')) order by id loop
   perform public.korlix_pod_v1(p_actor,'get',old.id,'{}');
  end loop;
 end if;
 if p_action='list' then
  return jsonb_build_object('episodes',coalesce((select jsonb_agg(public.korlix_pod_present_v1(x.id) order by x.created_at desc) from (select id,created_at from public.korlix_pod_sessions where owner_id=p_actor and deleted_at is null order by created_at desc limit 50)x),'[]'));
 end if;
 if p_action='create' then
  if p_id is null or jsonb_typeof(p_data->'input') is distinct from 'object' or jsonb_typeof(p_data->'limits') is distinct from 'object' then raise exception 'Choose a pod topic and duration.' using errcode='22023';end if;
  u:=p_data->'input';e:=p_data->'limits';
  if coalesce(u->>'category','') not in('trending','politics','sports','religion','culture','business','technology') or length(btrim(coalesce(u->>'topic',''))) not between 1 and 240 or coalesce(u->>'durationSeconds','') not in('300','600','900') or coalesce(u->>'hostCount','') not in('2','3') or coalesce(u->>'style','') not in('balanced','relaxed','debate') then raise exception 'Choose an available pod topic, duration and host count.' using errcode='22023';end if;
  h:=encode(sha256(convert_to(u::text,'UTF8')),'hex');
  select * into s from public.korlix_pod_sessions where id=p_id for update;
  if found then
   if s.owner_id<>p_actor or s.request_hash<>h or s.deleted_at is not null then raise exception 'Use a new Listen request for this pod.' using errcode='40001';end if;
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'replayed',true);
  end if;
  if exists(select 1 from public.korlix_pod_sessions where owner_id=p_actor and state in('ready','active','paused')) then raise exception 'Finish your current pod before starting another.' using errcode='40001';end if;
  if exists(select 1 from public.korlix_pod_operations o1 join public.korlix_pod_sessions s1 on s1.id=o1.episode_id where s1.owner_id=p_actor and o1.state='claimed') then raise exception 'Wait for your previous pod request to stop before starting another.' using errcode='40001';end if;
  if (select count(*) from public.korlix_pod_sessions where owner_id=p_actor and created_at>v_now-interval '1 hour')>=12 then raise exception 'Please wait before starting more pods.' using errcode='54000';end if;
  if (select count(*) from public.korlix_pod_sessions where owner_id=p_actor and deleted_at is null)>=50 then raise exception 'Delete an ended pod before starting another.' using errcode='54000';end if;
  if coalesce(e->>'tier','')='' or coalesce(e->>'maxSessionSeconds','') !~ '^[0-9]+$' or coalesce(e->>'maxResponses','') !~ '^[0-9]+$' or coalesce(e->>'monthlySessions','') !~ '^[0-9]+$' or coalesce(e->>'monthlySeconds','') !~ '^[0-9]+$' or coalesce(e->>'monthlyTokens','') !~ '^[0-9]+$' then raise exception 'Your pod allowance could not be verified.' using errcode='42501';end if;
  max_seconds:=least(900,(e->>'maxSessionSeconds')::integer);max_responses:=least(1000,(e->>'maxResponses')::integer);
  if (u->>'durationSeconds')::integer>max_seconds or max_responses<1 then raise exception 'Choose a shorter episode within your allowance.' using errcode='54000';end if;
  rq:=gen_random_uuid();
  if p_data->'unlimited'='true'::jsonb then
   insert into public.korlix_live_convo_sessions(id,user_id,month_key,tier,status,max_duration_seconds,max_response_count) values(rq,p_actor,date_trunc('month',timezone('utc',v_now))::date,'developer_unlimited','reserved',(u->>'durationSeconds')::integer,max_responses);
  else
   q:=public.korlix_live_convo_reserve_session(rq,p_actor,e->>'tier',(e->>'monthlySessions')::integer,(e->>'monthlySeconds')::integer,(e->>'monthlyTokens')::bigint,(u->>'durationSeconds')::integer,max_responses);
   if q->'allowed' is distinct from 'true'::jsonb then raise exception '%',coalesce(q->>'message','Your LIVE CONVO allowance is unavailable.') using errcode='54000';end if;
   if (q->>'remainingSeconds')::integer<(u->>'durationSeconds')::integer then raise exception 'Your remaining LIVE CONVO time is too short for this episode.' using errcode='54000';end if;
  end if;
  insert into public.korlix_pod_sessions(id,owner_id,quota_session_id,input,request_hash,limits,unlimited,duration_seconds) values(p_id,p_actor,rq,u,h,e,coalesce((p_data->>'unlimited')::boolean,false),(u->>'durationSeconds')::integer);
  return jsonb_build_object('episode',public.korlix_pod_present_v1(p_id),'replayed',false);
 end if;
 select * into s from public.korlix_pod_sessions where id=p_id and owner_id=p_actor for update;
 if not found or (s.deleted_at is not null and p_action not in('remove','receipt','finish','fail')) then raise exception 'Pod not found.' using errcode='P0002';end if;

 -- Settle only active time, capped at the last heartbeat's bounded disconnect grace and absolute deadline.
 if s.state='active' then
  until_at:=least(v_now,s.last_heartbeat_at+interval '35 seconds',s.deadline_at);
  elapsed:=greatest(0,floor(extract(epoch from (until_at-s.accounted_at))*1000)::bigint);
  update public.korlix_pod_sessions set active_millis=least(duration_seconds::bigint*1000,active_millis+elapsed),accounted_at=v_now where id=s.id;
 end if;
 if s.state in('ready','active','paused') then
  if (s.started_at is null and v_now>=s.created_at+interval '3 minutes') or (s.deadline_at is not null and v_now>=s.deadline_at) then
   update public.korlix_pod_sessions set state='ended',phase='ended',version=version+1,end_reason=case when started_at is null then 'ready_expired' else 'time_limit' end,updated_at=v_now where id=s.id;
  elsif (s.state='active' or exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed' and version=s.version)) and v_now>s.last_heartbeat_at+interval '35 seconds' then
   update public.korlix_pod_sessions set state='paused',phase='paused',version=version+1,end_reason='heartbeat_lost',updated_at=v_now where id=s.id;
  end if;
 end if;
 if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed' and lease_until<=v_now and kind='prepare') then
  update public.korlix_pod_sessions set preparation_error='The next voice could not finish preparing. Pause and resume to try again.',preparation_uncertain=exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed' and kind='prepare' and dispatched<>'{}'::jsonb),updated_at=v_now where id=s.id;
  update public.korlix_pod_operations set state='expired',uncertain=dispatched<>'{}'::jsonb,completed_at=v_now where episode_id=s.id and state='claimed' and kind='prepare' and lease_until<=v_now;
 end if;
 if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed' and lease_until<=v_now) then
  update public.korlix_pod_operations set state='expired',uncertain=dispatched<>'{}'::jsonb,completed_at=v_now where episode_id=s.id and state='claimed' and lease_until<=v_now;
  update public.korlix_pod_sessions set state=case when state='ended' then state else 'failed' end,phase='ended',version=version+1,end_reason=coalesce(end_reason,'operation_expired'),error='This pod request expired. No automatic retry was made.',updated_at=v_now where id=s.id;
 end if;
 q:=public.korlix_pod_account_v1(s.id);
 select * into s from public.korlix_pod_sessions where id=s.id;
 if s.state in('ended','failed') or s.deleted_at is not null then
  update public.korlix_pod_operations set state='interrupted',result='{}',completed_at=v_now where episode_id=s.id and state='prepared';
 end if;

 if p_action='get' then
  select * into o from public.korlix_pod_operations where episode_id=s.id and state='claimed';
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'brief',s.brief,'operation',case when o.request_id is null then null else jsonb_build_object('id',o.request_id,'kind',o.kind,'state',o.state,'version',o.version,'leaseUntil',o.lease_until) end);
 end if;
 if p_action='control' then
  a:=p_data->>'action';
  if coalesce(a,'') not in('pause','resume','interrupt','end','heartbeat') then raise exception 'Choose an available pod control.' using errcode='22023';end if;
  if s.state not in('ended','failed') then
   if a='heartbeat' then
    update public.korlix_pod_sessions set last_heartbeat_at=v_now,updated_at=v_now where id=s.id;
   elsif a='resume' then
    if s.preparation_uncertain then raise exception 'AI usage for the prepared turn could not be confirmed. Start a new pod.' using errcode='40001';end if;
    if s.preparation_error is not null and s.state<>'paused' then raise exception 'Pause before retrying the next voice.' using errcode='40001';end if;
    if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed') then raise exception 'Wait for the interrupted request to stop before resuming.' using errcode='40001';end if;
    update public.korlix_pod_sessions set state=case when started_at is null then 'ready' else 'active' end,phase=case when started_at is null then 'ready' else 'listening' end,last_heartbeat_at=v_now,accounted_at=v_now,end_reason=null,preparation_error=null,preparation_uncertain=false,updated_at=v_now where id=s.id;
   else
    if a in('interrupt','end') then
     update public.korlix_pod_operations set state='interrupted',result='{}',completed_at=v_now where episode_id=s.id and state='prepared';
    end if;
    update public.korlix_pod_sessions set state=case when a='end' then 'ended' else 'paused' end,phase=case when a='end' then 'ended' else 'paused' end,version=version+1,end_reason=case when a='end' then 'user_ended' else a end,updated_at=v_now where id=s.id;
   end if;
  end if;
  perform public.korlix_pod_account_v1(s.id);
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm deletion of this pod.' using errcode='22023';end if;
  if s.state not in('ended','failed') or exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed') then raise exception 'End this pod and wait for its request to stop before deleting it.' using errcode='40001';end if;
  update public.korlix_pod_sessions set input='{}',turns='[]',brief='{}',sources='[]',summary=null,error=null,preparation_error=null,preparation_uncertain=false,deleted_at=coalesce(deleted_at,v_now),updated_at=v_now where id=s.id;
  update public.korlix_pod_operations set result='{}' where episode_id=s.id;
  return jsonb_build_object('deleted',true);
 end if;

 if coalesce(p_data->>'requestId','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Use a valid pod request.' using errcode='22023';end if;
 rq:=(p_data->>'requestId')::uuid;
 select * into o from public.korlix_pod_operations where episode_id=s.id and request_id=rq for update;
 if p_action in('claim','contribute') then
  if p_action='claim' then
   k:=p_data->>'kind';incoming_version:=(p_data->>'version')::integer;
   if coalesce(k,'') not in('next','prepare','transcribe') or incoming_version is null then raise exception 'Choose a valid pod operation.' using errcode='22023';end if;
   h:=encode(sha256(convert_to(jsonb_build_object('kind',k,'version',incoming_version)::text,'UTF8')),'hex');
  else
   k:='contribute';
   if length(btrim(coalesce(p_data->>'text',''))) not between 1 and 1000 then raise exception 'Write a contribution of 1 to 1,000 characters.' using errcode='22023';end if;
   h:=encode(sha256(convert_to(p_data->>'text','UTF8')),'hex');
  end if;
  if o.request_id is not null then
   if o.request_hash<>h or o.kind<>k then raise exception 'Use a new request after changing your contribution or episode.' using errcode='40001';end if;
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'dispatch',false,'replayed',true,'brief',s.brief,'result',case when k='prepare' then '{}'::jsonb else o.result end,'operation',jsonb_build_object('id',o.request_id,'kind',o.kind,'state',o.state,'version',o.version,'leaseUntil',o.lease_until));
  end if;
  if s.state in('ended','failed') or s.deleted_at is not null then raise exception 'This pod has ended. Start a new episode to continue.' using errcode='40001';end if;
  if k='contribute' then
   update public.korlix_pod_operations set state='interrupted',result='{}',completed_at=v_now where episode_id=s.id and state='prepared';
   if s.state<>'paused' then raise exception 'Pause or interrupt before adding your contribution.' using errcode='40001';end if;
   if (select count(*) from public.korlix_pod_operations where episode_id=s.id and kind='contribute')>=12 then raise exception 'This episode reached its contribution limit.' using errcode='54000';end if;
   turn_data:=jsonb_build_object('id',rq,'seq',jsonb_array_length(s.turns)+1,'speaker','user','text',btrim(p_data->>'text'),'sourceIds','[]'::jsonb,'createdAt',v_now);
   update public.korlix_pod_sessions set turns=turns||jsonb_build_array(turn_data),version=version+1,updated_at=v_now where id=s.id;
   insert into public.korlix_pod_operations(episode_id,request_id,kind,request_hash,version,state,result,completed_at) values(s.id,rq,k,h,s.version+1,'completed',jsonb_build_object('turn',turn_data),v_now);
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'replayed',false);
  end if;
  if k in('next','prepare') and s.preparation_error is not null then raise exception '%',s.preparation_error using errcode='40001';end if;
  if incoming_version<>s.version then raise exception 'This pod changed. Refresh before requesting another turn.' using errcode='40001';end if;
  if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state in('claimed','prepared')) then raise exception 'A pod request is still running or ready to play. Wait for it to finish.' using errcode='40001';end if;
  if (k='prepare' and (s.state<>'active' or s.started_at is null or s.summary is not null)) then raise exception 'Start listening before preparing another voice, and finish the pod after its closing.' using errcode='40001';end if;
  if (k='next' and s.state not in('ready','active')) or (k='transcribe' and s.state<>'paused') then raise exception 'Resume to listen, or pause to record your contribution.' using errcode='40001';end if;
  if (select count(*) from public.korlix_pod_operations where episode_id=s.id and (case when k in('next','prepare') then kind in('next','prepare') else kind=k end))>=(case when k in('next','prepare') then 36 else 12 end) then raise exception 'This episode reached its request limit.' using errcode='54000';end if;
  insert into public.korlix_pod_operations(episode_id,request_id,kind,request_hash,version,state,lease_until) values(s.id,rq,k,h,s.version,'claimed',least(v_now+interval '215 seconds',coalesce(s.deadline_at,s.created_at+interval '3 minutes'))) returning * into o;
  update public.korlix_pod_sessions set phase=case when k='next' then 'preparing' when k='prepare' then phase else 'transcribing' end,last_heartbeat_at=v_now,updated_at=v_now where id=s.id;
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'dispatch',true,'replayed',false,'brief',s.brief,'operation',jsonb_build_object('id',rq,'kind',k,'state',o.state,'version',o.version,'leaseUntil',o.lease_until));
 end if;
 if o.request_id is null then raise exception 'Pod request not found.' using errcode='P0002';end if;
 if p_action='discard_prepared' then
  incoming_version:=(p_data->>'version')::integer;
  if incoming_version is null or incoming_version<>s.version or s.state not in('active','paused') then raise exception 'This pod changed. Refresh before retrying its prepared voice.' using errcode='40001';end if;
  if o.kind='prepare' and o.state='completed' and s.turns->-1->>'id'=rq::text then
   return jsonb_build_object('alreadyPlayed',true,'episode',public.korlix_pod_present_v1(s.id),'turn',o.result->'turn');
  end if;
  if o.kind<>'prepare' or o.state<>'prepared' then raise exception 'This prepared voice is no longer available.' using errcode='40001';end if;
  update public.korlix_pod_operations set state='interrupted',result='{}',completed_at=v_now where episode_id=s.id and request_id=rq;
  update public.korlix_pod_sessions set preparation_error='The prepared audio expired. Pause and resume to prepare it again.',preparation_uncertain=false,updated_at=v_now where id=s.id;
  return jsonb_build_object('discarded',true,'episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='play_prepared' then
  incoming_version:=(p_data->>'version')::integer;
  if incoming_version is null or incoming_version<>s.version or s.state<>'active' or s.deleted_at is not null or s.deadline_at<=v_now then raise exception 'This pod changed. Refresh before playing its prepared voice.' using errcode='40001';end if;
  if o.kind<>'prepare' then raise exception 'Choose the prepared voice for this pod.' using errcode='22023';end if;
  if o.state='completed' and s.turns->-1->>'id'=rq::text then
   return jsonb_build_object('committed',true,'replayed',true,'episode',public.korlix_pod_present_v1(s.id))||o.result;
  end if;
  if o.state<>'prepared' then raise exception 'This prepared voice is no longer available. Refresh your pod.' using errcode='40001';end if;
  v_result:=o.result;
  if (v_result->>'baseTurnCount')::integer is distinct from jsonb_array_length(s.turns) or
     v_result->>'baseLastTurnId' is distinct from s.turns->-1->>'id'
  then raise exception 'The discussion changed before this voice could play.' using errcode='40001';end if;
  turn_data:=jsonb_set(v_result->'turn','{createdAt}',to_jsonb(v_now));
  update public.korlix_pod_sessions set turns=turns||jsonb_build_array(turn_data),
   brief=coalesce(v_result->'brief',brief),sources=coalesce(v_result->'sources',v_result->'brief'->'sources',sources),
   checked_at=coalesce((v_result->>'checkedAt')::timestamptz,(v_result->'brief'->>'checkedAt')::timestamptz,checked_at),
   summary=coalesce(left(v_result->>'summary',2000),summary),phase='listening',updated_at=v_now where id=s.id;
  v_result:=jsonb_build_object('turn',turn_data);
  update public.korlix_pod_operations set state='completed',result=v_result,completed_at=v_now where episode_id=s.id and request_id=rq;
  return jsonb_build_object('committed',true,'replayed',false,'episode',public.korlix_pod_present_v1(s.id))||v_result;
 end if;
 if p_action='dispatch' then
  k:=p_data->>'callKey';
  if coalesce(k,'') not in('research','turn','speak','transcribe') or (o.kind='transcribe')<>(k='transcribe') then raise exception 'Invalid provider step.' using errcode='22023';end if;
  if o.state<>'claimed' or o.version<>s.version or o.lease_until<=v_now or (o.kind='next' and s.state not in('ready','active')) or (o.kind='prepare' and s.state<>'active') or (o.kind='transcribe' and s.state<>'paused') or v_now>s.last_heartbeat_at+interval '35 seconds' then return jsonb_build_object('allowed',false,'episode',public.korlix_pod_present_v1(s.id));end if;
  if o.dispatched ? k then raise exception 'This provider step was already dispatched. It will not be repeated automatically.' using errcode='40001';end if;
  update public.korlix_pod_operations set dispatched=dispatched||jsonb_build_object(k,v_now) where episode_id=s.id and request_id=rq;
  update public.korlix_pod_sessions set provider_attempted=true,updated_at=v_now where id=s.id;
  return jsonb_build_object('allowed',true,'episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='receipt' then
  k:=p_data->>'callKey';u:=coalesce(p_data->'usage','{}');e:=coalesce(p_data->'evidence','{}');
  if not(o.dispatched ? coalesce(k,'')) or jsonb_typeof(u)<>'object' or jsonb_typeof(e)<>'object' then raise exception 'Usage does not match a dispatched provider step.' using errcode='22023';end if;
  if octet_length(e::text)>12000 or octet_length(u::text)>4000 then raise exception 'Usage receipt is too large.' using errcode='22023';end if;
  for old in select key,value from jsonb_each(u) loop
   if old.key not in('totalTokens','inputTokens','outputTokens','inputAudioTokens','outputAudioTokens','transcriptionTokens') or jsonb_typeof(old.value)<>'number' or old.value::text !~ '^[0-9]+$' or (old.value::text)::numeric>10000000 then raise exception 'Usage counters must be actual nonnegative provider integers.' using errcode='22023';end if;
  end loop;
  if k='transcribe' and coalesce((u->>'totalTokens')::bigint,0)>0 then raise exception 'Transcription totals belong only in transcriptionTokens.' using errcode='22023';end if;
  h:=encode(sha256(convert_to(jsonb_build_object('usage',u,'evidence',e)::text,'UTF8')),'hex');
  select payload_hash into a from public.korlix_pod_usage_receipts where episode_id=s.id and request_id=rq and call_key=k;
  if found then
   if a<>h then raise exception 'A provider usage receipt cannot be changed.' using errcode='40001';end if;
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'replayed',true,'allowed',o.state='claimed' and o.version=s.version and s.state not in('ended','failed'));
  end if;
  insert into public.korlix_pod_usage_receipts(episode_id,request_id,call_key,usage,evidence,payload_hash) values(s.id,rq,k,u,e,h);
  update public.korlix_pod_sessions set
   response_count=response_count+case when k in('research','turn') then 1 else 0 end,
   total_tokens=total_tokens+coalesce((u->>'totalTokens')::bigint,0),input_tokens=input_tokens+coalesce((u->>'inputTokens')::bigint,0),
   output_tokens=output_tokens+coalesce((u->>'outputTokens')::bigint,0),input_audio_tokens=input_audio_tokens+coalesce((u->>'inputAudioTokens')::bigint,0),
   output_audio_tokens=output_audio_tokens+coalesce((u->>'outputAudioTokens')::bigint,0),transcription_tokens=transcription_tokens+coalesce((u->>'transcriptionTokens')::bigint,0),updated_at=v_now where id=s.id;
  q:=public.korlix_pod_account_v1(s.id);
  select * into s from public.korlix_pod_sessions where id=s.id;
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'replayed',false,'allowed',o.state='claimed' and o.version=s.version and s.state not in('ended','failed'));
 end if;
 if p_action='fail' then
  if o.state='claimed' then
   any_steps:=o.dispatched<>'{}'::jsonb;
   update public.korlix_pod_operations set state=case when o.version<>s.version then 'interrupted' else 'failed' end,uncertain=coalesce((p_data->>'uncertain')::boolean,false) or exists(select 1 from public.korlix_pod_usage_receipts r where r.episode_id=s.id and r.request_id=rq and r.evidence->>'status'='uncertain') or exists(select 1 from jsonb_object_keys(o.dispatched) keys(k) where not exists(select 1 from public.korlix_pod_usage_receipts r where r.episode_id=s.id and r.request_id=rq and r.call_key=keys.k)),completed_at=v_now where episode_id=s.id and request_id=rq;
   if o.version=s.version and s.state not in('ended','failed') and o.kind='prepare' then
    select uncertain into prep_uncertain from public.korlix_pod_operations where episode_id=s.id and request_id=rq;
    update public.korlix_pod_sessions set preparation_error=left(coalesce(p_data->>'error','The next voice could not finish preparing. Pause and resume to try again.'),300),preparation_uncertain=prep_uncertain,updated_at=v_now where id=s.id;
   elsif o.version=s.version and s.state not in('ended','failed') then
    update public.korlix_pod_sessions set state='failed',phase='ended',version=version+1,end_reason='provider_failed',error=left(coalesce(p_data->>'error','This pod request could not finish.'),300),updated_at=v_now where id=s.id;
   end if;
  end if;
  perform public.korlix_pod_account_v1(s.id);
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='finish' then
  if o.kind='prepare' and o.state='prepared' then return jsonb_build_object('committed',true,'prepared',true,'preparedId',rq,'replayed',true,'episode',public.korlix_pod_present_v1(s.id));end if;
  if o.state<>'claimed' then return jsonb_build_object('committed',o.state='completed','replayed',true,'episode',public.korlix_pod_present_v1(s.id))||(case when o.kind='prepare' then '{}'::jsonb else o.result end);end if;
  if o.version<>s.version or s.state in('ended','failed') or s.deleted_at is not null or v_now>s.last_heartbeat_at+interval '35 seconds' then
   update public.korlix_pod_operations set state='interrupted',uncertain=exists(select 1 from jsonb_object_keys(o.dispatched) keys(k) where not exists(select 1 from public.korlix_pod_usage_receipts r where r.episode_id=s.id and r.request_id=rq and r.call_key=keys.k)),completed_at=v_now where episode_id=s.id and request_id=rq;
   return jsonb_build_object('committed',false,'episode',public.korlix_pod_present_v1(s.id));
  end if;
  if exists(select 1 from jsonb_object_keys(o.dispatched) keys(k) where not exists(select 1 from public.korlix_pod_usage_receipts r where r.episode_id=s.id and r.request_id=rq and r.call_key=keys.k)) then raise exception 'Record provider usage before saving this turn.' using errcode='40001';end if;
  v_result:=coalesce(p_data->'result','{}');
  if o.kind='transcribe' then
   if not(o.dispatched ? 'transcribe') or jsonb_typeof(v_result->'text') is distinct from 'string' or length(v_result->>'text')>1000 then raise exception 'No usable transcription was returned.' using errcode='22023';end if;
   v_result:=jsonb_build_object('text',v_result->>'text');
  else
   turn_data:=v_result->'turn';
   if not(o.dispatched ? 'speak') or jsonb_typeof(turn_data) is distinct from 'object' or coalesce(turn_data->>'speaker','') not in('host','analyst','challenger') or (turn_data->>'speaker'='challenger' and (s.input->>'hostCount')::integer<>3) or length(btrim(coalesce(turn_data->>'text',''))) not between 1 and 480 then raise exception 'No usable host turn was returned.' using errcode='22023';end if;
   if o.kind='prepare' and (s.state<>'active' or s.started_at is null or s.summary is not null or v_result->'welcome'='true'::jsonb) then raise exception 'Only a running discussion can prepare its next voice.' using errcode='40001';end if;
   if v_result->'welcome'='true'::jsonb then
    expected_welcome:='Hey, I’m K-Nova. Welcome to The Pod and You, with ' ||
      (case when (s.input->>'hostCount')::integer=3 then 'our AI Analyst and Challenger' else 'our AI Analyst' end) ||
      '. Next, we’ll check sources before discussing the facts. That check can take a little time. You can pause us, or use Chime in to add your take.';
    if s.started_at is not null or exists(select 1 from jsonb_array_elements(s.turns) t where t->>'speaker'<>'user') or
       o.dispatched ? 'research' or o.dispatched ? 'turn' or turn_data->>'speaker'<>'host' or
       turn_data->>'text' is distinct from expected_welcome or turn_data->'sourceIds' is distinct from '[]'::jsonb or
       v_result ? 'brief' or v_result ? 'sources' or v_result ? 'checkedAt' or v_result ? 'summary'
    then raise exception 'The opening welcome must be the fixed, source-free first host turn.' using errcode='22023';end if;
   elsif not(o.dispatched ? 'turn') then
    -- The research response itself contains the first factual Analyst turn. No second text request is required.
    if not(o.dispatched ? 'research') or s.started_at is null or coalesce(s.brief->>'text','')<>'' or
       turn_data->>'speaker'<>'analyst' or jsonb_typeof(turn_data->'sourceIds') is distinct from 'array' or
       coalesce(jsonb_array_length(turn_data->'sourceIds'),0)=0 or
       length(btrim(coalesce(v_result->'brief'->>'text',''))) not between 1 and 12000 or
       jsonb_typeof(v_result->'sources') is distinct from 'array'
    then raise exception 'The research opening requires its verified brief and sources.' using errcode='22023';end if;
    if exists(select 1 from jsonb_array_elements_text(turn_data->'sourceIds') ids(id) where
      not exists(select 1 from jsonb_array_elements(v_result->'sources') src where src->>'id'=ids.id))
    then raise exception 'The research opening may cite only its retrieved sources.' using errcode='22023';end if;
   end if;
   if v_result ? 'brief' and (jsonb_typeof(v_result->'brief')<>'object' or octet_length((v_result->'brief')::text)>20000) then raise exception 'Research brief is invalid.' using errcode='22023';end if;
   if v_result ? 'sources' and (jsonb_typeof(v_result->'sources')<>'array' or jsonb_array_length(v_result->'sources')>12) then raise exception 'Research sources are invalid.' using errcode='22023';end if;
   turn_data:=jsonb_build_object('id',rq,'seq',jsonb_array_length(s.turns)+1,'speaker',turn_data->>'speaker','text',btrim(turn_data->>'text'),'sourceIds',coalesce(turn_data->'sourceIds','[]'),'createdAt',v_now);
   if o.kind='prepare' then
    v_result:=v_result||jsonb_build_object('turn',turn_data,'baseTurnCount',jsonb_array_length(s.turns),'baseLastTurnId',s.turns->-1->>'id');
    update public.korlix_pod_operations set state='prepared',result=v_result,completed_at=v_now where episode_id=s.id and request_id=rq;
    return jsonb_build_object('committed',true,'prepared',true,'preparedId',rq,'replayed',false,'episode',public.korlix_pod_present_v1(s.id));
   end if;
   update public.korlix_pod_sessions set turns=turns||jsonb_build_array(turn_data),
    brief=coalesce(v_result->'brief',brief),sources=coalesce(v_result->'sources',v_result->'brief'->'sources',sources),
    checked_at=coalesce((v_result->>'checkedAt')::timestamptz,(v_result->'brief'->>'checkedAt')::timestamptz,checked_at),
    summary=coalesce(left(v_result->>'summary',2000),summary),started_at=coalesce(started_at,v_now),deadline_at=coalesce(deadline_at,v_now+duration_seconds*interval '1 second'),
    state='active',phase='listening',accounted_at=v_now,updated_at=v_now where id=s.id;
   v_result:=jsonb_build_object('turn',turn_data);
  end if;
  update public.korlix_pod_operations set state='completed',result=v_result,completed_at=v_now where episode_id=s.id and request_id=rq;
  return jsonb_build_object('committed',true,'replayed',false,'episode',public.korlix_pod_present_v1(s.id))||v_result;
 end if;
 raise exception 'Unknown pod action.' using errcode='22023';
end;
$$;
revoke all on function public.korlix_pod_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_pod_v1(uuid,text,uuid,jsonb) to service_role;
