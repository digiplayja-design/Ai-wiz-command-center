-- K202: selectable cash accounts with legacy replay compatibility, and private
-- read-only reporting over the complete recorded ledger. Existing entries and
-- request data remain immutable; no financial history is rewritten.
alter table public.korlix_bookkeeping_entries drop constraint korlix_bookkeeping_entries_check1;
alter table public.korlix_bookkeeping_entries add constraint bookkeeping_operating_legs check(
 (kind='income' and debit_account ~ '^1[01][0-9]{2}$' and credit_account ~ '^4[0-9]{3}$' and reversal_of is null) or
 (kind='expense' and credit_account ~ '^1[01][0-9]{2}$' and debit_account ~ '^5[0-9]{3}$' and reversal_of is null) or
 (kind='reversal' and reversal_of is not null));
create or replace function public.korlix_bookkeeping_guard_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare original public.korlix_bookkeeping_entries;
begin
 if tg_op<>'INSERT' then raise exception 'Bookkeeping history is immutable.' using errcode='23514'; end if;
 if tg_table_name='korlix_bookkeeping_entries' then
  if not exists(select 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.created_by) then
   raise exception 'Business owner required.' using errcode='42501';
  end if;
  if new.kind in ('income','expense') then
   if not exists(select 1 from public.korlix_bookkeeping_accounts aa where aa.business_id=new.business_id and aa.code=new.debit_account and aa.kind=case when new.kind='income' then 'cash' else 'expense' end) or
    not exists(select 1 from public.korlix_bookkeeping_accounts aa where aa.business_id=new.business_id and aa.code=new.credit_account and aa.kind=case when new.kind='income' then 'income' else 'cash' end) then
    raise exception 'Choose a cash account and matching operating category.' using errcode='23514';
   end if;
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
create or replace function public.korlix_bookkeeping_v1(p_actor uuid,p_action text,p_business uuid default null,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; e public.korlix_bookkeeping_entries; orig public.korlix_bookkeeping_entries;
 req jsonb; result jsonb; rows_json jsonb; k uuid; n integer; offset_n integer; from_date date; until_date date;
 cash_json jsonb; cash_code text; amount bigint; account_code text; entry_kind text; inc numeric; exp numeric; total_n bigint;
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
  -- Omitted/default cash account retains the pre-K202 request representation.
  -- A lost response from the previous release can be replayed unchanged.
  if p_action='post' and coalesce(req->>'cash_account','1000')='1000' then req=req-'cash_account'; end if;
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
   cash_code=coalesce(req->>'cash_account','1000');
   if not exists(select 1 from public.korlix_bookkeeping_accounts where business_id=b.id and code=cash_code and kind='cash') then raise exception 'Choose a cash account for this business.'; end if;
   entry_kind=req->>'kind'; amount=(req->>'amount_cents')::bigint; account_code=req->>'category';
   if entry_kind not in ('income','expense') or not exists(select 1 from public.korlix_bookkeeping_accounts where business_id=b.id and code=account_code and kind=entry_kind) then
    raise exception 'Choose a category for this entry type.'; end if;
   insert into public.korlix_bookkeeping_entries(business_id,entry_date,kind,amount_cents,debit_account,credit_account,counterparty,purpose,receipt_reference,request_key,request_data,created_by)
   values(b.id,(req->>'entry_date')::date,entry_kind,amount,
    case when entry_kind='income' then cash_code else account_code end,
    case when entry_kind='income' then account_code else cash_code end,
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
    'cash_account',ca.code,'cash_account_name',ca.name,'category_name',a.name,'category',a.code,'original_kind',coalesce(o.kind,j.kind),'reversed_by',r.id) row
   from public.korlix_bookkeeping_entries j
   left join public.korlix_bookkeeping_entries o on o.id=j.reversal_of
   left join public.korlix_bookkeeping_entries r on r.reversal_of=j.id
   join public.korlix_bookkeeping_accounts a on a.business_id=j.business_id and a.code=case when j.debit_account ~ '^[45]' then j.debit_account else j.credit_account end
   join public.korlix_bookkeeping_accounts ca on ca.business_id=j.business_id and ca.code=case when j.debit_account ~ '^1[01]' then j.debit_account else j.credit_account end
   where j.business_id=b.id and j.entry_date>=from_date and j.entry_date<until_date
   order by j.entry_date desc,j.created_at desc,j.id limit case when p_action='export' then 5000 else 50 end offset case when p_action='export' then 0 else offset_n end
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('code',a.code,'name',a.name,'kind',a.kind) order by a.code),'[]'::jsonb) into result from public.korlix_bookkeeping_accounts a where business_id=b.id and kind in ('income','expense');
  select coalesce(jsonb_agg(jsonb_build_object('code',a.code,'name',a.name,'kind',a.kind) order by a.code),'[]'::jsonb) into cash_json from public.korlix_bookkeeping_accounts a where business_id=b.id and kind='cash';
  return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key','month',p_data->>'month','income_cents',inc::text,'expense_cents',exp::text,
   'net_cents',(inc-exp)::text,'entry_count',total_n,'offset',offset_n,'entries',rows_json,'categories',result,'cash_accounts',cash_json);
 end if;
 raise exception 'Unknown bookkeeping action.';
end $$;
create function public.korlix_bookkeeping_reports_v1(p_actor uuid,p_business uuid,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; from_date date; until_date date; year_date date;
 accounts_json jsonb; rows_json jsonb; opening_json jsonb; total_n bigint; cash_n bigint; journal_n bigint; first_date date;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Invalid request.'; end if;
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if coalesce(p_data->>'period','') !~ '^20[0-9]{2}(-(0[1-9]|1[0-2]))?$' then raise exception 'Choose YYYY or YYYY-MM between 2000 and 2099.'; end if;
 from_date=(p_data->>'period'||case when length(p_data->>'period')=4 then '-01-01' else '-01' end)::date;
 until_date=(from_date+case when length(p_data->>'period')=4 then interval '1 year' else interval '1 month' end)::date;
 year_date=date_trunc('year',from_date)::date;
 select coalesce(jsonb_agg(jsonb_build_object('code',aa.code,'name',aa.name,'kind',aa.kind,
  'beginning_cents',coalesce(ll.beginning,0)::text,'period_debit_cents',coalesce(ll.debits,0)::text,
  'period_credit_cents',coalesce(ll.credits,0)::text,'closing_cents',coalesce(ll.closing,0)::text,'prior_year_cents',coalesce(ll.prior_year,0)::text) order by aa.code),'[]') into accounts_json
 from public.korlix_bookkeeping_accounts aa left join (
  select account_code,
   sum(debit_cents-credit_cents) filter(where entry_date<from_date) beginning,
   sum(debit_cents) filter(where entry_date>=from_date) debits,
   sum(credit_cents) filter(where entry_date>=from_date) credits,
   sum(debit_cents-credit_cents) closing,
   sum(debit_cents-credit_cents) filter(where entry_date<year_date) prior_year
  from public.korlix_bookkeeping_all_lines where business_id=b.id and entry_date<until_date group by account_code
 ) ll on ll.account_code=aa.code where aa.business_id=b.id;
 select jsonb_build_object('id',jj.id,'entry_date',jj.entry_date) into opening_json from public.korlix_bookkeeping_journals jj where jj.business_id=b.id and jj.kind='opening'
 and not exists(select 1 from public.korlix_bookkeeping_journals rr where rr.reversal_of=jj.id);
 select count(*) into cash_n from public.korlix_bookkeeping_entries where business_id=b.id and entry_date>=from_date and entry_date<until_date;
 select count(*) into journal_n from public.korlix_bookkeeping_journals where business_id=b.id and entry_date>=from_date and entry_date<until_date;
 select min(entry_date) into first_date from public.korlix_bookkeeping_all_lines where business_id=b.id and entry_date<until_date;
 if p_data->'include_lines'='true'::jsonb then
  select count(*) into total_n from public.korlix_bookkeeping_all_lines where business_id=b.id and entry_date>=from_date and entry_date<until_date;
  if total_n>50000 then raise exception 'This period exceeds the 50,000-line export limit. Choose a shorter period.' using errcode='54000'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.entry_date,x.created_at,x.source,x.entry_id,x.account_code),'[]') into rows_json from (
   select ll.entry_id,ll.entry_date,ll.source,ll.kind,ll.purpose,ll.account_code,aa.name account_name,aa.kind account_kind,ll.debit_cents::text,ll.credit_cents::text,ll.reversal_of,ll.created_at,
    coalesce((select jsonb_agg(jsonb_build_object('receipt_id',rl.receipt_id,'filename',rr.filename,'sha256',rr.sha256) order by rl.receipt_id)
      from public.korlix_bookkeeping_receipt_links rl join public.korlix_bookkeeping_receipts rr on rr.id=rl.receipt_id
      where ll.source='cash' and rl.business_id=b.id and rl.entry_id=coalesce(ll.reversal_of,ll.entry_id) and rl.unlinked_at is null),'[]'::jsonb) receipts
   from public.korlix_bookkeeping_all_lines ll join public.korlix_bookkeeping_accounts aa on aa.business_id=ll.business_id and aa.code=ll.account_code
   where ll.business_id=b.id and ll.entry_date>=from_date and ll.entry_date<until_date
  ) x;
 end if;
 return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key','period',p_data->>'period','from_date',from_date,'as_of',until_date-1,
  'generated_at',now(),'accounts',accounts_json,'opening',opening_json,'first_recorded_date',first_date,
  'cash_entry_count',cash_n,'journal_count',journal_n,'lines',rows_json);
end $$;
revoke all on function public.korlix_bookkeeping_reports_v1(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_reports_v1(uuid,uuid,jsonb) to service_role;
-- CREATE OR REPLACE preserves old grants; reiterate the server-only boundary.
revoke all on function public.korlix_bookkeeping_v1(uuid,text,uuid,jsonb),public.korlix_bookkeeping_guard_v1() from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_v1(uuid,text,uuid,jsonb) to service_role;
comment on function public.korlix_bookkeeping_reports_v1(uuid,uuid,jsonb) is 'K202 owner-scoped, read-only recorded cash-basis P&L, balance-sheet and trial-balance inputs; no completeness, reconciliation or tax-filing assertion.';
