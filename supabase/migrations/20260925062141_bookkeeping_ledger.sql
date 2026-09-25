-- K201: balanced, immutable multi-line documents for non-operating activity.
-- Existing operating cash/receipt entries remain unchanged and are included in
-- the combined ledger. JSON lines live atomically in one immutable document;
-- the INSERT guard enforces account ownership, exact cents and equal totals.
alter table public.korlix_bookkeeping_accounts drop constraint korlix_bookkeeping_accounts_kind_check;
alter table public.korlix_bookkeeping_accounts drop constraint korlix_bookkeeping_accounts_check;
alter table public.korlix_bookkeeping_accounts add constraint bookkeeping_account_kind check(kind in ('cash','asset','liability','equity','income','expense'));
alter table public.korlix_bookkeeping_accounts add constraint bookkeeping_account_code check(
 (kind='cash' and code ~ '^1[01][0-9]{2}$') or (kind='asset' and code ~ '^1[2-9][0-9]{2}$') or
 (kind='liability' and code ~ '^2[0-9]{3}$') or (kind='equity' and code ~ '^3[0-9]{3}$') or
 (kind='income' and code ~ '^4[0-9]{3}$') or (kind='expense' and code ~ '^5[0-9]{3}$'));
alter table public.korlix_bookkeeping_accounts add column request_key uuid, add column creation_request jsonb;
create unique index bookkeeping_account_request on public.korlix_bookkeeping_accounts(business_id,request_key) where request_key is not null;
create unique index bookkeeping_account_name on public.korlix_bookkeeping_accounts(business_id,lower(name));

create function public.korlix_bookkeeping_seed_accounts_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 insert into public.korlix_bookkeeping_accounts(business_id,code,name,kind) values
 (new.id,'1200','Equipment','asset'),(new.id,'1900','Other assets','asset'),
 (new.id,'2000','Loans payable','liability'),(new.id,'2100','Credit cards payable','liability'),(new.id,'2900','Other liabilities','liability'),
 (new.id,'3000','Owner / shareholder capital','equity'),(new.id,'3100','Owner draws / distributions','equity'),(new.id,'3200','Retained earnings','equity');
 return new;
end $$;
create trigger bookkeeping_seed_accounts after insert on public.korlix_bookkeeping_businesses for each row execute function public.korlix_bookkeeping_seed_accounts_v1();
insert into public.korlix_bookkeeping_accounts(business_id,code,name,kind)
 select b.id,s.code,s.name,s.kind from public.korlix_bookkeeping_businesses b cross join (values
 ('1200','Equipment','asset'),('1900','Other assets','asset'),('2000','Loans payable','liability'),
 ('2100','Credit cards payable','liability'),('2900','Other liabilities','liability'),
 ('3000','Owner / shareholder capital','equity'),('3100','Owner draws / distributions','equity'),('3200','Retained earnings','equity')) s(code,name,kind);

create table public.korlix_bookkeeping_journals (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 entry_date date not null check(entry_date between date '2000-01-01' and date '2099-12-31'),
 kind text not null check(kind in ('contribution','distribution','loan_received','loan_principal','asset_purchase','transfer','adjustment','opening','reversal')),
 purpose text not null check(length(btrim(purpose)) between 1 and 500),
 lines jsonb not null, request_key uuid not null, request_data jsonb not null,
 reversal_of uuid, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(business_id,id),unique(business_id,request_key),unique(reversal_of),
 foreign key(business_id,reversal_of) references public.korlix_bookkeeping_journals(business_id,id),
 check((kind='reversal')=(reversal_of is not null))
);
create index bookkeeping_journals_period on public.korlix_bookkeeping_journals(business_id,entry_date desc,created_at desc,id);
create index bookkeeping_journals_actor on public.korlix_bookkeeping_journals(created_by);
create index bookkeeping_journals_reversal on public.korlix_bookkeeping_journals(business_id,reversal_of);

create function public.korlix_bookkeeping_journal_guard_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare ln jsonb; account_kind text; seen text[]='{}'; d numeric=0; c numeric=0;
 original public.korlix_bookkeeping_journals; expected jsonb; opening_date date; debit_kind text; credit_kind text;
begin
 if tg_op<>'INSERT' then raise exception 'Bookkeeping history is immutable.' using errcode='23514'; end if;
 perform 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.created_by for update;
 if not found then raise exception 'Business owner required.' using errcode='42501'; end if;
 select jj.entry_date into opening_date from public.korlix_bookkeeping_journals jj where jj.business_id=new.business_id and jj.kind='opening'
 and not exists(select 1 from public.korlix_bookkeeping_journals rr where rr.reversal_of=jj.id);
 -- This trigger also prevents legacy cash/receipt activity before a cutover.
 if tg_table_name='korlix_bookkeeping_entries' then
  if opening_date is not null and new.entry_date<=opening_date then raise exception 'Entry date must be after the opening balance date.' using errcode='23514'; end if;
  return new;
 end if;
 if jsonb_typeof(new.lines)<>'array' or jsonb_array_length(new.lines) not between 2 and 100 then raise exception 'Use 2 to 100 balanced lines.' using errcode='23514'; end if;
 for ln in select value from jsonb_array_elements(new.lines) loop
  if jsonb_typeof(ln)<>'object' or (ln-'account'-'debit_cents'-'credit_cents')<>'{}'::jsonb or
   jsonb_typeof(ln->'account') is distinct from 'string' or jsonb_typeof(ln->'debit_cents') is distinct from 'string' or jsonb_typeof(ln->'credit_cents') is distinct from 'string' or
   coalesce(ln->>'account','') !~ '^[0-9]{4}$' or coalesce(ln->>'debit_cents','') !~ '^(0|[1-9][0-9]{0,11})$' or coalesce(ln->>'credit_cents','') !~ '^(0|[1-9][0-9]{0,11})$' then
   raise exception 'Invalid journal line.' using errcode='23514';
  end if;
  if ((ln->>'debit_cents')::bigint>0)=((ln->>'credit_cents')::bigint>0) or ln->>'account'=any(seen) then raise exception 'Use each account once with one positive debit or credit.' using errcode='23514'; end if;
  select aa.kind into account_kind from public.korlix_bookkeeping_accounts aa where aa.business_id=new.business_id and aa.code=ln->>'account';
  if not found or account_kind not in ('cash','asset','liability','equity') then raise exception 'Choose an asset, cash, liability or equity account.' using errcode='23514'; end if;
  if (ln->>'debit_cents')::bigint>0 then debit_kind=account_kind; else credit_kind=account_kind; end if;
  seen=array_append(seen,ln->>'account'); d=d+(ln->>'debit_cents')::bigint; c=c+(ln->>'credit_cents')::bigint;
 end loop;
 if d<>c then raise exception 'Debits and credits must balance.' using errcode='23514'; end if;
 if new.kind not in ('opening','adjustment','reversal') then
  if jsonb_array_length(new.lines)<>2 or not (
   (new.kind in ('contribution','loan_received') and debit_kind='cash' and credit_kind=case when new.kind='contribution' then 'equity' else 'liability' end) or
   (new.kind='distribution' and debit_kind='equity' and credit_kind='cash') or
   (new.kind='loan_principal' and debit_kind='liability' and credit_kind='cash') or
   (new.kind='asset_purchase' and debit_kind='asset' and credit_kind in ('cash','liability')) or
   (new.kind='transfer' and debit_kind='cash' and credit_kind='cash')) then raise exception 'Accounts do not match the selected transaction type.' using errcode='23514'; end if;
 end if;
 if new.kind='reversal' then
  select * into original from public.korlix_bookkeeping_journals where business_id=new.business_id and id=new.reversal_of;
  select jsonb_agg(jsonb_build_object('account',x->>'account','debit_cents',x->>'credit_cents','credit_cents',x->>'debit_cents') order by x->>'account') into expected from jsonb_array_elements(original.lines) x;
  if original.id is null or original.kind='reversal' or original.entry_date<>new.entry_date or new.lines<>expected then raise exception 'A reversal must exactly offset its original journal.' using errcode='23514'; end if;
 elsif new.kind='opening' then
  if opening_date is not null then raise exception 'Opening balances already exist. Reverse them before replacing.' using errcode='40001'; end if;
  if exists(select 1 from public.korlix_bookkeeping_entries where business_id=new.business_id and entry_date<=new.entry_date) or
   exists(select 1 from public.korlix_bookkeeping_journals where business_id=new.business_id and kind not in ('opening','reversal') and entry_date<=new.entry_date) then raise exception 'Opening balances must be dated before all recorded activity.' using errcode='23514'; end if;
 elsif opening_date is not null and new.entry_date<=opening_date then raise exception 'Entry date must be after the opening balance date.' using errcode='23514'; end if;
 return new;
end $$;
create trigger bookkeeping_journal_guard before insert or update or delete on public.korlix_bookkeeping_journals for each row execute function public.korlix_bookkeeping_journal_guard_v1();
create trigger bookkeeping_cash_cutover_guard before insert on public.korlix_bookkeeping_entries for each row execute function public.korlix_bookkeeping_journal_guard_v1();

create view public.korlix_bookkeeping_all_lines with(security_invoker=true) as
 select ll.entry_id,ll.business_id,ll.entry_date,ll.account_code,ll.debit_cents,ll.credit_cents,'cash'::text source,ee.kind,ee.purpose,ee.reversal_of,ee.created_at
 from public.korlix_bookkeeping_journal_lines ll join public.korlix_bookkeeping_entries ee on ee.id=ll.entry_id
 union all
 select jj.id,jj.business_id,jj.entry_date,ln->>'account',(ln->>'debit_cents')::bigint,(ln->>'credit_cents')::bigint,'journal',jj.kind,jj.purpose,jj.reversal_of,jj.created_at
 from public.korlix_bookkeeping_journals jj cross join lateral jsonb_array_elements(jj.lines) ln;

create function public.korlix_bookkeeping_ledger_v1(p_actor uuid,p_action text,p_business uuid,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; j public.korlix_bookkeeping_journals; orig public.korlix_bookkeeping_journals;
 a public.korlix_bookkeeping_accounts; req jsonb; k uuid; result jsonb; accounts_json jsonb; lines_json jsonb;
 from_date date; until_date date; total_n bigint; offset_n int; start_code int; end_code int; next_code text; opening_json jsonb;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Invalid request.'; end if;
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if p_action in ('post','reverse','account') then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Review and confirm first.'; end if;
  k=(p_data->>'request_key')::uuid; if k is null then raise exception 'Request key required.'; end if;
  req=(p_data-'request_key'-'confirmed')||jsonb_build_object('action',p_action);
  if p_action='account' then
   select * into a from public.korlix_bookkeeping_accounts where business_id=b.id and request_key=k;
   if found then
    if a.creation_request<>req then raise exception 'This request key has already been used.' using errcode='40001'; end if;
    return jsonb_build_object('account',to_jsonb(a)-'creation_request'-'request_key'-'business_id');
   end if;
   if req->>'kind' not in ('cash','asset','liability','equity') or length(btrim(req->>'name')) not between 1 and 80 or req->>'name' is null then raise exception 'Choose an account type and a name up to 80 characters.'; end if;
   if (select count(*) from public.korlix_bookkeeping_accounts where business_id=b.id)>=100 then raise exception 'Up to 100 accounts per business.'; end if;
   start_code=case req->>'kind' when 'cash' then 1001 when 'asset' then 1201 when 'liability' then 2001 else 3001 end;
   end_code=case req->>'kind' when 'cash' then 1199 when 'asset' then 1999 when 'liability' then 2999 else 3999 end;
   select gs::text into next_code from generate_series(start_code,end_code) gs where not exists(select 1 from public.korlix_bookkeeping_accounts aa where aa.business_id=b.id and aa.code=gs::text) order by gs limit 1;
   insert into public.korlix_bookkeeping_accounts(business_id,code,name,kind,request_key,creation_request) values(b.id,next_code,btrim(req->>'name'),req->>'kind',k,req) returning * into a;
   insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'account_created',jsonb_build_object('code',a.code,'name',a.name,'kind',a.kind));
   return jsonb_build_object('account',to_jsonb(a)-'creation_request'-'request_key'-'business_id');
  end if;
  select * into j from public.korlix_bookkeeping_journals where business_id=b.id and request_key=k;
  if found then
   if j.request_data<>req then raise exception 'This request key has already been used.' using errcode='40001'; end if;
   return jsonb_build_object('journal',to_jsonb(j)-'request_key'-'request_data');
  end if;
  if p_action='reverse' then
   select * into orig from public.korlix_bookkeeping_journals where business_id=b.id and id=(req->>'journal_id')::uuid;
   if not found then raise exception 'Journal not found.' using errcode='P0002'; end if;
   if orig.kind='reversal' or exists(select 1 from public.korlix_bookkeeping_journals where reversal_of=orig.id) then raise exception 'This journal has already been reversed or is itself a reversal.' using errcode='40001'; end if;
   select jsonb_agg(jsonb_build_object('account',x->>'account','debit_cents',x->>'credit_cents','credit_cents',x->>'debit_cents') order by x->>'account') into lines_json from jsonb_array_elements(orig.lines) x;
   insert into public.korlix_bookkeeping_journals(business_id,entry_date,kind,purpose,lines,request_key,request_data,reversal_of,created_by)
   values(b.id,orig.entry_date,'reversal',btrim(req->>'reason'),lines_json,k,req,orig.id,p_actor) returning * into j;
  else
   if req->>'kind' is null or req->>'kind'='reversal' then raise exception 'Choose a journal type.'; end if;
   insert into public.korlix_bookkeeping_journals(business_id,entry_date,kind,purpose,lines,request_key,request_data,created_by)
   values(b.id,(req->>'entry_date')::date,req->>'kind',btrim(req->>'purpose'),req->'lines',k,req,p_actor) returning * into j;
  end if;
  insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'journal_'||p_action,jsonb_build_object('journal_id',j.id));
  return jsonb_build_object('journal',to_jsonb(j)-'request_key'-'request_data');
 end if;
 if p_action in ('list','export') then
  if coalesce(p_data->>'month','') !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' then raise exception 'Choose a month between 2000 and 2099.'; end if;
  from_date=(p_data->>'month'||'-01')::date; until_date=(from_date+interval '1 month')::date; offset_n=coalesce((p_data->>'offset')::int,0);
  if offset_n<0 or offset_n>1000000 then raise exception 'Invalid page offset.'; end if;
  select count(*) into total_n from public.korlix_bookkeeping_journals where business_id=b.id and entry_date>=from_date and entry_date<until_date;
  select coalesce(jsonb_agg(x.row order by x.entry_date desc,x.created_at desc,x.id),'[]') into result from (
   select jj.id,jj.entry_date,jj.created_at,(to_jsonb(jj)-'request_key'-'request_data')||jsonb_build_object('reversed_by',rr.id) row
   from public.korlix_bookkeeping_journals jj left join public.korlix_bookkeeping_journals rr on rr.reversal_of=jj.id
   where jj.business_id=b.id and jj.entry_date>=from_date and jj.entry_date<until_date order by jj.entry_date desc,jj.created_at desc,jj.id limit 50 offset offset_n) x;
  select coalesce(jsonb_agg(jsonb_build_object('code',aa.code,'name',aa.name,'kind',aa.kind,'balance_cents',coalesce(ll.net,0)::text) order by aa.code),'[]') into accounts_json
  from public.korlix_bookkeeping_accounts aa left join (
   select account_code,sum(debit_cents-credit_cents) net from public.korlix_bookkeeping_all_lines where business_id=b.id and entry_date<until_date group by account_code
  ) ll on ll.account_code=aa.code where aa.business_id=b.id;
  select jsonb_build_object('id',jj.id,'entry_date',jj.entry_date) into opening_json from public.korlix_bookkeeping_journals jj where jj.business_id=b.id and jj.kind='opening' and not exists(select 1 from public.korlix_bookkeeping_journals rr where rr.reversal_of=jj.id);
  if p_action='export' then
   if (select count(*) from public.korlix_bookkeeping_all_lines where business_id=b.id and entry_date>=from_date and entry_date<until_date)>10000 then raise exception 'This month exceeds the 10,000-line export limit. Contact support for a complete export.' using errcode='54000'; end if;
   select coalesce(jsonb_agg(to_jsonb(x) order by x.entry_date,x.created_at,x.entry_id,x.account_code),'[]') into lines_json from (
    select ll.entry_id,ll.entry_date,ll.source,ll.kind,ll.purpose,ll.account_code,aa.name account_name,aa.kind account_kind,ll.debit_cents::text,ll.credit_cents::text,ll.reversal_of,ll.created_at
    from public.korlix_bookkeeping_all_lines ll join public.korlix_bookkeeping_accounts aa on aa.business_id=ll.business_id and aa.code=ll.account_code
    where ll.business_id=b.id and ll.entry_date>=from_date and ll.entry_date<until_date) x;
  end if;
  return jsonb_build_object('business',to_jsonb(b)-'request_key'-'creation_request','month',p_data->>'month','as_of',(until_date-1)::text,'accounts',accounts_json,'journals',result,'journal_count',total_n,'offset',offset_n,'opening',opening_json,'lines',lines_json);
 end if;
 raise exception 'Unknown ledger action.';
end $$;

alter table public.korlix_bookkeeping_journals enable row level security;
revoke all on public.korlix_bookkeeping_journals,public.korlix_bookkeeping_all_lines from public,anon,authenticated,service_role;
grant select,insert on public.korlix_bookkeeping_journals to service_role;
grant select on public.korlix_bookkeeping_all_lines to service_role;
revoke all on function public.korlix_bookkeeping_seed_accounts_v1(),public.korlix_bookkeeping_journal_guard_v1(),public.korlix_bookkeeping_ledger_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_ledger_v1(uuid,text,uuid,jsonb) to service_role;
