begin;

create table public.korlix_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  email text check (email is null or length(email) <= 254),
  phone text check (phone is null or length(phone) <= 60),
  phone_key text check (phone_key is null or phone_key ~ '^[0-9]{7,15}$'),
  category text not null default 'unknown' check (category in ('friend','family','customer','unknown','lead','partner','vendor')),
  source text not null default 'manual' check (source in ('manual','phone','email','facebook','spreadsheet')),
  company text not null default '' check (length(company) <= 160),
  notes text not null default '' check (length(notes) <= 4000),
  tags text[] not null default '{}' check (cardinality(tags) <= 12),
  favorite boolean not null default false,
  follow_up_on date,
  email_permission text not null default 'none' check (email_permission in ('none','transactional','marketing','blocked')),
  call_permission text not null default 'none' check (call_permission in ('none','allowed','blocked')),
  consent_at timestamptz,
  do_not_contact boolean not null default false,
  call_brief text not null default '' check (length(call_brief) <= 2000),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  check (email_permission <> 'marketing' or consent_at is not null)
);
create unique index korlix_contacts_email_unique on public.korlix_contacts (user_id,lower(email)) where email is not null and archived_at is null;
create unique index korlix_contacts_phone_unique on public.korlix_contacts (user_id,phone_key) where phone_key is not null and archived_at is null;
create unique index korlix_contacts_name_only_unique on public.korlix_contacts (user_id,lower(name),source) where email is null and phone_key is null and archived_at is null;
create index korlix_contacts_owner_name on public.korlix_contacts (user_id,name,id) where archived_at is null;
create index korlix_contacts_email_guard on public.korlix_contacts (user_id,lower(email));
create index korlix_contacts_owner_followup on public.korlix_contacts (user_id,follow_up_on) where archived_at is null;
alter table public.korlix_contacts enable row level security;
revoke all on public.korlix_contacts from public, anon, authenticated;
grant select,insert,update,delete on public.korlix_contacts to service_role;
comment on table public.korlix_contacts is 'Enterprise CRM. Server-only API checks current user_profiles.tier and scopes every operation by verified user ID.';

create function public.korlix_contacts_import_v1(p_user_id uuid,p_contacts jsonb)
returns jsonb language plpgsql security invoker set search_path = public, pg_temp as $$
declare c jsonb; imported integer := 0; duplicates integer := 0;
begin
  if not exists (select 1 from public.user_profiles where id=p_user_id and lower(trim(tier))='enterprise') then
    raise exception 'Enterprise required' using errcode='42501';
  end if;
  if jsonb_typeof(p_contacts) is distinct from 'array' then raise exception 'Invalid contact array'; end if;
  if jsonb_array_length(p_contacts) not between 1 and 1000 then raise exception 'Import must contain 1 to 1000 contacts'; end if;
  for c in select value from jsonb_array_elements(p_contacts) loop
    begin
      insert into public.korlix_contacts(user_id,name,email,phone,phone_key,category,source,company,notes,tags,follow_up_on,call_brief)
      values(p_user_id,c->>'name',nullif(lower(c->>'email'),''),nullif(c->>'phone',''),nullif(c->>'phone_key',''),
        coalesce(c->>'category','unknown'),coalesce(c->>'source','manual'),coalesce(c->>'company',''),coalesce(c->>'notes',''),
        array(select jsonb_array_elements_text(coalesce(c->'tags','[]'::jsonb))),nullif(c->>'follow_up_on','')::date,coalesce(c->>'call_brief',''));
      imported := imported + 1;
    exception when unique_violation then duplicates := duplicates + 1;
    end;
  end loop;
  return jsonb_build_object('imported',imported,'duplicates',duplicates);
end $$;
revoke all on function public.korlix_contacts_import_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_contacts_import_v1(uuid,jsonb) to service_role;

-- Existing autonomous delivery checks recipient status. CRM permission removal
-- suppresses the same recipient rather than only hiding a client-side button.
create function public.korlix_contacts_suppress_email_v1() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if tg_op='INSERT' then
    if new.email is not null and (new.do_not_contact or new.email_permission='blocked') then
      update public.korlix_agent_email_recipients set active=false,consent_status='suppressed',
        suppressed_at=now(),suppression_reason='crm_contact_permission_removed',updated_at=now()
        where user_id=new.user_id and lower(email)=lower(new.email) and consent_status <> 'unsubscribed';
    end if;
    return new;
  end if;
  if old.email is not null and (new.do_not_contact or new.archived_at is not null
    or new.email_permission='blocked' or (new.email_permission='none' and old.email_permission <> 'none') or old.email is distinct from new.email) then
    update public.korlix_agent_email_recipients set active=false,consent_status='suppressed',
      suppressed_at=now(),suppression_reason='crm_contact_permission_removed',updated_at=now()
      where user_id=old.user_id and lower(email)=lower(old.email) and consent_status <> 'unsubscribed';
  elsif new.email_permission='transactional' and old.email_permission='marketing' then
    update public.korlix_agent_email_recipients set consent_status='transactional_only',updated_at=now()
      where user_id=new.user_id and lower(email)=lower(new.email) and consent_status='marketing_opt_in';
  end if;
  return new;
end $$;
create trigger korlix_contacts_suppress_email after insert or update on public.korlix_contacts
for each row execute function public.korlix_contacts_suppress_email_v1();

-- Prevent a concurrent link/reactivation from bypassing a CRM permission change.
create function public.korlix_contacts_guard_email_v1() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare c public.korlix_contacts;
begin
  if new.active and new.consent_status in ('transactional_only','marketing_opt_in') then
    for c in select * from public.korlix_contacts where user_id=new.user_id
      and lower(email)=lower(new.email) for update loop
      if c.do_not_contact or c.archived_at is not null or c.email_permission='blocked'
        or (new.source_reference='crm:' || c.id::text and (c.email_permission='none'
          or (new.consent_status='marketing_opt_in' and c.email_permission <> 'marketing'))) then
        raise exception 'CRM contact does not permit this email activity' using errcode='42501';
      end if;
    end loop;
  end if;
  return new;
end $$;
create trigger korlix_contacts_guard_email before insert or update on public.korlix_agent_email_recipients
for each row execute function public.korlix_contacts_guard_email_v1();
revoke all on function public.korlix_contacts_suppress_email_v1() from public,anon,authenticated;
revoke all on function public.korlix_contacts_guard_email_v1() from public,anon,authenticated;
commit;
