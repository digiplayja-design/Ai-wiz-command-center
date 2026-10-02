-- KORLIX Business Directory. Private tables; only verified server routes call RPC.
create table public.korlix_directory_businesses (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 slug text not null unique, owner_name text not null default '', draft jsonb not null default '{}', published jsonb,
 state text not null default 'draft' check(state in ('draft','pending','published','needs_changes','hidden')),
 version integer not null default 1, review_note text not null default '', consent_at timestamptz,
 verification_state text not null default 'none' check(verification_state in ('none','pending','approved','needs_changes','revoked')),
 verification_note text not null default '', evidence_note text not null default '', checked_at timestamptz, checks jsonb not null default '[]',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(jsonb_typeof(draft)='object'), check(octet_length(draft::text)<40000)
);
create index korlix_directory_owner_idx on public.korlix_directory_businesses(owner_id,updated_at desc);
create index korlix_directory_review_idx on public.korlix_directory_businesses(state,updated_at);
create index korlix_directory_search_idx on public.korlix_directory_businesses using gin(to_tsvector('simple',coalesce(published->>'name','')||' '||coalesce(published->>'category','')||' '||coalesce(published->>'description','')||' '||coalesce(published->>'city','')||' '||coalesce(published->>'service_area',''))) where published is not null;
create table public.korlix_directory_assets (
 id uuid primary key, business_id uuid not null references public.korlix_directory_businesses(id) on delete cascade,
 purpose text not null check(purpose in ('photo','evidence')), path text not null unique, mime text not null, created_at timestamptz not null default now()
);
create index korlix_directory_assets_business_idx on public.korlix_directory_assets(business_id);
create table public.korlix_directory_memberships (
 business_id uuid primary key references public.korlix_directory_businesses(id) on delete cascade,
 generation uuid not null default gen_random_uuid(), interval text not null default 'month' check(interval in ('month','year')),
 checkout_id text unique, checkout_url text, checkout_expires timestamptz,
 customer_id text unique, subscription_id text unique, state text not null default 'none', paid_until timestamptz,
 invoice_id text, blocked_invoice text, livemode boolean not null default false, last_sync timestamptz, cancel_at_period_end boolean not null default false,
 updated_at timestamptz not null default now()
);
create table public.korlix_directory_reports (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.korlix_directory_businesses(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null, reason text not null check(length(reason) between 10 and 1000),
 resolved boolean not null default false, created_at timestamptz not null default now()
);
create index korlix_directory_reports_business_idx on public.korlix_directory_reports(business_id,resolved);
create table public.korlix_directory_audit (
 id bigint generated always as identity primary key, business_id uuid not null references public.korlix_directory_businesses(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null, action text not null, note text not null default '', created_at timestamptz not null default now()
);
create index korlix_directory_audit_business_idx on public.korlix_directory_audit(business_id,created_at desc);
create table public.korlix_directory_metrics (
 business_id uuid not null references public.korlix_directory_businesses(id) on delete cascade, day date not null default current_date,
 views integer not null default 0, contacts integer not null default 0, primary key(business_id,day)
);
DO $$ declare t text; begin
 foreach t in array array['businesses','assets','memberships','reports','audit','metrics'] loop
 execute format('alter table public.korlix_directory_%I enable row level security',t);
 execute format('revoke all on public.korlix_directory_%I from public,anon,authenticated',t);
 execute format('grant all on public.korlix_directory_%I to service_role',t);
 end loop;
end $$;
revoke all on sequence public.korlix_directory_audit_id_seq from public,anon,authenticated;
grant usage,select on sequence public.korlix_directory_audit_id_seq to service_role;

create function public.korlix_directory_card(b public.korlix_directory_businesses) returns jsonb
language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object('id',b.id,'slug',b.slug,'details', b.published - 'photos' - 'offer' || jsonb_build_object(
 'photos', coalesce((select jsonb_agg(x.value) from jsonb_array_elements(coalesce(b.published->'photos','[]')) with ordinality x(value,n) where x.n<=case when v.ok then 12 else 3 end),'[]'::jsonb),
 'offer',case when v.ok and coalesce(b.published->'offer'->>'expires','')>=current_date::text then b.published->'offer' else null end),
 'verified',v.ok,'verified_at',case when v.ok then b.checked_at else null end,'checks',case when v.ok then b.checks else '[]'::jsonb end)
 from (select b.verification_state='approved' and exists(select 1 from public.korlix_directory_memberships m where m.business_id=b.id and m.livemode and m.state='active' and m.paid_until>now() and m.blocked_invoice is null) as ok) v;
$$;
revoke all on function public.korlix_directory_card(public.korlix_directory_businesses) from public,anon,authenticated;
grant execute on function public.korlix_directory_card(public.korlix_directory_businesses) to service_role;

create function public.korlix_directory_command(p_actor uuid,p_admin boolean,p_action text,p_id uuid default null,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare b public.korlix_directory_businesses; m public.korlix_directory_memberships; result jsonb; n integer; entry jsonb; identity_changed boolean; aid uuid;
begin
 if p_action='browse' then
  select coalesce(jsonb_agg(public.korlix_directory_card(t)),'[]') into result from (
   select * from public.korlix_directory_businesses d where d.published is not null and d.state<>'hidden'
    and (not (p ? 'ids') or d.id::text in (select jsonb_array_elements_text(p->'ids')))
    and (coalesce(p->>'q','')='' or to_tsvector('simple',coalesce(d.published->>'name','')||' '||coalesce(d.published->>'category','')||' '||coalesce(d.published->>'description','')||' '||coalesce(d.published->>'city','')||' '||coalesce(d.published->>'service_area','')) @@ plainto_tsquery('simple',p->>'q'))
    and (coalesce(p->>'category','')='' or d.published->>'category'=p->>'category')
    and (coalesce(p->>'city','')='' or position(lower(p->>'city') in lower(coalesce(d.published->>'city','')||' '||coalesce(d.published->>'service_area','')||' '||coalesce(d.published->>'country','')))>0)
   order by d.created_at desc,d.id limit 25 offset least(greatest(coalesce((p->>'offset')::int,0),0),10000)
  ) t;
  return jsonb_build_object('businesses',result);
 end if;
 if p_action='public' then
  select * into b from public.korlix_directory_businesses where (id=p_id or slug=p->>'slug') and published is not null and state<>'hidden';
  if not found then raise exception 'DIR404: Business not found.'; end if;
  return public.korlix_directory_card(b);
 end if;
 if p_action='metrics' then
  if not exists(select 1 from public.korlix_directory_businesses where id=p_id and published is not null and state<>'hidden') then raise exception 'DIR404: Business not found.'; end if;
  insert into public.korlix_directory_metrics(business_id,views,contacts) values(p_id,case when p->>'kind'='view' then 1 else 0 end,case when p->>'kind'='contact' then 1 else 0 end)
  on conflict(business_id,day) do update set views=korlix_directory_metrics.views+excluded.views,contacts=korlix_directory_metrics.contacts+excluded.contacts;
  return '{"ok":true}';
 end if;
 if p_action='report' then
  if not exists(select 1 from public.korlix_directory_businesses where id=p_id and published is not null and state<>'hidden') then raise exception 'DIR404: Business not found.'; end if;
  insert into public.korlix_directory_reports(business_id,actor_id,reason) values(p_id,p_actor,p->>'reason'); return '{"ok":true}';
 end if;
 if p_action='billing_lookup' then
  select * into m from public.korlix_directory_memberships where subscription_id=p->>'subscription_id' or customer_id=p->>'customer_id';
  return coalesce(to_jsonb(m),'null');
 end if;
 if p_action='billing_apply' or p_action='billing_hold' then
  select * into m from public.korlix_directory_memberships where business_id=p_id for update;
  if not found then raise exception 'DIR404: Membership not found.'; end if;
  if p_action='billing_apply' and m.last_sync is not null and (p->>'observed_at')::timestamptz<m.last_sync then return '{"ok":true,"stale":true}'; end if;
  if p_action='billing_hold' then
   if m.customer_id<>p->>'customer_id' then raise exception 'DIR409: Membership changed.'; end if;
   update public.korlix_directory_memberships set blocked_invoice=coalesce(invoice_id,'hold'),state='suspended',last_sync=now(),updated_at=now() where business_id=p_id;
  else
   if m.livemode is distinct from coalesce((p->>'livemode')::boolean,false) or m.generation<>(p->>'generation')::uuid or (m.subscription_id is not null and m.subscription_id<>p->>'subscription_id') then raise exception 'DIR409: Membership changed.'; end if;
   update public.korlix_directory_memberships set subscription_id=p->>'subscription_id',customer_id=p->>'customer_id',state=p->>'state',paid_until=(p->>'paid_until')::timestamptz,invoice_id=p->>'invoice_id',
    blocked_invoice=case when blocked_invoice is not null and p->>'state'='active' and invoice_id is distinct from p->>'invoice_id' then null else blocked_invoice end,
    cancel_at_period_end=coalesce((p->>'cancel_at_period_end')::boolean,false),last_sync=coalesce((p->>'observed_at')::timestamptz,now()),updated_at=now() where business_id=p_id;
  end if;
  return '{"ok":true}';
 end if;
 if p_actor is null then raise exception 'DIR401: Sign in to manage your business.'; end if;
 if p_action='mine' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.updated_at desc),'[]') into result from public.korlix_directory_businesses t where owner_id=p_actor;
  return jsonb_build_object('businesses',result);
 end if;
 if p_action='admin_queue' then
  if not p_admin then raise exception 'DIR403: Directory administrator access required.'; end if;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (select d.id,d.slug,d.draft->>'name' as name,d.state,d.version,d.verification_state,d.updated_at,(select count(*) from public.korlix_directory_reports r where r.business_id=d.id and not r.resolved) as reports from public.korlix_directory_businesses d where (coalesce(p->>'q','')<>'' and position(lower(p->>'q') in lower(coalesce(d.draft->>'name','')||' '||d.slug))>0) or (coalesce(p->>'q','')='' and (d.state='pending' or d.verification_state='pending' or exists(select 1 from public.korlix_directory_reports r where r.business_id=d.id and not r.resolved))) order by d.updated_at limit 100) t;
  return jsonb_build_object('businesses',result);
 end if;
 if p_action='create' then
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,172));
  if (select count(*) from public.korlix_directory_businesses where owner_id=p_actor)>=10 then raise exception 'DIR409: You can manage up to 10 locations.'; end if;
  aid=gen_random_uuid();
  insert into public.korlix_directory_businesses(id,owner_id,slug,draft,owner_name) values(aid,p_actor,coalesce(nullif(p->>'slug',''),'business')||'-'||aid::text,p->'details',p->>'owner_name') returning * into b;
  return to_jsonb(b);
 end if;
 select * into b from public.korlix_directory_businesses where id=p_id for update;
 if not found then raise exception 'DIR404: Business not found.'; end if;
 if b.owner_id<>p_actor and not p_admin then raise exception 'DIR403: This business belongs to another account.'; end if;
 if p_action='get' then
  return jsonb_build_object('business',to_jsonb(b),'membership',coalesce((select to_jsonb(t) - 'checkout_url' from public.korlix_directory_memberships t where business_id=p_id),'{}'),
   'assets',coalesce((select jsonb_agg(to_jsonb(a)-'path' order by a.created_at,a.id) from public.korlix_directory_assets a where business_id=p_id),'[]'),
   'metrics',case when (public.korlix_directory_card(b)->>'verified')::boolean then coalesce((select jsonb_agg(to_jsonb(t)) from public.korlix_directory_metrics t where business_id=p_id and day>=current_date-30),'[]') else '[]'::jsonb end,
   'reports',case when p_admin then coalesce((select jsonb_agg(to_jsonb(r)) from public.korlix_directory_reports r where business_id=p_id and not resolved),'[]') else '[]'::jsonb end);
 end if;
 if p_action='asset' then
  select count(*) into n from public.korlix_directory_assets where business_id=p_id and purpose=p->>'purpose';
  if n>=(case when p->>'purpose'='evidence' then 5 else 20 end) then raise exception 'DIR409: Upload limit reached. Remove unused files first.'; end if;
  insert into public.korlix_directory_assets(id,business_id,purpose,path,mime) values((p->>'id')::uuid,p_id,p->>'purpose',p->>'path',p->>'mime');
  return '{"ok":true}';
 end if;
 if p_action='asset_remove' then
  if b.owner_id<>p_actor then raise exception 'DIR403: Owner access required.'; end if;
  aid=(p->>'id')::uuid;
  if coalesce(b.draft->'photos','[]') ? aid::text or coalesce(b.published->'photos','[]') ? aid::text then raise exception 'DIR409: Remove this photo from your draft and approved listing before deleting the file.'; end if;
  delete from public.korlix_directory_assets where business_id=p_id and id=aid returning to_jsonb(korlix_directory_assets) into result;
  if result is null then raise exception 'DIR404: File not found.'; end if;
  if result->>'purpose'='evidence' then
   update public.korlix_directory_businesses set verification_state=case when verification_state in ('approved','pending') then 'needs_changes' else verification_state end,version=version+1,updated_at=now() where id=p_id;
  end if;
  return result;
 end if;
 if p_action='asset_get' then
  select to_jsonb(a) into result from public.korlix_directory_assets a where business_id=p_id and id=(p->>'id')::uuid;
  if result is null then raise exception 'DIR404: File not found.'; end if; return result;
 end if;
 if p_action='checkout_start' then
  if b.owner_id<>p_actor then raise exception 'DIR403: Only the owner can manage payment.'; end if;
  if b.verification_state<>'approved' or b.published is null or b.state='hidden' then raise exception 'DIR409: Complete the listing and verification reviews before subscribing.'; end if;
  insert into public.korlix_directory_memberships(business_id) values(p_id) on conflict do nothing;
  select * into m from public.korlix_directory_memberships where business_id=p_id for update;
  if m.subscription_id is not null and m.state not in ('canceled','incomplete_expired') then raise exception 'DIR409: A membership already exists. Manage or refresh it instead.'; end if;
  if m.checkout_expires>now() then
   if m.interval<>p->>'interval' then raise exception 'DIR409: A checkout with a different billing interval is already open. Complete it or wait for it to expire.'; end if;
   return to_jsonb(m); end if;
  if m.state='checkout' and m.checkout_expires is not null and coalesce(p->>'expired_generation','')<>m.generation::text then raise exception 'DIR409: Previous checkout must be reconciled before starting another.'; end if;
  update public.korlix_directory_memberships set generation=gen_random_uuid(),interval=p->>'interval',checkout_id=null,checkout_url=null,checkout_expires=now()+interval '1 hour',subscription_id=null,customer_id=null,state='checkout',paid_until=null,invoice_id=null,blocked_invoice=null,livemode=coalesce((p->>'livemode')::boolean,false),last_sync=null,updated_at=now() where business_id=p_id returning * into m;
  return to_jsonb(m);
 end if;
 if p_action='checkout_saved' then
  update public.korlix_directory_memberships set checkout_id=p->>'checkout_id',checkout_url=p->>'checkout_url' where business_id=p_id and generation=(p->>'generation')::uuid;
  if not found then raise exception 'DIR409: Checkout changed. Refresh and retry.'; end if; return '{"ok":true}';
 end if;
 if p_action='verification_submit' then
  if b.owner_id<>p_actor then raise exception 'DIR403: Owner access required.'; end if;
  if length(p->>'evidence_note')<20 then raise exception 'DIR400: Explain how you own or represent this business.'; end if;
  update public.korlix_directory_businesses set verification_state='pending',evidence_note=p->>'evidence_note',verification_note='',version=version+1,updated_at=now() where id=p_id returning * into b;
 elsif p_action in ('save','submit') then
  if b.owner_id<>p_actor then raise exception 'DIR403: Owner access required.'; end if;
  if b.version<>(p->>'version')::int then raise exception 'DIR409: This listing changed. Refresh before saving.'; end if;
  for entry in select value from jsonb_array_elements(coalesce(p->'details'->'photos','[]')) loop
   if not exists(select 1 from public.korlix_directory_assets where id=(entry#>>'{}')::uuid and business_id=p_id and purpose='photo') then raise exception 'DIR400: Choose photos uploaded to this business.'; end if;
  end loop;
  identity_changed = exists(select 1 from unnest(array['name','phone','email','address','city','country','service_area','website']) k where b.draft->>k is distinct from p->'details'->>k) or b.owner_name is distinct from p->>'owner_name';
  if p_action='submit' and coalesce((p->>'consent')::boolean,false)<>true then raise exception 'DIR400: Confirm the public listing preview before submitting.'; end if;
  update public.korlix_directory_businesses set draft=p->'details',owner_name=p->>'owner_name',state=case when p_action='submit' then 'pending' when state='pending' then 'draft' else state end,
   consent_at=case when p_action='submit' then now() else consent_at end,verification_state=case when identity_changed and verification_state='approved' then 'needs_changes' else verification_state end,
   version=version+1,updated_at=now() where id=p_id returning * into b;
 elsif p_action='hide' then
  update public.korlix_directory_businesses set state='hidden',published=null,version=version+1,updated_at=now() where id=p_id returning * into b;
 elsif p_action in ('review','verification_review','resolve_reports') then
  if not p_admin then raise exception 'DIR403: Directory administrator access required.'; end if;
  if b.version<>(p->>'version')::int then raise exception 'DIR409: This listing changed. Refresh before reviewing.'; end if;
  if length(coalesce(p->>'note',''))<5 then raise exception 'DIR400: Add a review note.'; end if;
  if p_action='review' then
   if p->>'decision'='approve' then
    if b.state<>'pending' or b.consent_at is null then raise exception 'DIR409: The owner must submit this version first.'; end if;
    update public.korlix_directory_businesses set published=draft,state='published',review_note=p->>'note',version=version+1,updated_at=now() where id=p_id returning * into b;
   elsif p->>'decision'='hide' then
    update public.korlix_directory_businesses set published=null,state='hidden',review_note=p->>'note',version=version+1,updated_at=now() where id=p_id returning * into b;
   else
    update public.korlix_directory_businesses set state='needs_changes',review_note=p->>'note',version=version+1,updated_at=now() where id=p_id returning * into b;
   end if;
  elsif p_action='verification_review' then
   if p->>'decision'='approve' and (b.verification_state<>'pending' or p->'checks' @> '["email","phone","ownership"]'::jsonb is not true) then raise exception 'DIR400: Complete and document email, phone and ownership checks first.'; end if;
   update public.korlix_directory_businesses set verification_state=case p->>'decision' when 'approve' then 'approved' when 'revoke' then 'revoked' else 'needs_changes' end,
    checks=case when p->>'decision'='approve' then p->'checks' else '[]'::jsonb end,checked_at=case when p->>'decision'='approve' then now() else null end,verification_note=p->>'note',version=version+1,updated_at=now() where id=p_id returning * into b;
  else
   update public.korlix_directory_reports set resolved=true where business_id=p_id;
  end if;
  insert into public.korlix_directory_audit(business_id,actor_id,action,note) values(p_id,p_actor,p_action||':'||coalesce(p->>'decision',''),p->>'note');
 else raise exception 'DIR400: Unsupported directory action.';
 end if;
 return to_jsonb(b);
end $$;
revoke all on function public.korlix_directory_command(uuid,boolean,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_directory_command(uuid,boolean,text,uuid,jsonb) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('korlix-directory','korlix-directory',false,5242880,array['image/jpeg','application/pdf']) on conflict(id) do nothing;
notify pgrst,'reload schema';
