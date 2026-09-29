-- Add journal evidence without changing original files or existing cash links.
alter table public.korlix_bookkeeping_receipt_links alter column entry_id drop not null;
alter table public.korlix_bookkeeping_receipt_links add column journal_id uuid;
alter table public.korlix_bookkeeping_receipt_links add column request_key uuid;
alter table public.korlix_bookkeeping_receipt_links add constraint bookkeeping_receipt_one_target
 check((entry_id is not null)::integer+(journal_id is not null)::integer=1);
alter table public.korlix_bookkeeping_receipt_links add constraint bookkeeping_receipt_journal_fk
 foreign key(business_id,journal_id) references public.korlix_bookkeeping_journals(business_id,id);
create index bookkeeping_receipt_links_journal on public.korlix_bookkeeping_receipt_links(business_id,journal_id) where journal_id is not null;
create unique index bookkeeping_receipt_link_request on public.korlix_bookkeeping_receipt_links(business_id,request_key) where request_key is not null;
create function public.korlix_bookkeeping_receipt_insert_guard_v1() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 perform 1 from public.korlix_bookkeeping_businesses where id=new.business_id and owner_id=new.linked_by for update;
 if not found then raise exception 'Business owner required.' using errcode='42501'; end if;
 if not exists(select 1 from public.korlix_bookkeeping_receipts where id=new.receipt_id and business_id=new.business_id and created_by=new.linked_by and state='ready') then raise exception 'Choose a ready receipt in this business.' using errcode='23514'; end if;
 if new.entry_id is not null and not exists(select 1 from public.korlix_bookkeeping_entries e where e.id=new.entry_id and e.business_id=new.business_id and e.kind<>'reversal' and not exists(select 1 from public.korlix_bookkeeping_entries r where r.reversal_of=e.id)) then raise exception 'Choose an active operating entry in this business.' using errcode='23514'; end if;
 if new.journal_id is not null and not exists(select 1 from public.korlix_bookkeeping_journals j where j.id=new.journal_id and j.business_id=new.business_id and j.kind<>'reversal' and not exists(select 1 from public.korlix_bookkeeping_journals r where r.reversal_of=j.id)) then raise exception 'Choose an active journal in this business.' using errcode='23514'; end if;
 return new;
end $$;
create trigger bookkeeping_receipt_links_insert_guard before insert on public.korlix_bookkeeping_receipt_links for each row execute function public.korlix_bookkeeping_receipt_insert_guard_v1();
revoke all on function public.korlix_bookkeeping_receipt_insert_guard_v1() from public,anon,authenticated;
create function public.korlix_bookkeeping_evidence_v1(p_business uuid,p_source text,p_entry uuid) returns jsonb
language sql stable security invoker set search_path=pg_catalog,public as $$
 select coalesce(jsonb_agg(jsonb_build_object('receipt_id',r.id,'filename',r.filename,'sha256',r.sha256) order by r.id),'[]'::jsonb)
 from public.korlix_bookkeeping_receipt_links l join public.korlix_bookkeeping_receipts r on r.id=l.receipt_id and r.business_id=l.business_id
 where l.business_id=p_business and l.unlinked_at is null and
 ((p_source='cash' and l.entry_id=p_entry) or (p_source='journal' and l.journal_id=p_entry));
$$;
revoke all on function public.korlix_bookkeeping_evidence_v1(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_evidence_v1(uuid,text,uuid) to service_role;
create or replace function public.korlix_bookkeeping_receipts_v1(p_actor uuid,p_action text,p_business uuid,p_receipt uuid default null,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; rec public.korlix_bookkeeping_receipts; link public.korlix_bookkeeping_receipt_links;
 scan public.korlix_bookkeeping_receipt_scans; ent public.korlix_bookkeeping_entries;
 result jsonb; items jsonb; total_n integer; used_bytes bigint; offset_n integer; target_entry_id uuid; target_journal_id uuid; journal public.korlix_bookkeeping_journals; k uuid; dispatch boolean:=false;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Invalid receipt request.'; end if;
 -- All write paths use the same lock order: owner quota, business, receipt.
 perform pg_advisory_xact_lock(hashtextextended('bookkeeping-receipts:'||p_actor::text,0));
 select * into b from public.korlix_bookkeeping_businesses where id=p_business and owner_id=p_actor for update;
 if not found then raise exception 'Business not found.' using errcode='P0002'; end if;
 if p_action='list' then
  offset_n=coalesce((p_data->>'offset')::integer,0);if offset_n<0 or offset_n>10000 then raise exception 'Invalid receipt page.'; end if;
  select count(*) into total_n from public.korlix_bookkeeping_receipts where business_id=b.id and state<>'removed';
  select coalesce(sum(byte_size+preview_size),0) into used_bytes from public.korlix_bookkeeping_receipts where created_by=p_actor and state<>'removed';
  select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) into items from (
   select rr.id,rr.created_at,(to_jsonb(rr)-'request_key'-'created_by'-'upload_token'-'upload_lease_until')||jsonb_build_object(
    'link',(select to_jsonb(ll) from public.korlix_bookkeeping_receipt_links ll where ll.receipt_id=rr.id and ll.unlinked_at is null),
    'linked_entry',(select jsonb_build_object('kind',ee.kind,'entry_date',ee.entry_date,'amount_cents',ee.amount_cents::text,'purpose',ee.purpose) from public.korlix_bookkeeping_receipt_links ll join public.korlix_bookkeeping_entries ee on ee.id=ll.entry_id where ll.receipt_id=rr.id and ll.unlinked_at is null),
    'linked_journal',(select jsonb_build_object('id',jj.id,'kind',jj.kind,'entry_date',jj.entry_date,'purpose',jj.purpose) from public.korlix_bookkeeping_receipt_links ll join public.korlix_bookkeeping_journals jj on jj.id=ll.journal_id where ll.receipt_id=rr.id and ll.unlinked_at is null),
    'retained',exists(select 1 from public.korlix_bookkeeping_receipt_links ll where ll.receipt_id=rr.id),
    'scan',(select to_jsonb(ss)-'request_key'-'actor_id' from public.korlix_bookkeeping_receipt_scans ss where ss.receipt_id=rr.id order by ss.created_at desc,ss.id limit 1)) item
   from public.korlix_bookkeeping_receipts rr where rr.business_id=b.id and rr.state<>'removed' order by rr.created_at desc,rr.id limit 30 offset offset_n
  ) x;
  return jsonb_build_object('receipts',items,'total',total_n,'offset',offset_n,'used_bytes',used_bytes,'max_bytes',262144000,'max_file_bytes',8388608);
 end if;
 if p_action='entry_receipts' then
  target_entry_id=(p_data->>'entry_id')::uuid;
  if not exists(select 1 from public.korlix_bookkeeping_entries where id=target_entry_id and business_id=b.id) then raise exception 'Entry not found.' using errcode='P0002'; end if;
  select coalesce(reversal_of,id) into target_entry_id from public.korlix_bookkeeping_entries where id=target_entry_id and business_id=b.id;
  select coalesce(jsonb_agg((to_jsonb(rr)-'request_key'-'created_by'-'upload_token'-'upload_lease_until')||jsonb_build_object('link',to_jsonb(ll)) order by ll.linked_at),'[]'::jsonb) into items
   from public.korlix_bookkeeping_receipt_links ll join public.korlix_bookkeeping_receipts rr on rr.id=ll.receipt_id where ll.business_id=b.id and ll.entry_id=target_entry_id;
  return jsonb_build_object('receipts',items);
 end if;
 if p_action='journal_receipts' then
  select * into journal from public.korlix_bookkeeping_journals where id=(p_data->>'journal_id')::uuid and business_id=b.id;
  if not found then raise exception 'Journal not found.' using errcode='P0002'; end if;
  target_journal_id=coalesce(journal.reversal_of,journal.id);
  select coalesce(jsonb_agg((to_jsonb(rr)-'request_key'-'created_by'-'upload_token'-'upload_lease_until')||jsonb_build_object('link',to_jsonb(ll)) order by ll.linked_at,ll.id),'[]'::jsonb) into items
   from public.korlix_bookkeeping_receipt_links ll join public.korlix_bookkeeping_receipts rr on rr.id=ll.receipt_id
   where ll.business_id=b.id and ll.journal_id=target_journal_id;
  return jsonb_build_object('receipts',items,'journal_id',journal.id,'evidence_journal_id',target_journal_id,
   'can_attach',journal.kind<>'reversal' and not exists(select 1 from public.korlix_bookkeeping_journals where reversal_of=journal.id));
 end if;
 if p_action='reserve_upload' then
  k=(p_data->>'request_key')::uuid;
  select * into rec from public.korlix_bookkeeping_receipts where business_id=b.id and request_key=k;
  if found then
   if rec.sha256<>p_data->>'sha256' or rec.byte_size<>(p_data->>'byte_size')::integer or rec.state in ('deleting','removed') then raise exception 'This upload request has already been used. Choose the original file or start a new upload.' using errcode='40001'; end if;
  else
   select * into rec from public.korlix_bookkeeping_receipts where business_id=b.id and sha256=p_data->>'sha256' and state<>'removed';
   if found and rec.state='deleting' then raise exception 'This receipt is being deleted. Finish deletion before uploading again.' using errcode='40001'; end if;
   if not found then
    select coalesce(sum(byte_size+preview_size),0),count(*) into used_bytes,total_n from public.korlix_bookkeeping_receipts where created_by=p_actor and state<>'removed';
    if used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000 or total_n>=1000 then raise exception 'Receipt storage limit reached: 250 MB or 1,000 files across your businesses.' using errcode='54000'; end if;
    insert into public.korlix_bookkeeping_receipts(business_id,created_by,request_key,filename,mime_type,byte_size,sha256,preview_size,preview_sha256,pages)
     values(b.id,p_actor,k,p_data->>'filename',p_data->>'mime_type',(p_data->>'byte_size')::integer,p_data->>'sha256',coalesce((p_data->>'preview_size')::integer,0),p_data->>'preview_sha256',coalesce((p_data->>'pages')::integer,1)) returning * into rec;
    insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'receipt_upload_reserved',jsonb_build_object('receipt_id',rec.id,'sha256',rec.sha256));dispatch=true;
   end if;
  end if;
  if rec.state='uploading' and rec.upload_lease_until<=now() then
   update public.korlix_bookkeeping_receipts set upload_token=gen_random_uuid(),upload_lease_until=now()+interval '10 minutes' where id=rec.id returning * into rec;dispatch=true;
  end if;
 else
  select * into rec from public.korlix_bookkeeping_receipts where id=p_receipt and business_id=b.id for update;
  if not found or rec.state='removed' then
   if p_action='finish_delete' and found then return jsonb_build_object('removed',true); end if;
   raise exception 'Receipt not found.' using errcode='P0002';
  end if;
 end if;
 if p_action in ('get','reserve_upload','ready') then
  if p_action='ready' then
   if rec.state='uploading' then
    if rec.upload_token is distinct from (p_data->>'upload_token')::uuid then raise exception 'This upload lease changed. Refresh the receipt.' using errcode='40001'; end if;
    update public.korlix_bookkeeping_receipts set state='ready',ready_at=now() where id=rec.id returning * into rec;
    insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'receipt_uploaded',jsonb_build_object('receipt_id',rec.id));
   elsif rec.state<>'ready' then raise exception 'This receipt is not available.' using errcode='40001'; end if;
  end if;
  return jsonb_build_object('receipt',to_jsonb(rec)-'request_key'-'upload_token'-'upload_lease_until','dispatch',dispatch,'upload_token',rec.upload_token,'object_path',p_actor::text||'/'||b.id::text||'/'||rec.id::text||'/original','preview_path',case when rec.preview_size>0 then p_actor::text||'/'||b.id::text||'/'||rec.id::text||'/preview.webp' else null end);
 end if;
 if p_action in ('begin_delete','finish_delete') then
  if (p_data->'confirmed') is distinct from 'true'::jsonb then raise exception 'Confirm receipt deletion.'; end if;
  if rec.state='uploading' and rec.upload_lease_until>now() then raise exception 'This upload may still be running. Refresh or wait up to 10 minutes before deleting.' using errcode='40001'; end if;
  if exists(select 1 from public.korlix_bookkeeping_receipt_links where receipt_id=rec.id) then raise exception 'A receipt used as entry evidence is retained with its history. It cannot be deleted here.' using errcode='40001'; end if;
  if exists(select 1 from public.korlix_bookkeeping_receipt_scans where receipt_id=rec.id and state='scanning' and created_at>now()-interval '5 minutes') then raise exception 'Wait for the active scan before deleting.' using errcode='40001'; end if;
  if p_action='begin_delete' then
   update public.korlix_bookkeeping_receipts set state='deleting' where id=rec.id;
   return jsonb_build_object('object_path',p_actor::text||'/'||b.id::text||'/'||rec.id::text||'/original','preview_path',case when rec.preview_size>0 then p_actor::text||'/'||b.id::text||'/'||rec.id::text||'/preview.webp' else null end);
  end if;
  if rec.state<>'deleting' then raise exception 'Start receipt deletion first.'; end if;
  update public.korlix_bookkeeping_receipts set state='removed',removed_at=now() where id=rec.id;
  insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'receipt_deleted',jsonb_build_object('receipt_id',rec.id,'sha256',rec.sha256));
  return jsonb_build_object('removed',true);
 end if;
 if rec.state<>'ready' then raise exception 'Finish uploading this receipt first.' using errcode='40001'; end if;
 if p_action in ('link','link_journal','post_entry','unlink') then
  if (p_data->'confirmed') is distinct from 'true'::jsonb then raise exception 'Review and confirm receipt attachment.'; end if;
  if p_action='unlink' then
   select * into link from public.korlix_bookkeeping_receipt_links where id=(p_data->>'link_id')::uuid and receipt_id=rec.id and business_id=b.id;
   if not found then raise exception 'Receipt link not found.' using errcode='P0002'; end if;
   if length(btrim(coalesce(p_data->>'reason',''))) not between 1 and 500 then raise exception 'Enter a correction reason.'; end if;
   if link.unlinked_at is null then
    update public.korlix_bookkeeping_receipt_links set unlinked_at=now(),unlink_reason=btrim(p_data->>'reason') where id=link.id returning * into link;
    insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'receipt_unlinked',to_jsonb(link));
   end if;
   return jsonb_build_object('link',to_jsonb(link));
  end if;
  k=case when p_action='post_entry' then (p_data->'entry'->>'request_key')::uuid else (p_data->>'request_key')::uuid end;
  if p_action='link_journal' and k is null then raise exception 'A receipt attachment request key is required.'; end if;
  if k is not null then
   select * into link from public.korlix_bookkeeping_receipt_links where business_id=b.id and request_key=k;
   if found then
    if link.receipt_id<>rec.id or
     (p_action='link_journal' and link.journal_id is distinct from (p_data->>'journal_id')::uuid) or
     (p_action='link' and link.entry_id is distinct from (p_data->>'entry_id')::uuid) then
     raise exception 'This attachment request key has already been used.' using errcode='40001';
    end if;
    if p_action='post_entry' then result=public.korlix_bookkeeping_v1(p_actor,'post',b.id,p_data->'entry');
     if link.entry_id is distinct from (result->'entry'->>'id')::uuid then raise exception 'This attachment request key has already been used.' using errcode='40001'; end if;
    end if;
    return coalesce(result,'{}'::jsonb)||jsonb_build_object('link',to_jsonb(link),'reused',true);
   end if;
  end if;
  if p_action='link_journal' then
   target_journal_id=(p_data->>'journal_id')::uuid;
   select * into journal from public.korlix_bookkeeping_journals where id=target_journal_id and business_id=b.id;
   if not found then raise exception 'Journal not found.' using errcode='P0002'; end if;
   if journal.kind='reversal' or exists(select 1 from public.korlix_bookkeeping_journals where reversal_of=journal.id) then raise exception 'Choose a journal that has not been reversed.' using errcode='40001'; end if;
  else
   if p_action='post_entry' then
    result=public.korlix_bookkeeping_v1(p_actor,'post',b.id,p_data->'entry');target_entry_id=(result->'entry'->>'id')::uuid;
    -- Preserve evidence history when replaying a pre-upgrade posted entry.
    select * into link from public.korlix_bookkeeping_receipt_links where receipt_id=rec.id and entry_id=target_entry_id order by linked_at,id limit 1;
    if found then return result||jsonb_build_object('link',to_jsonb(link),'reused',true); end if;
   else target_entry_id=(p_data->>'entry_id')::uuid; end if;
   select * into ent from public.korlix_bookkeeping_entries where id=target_entry_id and business_id=b.id;
   if not found then raise exception 'Entry not found.' using errcode='P0002'; end if;
   if ent.kind='reversal' or exists(select 1 from public.korlix_bookkeeping_entries where reversal_of=ent.id) then raise exception 'Choose an entry that has not been reversed.' using errcode='40001'; end if;
  end if;
  select * into link from public.korlix_bookkeeping_receipt_links where receipt_id=rec.id and unlinked_at is null;
  if found then
   if link.entry_id is distinct from target_entry_id or link.journal_id is distinct from target_journal_id then
    raise exception 'This receipt is already linked. Correct its current association first.' using errcode='40001';
   end if;
   if k is not null and link.request_key is distinct from k then raise exception 'This receipt is already attached. Refresh its history before making another decision.' using errcode='40001'; end if;
  else
   insert into public.korlix_bookkeeping_receipt_links(business_id,receipt_id,entry_id,journal_id,request_key,linked_by)
    values(b.id,rec.id,target_entry_id,target_journal_id,k,p_actor) returning * into link;
   insert into public.korlix_bookkeeping_audit(business_id,actor_id,action,details) values(b.id,p_actor,'receipt_linked',to_jsonb(link));
  end if;
  return coalesce(result,'{}'::jsonb)||jsonb_build_object('link',to_jsonb(link));
 end if;
 if p_action='scan_status' then
  select to_jsonb(ss)-'request_key'-'actor_id' into result from public.korlix_bookkeeping_receipt_scans ss where receipt_id=rec.id order by created_at desc,id limit 1;
  return jsonb_build_object('scan',result);
 end if;
 if p_action='scan_begin' then
  if (p_data->'confirmed') is distinct from 'true'::jsonb then raise exception 'Confirm AI scanning first.'; end if;
  k=(p_data->>'request_key')::uuid;
  select * into scan from public.korlix_bookkeeping_receipt_scans where actor_id=p_actor and request_key=k;
  if found then
   if scan.receipt_id<>rec.id then raise exception 'This scan request has already been used.' using errcode='40001'; end if;
  else
   update public.korlix_bookkeeping_receipt_scans set state='expired',finished_at=now() where actor_id=p_actor and state='scanning' and created_at<=now()-interval '5 minutes';
   if exists(select 1 from public.korlix_bookkeeping_receipt_scans where actor_id=p_actor and state='scanning') then raise exception 'A receipt scan is already running. Refresh its status before scanning again.' using errcode='40001'; end if;
   if coalesce((p_data->>'daily_limit')::integer,0) not between 1 and 250 then raise exception 'Scanning usage is unavailable.'; end if;
   select count(*) into total_n from public.korlix_bookkeeping_receipt_scans where actor_id=p_actor and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
   if total_n>=(p_data->>'daily_limit')::integer then raise exception 'Daily receipt scan limit reached. Try again tomorrow.' using errcode='54000'; end if;
   if rec.pages>3 then raise exception 'AI receipt scanning supports up to 3 PDF pages. Upload a shorter receipt or enter its details manually.'; end if;
   insert into public.korlix_bookkeeping_receipt_scans(business_id,receipt_id,actor_id,request_key) values(b.id,rec.id,p_actor,k) returning * into scan;dispatch=true;
  end if;
  return jsonb_build_object('scan',to_jsonb(scan)-'request_key'-'actor_id','dispatch',dispatch);
 end if;
 if p_action in ('scan_finish','scan_fail') then
  select * into scan from public.korlix_bookkeeping_receipt_scans where id=(p_data->>'scan_id')::uuid and receipt_id=rec.id and actor_id=p_actor for update;
  if not found then raise exception 'Scan not found.' using errcode='P0002'; end if;
  if scan.state='scanning' then
   update public.korlix_bookkeeping_receipt_scans set state=case when p_action='scan_finish' then 'ready' else 'failed' end,
    suggestions=case when p_action='scan_finish' then p_data->'suggestions' else null end,finished_at=now() where id=scan.id returning * into scan;
  end if;
  return jsonb_build_object('scan',to_jsonb(scan)-'request_key'-'actor_id');
 end if;
 raise exception 'Unknown receipt action.';
end $$;

create or replace function public.korlix_bookkeeping_reports_v1(p_actor uuid,p_business uuid,p_data jsonb default '{}') returns jsonb
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
    public.korlix_bookkeeping_evidence_v1(b.id,ll.source,coalesce(ll.reversal_of,ll.entry_id)) receipts
   from public.korlix_bookkeeping_all_lines ll join public.korlix_bookkeeping_accounts aa on aa.business_id=ll.business_id and aa.code=ll.account_code
   where ll.business_id=b.id and ll.entry_date>=from_date and ll.entry_date<until_date
  ) x;
 end if;
 return jsonb_build_object('business',to_jsonb(b)-'creation_request'-'request_key','period',p_data->>'period','from_date',from_date,'as_of',until_date-1,
  'generated_at',now(),'accounts',accounts_json,'opening',opening_json,'first_recorded_date',first_date,
  'cash_entry_count',cash_n,'journal_count',journal_n,'lines',rows_json);
end $$;
create or replace function public.korlix_bookkeeping_ledger_v1(p_actor uuid,p_action text,p_business uuid,p_data jsonb default '{}') returns jsonb
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
    select ll.entry_id,ll.entry_date,ll.source,ll.kind,ll.purpose,ll.account_code,aa.name account_name,aa.kind account_kind,ll.debit_cents::text,ll.credit_cents::text,ll.reversal_of,ll.created_at,
     public.korlix_bookkeeping_evidence_v1(b.id,ll.source,coalesce(ll.reversal_of,ll.entry_id)) receipts
    from public.korlix_bookkeeping_all_lines ll join public.korlix_bookkeeping_accounts aa on aa.business_id=ll.business_id and aa.code=ll.account_code
    where ll.business_id=b.id and ll.entry_date>=from_date and ll.entry_date<until_date) x;
  end if;
  return jsonb_build_object('business',to_jsonb(b)-'request_key'-'creation_request','month',p_data->>'month','as_of',(until_date-1)::text,'accounts',accounts_json,'journals',result,'journal_count',total_n,'offset',offset_n,'opening',opening_json,'lines',lines_json);
 end if;
 raise exception 'Unknown ledger action.';
end $$;

revoke all on function public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb),public.korlix_bookkeeping_reports_v1(uuid,uuid,jsonb),public.korlix_bookkeeping_ledger_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb),public.korlix_bookkeeping_reports_v1(uuid,uuid,jsonb),public.korlix_bookkeeping_ledger_v1(uuid,text,uuid,jsonb) to service_role;
