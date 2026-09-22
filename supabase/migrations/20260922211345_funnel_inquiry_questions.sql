begin;
-- Refuse to overwrite an intervening capture-function change.
do $$ begin
 if (select md5(prosrc) from pg_proc where oid='public.korlix_funnel_v1(uuid,text,uuid,jsonb)'::regprocedure) is distinct from '1b6cbeffb7ab1017ca420380d7f21272' then
  raise exception 'The capture function changed. Review K153 against its current definition before applying.';
 end if;
end $$;
-- Additive, private answer snapshots. Existing inquiries keep an empty array.
alter table public.korlix_funnel_leads add column answers jsonb not null default '[]'
 check(jsonb_typeof(answers)='array' and jsonb_array_length(answers)<=4 and octet_length(answers::text)<=12000);

create function public.korlix_funnel_answers_v1(p_document jsonb,p_answers jsonb)
returns jsonb language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare qs jsonb:=coalesce(p_document->'questions','[]'); supplied jsonb:=coalesce(p_answers,'[]');
 q jsonb; a jsonb; v text; result jsonb:='[]'; seen text[]:='{}';
begin
 if jsonb_typeof(qs) is distinct from 'array' or jsonb_typeof(supplied) is distinct from 'array' then raise exception 'Check the inquiry answers.'; end if;
 if jsonb_array_length(qs)>4 or jsonb_array_length(supplied)<>jsonb_array_length(qs) then raise exception 'Complete the inquiry questions.'; end if;
 for q in select value from jsonb_array_elements(qs) loop
  if jsonb_typeof(q) is distinct from 'object' or jsonb_typeof(q->'id') is distinct from 'string'
    or q->>'id' !~ '^q-[1-4]$' or q->>'id'=any(seen)
    or coalesce(q->>'type','') not in ('text','choice') or jsonb_typeof(q->'required') is distinct from 'boolean'
    or jsonb_typeof(q->'label') is distinct from 'string' or length(trim(q->>'label')) not between 1 and 120
    or (q->>'label') ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' then raise exception 'This form needs its questions completed.'; end if;
  seen:=array_append(seen,q->>'id');
  if (select count(*) from jsonb_array_elements(supplied) x where x->>'id'=q->>'id')<>1 then raise exception 'Check the inquiry answers.'; end if;
  select value into a from jsonb_array_elements(supplied) where value->>'id'=q->>'id';
  if jsonb_typeof(a->'value') is distinct from 'string' then raise exception 'Check the inquiry answers.'; end if;
  v:=trim(a->>'value');
  if length(v)>(case when q->>'type'='choice' then 80 else 500 end)
    or v ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' or ((q->>'required')::boolean and v='') then raise exception 'Complete the required inquiry answers.'; end if;
  if q->>'type'='choice' then
   if jsonb_typeof(q->'options') is distinct from 'array' then raise exception 'Check the question choices.'; end if;
   if jsonb_array_length(q->'options') not between 2 and 8
    or exists(select 1 from jsonb_array_elements(q->'options') x where jsonb_typeof(x) is distinct from 'string' or length(trim(x#>>'{}')) not between 1 and 80)
    or (select count(distinct value) from jsonb_array_elements(q->'options'))<>jsonb_array_length(q->'options') then raise exception 'Check the question choices.'; end if;
   if v<>'' and not exists(select 1 from jsonb_array_elements_text(q->'options') o where o=v) then raise exception 'Choose one of the listed answers.'; end if;
  end if;
  -- Labels and types come only from the locked published document, never the visitor.
  result:=result||jsonb_build_array(jsonb_build_object('id',q->>'id','label',q->>'label','type',q->>'type','value',v));
 end loop;
 return result;
end $$;
revoke all on function public.korlix_funnel_answers_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_answers_v1(jsonb,jsonb) to service_role;

-- Keep K149 replay, ownership, limits and capture transaction unchanged.
create or replace function public.korlix_funnel_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_contacts; n integer; out jsonb; requested uuid; enterprise boolean; answer_snapshot jsonb;
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
    answer_snapshot:=public.korlix_funnel_answers_v1(f.published,p_data->'answers');
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
    insert into public.korlix_funnel_leads(funnel_id,request_id,published_version,contact_id,name,email,phone,message,utm,consent_text,answers)
      values(f.id,requested,f.published_version,c.id,p_data->>'name',lower(p_data->>'email'),coalesce(p_data->>'phone',''),coalesce(p_data->>'message',''),
        coalesce(p_data->'utm','{}'),'I agree that '||(f.published->>'brand')||' may contact me about this request. This does not subscribe me to marketing messages.',answer_snapshot);
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
