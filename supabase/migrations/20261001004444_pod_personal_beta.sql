-- Personal, on-demand pods. Only the authenticated backend service can call these functions.
-- Provider usage and dispatch receipts are retained when a user deletes transcript history.
create table public.korlix_pod_sessions (
 id uuid primary key,
 owner_id uuid not null references auth.users(id) on delete cascade,
 quota_session_id uuid not null unique,
 input jsonb not null,
 request_hash text not null,
 limits jsonb not null,
 unlimited boolean not null default false,
 state text not null default 'ready' check(state in('ready','active','paused','ended','failed')),
 phase text not null default 'ready',
 version integer not null default 0 check(version>=0),
 duration_seconds integer not null check(duration_seconds in(300,600,900)),
 started_at timestamptz,
 deadline_at timestamptz,
 last_heartbeat_at timestamptz not null default clock_timestamp(),
 accounted_at timestamptz not null default clock_timestamp(),
 active_millis bigint not null default 0 check(active_millis>=0 and active_millis<=900000),
 provider_attempted boolean not null default false,
 turns jsonb not null default '[]',
 brief jsonb not null default '{}',
 sources jsonb not null default '[]',
 checked_at timestamptz,
 summary text,
 end_reason text,
 error text,
 response_count integer not null default 0 check(response_count>=0),
 total_tokens bigint not null default 0 check(total_tokens>=0),
 input_tokens bigint not null default 0 check(input_tokens>=0),
 output_tokens bigint not null default 0 check(output_tokens>=0),
 input_audio_tokens bigint not null default 0 check(input_audio_tokens>=0),
 output_audio_tokens bigint not null default 0 check(output_audio_tokens>=0),
 transcription_tokens bigint not null default 0 check(transcription_tokens>=0),
 deleted_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 check((started_at is null and deadline_at is null) or (started_at is not null and deadline_at=started_at+duration_seconds*interval '1 second'))
);
create unique index korlix_pod_one_active_owner on public.korlix_pod_sessions(owner_id) where state in('ready','active','paused');
create index korlix_pod_owner_history on public.korlix_pod_sessions(owner_id,created_at desc);
create index korlix_pod_recovery on public.korlix_pod_sessions(updated_at,id) where state in('ready','active','paused');

create table public.korlix_pod_operations (
 episode_id uuid not null references public.korlix_pod_sessions(id) on delete cascade,
 request_id uuid not null,
 kind text not null check(kind in('next','transcribe','contribute')),
 request_hash text not null,
 version integer not null,
 state text not null check(state in('claimed','completed','failed','interrupted','expired')),
 lease_until timestamptz,
 dispatched jsonb not null default '{}',
 result jsonb not null default '{}',
 uncertain boolean not null default false,
 created_at timestamptz not null default clock_timestamp(),
 completed_at timestamptz,
 primary key(episode_id,request_id)
);
create unique index korlix_pod_one_claim on public.korlix_pod_operations(episode_id) where state='claimed';
create table public.korlix_pod_usage_receipts (
 episode_id uuid not null,
 request_id uuid not null,
 call_key text not null check(call_key in('research','turn','speak','transcribe')),
 usage jsonb not null,
 evidence jsonb not null default '{}',
 payload_hash text not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(episode_id,request_id,call_key),
 foreign key(episode_id,request_id) references public.korlix_pod_operations(episode_id,request_id) on delete cascade
);
alter table public.korlix_pod_sessions enable row level security;
alter table public.korlix_pod_operations enable row level security;
alter table public.korlix_pod_usage_receipts enable row level security;
revoke all on public.korlix_pod_sessions,public.korlix_pod_operations,public.korlix_pod_usage_receipts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_pod_sessions,public.korlix_pod_operations,public.korlix_pod_usage_receipts to service_role;

create function public.korlix_pod_present_v1(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object(
  'id',id,'category',input->>'category','topic',input->>'topic',
  'durationSeconds',duration_seconds,'hostCount',(input->>'hostCount')::integer,'style',input->>'style',
  'state',state,'phase',phase,'version',version,'createdAt',created_at,'startedAt',started_at,'deadlineAt',deadline_at,
  'serverNow',clock_timestamp(),'turns',turns,'sources',sources,'checkedAt',checked_at,'summary',summary,
  'endReason',end_reason,'error',error,'activeSeconds',floor(active_millis/1000.0)::integer,
  'usageLabel','Personal beta · uses your LIVE CONVO session and time allowance. AI usage limits also apply.'
 ) from public.korlix_pod_sessions where id=p_id;
$$;

-- This helper accepts only persisted server counters. It never accepts client totals or prices.
create function public.korlix_pod_account_v1(p_id uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare s public.korlix_pod_sessions; r jsonb;
begin
 select * into s from public.korlix_pod_sessions where id=p_id for update;
 if not found then raise exception 'Pod not found.' using errcode='P0002';end if;
 if not s.provider_attempted and s.started_at is null then
  if s.state in('ended','failed') then
   if s.unlimited then
    delete from public.korlix_live_convo_sessions where id=s.quota_session_id and user_id=s.owner_id and status='reserved';
   else
    perform public.korlix_live_convo_cancel_reservation(s.quota_session_id,s.owner_id,coalesce(s.end_reason,'pod_not_started'));
   end if;
  end if;
  return jsonb_build_object('allowed',true);
 end if;
 if s.unlimited then
  update public.korlix_live_convo_sessions set
   status=case when s.state in('ended','failed') then 'ended' else 'active' end,
   duration_seconds=greatest(duration_seconds,(s.active_millis/1000)::integer),response_count=greatest(response_count,s.response_count),
   total_tokens=greatest(total_tokens,s.total_tokens),input_tokens=greatest(input_tokens,s.input_tokens),
   output_tokens=greatest(output_tokens,s.output_tokens),input_audio_tokens=greatest(input_audio_tokens,s.input_audio_tokens),
   output_audio_tokens=greatest(output_audio_tokens,s.output_audio_tokens),transcription_tokens=greatest(transcription_tokens,s.transcription_tokens),
   ended_at=case when s.state in('ended','failed') then coalesce(ended_at,clock_timestamp()) else ended_at end,
   end_reason=s.end_reason,last_seen_at=clock_timestamp(),updated_at=clock_timestamp()
   where id=s.quota_session_id and user_id=s.owner_id and tier='developer_unlimited';
  if not found then raise exception 'Pod accounting is unavailable.' using errcode='40001';end if;
  return jsonb_build_object('allowed',true);
 end if;
 r:=public.korlix_live_convo_report_usage(
  s.quota_session_id,s.owner_id,(s.active_millis/1000)::integer,s.response_count,
  s.total_tokens,s.input_tokens,s.output_tokens,s.input_audio_tokens,s.output_audio_tokens,0,s.transcription_tokens,
  (s.limits->>'monthlySeconds')::integer,(s.limits->>'monthlyTokens')::bigint,s.state in('ended','failed'),s.end_reason);
 if r->>'code'='session_not_found' then raise exception 'Pod accounting is unavailable.' using errcode='40001';end if;
 if r->'allowed'='false'::jsonb and s.state not in('ended','failed') then
  update public.korlix_pod_sessions set state='ended',phase='ended',version=version+1,end_reason='allowance_reached',updated_at=clock_timestamp() where id=s.id;
  update public.korlix_live_convo_sessions set status='ended',ended_at=coalesce(ended_at,clock_timestamp()),end_reason='pod_allowance_reached' where id=s.quota_session_id and user_id=s.owner_id;
 end if;
 return r;
end;
$$;

create function public.korlix_pod_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 s public.korlix_pod_sessions; o public.korlix_pod_operations; old record;
 v_now timestamptz:=clock_timestamp(); until_at timestamptz; elapsed bigint;
 h text; rq uuid; k text; a text; q jsonb; u jsonb; e jsonb; v_result jsonb; turn_data jsonb; public_episode jsonb;
 incoming_version integer; max_seconds integer; max_responses integer; n integer; any_steps boolean;
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
 if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed' and lease_until<=v_now) then
  update public.korlix_pod_operations set state='expired',uncertain=dispatched<>'{}'::jsonb,completed_at=v_now where episode_id=s.id and state='claimed' and lease_until<=v_now;
  update public.korlix_pod_sessions set state=case when state='ended' then state else 'failed' end,phase='ended',version=version+1,end_reason=coalesce(end_reason,'operation_expired'),error='This pod request expired. No automatic retry was made.',updated_at=v_now where id=s.id;
 end if;
 q:=public.korlix_pod_account_v1(s.id);
 select * into s from public.korlix_pod_sessions where id=s.id;

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
    if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed') then raise exception 'Wait for the interrupted request to stop before resuming.' using errcode='40001';end if;
    update public.korlix_pod_sessions set state=case when started_at is null then 'ready' else 'active' end,phase=case when started_at is null then 'ready' else 'listening' end,last_heartbeat_at=v_now,accounted_at=v_now,end_reason=null,updated_at=v_now where id=s.id;
   else
    update public.korlix_pod_sessions set state=case when a='end' then 'ended' else 'paused' end,phase=case when a='end' then 'ended' else 'paused' end,version=version+1,end_reason=case when a='end' then 'user_ended' else a end,updated_at=v_now where id=s.id;
   end if;
  end if;
  perform public.korlix_pod_account_v1(s.id);
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='remove' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm deletion of this pod.' using errcode='22023';end if;
  if s.state not in('ended','failed') or exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed') then raise exception 'End this pod and wait for its request to stop before deleting it.' using errcode='40001';end if;
  update public.korlix_pod_sessions set input='{}',turns='[]',brief='{}',sources='[]',summary=null,error=null,deleted_at=coalesce(deleted_at,v_now),updated_at=v_now where id=s.id;
  update public.korlix_pod_operations set result='{}' where episode_id=s.id;
  return jsonb_build_object('deleted',true);
 end if;

 if coalesce(p_data->>'requestId','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Use a valid pod request.' using errcode='22023';end if;
 rq:=(p_data->>'requestId')::uuid;
 select * into o from public.korlix_pod_operations where episode_id=s.id and request_id=rq for update;
 if p_action in('claim','contribute') then
  if p_action='claim' then
   k:=p_data->>'kind';incoming_version:=(p_data->>'version')::integer;
   if coalesce(k,'') not in('next','transcribe') or incoming_version is null then raise exception 'Choose a valid pod operation.' using errcode='22023';end if;
   h:=encode(sha256(convert_to(jsonb_build_object('kind',k,'version',incoming_version)::text,'UTF8')),'hex');
  else
   k:='contribute';
   if length(btrim(coalesce(p_data->>'text',''))) not between 1 and 1000 then raise exception 'Write a contribution of 1 to 1,000 characters.' using errcode='22023';end if;
   h:=encode(sha256(convert_to(p_data->>'text','UTF8')),'hex');
  end if;
  if o.request_id is not null then
   if o.request_hash<>h or o.kind<>k then raise exception 'Use a new request after changing your contribution or episode.' using errcode='40001';end if;
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'dispatch',false,'replayed',true,'brief',s.brief,'result',o.result,'operation',jsonb_build_object('id',o.request_id,'kind',o.kind,'state',o.state,'version',o.version,'leaseUntil',o.lease_until));
  end if;
  if s.state in('ended','failed') or s.deleted_at is not null then raise exception 'This pod has ended. Start a new episode to continue.' using errcode='40001';end if;
  if k='contribute' then
   if s.state<>'paused' then raise exception 'Pause or interrupt before adding your contribution.' using errcode='40001';end if;
   if (select count(*) from public.korlix_pod_operations where episode_id=s.id and kind='contribute')>=12 then raise exception 'This episode reached its contribution limit.' using errcode='54000';end if;
   turn_data:=jsonb_build_object('id',rq,'seq',jsonb_array_length(s.turns)+1,'speaker','user','text',btrim(p_data->>'text'),'sourceIds','[]'::jsonb,'createdAt',v_now);
   update public.korlix_pod_sessions set turns=turns||jsonb_build_array(turn_data),version=version+1,updated_at=v_now where id=s.id;
   insert into public.korlix_pod_operations(episode_id,request_id,kind,request_hash,version,state,result,completed_at) values(s.id,rq,k,h,s.version+1,'completed',jsonb_build_object('turn',turn_data),v_now);
   return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'replayed',false);
  end if;
  if incoming_version<>s.version then raise exception 'This pod changed. Refresh before requesting another turn.' using errcode='40001';end if;
  if exists(select 1 from public.korlix_pod_operations where episode_id=s.id and state='claimed') then raise exception 'A pod request is still running. Wait for it to finish.' using errcode='40001';end if;
  if (k='next' and s.state not in('ready','active')) or (k='transcribe' and s.state<>'paused') then raise exception 'Resume to listen, or pause to record your contribution.' using errcode='40001';end if;
  if (select count(*) from public.korlix_pod_operations where episode_id=s.id and kind=k)>=(case when k='next' then 36 else 12 end) then raise exception 'This episode reached its request limit.' using errcode='54000';end if;
  insert into public.korlix_pod_operations(episode_id,request_id,kind,request_hash,version,state,lease_until) values(s.id,rq,k,h,s.version,'claimed',least(v_now+interval '170 seconds',coalesce(s.deadline_at,s.created_at+interval '3 minutes'))) returning * into o;
  update public.korlix_pod_sessions set phase=case when k='next' then 'preparing' else 'transcribing' end,last_heartbeat_at=v_now,updated_at=v_now where id=s.id;
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id),'dispatch',true,'replayed',false,'brief',s.brief,'operation',jsonb_build_object('id',rq,'kind',k,'state',o.state,'version',o.version,'leaseUntil',o.lease_until));
 end if;
 if o.request_id is null then raise exception 'Pod request not found.' using errcode='P0002';end if;
 if p_action='dispatch' then
  k:=p_data->>'callKey';
  if coalesce(k,'') not in('research','turn','speak','transcribe') or (o.kind='transcribe')<>(k='transcribe') then raise exception 'Invalid provider step.' using errcode='22023';end if;
  if o.state<>'claimed' or o.version<>s.version or o.lease_until<=v_now or (o.kind='next' and s.state not in('ready','active')) or (o.kind='transcribe' and s.state<>'paused') or v_now>s.last_heartbeat_at+interval '35 seconds' then return jsonb_build_object('allowed',false,'episode',public.korlix_pod_present_v1(s.id));end if;
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
   response_count=response_count+case when k='turn' then 1 else 0 end,
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
   if o.version=s.version and s.state not in('ended','failed') then
    update public.korlix_pod_sessions set state='failed',phase='ended',version=version+1,end_reason='provider_failed',error=left(coalesce(p_data->>'error','This pod request could not finish.'),300),updated_at=v_now where id=s.id;
   end if;
  end if;
  perform public.korlix_pod_account_v1(s.id);
  return jsonb_build_object('episode',public.korlix_pod_present_v1(s.id));
 end if;
 if p_action='finish' then
  if o.state<>'claimed' then return jsonb_build_object('committed',o.state='completed','replayed',true,'episode',public.korlix_pod_present_v1(s.id))||o.result;end if;
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
   if not(o.dispatched ? 'turn') or not(o.dispatched ? 'speak') or jsonb_typeof(turn_data) is distinct from 'object' or coalesce(turn_data->>'speaker','') not in('host','analyst','challenger') or (turn_data->>'speaker'='challenger' and (s.input->>'hostCount')::integer<>3) or length(btrim(coalesce(turn_data->>'text',''))) not between 1 and 480 then raise exception 'No usable host turn was returned.' using errcode='22023';end if;
   if v_result ? 'brief' and (jsonb_typeof(v_result->'brief')<>'object' or octet_length((v_result->'brief')::text)>20000) then raise exception 'Research brief is invalid.' using errcode='22023';end if;
   if v_result ? 'sources' and (jsonb_typeof(v_result->'sources')<>'array' or jsonb_array_length(v_result->'sources')>12) then raise exception 'Research sources are invalid.' using errcode='22023';end if;
   turn_data:=jsonb_build_object('id',rq,'seq',jsonb_array_length(s.turns)+1,'speaker',turn_data->>'speaker','text',btrim(turn_data->>'text'),'sourceIds',coalesce(turn_data->'sourceIds','[]'),'createdAt',v_now);
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
revoke all on function public.korlix_pod_present_v1(uuid),public.korlix_pod_account_v1(uuid),public.korlix_pod_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_pod_present_v1(uuid),public.korlix_pod_account_v1(uuid),public.korlix_pod_v1(uuid,text,uuid,jsonb) to service_role;
