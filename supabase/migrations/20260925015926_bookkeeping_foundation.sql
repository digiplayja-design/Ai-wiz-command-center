-- K198: manual USD cash activity. Each immutable entry contains exactly two
-- equal legs, so an unbalanced or partly written journal cannot be stored.
create table public.korlix_bookkeeping_businesses (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 name text not null check(length(btrim(name)) between 1 and 120),
 legal_structure text not null check(legal_structure in ('sole_proprietor','llc','corporation','partnership','other')),
 tax_treatment text not null check(tax_treatment in ('sole_proprietor','partnership','c_corporation','s_corporation','unsure')),
 contractor_income boolean not null default false,
 currency text not null default 'USD' check(currency='USD'),
 basis text not null default 'cash' check(basis='cash'),
 version integer not null default 1 check(version>0),
 request_key uuid not null,
 creation_request jsonb not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(owner_id,request_key),
 check(tax_treatment='unsure' or legal_structure='other' or
  (legal_structure='sole_proprietor' and tax_treatment='sole_proprietor') or
  (legal_structure='partnership' and tax_treatment='partnership') or
  (legal_structure='corporation' and tax_treatment in ('c_corporation','s_corporation')) or legal_structure='llc')
);
create index korlix_bookkeeping_business_owner on public.korlix_bookkeeping_businesses(owner_id,created_at);
create table public.korlix_bookkeeping_accounts (
 business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 code text not null,
 name text not null,
 kind text not null check(kind in ('cash','income','expense')),
 primary key(business_id,code),
 check((kind='cash' and code='1000') or (kind='income' and code like '4___') or (kind='expense' and code like '5___'))
);
create table public.korlix_bookkeeping_entries (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 entry_date date not null check(entry_date between date '2000-01-01' and date '2100-12-31'),
 kind text not null check(kind in ('income','expense','reversal')),
 amount_cents bigint not null check(amount_cents between 1 and 999999999999),
 debit_account text not null,
 credit_account text not null,
 counterparty text not null default '' check(length(counterparty)<=160),
 purpose text not null check(length(btrim(purpose)) between 1 and 500),
 receipt_reference text not null default '' check(length(receipt_reference)<=160),
 request_key uuid not null,
 request_data jsonb not null,
 reversal_of uuid,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(business_id,id),
 unique(business_id,request_key),
 unique(reversal_of),
 foreign key(business_id,debit_account) references public.korlix_bookkeeping_accounts(business_id,code),
 foreign key(business_id,credit_account) references public.korlix_bookkeeping_accounts(business_id,code),
 foreign key(business_id,reversal_of) references public.korlix_bookkeeping_entries(business_id,id),
 check(debit_account<>credit_account),
 check((kind='income' and debit_account='1000' and credit_account like '4___' and reversal_of is null) or
 (kind='expense' and credit_account='1000' and debit_account like '5___' and reversal_of is null) or
 (kind='reversal' and reversal_of is not null))
);
create index korlix_bookkeeping_entries_month on public.korlix_bookkeeping_entries(business_id,entry_date desc,created_at desc,id);
create table public.korlix_bookkeeping_audit (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 actor_id uuid not null references auth.users(id),
 action text not null,
 details jsonb not null,
 created_at timestamptz not null default now()
);
create index korlix_bookkeeping_audit_business on public.korlix_bookkeeping_audit(business_id,created_at);
create index korlix_bookkeeping_entries_debit on public.korlix_bookkeeping_entries(business_id,debit_account);
create index korlix_bookkeeping_entries_credit on public.korlix_bookkeeping_entries(business_id,credit_account);
create index korlix_bookkeeping_entries_reversal on public.korlix_bookkeeping_entries(business_id,reversal_of);
create index korlix_bookkeeping_entries_actor on public.korlix_bookkeeping_entries(created_by);
create index korlix_bookkeeping_audit_actor on public.korlix_bookkeeping_audit(actor_id);

create function public.korlix_bookkeeping_guard_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare original public.korlix_bookkeeping_entries;
begin
 if tg_op<>'INSERT' then raise exception 'Bookkeeping history is immutable.' using errcode='23514'; end if;
 if tg_table_name='korlix_bookkeeping_entries' then
  if not exists(select 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.created_by) then
   raise exception 'Business owner required.' using errcode='42501';
  end if;
  if new.kind='reversal' then
   select * into original from public.korlix_bookkeeping_entries where id=new.reversal_of and business_id=new.business_id;
   if not found or original.kind='reversal' or original.amount_cents<>new.amount_cents or
    original.debit_account<>new.credit_account or original.credit_account<>new.debit_account or original.entry_date<>new.entry_date then
     raise exception 'A correction must offset its original entry.' using errcode='23514';
   end if;
  end if;
 end if;
 return new;
end $$;
create trigger bookkeeping_entry_guard before insert or update or delete on public.korlix_bookkeeping_entries
 for each row execute function public.korlix_bookkeeping_guard_v1();
create trigger bookkeeping_audit_guard before update or delete on public.korlix_bookkeeping_audit
 for each row execute function public.korlix_bookkeeping_guard_v1();
create trigger bookkeeping_account_guard before update or delete on public.korlix_bookkeeping_accounts
 for each row execute function public.korlix_bookkeeping_guard_v1();

-- Security-invoker view exposes the two legs for accountant tooling; browser
-- roles have no access. A cash control account is NOT a connected bank balance.
create view public.korlix_bookkeeping_journal_lines with (security_invoker=true) as
 select id entry_id,business_id,entry_date,debit_account account_code,amount_cents debit_cents,0::bigint credit_cents from public.korlix_bookkeeping_entries
 union all
 select id,business_id,entry_date,credit_account,0::bigint,amount_cents from public.korlix_bookkeeping_entries;

create function public.korlix_bookkeeping_v1(p_actor uuid,p_action text,p_business uuid default null,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; e public.korlix_bookkeeping_entries; orig public.korlix_bookkeeping_entries;
 req jsonb; result jsonb; rows_json jsonb; k uuid; n integer; offset_n integer; from_date date; until_date date;
 amount bigint; account_code text; entry_kind text; inc numeric; exp numeric; total_n bigint;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid request.'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(x)-'creation_request'-'request_key' order by x.created_at),'[]'::jsonb) into result
  from public.korlix_bookkeeping_businesses x where owner_id=p_actor;
  return jsonb_build_object('businesses',result);
 end if;
 if p_action in ('create_business','update_business') then
  req=jsonb_build_object('name',btrim(p_data->>'name'),'legal_structure',p_data->>'legal_structure',
    'tax_treatment',p_data->>'tax_treatment','contractor_income',coalesce((p_data->>'contractor_income')::boolean,false));
  if p_action='create_business' then
   k=(p_data->>'request_key')::uuid;
   perform pg_advisory_xact_lock(hashtextextended('bookkeeping-owner:'||p_actor::text,0));
   select * into b from public.korlix_bookkeeping_businesses where owner_id=p_actor and request_key=k;
   if found then
    if b.creation_request<>req then raise exception 'This request key has already been used.' using errcode='40001'; end if;
    return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key');
   end if;
   if (select count(*) from public.korlix_bookkeeping_businesses where owner_id=p_actor)>=25 then raise exception 'You can create up to 25 businesses.'; end if;
   insert into public.korlix_bookkeeping_businesses(owner_id,name,legal_structure,tax_treatment,contractor_income,request_key,creation_request)
   values(p_actor,req->>'name',req->>'legal_structure',req->>'tax_treatment',(req->>'contractor_income')::boolean,k,req) returning * into b;
   insert into public.korlix_bookkeeping_accounts(business_id,code,name,kind) values
   (b.id,'1000','Recorded cash control','cash'),
   (b.id,'4000','Services','income'),(b.id,'4100','Sales','income'),(b.id,'4900','Other operating income','income'),
   (b.id,'5000','Supplies','expense'),(b.id,'5010','Software and subscriptions','expense'),
   (b.id,'5020','Advertising','expense'),(b.id,'5030','Rent','expense'),(b.id,'5040','Utilities','expense'),
   (b.id,'5050','Professional services','expense'),(b.id,'5060','Insurance','expense'),
   (b.id,'5070','Travel','expense'),(b.id,'5080','Meals','expense'),(b.id,'5090','Repairs and maintenance','expense'),
   (b.id,'5100','Contract labor','expense'),(b.id,'5110','Bank and processing fees','expense'),
   (b.id,'5990','Other operating expense','expense');
   insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'business_created',req);
   return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key');
  end if;
 end if;
 -- All reads and writes are scoped to the verified server actor. Row locks
 -- serialize write/idempotency checks for one business in a single transaction.
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if p_action='update_business' then
  if (p_data->>'version')::integer is distinct from b.version then raise exception 'This profile changed. Refresh and try again.' using errcode='40001'; end if;
  insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details)
   values(b.id,p_actor,'business_updated',jsonb_build_object('before',to_jsonb(b)-'creation_request'-'request_key','after',req));
  update public.korlix_bookkeeping_businesses set name=req->>'name',legal_structure=req->>'legal_structure',tax_treatment=req->>'tax_treatment',
   contractor_income=(req->>'contractor_income')::boolean,version=version+1,updated_at=now() where id=b.id returning * into b;
  return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key');
 end if;
 if p_action in ('post','reverse') then
  if (p_data->'confirmed') is distinct from 'true'::jsonb then raise exception 'Review and confirm the entry first.'; end if;
  k=(p_data->>'request_key')::uuid;
  req=p_data-'request_key'-'confirmed';
  select * into e from public.korlix_bookkeeping_entries where business_id=b.id and request_key=k;
  if found then
   if e.request_data<>req then raise exception 'This request key has already been used.' using errcode='40001'; end if;
   return jsonb_build_object('entry',to_jsonb(e)-'request_data'-'request_key'||jsonb_build_object('amount_cents',e.amount_cents::text));
  end if;
  if p_action='reverse' then
   select * into orig from public.korlix_bookkeeping_entries where business_id=b.id and id=(req->>'entry_id')::uuid;
   if not found then raise exception 'Entry not found.' using errcode='P0002'; end if;
   if orig.kind='reversal' or exists(select 1 from public.korlix_bookkeeping_entries where reversal_of=orig.id) then
    raise exception 'This entry has already been reversed or is itself a reversal.' using errcode='40001'; end if;
   insert into public.korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,counterparty,purpose,receipt_reference,request_key,request_data,reversal_of,created_by)
   values(b.id,orig.entry_date,'reversal',orig.amount_cents,orig.credit_account,orig.debit_account,orig.counterparty,btrim(req->>'reason'),orig.receipt_reference,k,req,orig.id,p_actor) returning * into e;
  else
   entry_kind=req->>'kind'; amount=(req->>'amount_cents')::bigint; account_code=req->>'category';
   if entry_kind not in ('income','expense') or not exists(select 1 from public.korlix_bookkeeping_accounts where business_id=b.id and code=account_code and kind=entry_kind) then
    raise exception 'Choose a category for this entry type.'; end if;
   insert into public.korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,counterparty,purpose,receipt_reference,request_key,request_data,created_by)
   values(b.id,(req->>'entry_date')::date,entry_kind,amount,
    case when entry_kind='income' then '1000' else account_code end,
    case when entry_kind='income' then account_code else '1000' end,
    coalesce(req->>'counterparty',''),btrim(req->>'purpose'),coalesce(req->>'receipt_reference',''),k,req,p_actor) returning * into e;
  end if;
  insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,p_action,jsonb_build_object('entry_id',e.id));
  return jsonb_build_object('entry',to_jsonb(e)-'request_data'-'request_key'||jsonb_build_object('amount_cents',e.amount_cents::text));
 end if;
 if p_action in ('overview','export') then
  if coalesce(p_data->>'month','') !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' then raise exception 'Choose a month between 2000 and 2099.'; end if;
  from_date=(p_data->>'month'||'-01')::date; until_date=(from_date+interval '1 month')::date;
  offset_n=coalesce((p_data->>'offset')::integer,0);
  if offset_n<0 or offset_n>1000000 then raise exception 'Invalid page offset.'; end if;
  select count(*) into total_n from public.korlix_bookkeeping_entries where business_id=b.id and entry_date>=from_date and entry_date<until_date;
  if p_action='export' and total_n>5000 then raise exception 'This month exceeds the 5,000-entry export limit. Contact support for a complete export.' using errcode='54000'; end if;
  select coalesce(sum(case when a.kind='income' then l.credit_cents-l.debit_cents else 0 end),0),
   coalesce(sum(case when a.kind='expense' then l.debit_cents-l.credit_cents else 0 end),0) into inc,exp
  from public.korlix_bookkeeping_journal_lines l join public.korlix_bookkeeping_accounts a on a.business_id=l.business_id and a.code=l.account_code
  where l.business_id=b.id and l.entry_date>=from_date and l.entry_date<until_date;
  select coalesce(jsonb_agg(x.row order by x.entry_date desc,x.created_at desc,x.id),'[]'::jsonb) into rows_json from (
   select j.entry_date,j.created_at,j.id,(to_jsonb(j)-'request_data'-'request_key')||jsonb_build_object('amount_cents',j.amount_cents::text,
    'category_name',a.name,'category',a.code,'original_kind',coalesce(o.kind,j.kind),'reversed_by',r.id) row
   from public.korlix_bookkeeping_entries j
   left join public.korlix_bookkeeping_entries o on o.id=j.reversal_of
   left join public.korlix_bookkeeping_entries r on r.reversal_of=j.id
   join public.korlix_bookkeeping_accounts a on a.business_id=j.business_id and a.code=case when j.debit_account<>'1000' then j.debit_account else j.credit_account end
   where j.business_id=b.id and j.entry_date>=from_date and j.entry_date<until_date
   order by j.entry_date desc,j.created_at desc,j.id limit case when p_action='export' then 5000 else 50 end offset case when p_action='export' then 0 else offset_n end
  ) x;
  select coalesce(jsonb_agg(to_jsonb(a)-'business_id' order by a.code),'[]'::jsonb) into result from public.korlix_bookkeeping_accounts a where business_id=b.id and kind<>'cash';
  return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key','month',p_data->>'month','income_cents',inc::text,'expense_cents',exp::text,
   'net_cents',(inc-exp)::text,'entry_count',total_n,'offset',offset_n,'entries',rows_json,'categories',result);
 end if;
 raise exception 'Unknown bookkeeping action.';
end $$;

alter table public.korlix_bookkeeping_businesses enable row level security;
alter table public.korlix_bookkeeping_accounts enable row level security;
alter table public.korlix_bookkeeping_entries enable row level security;
alter table public.korlix_bookkeeping_audit enable row level security;
revoke all on public.korlix_bookkeeping_businesses,public.korlix_bookkeeping_accounts,public.korlix_bookkeeping_entries,public.korlix_bookkeeping_audit,public.korlix_bookkeeping_journal_lines from public,anon,authenticated,service_role;
grant select,insert on public.korlix_bookkeeping_businesses,public.korlix_bookkeeping_accounts,public.korlix_bookkeeping_entries,public.korlix_bookkeeping_audit to service_role;
grant update(name,legal_structure,tax_treatment,contractor_income,version,updated_at) on public.korlix_bookkeeping_businesses to service_role;
grant select on public.korlix_bookkeeping_journal_lines to service_role;
revoke all on function public.korlix_bookkeeping_guard_v1() from public,anon,authenticated;
revoke all on function public.korlix_bookkeeping_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_v1(uuid,text,uuid,jsonb) to service_role;
comment on function public.korlix_bookkeeping_v1(uuid,text,uuid,jsonb) is 'K198 verified-server-owner manual USD cash ledger. Browser roles cannot execute. Category names do not establish tax deductibility.';
