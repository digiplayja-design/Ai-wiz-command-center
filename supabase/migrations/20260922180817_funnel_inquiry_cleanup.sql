begin;
create table public.korlix_funnel_removed_requests (
  funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
  request_id uuid not null,
  expires_at timestamptz not null,
  primary key(funnel_id,request_id)
);
create table public.korlix_funnel_cleanup_receipts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
  selection_hash text not null,
  deleted_count integer not null check(deleted_count between 1 and 100),
  created_at timestamptz not null default now()
);
create index korlix_funnel_cleanup_receipts_owner on public.korlix_funnel_cleanup_receipts(user_id,created_at);
alter table public.korlix_funnel_removed_requests enable row level security;
alter table public.korlix_funnel_cleanup_receipts enable row level security;
revoke all on public.korlix_funnel_removed_requests,public.korlix_funnel_cleanup_receipts from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnel_removed_requests,public.korlix_funnel_cleanup_receipts to service_role;

-- Internal service helper: no contact contents or approval nonces are returned.
create function public.korlix_funnel_cleanup_state_v1(p_lead uuid)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'fingerprint',md5(jsonb_build_array(to_jsonb(l),
    (select jsonb_agg(jsonb_build_array(t.id,t.version,t.state,t.message_id,t.funnel_id) order by t.id) from public.korlix_funnel_followup_tasks t where t.lead_id=l.id),
    (select jsonb_agg(jsonb_build_array(q.id,q.version,q.state,q.funnel_id) order by q.id) from public.korlix_funnel_sequences q where q.lead_id=l.id)
  )::text),
  'followups',(select count(*) from public.korlix_funnel_followup_tasks where lead_id=l.id),
  'sequences',(select count(*) from public.korlix_funnel_sequences where lead_id=l.id),
  'blocked_reason',case
   when exists(select 1 from public.korlix_funnel_followup_tasks where lead_id=l.id and funnel_id<>l.funnel_id)
     or exists(select 1 from public.korlix_funnel_sequences where lead_id=l.id and funnel_id<>l.funnel_id) then 'Record associations require review.'
   when exists(select 1 from public.korlix_funnel_followup_tasks where lead_id=l.id and (message_id is not null or state='sent')) then 'Recorded email activity must be retained.'
   when exists(select 1 from public.korlix_funnel_followup_tasks where lead_id=l.id and state in ('review','scheduled','processing','needs_review')) then 'Resolve open follow-ups before deleting.'
   when exists(select 1 from public.korlix_funnel_sequences where lead_id=l.id and state in ('active','paused')) then 'Stop the inquiry sequence before deleting.'
   else null end
 ) from public.korlix_funnel_leads l where l.id=p_lead
$$;

create function public.korlix_funnel_cleanup_preview_v1(p_actor uuid,p_id uuid,p_data jsonb default '{}')
returns jsonb language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare mode text:=p_data->>'mode'; cutoff timestamptz; target uuid; statuses jsonb:=p_data->'statuses'; result jsonb;
begin
 if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Funnel Studio requires Enterprise.' using errcode='42501'; end if;
 if not exists(select 1 from public.korlix_funnels where id=p_id and user_id=p_actor) then raise exception 'Funnel not found.' using errcode='P0002'; end if;
 if mode='single' then
  begin target:=(p_data->>'lead_id')::uuid; exception when invalid_text_representation then raise exception 'Invalid inquiry.'; end;
  if not exists(select 1 from public.korlix_funnel_leads where id=target and funnel_id=p_id) then raise exception 'Inquiry not found.' using errcode='P0002'; end if;
 elsif mode='retention' then
  if jsonb_typeof(statuses) is distinct from 'array' then raise exception 'Choose Won, Lost, or both.'; end if;
  if jsonb_array_length(statuses) not between 1 and 2 or exists(select 1 from jsonb_array_elements_text(statuses) x where x not in ('won','lost')) then raise exception 'Choose Won, Lost, or both.'; end if;
  if coalesce(p_data->>'before','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a valid UTC cutoff date.'; end if;
  begin cutoff:=(p_data->>'before')::date::timestamp at time zone 'UTC';
  exception when invalid_datetime_format or datetime_field_overflow then raise exception 'Choose a valid UTC cutoff date.'; end;
  if cutoff<'2000-01-01T00:00:00Z' or cutoff>date_trunc('day',now() at time zone 'UTC') at time zone 'UTC' then raise exception 'Choose a valid UTC cutoff date, no later than today.'; end if;
 else raise exception 'Choose a valid cleanup mode.';
 end if;
 with candidates as materialized (
  select l.id,l.name,l.email,l.inbox_status,l.created_at,public.korlix_funnel_cleanup_state_v1(l.id) state
  from public.korlix_funnel_leads l where l.funnel_id=p_id
    and ((mode='single' and l.id=target) or (mode='retention' and l.created_at<cutoff and statuses ? l.inbox_status))
 ), chosen as (
  select * from candidates where state->>'blocked_reason' is null order by created_at,id limit 100
 ), blocked as (
  select * from candidates where state->>'blocked_reason' is not null order by created_at,id limit 5
 ) select jsonb_build_object(
  'matched',(select count(*) from candidates),'eligible',(select count(*) from candidates where state->>'blocked_reason' is null),
  'blocked',(select count(*) from candidates where state->>'blocked_reason' is not null),
  'selected',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'email',email,'status',inbox_status,'created_at',created_at,
    'fingerprint',state->>'fingerprint','followups',(state->>'followups')::integer,'sequences',(state->>'sequences')::integer) order by created_at,id) from chosen),'[]'),
  'blocked_examples',coalesce((select jsonb_agg(jsonb_build_object('name',name,'reason',state->>'blocked_reason') order by created_at,id) from blocked),'[]')
 ) into result;
 return result;
end $$;

create function public.korlix_funnel_cleanup_delete_v1(p_actor uuid,p_id uuid,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare items jsonb:=p_data->'items'; receipt uuid; count_requested integer; ids uuid[]; item jsonb; state jsonb; prior public.korlix_funnel_cleanup_receipts;
begin
 if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then raise exception 'Funnel Studio requires Enterprise.' using errcode='42501'; end if;
 perform 1 from public.korlix_funnels where id=p_id and user_id=p_actor for update;
 if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
 if jsonb_typeof(items) is distinct from 'array' then raise exception 'Preview the selection before deleting.'; end if;
 count_requested:=jsonb_array_length(items);
 if count_requested not between 1 and 100 then raise exception 'Review between 1 and 100 inquiries.'; end if;
 begin receipt:=(p_data->>'review_id')::uuid; select array_agg((x->>'id')::uuid) into ids from jsonb_array_elements(items) x;
 exception when invalid_text_representation then raise exception 'Invalid cleanup review.'; end;
 if receipt is null or cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Invalid cleanup review.'; end if;
 select * into prior from public.korlix_funnel_cleanup_receipts where id=receipt;
 if found then
  if prior.user_id<>p_actor or prior.funnel_id<>p_id or prior.selection_hash<>md5(items::text) then raise exception 'This cleanup review changed.' using errcode='40001'; end if;
  return jsonb_build_object('deleted_count',prior.deleted_count,'replayed',true);
 end if;
 perform 1 from public.korlix_funnel_leads where funnel_id=p_id and id=any(ids) order by id for update;
 if (select count(*) from public.korlix_funnel_leads where funnel_id=p_id and id=any(ids))<>count_requested then raise exception 'An inquiry changed or was removed. Preview cleanup again.' using errcode='40001'; end if;
 perform 1 from public.korlix_funnel_followup_tasks where lead_id=any(ids) order by id for update;
 perform 1 from public.korlix_funnel_sequences where lead_id=any(ids) order by id for update;
 for item in select value from jsonb_array_elements(items) loop
  state:=public.korlix_funnel_cleanup_state_v1((item->>'id')::uuid);
  if state->>'blocked_reason' is not null or state->>'fingerprint' is distinct from item->>'fingerprint' then raise exception 'An inquiry or follow-up changed. Preview cleanup again.' using errcode='40001'; end if;
 end loop;
 -- Form tokens expire within 30 minutes. Keep only non-content replay markers.
 delete from public.korlix_funnel_removed_requests where funnel_id=p_id and expires_at<now();
 insert into public.korlix_funnel_removed_requests(funnel_id,request_id,expires_at)
 select funnel_id,request_id,created_at+interval '31 minutes' from public.korlix_funnel_leads where id=any(ids) and created_at>now()-interval '31 minutes'
 on conflict(funnel_id,request_id) do update set expires_at=greatest(korlix_funnel_removed_requests.expires_at,excluded.expires_at);
 delete from public.korlix_funnel_followup_tasks where lead_id=any(ids);
 delete from public.korlix_funnel_sequences where lead_id=any(ids);
 delete from public.korlix_funnel_leads where id=any(ids) and funnel_id=p_id;
 delete from public.korlix_funnel_cleanup_receipts where user_id=p_actor and created_at<now()-interval '30 days';
 insert into public.korlix_funnel_cleanup_receipts(id,user_id,funnel_id,selection_hash,deleted_count) values(receipt,p_actor,p_id,md5(items::text),count_requested);
 return jsonb_build_object('deleted_count',count_requested,'replayed',false);
end $$;
revoke all on function public.korlix_funnel_cleanup_state_v1(uuid),public.korlix_funnel_cleanup_preview_v1(uuid,uuid,jsonb),public.korlix_funnel_cleanup_delete_v1(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_cleanup_state_v1(uuid),public.korlix_funnel_cleanup_preview_v1(uuid,uuid,jsonb),public.korlix_funnel_cleanup_delete_v1(uuid,uuid,jsonb) to service_role;

-- Preserve public-form retry idempotency after inquiry removal.
create or replace function public.korlix_funnel_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_contacts; n integer; out jsonb; requested uuid; enterprise boolean;
begin
  if p_action in ('public','lead') then
    select * into f from public.korlix_funnels where slug=p_data->>'slug' for update;
    if not found or f.state<>'published' or not exists(select 1 from public.user_profiles where id=f.user_id and lower(trim(tier))='enterprise') then
      raise exception 'This page is not available.' using errcode='P0002';
    end if;
    if p_action='public' then
      if coalesce((p_data->>'count')::boolean,false) then
        update public.korlix_funnels set page_requests=least(page_requests+1,1000000000) where id=f.id;
      end if;
      return jsonb_build_object('id',f.id,'slug',f.slug,'document',f.published,'published_version',f.published_version);
    end if;
    if (p_data->>'published_version')::integer is distinct from f.published_version then
      raise exception 'This page changed. Reload before submitting.' using errcode='40001';
    end if;
    requested := (p_data->>'request_id')::uuid;
    if exists(select 1 from public.korlix_funnel_removed_requests where funnel_id=f.id and request_id=requested and expires_at>=now()) then return jsonb_build_object('received',true); end if;
    delete from public.korlix_funnel_removed_requests where funnel_id=f.id and expires_at<now();
    if exists(select 1 from public.korlix_funnel_leads where funnel_id=f.id and request_id=requested) then return jsonb_build_object('received',true); end if;
    if length(coalesce(p_data->>'name','')) not between 1 and 160 or length(coalesce(p_data->>'email','')) not between 3 and 254 then raise exception 'Complete the required fields.'; end if;
    insert into public.korlix_funnel_usage(scope,n) values('lead:'||f.id,1)
      on conflict(scope,day) do update set n=korlix_funnel_usage.n+1 returning korlix_funnel_usage.n into n;
    if n>2000 then raise exception 'This form is temporarily at capacity. Please contact the business directly.' using errcode='54000'; end if;
    -- Public input never updates an existing contact, permission, suppression, or owner.
    select * into c from public.korlix_contacts where user_id=f.user_id and lower(email)=lower(p_data->>'email') and archived_at is null for update;
    if not found then
      begin
        insert into public.korlix_contacts(user_id,name,email,phone,category,source,tags,notes,email_permission,consent_at)
          values(f.user_id,p_data->>'name',lower(p_data->>'email'),nullif(p_data->>'phone',''),'lead','funnel',array['Funnel Studio'],
            'Funnel inquiry: '||f.name||'. Submitted details are unverified.','transactional',now()) returning * into c;
      exception when unique_violation then
        select * into c from public.korlix_contacts where user_id=f.user_id and lower(email)=lower(p_data->>'email') and archived_at is null;
        if not found then raise; end if;
      end;
    end if;
    insert into public.korlix_funnel_leads(funnel_id,request_id,published_version,contact_id,name,email,phone,message,utm,consent_text)
      values(f.id,requested,f.published_version,c.id,p_data->>'name',lower(p_data->>'email'),coalesce(p_data->>'phone',''),coalesce(p_data->>'message',''),
        coalesce(p_data->'utm','{}'),'I agree that '||(f.published->>'brand')||' may contact me about this request. This does not subscribe me to marketing messages.');
    return jsonb_build_object('received',true);
  end if;
  if p_actor is null or not exists(select 1 from public.user_profiles where id=p_actor and lower(trim(tier))='enterprise') then
    raise exception 'Funnel Studio requires Enterprise.' using errcode='42501';
  end if;
  if p_action='list' then
    return jsonb_build_object('funnels',coalesce((select jsonb_agg(row_to_json(x) order by x.updated_at desc) from
      (select f0.*, (select count(*) from public.korlix_funnel_leads l where l.funnel_id=f0.id) lead_count from public.korlix_funnels f0 where user_id=p_actor) x),'[]'::jsonb));
  elsif p_action='budget' then
    delete from public.korlix_funnel_usage where day<(now() at time zone 'UTC')::date-7;
    insert into public.korlix_funnel_usage(scope,n) values('ai:'||p_actor,1)
      on conflict(scope,day) do update set n=korlix_funnel_usage.n+1 returning korlix_funnel_usage.n into n;
    if n>10 then raise exception 'Your 10 daily NOVA funnel drafts have been used. You can still edit and publish manually.' using errcode='54000'; end if;
    return jsonb_build_object('remaining',10-n);
  elsif p_action='create' then
    perform pg_advisory_xact_lock(hashtextextended('funnels:'||p_actor,0));
    if (select count(*) from public.korlix_funnels where user_id=p_actor)>=50 then raise exception 'This workspace has reached its 50-funnel limit.' using errcode='54000'; end if;
    insert into public.korlix_funnels(user_id,name,slug,draft) values(p_actor,p_data->>'name',p_data->>'slug',p_data->'document') returning * into f;
    return to_jsonb(f);
  end if;
  select * into f from public.korlix_funnels where id=p_id and user_id=p_actor for update;
  if not found then raise exception 'Funnel not found.' using errcode='P0002'; end if;
  if p_action='leads' then
    return jsonb_build_object('leads',coalesce((select jsonb_agg(row_to_json(x) order by x.created_at desc) from
      (select * from public.korlix_funnel_leads where funnel_id=f.id order by created_at desc limit 100) x),'[]'::jsonb),
      'total',(select count(*) from public.korlix_funnel_leads where funnel_id=f.id),
      'campaigns',coalesce((select jsonb_agg(row_to_json(x)) from (select coalesce(nullif(utm->>'utm_source',''),'Direct / untagged') source,
        coalesce(nullif(utm->>'utm_campaign',''),'Untagged') campaign,count(*) leads from public.korlix_funnel_leads where funnel_id=f.id group by 1,2 order by 3 desc limit 50) x),'[]'::jsonb));
  end if;
  if (p_data->>'version')::integer is distinct from f.version then raise exception 'This funnel changed. Refresh and try again.' using errcode='40001'; end if;
  if p_action='save' then
    update public.korlix_funnels set name=p_data->>'name',draft=p_data->'document',version=version+1,updated_at=now() where id=f.id returning * into f;
  elsif p_action='publish' then
    if p_data->>'confirmed' is distinct from 'true' or nullif(f.draft->>'privacy_url','') is null or nullif(f.draft->>'contact_email','') is null then raise exception 'Review the page and complete publishing details.'; end if;
    update public.korlix_funnels set published=draft,published_version=version,state='published',version=version+1,published_at=now(),updated_at=now() where id=f.id returning * into f;
  elsif p_action='pause' then
    update public.korlix_funnels set state='paused',version=version+1,updated_at=now() where id=f.id returning * into f;
  else raise exception 'Unsupported funnel action.';
  end if;
  return to_jsonb(f);
end $$;
revoke all on function public.korlix_funnel_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_v1(uuid,text,uuid,jsonb) to service_role;
comment on function public.korlix_funnel_v1(uuid,text,uuid,jsonb) is 'Service-only funnel commands. Public actions return only the published document; owner actions require fresh Enterprise entitlement.';
commit;
