-- KORLIX Tax Prep: private organizers and reviewed snapshots of recorded books.
create table public.korlix_tax_workspaces (
 id uuid primary key,owner_id uuid not null references auth.users(id) on delete cascade,
 tax_year integer not null check(tax_year between 2000 and 2099),country text not null default 'US' check(country='US'),
 version integer not null default 1 check(version>0),business_ids uuid[] not null default '{}' check(cardinality(business_ids)<=25),
 data jsonb not null default '{}' check(jsonb_typeof(data)='object' and octet_length(data::text)<=262144),
 books jsonb not null default '[]' check(jsonb_typeof(books)='array' and octet_length(books::text)<=2097152),
 fingerprint text not null,snapshot_at timestamptz not null default now(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(owner_id,tax_year)
);
create table public.korlix_tax_requests (
 owner_id uuid not null references auth.users(id) on delete cascade,request_key uuid not null,
 workspace_id uuid not null references public.korlix_tax_workspaces(id) on delete cascade,
 action text not null,payload_hash text not null,result_version integer not null,created_at timestamptz not null default now(),primary key(owner_id,request_key)
);
create index korlix_tax_requests_workspace on public.korlix_tax_requests(workspace_id);
alter table public.korlix_tax_workspaces enable row level security;
alter table public.korlix_tax_requests enable row level security;
revoke all on public.korlix_tax_workspaces,public.korlix_tax_requests from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_tax_workspaces,public.korlix_tax_requests to service_role;
create function public.korlix_tax_books_v1(p_actor uuid,p_year integer,p_businesses uuid[]) returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare bid uuid;report jsonb;mileage jsonb;receipts jsonb;revision jsonb;books jsonb:='[]';item jsonb;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501';end if;
 if p_year not between 2000 and 2099 or p_businesses is null or cardinality(p_businesses)>25 or cardinality(p_businesses)<>(select count(distinct x) from unnest(p_businesses)x) then raise exception 'Choose valid businesses and a calendar year.';end if;
 -- Sorted business locks agree with the existing owner-scoped reporting/mutation locks.
 for bid in select unnest(p_businesses) order by 1 loop
  perform 1 from public.korlix_bookkeeping_businesses where id=bid and owner_id=p_actor for update;
  if not found then raise exception 'A linked business was not found.' using errcode='P0002';end if;
  report:=public.korlix_bookkeeping_reports_v1(p_actor,bid,jsonb_build_object('period',p_year::text));
  report:=report-'generated_at'-'lines';report:=jsonb_set(report,'{business}',(report->'business')-'owner_id');
  mileage:=public.korlix_bookkeeping_mileage_v1(p_actor,'list',bid,jsonb_build_object('period',p_year::text));
  select jsonb_build_object('expense_count',count(*),'without_receipt',count(*) filter(where not exists(select 1 from public.korlix_bookkeeping_receipt_links l where l.business_id=bid and l.entry_id=e.id and l.unlinked_at is null))) into receipts
   from public.korlix_bookkeeping_entries e where e.business_id=bid and e.kind='expense' and e.entry_date>=make_date(p_year,1,1) and e.entry_date<make_date(p_year+1,1,1) and not exists(select 1 from public.korlix_bookkeeping_entries rr where rr.reversal_of=e.id);
  select jsonb_build_object('events',count(*)::text,'last_event',max(created_at)) into revision from public.korlix_bookkeeping_audit where business_id=bid;
  item:=jsonb_build_object('report',report,'mileage',mileage->'summary','receipts',receipts,'revision',revision);
  books:=books||jsonb_build_array(item);
 end loop;
 return jsonb_build_object('books',books,'fingerprint',encode(sha256(convert_to(books::text,'UTF8')),'hex'));
end $$;
create function public.korlix_tax_prep_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare w public.korlix_tax_workspaces;request public.korlix_tax_requests;live jsonb;links uuid[];yr integer;k uuid;h text;review jsonb;reviews jsonb;book jsonb;account jsonb;bid text;code text;subreviews jsonb;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>280000 then raise exception 'Invalid tax preparation request.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text,226));
 if p_action='list' then
  return jsonb_build_object('workspaces',coalesce((select jsonb_agg(jsonb_build_object('id',id,'year',tax_year,'version',version,'businessCount',cardinality(business_ids),'updatedAt',updated_at) order by tax_year desc) from public.korlix_tax_workspaces where owner_id=p_actor),'[]'),
   'businesses',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'legal_structure',legal_structure,'tax_treatment',tax_treatment) order by name,id) from public.korlix_bookkeeping_businesses where owner_id=p_actor),'[]'));
 end if;
 if p_action='create' then
  yr:=(p_data->>'year')::integer;if yr<2000 or yr>extract(year from current_date)::integer+1 then raise exception 'Choose an available calendar year.';end if;
  select * into w from public.korlix_tax_workspaces where owner_id=p_actor and tax_year=yr;
  if found then
   live:=public.korlix_tax_books_v1(p_actor,w.tax_year,w.business_ids);
   return jsonb_build_object('workspace',to_jsonb(w)-'owner_id','stale',w.fingerprint<>live->>'fingerprint','checkedAt',now());
  end if;
  select coalesce(array_agg(x::uuid order by x),'{}') into links from jsonb_array_elements_text(p_data->'business_ids')x;
  live:=public.korlix_tax_books_v1(p_actor,yr,links);
  insert into public.korlix_tax_workspaces(id,owner_id,tax_year,business_ids,data,books,fingerprint) values(p_id,p_actor,yr,links,p_data->'data',live->'books',live->>'fingerprint') returning * into w;
  return jsonb_build_object('workspace',to_jsonb(w)-'owner_id');
 end if;
 select * into w from public.korlix_tax_workspaces where id=p_id and owner_id=p_actor for update;
 if not found then raise exception 'Tax workspace not found.' using errcode='P0002';end if;
 if p_action='delete' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm before removing this organizer.';end if;
  if w.version<>(p_data->>'version')::integer then raise exception 'This organizer changed. Refresh before removing it.' using errcode='40001';end if;
  delete from public.korlix_tax_workspaces where id=w.id;return jsonb_build_object('deleted',true);
 end if;
 if p_action in ('get','export') then
  live:=public.korlix_tax_books_v1(p_actor,w.tax_year,w.business_ids);
  if p_action='export' and (w.version is distinct from (p_data->>'version')::integer or w.fingerprint is distinct from p_data->>'fingerprint' or w.fingerprint<>live->>'fingerprint') then raise exception 'The organizer or linked books changed. Refresh and review them before exporting.' using errcode='40001';end if;
  return jsonb_build_object('workspace',to_jsonb(w)-'owner_id','stale',w.fingerprint<>live->>'fingerprint','checkedAt',now());
 end if;
 if p_action not in ('save','books') then raise exception 'Unknown tax preparation action.';end if;
 k:=(p_data->>'request_key')::uuid;h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 select * into request from public.korlix_tax_requests where owner_id=p_actor and request_key=k;
 if found then
  if request.workspace_id<>w.id or request.action<>p_action or request.payload_hash<>h then raise exception 'Use a new request after changing the organizer.' using errcode='40001';end if;
  if request.result_version<>w.version then raise exception 'That change was saved earlier. Refresh to see the latest organizer.' using errcode='40001';end if;
  return jsonb_build_object('workspace',to_jsonb(w)-'owner_id','replayed',true);
 end if;
 if w.version is distinct from (p_data->>'version')::integer then raise exception 'This organizer changed in another session. Refresh before saving.' using errcode='40001';end if;
 if (select count(*) from public.korlix_tax_requests where workspace_id=w.id)>=2000 then raise exception 'This organizer reached its saved-change limit.' using errcode='54000';end if;
 if p_action='save' then
  if jsonb_typeof(p_data->'data') is distinct from 'object' then raise exception 'Invalid organizer.';end if;
  update public.korlix_tax_workspaces set data=p_data->'data',version=version+1,updated_at=now() where id=w.id returning * into w;
 else
  select coalesce(array_agg(x::uuid order by x),'{}') into links from jsonb_array_elements_text(p_data->'business_ids')x;
  live:=public.korlix_tax_books_v1(p_actor,w.tax_year,links);
  -- Keep notes for remaining accounts but clear review marks when source changes.
  reviews:='{}';
  for book in select value from jsonb_array_elements(live->'books') loop
   bid:=book->'report'->'business'->>'id';subreviews:='{}';
   for account in select value from jsonb_array_elements(book->'report'->'accounts') loop
    code:=account->>'code';review:=w.data->'reviews'->bid->code;
    if review is not null then subreviews:=subreviews||jsonb_build_object(code,jsonb_build_object('status','pending','note',coalesce(review->>'note','')));end if;
   end loop;
   reviews:=reviews||jsonb_build_object(bid,subreviews);
  end loop;
  update public.korlix_tax_workspaces set business_ids=links,books=live->'books',fingerprint=live->>'fingerprint',snapshot_at=now(),data=jsonb_set(data,'{reviews}',case when fingerprint=live->>'fingerprint' then data->'reviews' else reviews end),version=version+1,updated_at=now() where id=w.id returning * into w;
 end if;
 insert into public.korlix_tax_requests(owner_id,request_key,workspace_id,action,payload_hash,result_version) values(p_actor,k,w.id,p_action,h,w.version);
 return jsonb_build_object('workspace',to_jsonb(w)-'owner_id');
end $$;
revoke all on function public.korlix_tax_books_v1(uuid,integer,uuid[]),public.korlix_tax_prep_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_tax_books_v1(uuid,integer,uuid[]),public.korlix_tax_prep_v1(uuid,text,uuid,jsonb) to service_role;
