begin;
create table public.korlix_funnels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check(length(name) between 1 and 100),
  slug text not null unique check(slug ~ '^[a-z0-9][a-z0-9-]{2,59}$'),
  draft jsonb not null check(jsonb_typeof(draft)='object' and octet_length(draft::text)<18000),
  published jsonb,
  state text not null default 'draft' check(state in ('draft','published','paused')),
  version integer not null default 1,
  published_version integer,
  page_requests bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  check(state<>'published' or (published is not null and published_version is not null))
);
create index korlix_funnels_owner on public.korlix_funnels(user_id,updated_at desc);
create table public.korlix_funnel_leads (
  id uuid primary key default gen_random_uuid(),
  funnel_id uuid not null references public.korlix_funnels(id) on delete cascade,
  request_id uuid not null,
  published_version integer not null,
  contact_id uuid references public.korlix_contacts(id) on delete set null,
  name text not null check(length(name) between 1 and 160),
  email text not null check(length(email) between 3 and 254),
  phone text not null default '' check(length(phone)<=60),
  message text not null default '' check(length(message)<=2000),
  utm jsonb not null default '{}' check(octet_length(utm::text)<2000),
  consent_text text not null,
  created_at timestamptz not null default now(),
  unique(funnel_id,request_id)
);
create index korlix_funnel_leads_recent on public.korlix_funnel_leads(funnel_id,created_at desc);
create index korlix_funnel_leads_contact on public.korlix_funnel_leads(contact_id);
create table public.korlix_funnel_usage (
  scope text not null,
  day date not null default (now() at time zone 'UTC')::date,
  n integer not null default 1,
  primary key(scope,day)
);
alter table public.korlix_funnels enable row level security;
alter table public.korlix_funnel_leads enable row level security;
alter table public.korlix_funnel_usage enable row level security;
revoke all on public.korlix_funnels,public.korlix_funnel_leads,public.korlix_funnel_usage from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_funnels,public.korlix_funnel_leads,public.korlix_funnel_usage to service_role;
alter table public.korlix_contacts drop constraint korlix_contacts_source_check;
alter table public.korlix_contacts add constraint korlix_contacts_source_check check(source in ('manual','phone','email','facebook','spreadsheet','funnel'));

create function public.korlix_funnel_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}')
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
