-- K199 private receipt originals, reviewed associations and bounded OCR jobs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('korlix-bookkeeping-receipts','korlix-bookkeeping-receipts',false,8388608,array['image/jpeg','image/png','image/webp','application/pdf'])
 on conflict(id) do nothing;
do $$ begin
 if not exists(select 1 from storage.buckets where id='korlix-bookkeeping-receipts' and public=false and file_size_limit=8388608) then
  raise exception 'Receipt bucket configuration conflicts with this migration.';
 end if;
end $$;
-- Even future permissive policies on other buckets cannot expose receipts.
create policy bookkeeping_receipts_server_only on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'korlix-bookkeeping-receipts') with check(bucket_id<>'korlix-bookkeeping-receipts');

create table public.korlix_bookkeeping_receipts (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.korlix_bookkeeping_businesses(id),
 created_by uuid not null references auth.users(id),
 request_key uuid not null,
 filename text not null check(length(filename) between 1 and 160),
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 8388608),
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 preview_size integer not null default 0 check(preview_size between 0 and 1048576),
 preview_sha256 text check(preview_sha256 ~ '^[0-9a-f]{64}$'),
 pages integer not null default 1 check(pages between 1 and 10),
 upload_token uuid not null default gen_random_uuid(),
 upload_lease_until timestamptz not null default now()+interval '10 minutes',
 state text not null default 'uploading' check(state in ('uploading','ready','deleting','removed')),
 created_at timestamptz not null default now(),
 ready_at timestamptz, removed_at timestamptz,
 unique(business_id,id),unique(business_id,request_key),
 check((preview_size=0)=(preview_sha256 is null))
);
create unique index bookkeeping_receipt_hash on public.korlix_bookkeeping_receipts(business_id,sha256) where state<>'removed';
create index bookkeeping_receipt_owner on public.korlix_bookkeeping_receipts(created_by,state);
create index bookkeeping_receipt_list on public.korlix_bookkeeping_receipts(business_id,created_at desc,id);
create table public.korlix_bookkeeping_receipt_links (
 id uuid primary key default gen_random_uuid(), business_id uuid not null,
 receipt_id uuid not null, entry_id uuid not null,
 linked_by uuid not null references auth.users(id), linked_at timestamptz not null default now(),
 unlinked_at timestamptz, unlink_reason text check(length(unlink_reason) between 1 and 500),
 foreign key(business_id,receipt_id) references public.korlix_bookkeeping_receipts(business_id,id),
 foreign key(business_id,entry_id) references public.korlix_bookkeeping_entries(business_id,id),
 check((unlinked_at is null)=(unlink_reason is null))
);
create unique index bookkeeping_receipt_one_active_entry on public.korlix_bookkeeping_receipt_links(receipt_id) where unlinked_at is null;
create index bookkeeping_receipt_links_receipt on public.korlix_bookkeeping_receipt_links(business_id,receipt_id);
create index bookkeeping_receipt_links_entry on public.korlix_bookkeeping_receipt_links(business_id,entry_id);
create index bookkeeping_receipt_links_actor on public.korlix_bookkeeping_receipt_links(linked_by);
create table public.korlix_bookkeeping_receipt_scans (
 id uuid primary key default gen_random_uuid(), business_id uuid not null, receipt_id uuid not null,
 actor_id uuid not null references auth.users(id),request_key uuid not null,
 state text not null default 'scanning' check(state in ('scanning','ready','failed','expired')),
 suggestions jsonb, created_at timestamptz not null default now(), finished_at timestamptz,
 foreign key(business_id,receipt_id) references public.korlix_bookkeeping_receipts(business_id,id),
 unique(actor_id,request_key), check(suggestions is null or (jsonb_typeof(suggestions)='object' and length(suggestions::text)<=6000))
);
create unique index bookkeeping_scan_one_pending on public.korlix_bookkeeping_receipt_scans(actor_id) where state='scanning';
create index bookkeeping_scan_receipt on public.korlix_bookkeeping_receipt_scans(business_id,receipt_id,created_at desc);
create index bookkeeping_scan_daily on public.korlix_bookkeeping_receipt_scans(actor_id,created_at);

create function public.korlix_bookkeeping_receipt_guard_v1() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if tg_op='DELETE' then raise exception 'Receipt history cannot be deleted.' using errcode='23514'; end if;
 if tg_table_name='korlix_bookkeeping_receipts' then
  if (to_jsonb(new)-array['state','ready_at','removed_at','upload_token','upload_lease_until'])<>(to_jsonb(old)-array['state','ready_at','removed_at','upload_token','upload_lease_until']) then raise exception 'Receipt originals cannot be replaced.' using errcode='23514'; end if;
  if (new.upload_token<>old.upload_token or new.upload_lease_until<>old.upload_lease_until) and (old.state<>'uploading' or new.state<>'uploading') then raise exception 'Upload lease is closed.' using errcode='23514'; end if;
  if new.state<>old.state and not ((old.state='uploading' and new.state in ('ready','deleting')) or (old.state='ready' and new.state='deleting') or (old.state='deleting' and new.state='removed')) then raise exception 'Invalid receipt transition.' using errcode='23514'; end if;
  if new.state in ('deleting','removed') and exists(select 1 from public.korlix_bookkeeping_receipt_links where receipt_id=new.id) then raise exception 'Receipts used as entry evidence must be retained.' using errcode='23514'; end if;
 elsif tg_table_name='korlix_bookkeeping_receipt_links' then
  if old.unlinked_at is not null or (to_jsonb(new)-array['unlinked_at','unlink_reason'])<>(to_jsonb(old)-array['unlinked_at','unlink_reason']) or new.unlinked_at is null then raise exception 'Receipt link history cannot be replaced.' using errcode='23514'; end if;
 else
  if old.state<>'scanning' or (to_jsonb(new)-array['state','suggestions','finished_at'])<>(to_jsonb(old)-array['state','suggestions','finished_at']) or new.state='scanning' then raise exception 'Scan history cannot be replaced.' using errcode='23514'; end if;
 end if;
 return new;
end $$;
create trigger bookkeeping_receipts_guard before update or delete on public.korlix_bookkeeping_receipts for each row execute function public.korlix_bookkeeping_receipt_guard_v1();
create trigger bookkeeping_receipt_links_guard before update or delete on public.korlix_bookkeeping_receipt_links for each row execute function public.korlix_bookkeeping_receipt_guard_v1();
create trigger bookkeeping_receipt_scans_guard before update or delete on public.korlix_bookkeeping_receipt_scans for each row execute function public.korlix_bookkeeping_receipt_guard_v1();

create function public.korlix_bookkeeping_receipts_v1(p_actor uuid,p_action text,p_business uuid,p_receipt uuid default null,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare b public.korlix_bookkeeping_businesses; rec public.korlix_bookkeeping_receipts; link public.korlix_bookkeeping_receipt_links;
 scan public.korlix_bookkeeping_receipt_scans; ent public.korlix_bookkeeping_entries;
 result jsonb; items jsonb; total_n integer; used_bytes bigint; offset_n integer; target_entry_id uuid; k uuid; dispatch boolean:=false;
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
    'retained',exists(select 1 from public.korlix_bookkeeping_receipt_links ll where ll.receipt_id=rr.id),
    'scan',(select to_jsonb(ss)-'request_key'-'actor_id' from public.korlix_bookkeeping_receipt_scans ss where ss.receipt_id=rr.id order by ss.created_at desc,ss.id limit 1)) item
   from public.korlix_bookkeeping_receipts rr where rr.business_id=b.id and rr.state<>'removed' order by rr.created_at desc,rr.id limit 30 offset offset_n
  ) x;
  return jsonb_build_object('receipts',items,'total',total_n,'offset',offset_n,'used_bytes',used_bytes,'max_bytes',262144000,'max_file_bytes',8388608);
 end if;
 if p_action='entry_receipts' then
  target_entry_id=(p_data->>'entry_id')::uuid;
  if not exists(select 1 from public.korlix_bookkeeping_entries where id=target_entry_id and business_id=b.id) then raise exception 'Entry not found.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg((to_jsonb(rr)-'request_key'-'created_by'-'upload_token'-'upload_lease_until')||jsonb_build_object('link',to_jsonb(ll)) order by ll.linked_at),'[]'::jsonb) into items
   from public.korlix_bookkeeping_receipt_links ll join public.korlix_bookkeeping_receipts rr on rr.id=ll.receipt_id where ll.business_id=b.id and ll.entry_id=target_entry_id;
  return jsonb_build_object('receipts',items);
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
 if p_action in ('link','post_entry','unlink') then
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
  if p_action='post_entry' then
   result=public.korlix_bookkeeping_v1(p_actor,'post',b.id,p_data->'entry');target_entry_id=(result->'entry'->>'id')::uuid;
  else target_entry_id=(p_data->>'entry_id')::uuid; end if;
  select * into ent from public.korlix_bookkeeping_entries where id=target_entry_id and business_id=b.id;
  if not found then raise exception 'Entry not found.' using errcode='P0002'; end if;
  if ent.kind='reversal' or exists(select 1 from public.korlix_bookkeeping_entries where reversal_of=ent.id) then raise exception 'Choose an entry that has not been reversed.' using errcode='40001'; end if;
  select * into link from public.korlix_bookkeeping_receipt_links where receipt_id=rec.id and unlinked_at is null;
  if found then
   if link.entry_id<>ent.id then raise exception 'This receipt is already linked. Correct its current association first.' using errcode='40001'; end if;
  else
   insert into public.korlix_bookkeeping_receipt_links(business_id,receipt_id,entry_id,linked_by) values(b.id,rec.id,ent.id,p_actor) returning * into link;
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

alter table public.korlix_bookkeeping_receipts enable row level security;
alter table public.korlix_bookkeeping_receipt_links enable row level security;
alter table public.korlix_bookkeeping_receipt_scans enable row level security;
revoke all on public.korlix_bookkeeping_receipts,public.korlix_bookkeeping_receipt_links,public.korlix_bookkeeping_receipt_scans from public,anon,authenticated,service_role;
grant select,insert on public.korlix_bookkeeping_receipts,public.korlix_bookkeeping_receipt_links,public.korlix_bookkeeping_receipt_scans to service_role;
grant update(state,ready_at,removed_at,upload_token,upload_lease_until) on public.korlix_bookkeeping_receipts to service_role;
grant update(unlinked_at,unlink_reason) on public.korlix_bookkeeping_receipt_links to service_role;
grant update(state,suggestions,finished_at) on public.korlix_bookkeeping_receipt_scans to service_role;
revoke all on function public.korlix_bookkeeping_receipt_guard_v1() from public,anon,authenticated;
revoke all on function public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_bookkeeping_receipts_v1(uuid,text,uuid,uuid,jsonb) to service_role;
