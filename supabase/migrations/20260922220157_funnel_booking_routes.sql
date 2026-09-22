begin;
do $$ begin
 if (select md5(prosrc) from pg_proc where oid='public.korlix_funnel_v1(uuid,text,uuid,jsonb)'::regprocedure) is distinct from 'a5ccdff3945815fd62cb96fae0fff2e7' then
  raise exception 'The capture function changed. Review K155 before applying.';
 end if;
end $$;
-- Additive private snapshots. Historical leads have no inferred booking outcome.
alter table public.korlix_funnel_leads add column outcome jsonb not null default '{}'
 check(jsonb_typeof(outcome)='object' and octet_length(outcome::text)<=8000);

create function public.korlix_funnel_outcome_v1(p_document jsonb,p_answers jsonb)
returns jsonb language plpgsql immutable security invoker set search_path=public,pg_temp as $$
declare routes jsonb:=coalesce(p_document->'booking_routes','[]'); r jsonb; q jsonb;
 active jsonb; picked jsonb; ids text[]:='{}'; conditions jsonb:='[]'; condition jsonb;
 destination text; result jsonb;
begin
 -- Revalidate active answers so a hidden conditional answer can never route.
 active:=public.korlix_funnel_answers_v1(p_document,p_answers);
 if jsonb_typeof(routes) is distinct from 'array' then raise exception 'Check the booking routes.'; end if;
 if jsonb_array_length(routes)>4 then raise exception 'Use up to four booking routes.'; end if;
 for r in select value from jsonb_array_elements(routes) loop
  if jsonb_typeof(r) is distinct from 'object' or jsonb_typeof(r->'id') is distinct from 'string'
   or r->>'id' !~ '^route-[1-4]$' or r->>'id'=any(ids)
   or jsonb_typeof(r->'name') is distinct from 'string' or length(trim(r->>'name')) not between 1 and 80
   or jsonb_typeof(r->'question_id') is distinct from 'string'
   or jsonb_typeof(r->'equals') is distinct from 'string' or length(trim(r->>'equals')) not between 1 and 80
   or jsonb_typeof(r->'url') is distinct from 'string' or length(r->>'url') not between 1 and 1000
   or jsonb_typeof(r->'button_label') is distinct from 'string' or length(trim(r->>'button_label')) not between 1 and 60
   then raise exception 'Complete the booking routes before publishing.'; end if;
  ids:=array_append(ids,r->>'id');
  condition:=jsonb_build_object('question_id',r->>'question_id','equals',r->>'equals');
  if conditions @> jsonb_build_array(condition) then raise exception 'Use each booking answer condition once.'; end if;
  conditions:=conditions||jsonb_build_array(condition);
  select value into q from jsonb_array_elements(coalesce(p_document->'questions','[]')) where value->>'id'=r->>'question_id';
  if q is null or q->>'type'<>'choice' or not exists(select 1 from jsonb_array_elements_text(q->'options') o where o=r->>'equals') then raise exception 'Choose a current multiple-choice answer for each booking route.'; end if;
  if r->>'url' !~ '^https://[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+(:[0-9]+)?([/?#][^[:space:]]*)?$'
   or r->>'url' ~ '^https://(localhost|127\.|0\.|169\.254\.)' then raise exception 'Enter a public HTTPS booking address.'; end if;
  if picked is null and exists(select 1 from jsonb_array_elements(active) a where a->>'id'=r->>'question_id' and a->>'value'=r->>'equals') then picked:=r; end if;
 end loop;
 destination:=coalesce(picked->>'url',p_document->>'booking_url','');
 if destination<>'' and (length(destination)>1000 or destination !~ '^https://[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+(:[0-9]+)?([/?#][^[:space:]]*)?$') then raise exception 'Enter a public HTTPS booking address.'; end if;
 result:=jsonb_build_object('route_id',coalesce(picked->>'id','default'),'route_name',coalesce(picked->>'name','Default next step'),
  'message',coalesce(p_document->>'thank_you','Thank you.'),'booking_url',destination,'button_label',coalesce(picked->>'button_label','Continue →'));
 return result;
end $$;
revoke all on function public.korlix_funnel_outcome_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_funnel_outcome_v1(jsonb,jsonb) to service_role;

-- Preserve the capture transaction, replay suppression, consent, and limits.
create or replace function public.korlix_funnel_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare f public.korlix_funnels; c public.korlix_contacts; n integer; out jsonb; requested uuid; enterprise boolean; answer_snapshot jsonb; outcome_snapshot jsonb;
begin
  if p_action in ('public','lead','receipt') then
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
    if p_action='receipt' then
      select outcome into out from public.korlix_funnel_leads
        where funnel_id=f.id and request_id=(p_data->>'request_id')::uuid;
      if out is null or out='{}'::jsonb then return null; end if;
      -- Return only the saved visitor-facing receipt, never contacts or answers.
      return jsonb_build_object('message',out->>'message','booking_url',out->>'booking_url','button_label',out->>'button_label');
    end if;
    if (p_data->>'published_version')::integer is distinct from f.published_version then
      raise exception 'This page changed. Reload before submitting.' using errcode='40001';
    end if;
    requested := (p_data->>'request_id')::uuid;
    if exists(select 1 from public.korlix_funnel_removed_requests where funnel_id=f.id and request_id=requested and expires_at>=now()) then return jsonb_build_object('received',true); end if;
    delete from public.korlix_funnel_removed_requests where funnel_id=f.id and expires_at<now();
    if exists(select 1 from public.korlix_funnel_leads where funnel_id=f.id and request_id=requested) then return jsonb_build_object('received',true); end if;
    answer_snapshot:=public.korlix_funnel_answers_v1(f.published,p_data->'answers');
    outcome_snapshot:=public.korlix_funnel_outcome_v1(f.published,answer_snapshot);
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
    insert into public.korlix_funnel_leads(funnel_id,request_id,published_version,contact_id,name,email,phone,message,utm,consent_text,answers,outcome)
      values(f.id,requested,f.published_version,c.id,p_data->>'name',lower(p_data->>'email'),coalesce(p_data->>'phone',''),coalesce(p_data->>'message',''),
        coalesce(p_data->'utm','{}'),'I agree that '||(f.published->>'brand')||' may contact me about this request. This does not subscribe me to marketing messages.',answer_snapshot,outcome_snapshot);
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
comment on function public.korlix_funnel_v1(uuid,text,uuid,jsonb) is 'Service-only funnel commands. Public actions return the published document or a minimal saved receipt; owner actions require fresh Enterprise entitlement.';
commit;
