-- K203G: preserve distinct same-detail rows only after documented owner review.
-- No cross-import overlap bypass; source bytes stay private and are not stored.
create or replace function public.korlix_bookkeeping_statement_guard_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare line jsonb; seen integer[]='{}'; fingerprints text[]='{}'; fingerprint text; duplicate_reason text; account_kind text; st public.korlix_bookkeeping_statement_imports; prior public.korlix_bookkeeping_statement_decisions;
begin
 if tg_op<>'INSERT' then raise exception 'Statement history is immutable.' using errcode='23514'; end if;
 perform 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.created_by for update;
 if not found then raise exception 'Business owner required.' using errcode='42501'; end if;
 if tg_table_name='korlix_bookkeeping_statement_imports' then
  select kind into account_kind from public.korlix_bookkeeping_accounts where business_id=new.business_id and code=new.cash_account;
  if account_kind is distinct from 'cash' then raise exception 'Choose a business cash account.' using errcode='23514'; end if;
  for line in select value from jsonb_array_elements(new.rows) loop
   if jsonb_typeof(line)<>'object' or (line-'line'-'date'-'description'-'amount_cents')<>'{}'::jsonb or
    jsonb_typeof(line->'line') is distinct from 'number' or jsonb_typeof(line->'date') is distinct from 'string' or
    jsonb_typeof(line->'description') is distinct from 'string' or jsonb_typeof(line->'amount_cents') is distinct from 'string' or
    coalesce(line->>'line','') !~ '^([2-9]|[1-9][0-9]{1,2})$' or (line->>'line')::integer>501 or
    coalesce(line->>'date','') !~ '^20[0-9]{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])$' or
    coalesce(line->>'amount_cents','') !~ '^-?[1-9][0-9]{0,11}$' or
    length(btrim(coalesce(line->>'description',''))) not between 1 and 160 then raise exception 'Invalid statement row.' using errcode='23514'; end if;
   if (line->>'date')::date::text<>line->>'date' or extract(year from (line->>'date')::date)<>new.statement_year or
      abs((line->>'amount_cents')::bigint)>999999999999 or (line->>'line')::integer=any(seen) then raise exception 'Invalid or duplicate statement row.' using errcode='23514'; end if;
   seen=array_append(seen,(line->>'line')::integer);
   fingerprint=jsonb_build_array(line->>'date',line->>'amount_cents',lower(line->>'description'))::text;
   if fingerprint=any(fingerprints) then
    duplicate_reason=btrim(coalesce(new.request_data->>'duplicate_review_reason',''));
    if length(duplicate_reason) not between 10 and 500 then
     raise exception 'Repeated statement rows require a reviewed explanation of 10–500 characters.' using errcode='23514';
    end if;
   end if;
   fingerprints=array_append(fingerprints,fingerprint);
  end loop;
 else
  select * into st from public.korlix_bookkeeping_statement_imports where id=new.statement_id and business_id=new.business_id;
  select value into line from jsonb_array_elements(st.rows) where (value->>'line')::integer=new.row_line;
  if line is null then raise exception 'Statement row not found.' using errcode='23514'; end if;
  if new.action='match' then
   if not exists(select 1 from public.korlix_bookkeeping_all_lines ll where ll.business_id=new.business_id and ll.entry_id=new.entry_id and ll.account_code=st.cash_account
     and ll.debit_cents-ll.credit_cents=(line->>'amount_cents')::bigint and abs(ll.entry_date-(line->>'date')::date)<=3 and ll.kind<>'reversal'
     and not exists(select 1 from public.korlix_bookkeeping_all_lines rev where rev.business_id=new.business_id and rev.reversal_of=ll.entry_id)) then raise exception 'Match does not correspond to a recorded cash movement.' using errcode='23514'; end if;
  else
   select * into prior from public.korlix_bookkeeping_statement_decisions where id=new.previous_match_id and business_id=new.business_id;
   if prior.action is distinct from 'match' or prior.statement_id<>new.statement_id or prior.row_line<>new.row_line then raise exception 'Correction must reference this row’s prior match.' using errcode='23514'; end if;
  end if;
 end if;
 return new;
end $$;

create or replace function public.korlix_bookkeeping_statements_v1(p_actor uuid,p_action text,p_business uuid,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; s public.korlix_bookkeeping_statement_imports;
 d public.korlix_bookkeeping_statement_decisions; prev public.korlix_bookkeeping_statement_decisions;
 req jsonb; k uuid; row_n integer; row_data jsonb; candidate uuid; movement bigint; matching public.korlix_bookkeeping_all_lines;
 rows_json jsonb; decision_json jsonb; reason_text text; other_count integer;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid statement request.'; end if;
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'cash_account',x.cash_account,'statement_year',x.statement_year,'row_count',jsonb_array_length(x.rows),'created_at',x.created_at,'has_repeated_rows',coalesce(x.request_data->>'duplicate_review_reason','')<>'') order by x.created_at desc,x.id),'[]'::jsonb) into rows_json
  from public.korlix_bookkeeping_statement_imports x where business_id=b.id;
  return jsonb_build_object('statements',rows_json);
 end if;
 if p_action='import' then
  if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Review and confirm the imported rows first.'; end if;
  k=(p_data->>'request_key')::uuid;req=p_data-'request_key'-'confirmed';
  select * into s from public.korlix_bookkeeping_statement_imports where business_id=b.id and request_key=k;
  if found then
   if s.request_data<>req then raise exception 'This request key was already used for different statement rows.' using errcode='40001'; end if;
   return jsonb_build_object('statement',jsonb_build_object('id',s.id,'row_count',jsonb_array_length(s.rows),'created_at',s.created_at,'duplicate_review_reason',coalesce(s.request_data->>'duplicate_review_reason','')),'reused',true);
  end if;
  select * into s from public.korlix_bookkeeping_statement_imports where business_id=b.id and source_sha256=req->>'source_sha256';
  if found then
   if s.request_data<>req then raise exception 'This CSV was imported with different mapping or account. Review the existing import.' using errcode='40001'; end if;
   return jsonb_build_object('statement',jsonb_build_object('id',s.id,'row_count',jsonb_array_length(s.rows),'created_at',s.created_at,'duplicate_review_reason',coalesce(s.request_data->>'duplicate_review_reason','')),'reused',true);
  end if;
  if exists(select 1 from public.korlix_bookkeeping_statement_imports existing
    cross join lateral jsonb_array_elements(existing.rows) old_row
    cross join lateral jsonb_array_elements(req->'rows') new_row
    where existing.business_id=b.id and existing.cash_account=req->>'cash_account' and existing.statement_year=(req->>'year')::integer
    and old_row->>'date'=new_row->>'date' and old_row->>'amount_cents'=new_row->>'amount_cents'
    and lower(old_row->>'description')=lower(new_row->>'description')) then
    raise exception 'One or more rows may already be imported for this cash account and year. Review saved statements before importing overlapping rows.' using errcode='40001';
  end if;
  insert into public.korlix_bookkeeping_statement_imports(business_id,cash_account,statement_year,source_sha256,rows,request_key,request_data,created_by)
   values(b.id,req->>'cash_account',(req->>'year')::integer,req->>'source_sha256',req->'rows',k,req,p_actor) returning * into s;
  insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'statement_imported',jsonb_build_object('statement_id',s.id,'row_count',jsonb_array_length(s.rows),'source_sha256',s.source_sha256,'duplicate_review_reason',coalesce(s.request_data->>'duplicate_review_reason','')));
  return jsonb_build_object('statement',jsonb_build_object('id',s.id,'row_count',jsonb_array_length(s.rows),'created_at',s.created_at,'duplicate_review_reason',coalesce(s.request_data->>'duplicate_review_reason','')),'reused',false);
 end if;
 if p_action not in ('get','match','unmatch') then raise exception 'Unknown statement action.'; end if;
 select * into s from public.korlix_bookkeeping_statement_imports where id=(p_data->>'statement_id')::uuid and business_id=b.id;
 if not found then raise exception 'Statement not found.' using errcode='P0002'; end if;
 if p_action='get' then
  select coalesce(jsonb_agg(to_jsonb(x)-'request_data'-'request_key'-'created_by' order by x.created_at,x.id),'[]'::jsonb) into decision_json
   from public.korlix_bookkeeping_statement_decisions x where business_id=b.id and statement_id=s.id;
  return jsonb_build_object('statement',jsonb_build_object('id',s.id,'cash_account',s.cash_account,'statement_year',s.statement_year,'rows',s.rows,'created_at',s.created_at,'duplicate_review_reason',coalesce(s.request_data->>'duplicate_review_reason','')),'decisions',decision_json);
 end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Review and confirm the match decision.'; end if;
 k=(p_data->>'request_key')::uuid;req=p_data-'request_key'-'confirmed';row_n=(req->>'row_line')::integer;
 row_data=null;select value into row_data from jsonb_array_elements(s.rows) where (value->>'line')::integer=row_n;
 if row_data is null then raise exception 'Statement row not found.' using errcode='P0002'; end if;
 select * into d from public.korlix_bookkeeping_statement_decisions where business_id=b.id and request_key=k;
 if found then
  if d.request_data<>req then raise exception 'This request key was already used.' using errcode='40001'; end if;
  return jsonb_build_object('decision',to_jsonb(d)-'request_data'-'request_key'-'created_by','reused',true);
 end if;
 select * into prev from public.korlix_bookkeeping_statement_decisions where business_id=b.id and statement_id=s.id and row_line=row_n order by created_at desc,id desc limit 1;
 if p_action='match' then
  if prev.id is not null and prev.action='match' then raise exception 'This statement row is already matched. Correct it first.' using errcode='40001'; end if;
  candidate=(req->>'entry_id')::uuid;movement=(row_data->>'amount_cents')::bigint;
  select * into matching from public.korlix_bookkeeping_all_lines ll where ll.business_id=b.id and ll.entry_id=candidate and ll.account_code=s.cash_account
   and ll.debit_cents-ll.credit_cents=movement and abs(ll.entry_date-(row_data->>'date')::date)<=3 and ll.kind<>'reversal'
   and not exists(select 1 from public.korlix_bookkeeping_all_lines rev where rev.business_id=b.id and rev.reversal_of=ll.entry_id) limit 1;
  if not found then raise exception 'This recorded cash entry does not match the selected amount, account and date.' using errcode='40001'; end if;
  select count(*) into other_count from public.korlix_bookkeeping_statement_decisions x
    where x.business_id=b.id and x.action='match' and x.entry_id=candidate and
      not exists(select 1 from public.korlix_bookkeeping_statement_decisions y where y.previous_match_id=x.id);
  if other_count>0 then raise exception 'This recorded entry is already matched to another statement row.' using errcode='40001'; end if;
  insert into public.korlix_bookkeeping_statement_decisions(business_id,statement_id,row_line,action,entry_id,request_key,request_data,created_by)
   values(b.id,s.id,row_n,'match',candidate,k,req,p_actor) returning * into d;
 else
  if prev.id is null or prev.action<>'match' or req->>'previous_match_id' is distinct from prev.id::text then raise exception 'Refresh the current match before correcting it.' using errcode='40001'; end if;
  reason_text=btrim(req->>'reason');
  insert into public.korlix_bookkeeping_statement_decisions(business_id,statement_id,row_line,action,previous_match_id,reason,request_key,request_data,created_by)
   values(b.id,s.id,row_n,'unmatch',prev.id,reason_text,k,req,p_actor) returning * into d;
 end if;
 insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'statement_'||p_action,jsonb_build_object('statement_id',s.id,'row_line',row_n,'decision_id',d.id,'entry_id',coalesce(d.entry_id,prev.entry_id)));
 return jsonb_build_object('decision',to_jsonb(d)-'request_data'-'request_key'-'created_by','reused',false);
end $$;
