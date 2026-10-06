-- Private owner-scoped originals shared by Receipt Wiz and finance inboxes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('korlix-receipt-wiz','korlix-receipt-wiz',false,8388608,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do nothing;
do $$ begin
 if not exists(select 1 from storage.buckets where id='korlix-receipt-wiz' and public=false and file_size_limit=8388608) then raise exception 'Receipt Wiz bucket configuration conflicts.'; end if;
end $$;
create policy receipt_wiz_private on storage.objects as restrictive for all to anon,authenticated
using(bucket_id<>'korlix-receipt-wiz') with check(bucket_id<>'korlix-receipt-wiz');
create table public.korlix_receipt_wiz (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 request_key uuid not null, filename text not null check(length(filename) between 1 and 160),
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 8388608),sha256 text not null check(sha256~'^[a-f0-9]{64}$'),
 preview_size integer not null default 0 check(preview_size between 0 and 1048576),preview_sha256 text check(preview_sha256~'^[a-f0-9]{64}$'),
 pages integer not null check(pages between 1 and 10),
 state text not null default 'uploading' check(state in ('uploading','ready','deleting')),
 upload_token uuid not null default gen_random_uuid(),upload_until timestamptz not null default now()+interval '2 minutes',
 details jsonb not null default '{}' check(jsonb_typeof(details)='object' and octet_length(details::text)<=16000),
 reviewed boolean not null default false,version integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(owner_id,request_key),unique(owner_id,sha256),check((preview_size=0)=(preview_sha256 is null))
);
create index receipt_wiz_owner_list on public.korlix_receipt_wiz(owner_id,created_at desc,id);
create table public.korlix_receipt_wiz_usage (
 owner_id uuid not null references auth.users(id) on delete cascade,day date not null,attempts integer not null check(attempts between 0 and 100),primary key(owner_id,day)
);
alter table public.korlix_receipt_wiz_usage enable row level security;
revoke all on public.korlix_receipt_wiz_usage from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_receipt_wiz_usage to service_role;
create table public.korlix_receipt_wiz_scans (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id) on delete cascade,
 receipt_id uuid not null references public.korlix_receipt_wiz(id) on delete cascade,request_key uuid not null,
 state text not null default 'scanning' check(state in ('scanning','ready','failed','expired')),
 receipt_version integer not null,suggestion jsonb,
 created_at timestamptz not null default now(),finished_at timestamptz,
 unique(owner_id,request_key),check(suggestion is null or (jsonb_typeof(suggestion)='object' and octet_length(suggestion::text)<=16000))
);
create index receipt_wiz_scan_daily on public.korlix_receipt_wiz_scans(owner_id,created_at);
create index receipt_wiz_scan_receipt on public.korlix_receipt_wiz_scans(receipt_id,created_at desc);
create unique index receipt_wiz_one_scan on public.korlix_receipt_wiz_scans(owner_id) where state='scanning';
alter table public.korlix_receipt_wiz enable row level security;
alter table public.korlix_receipt_wiz_scans enable row level security;
revoke all on public.korlix_receipt_wiz,public.korlix_receipt_wiz_scans from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_receipt_wiz,public.korlix_receipt_wiz_scans to service_role;

create function public.korlix_receipt_wiz_item_v1(p_receipt public.korlix_receipt_wiz) returns jsonb
language sql stable security invoker set search_path=pg_catalog,public as $$
 select (to_jsonb(p_receipt)-array['owner_id','request_key','upload_token','upload_until'])||jsonb_build_object('scan',(
 select jsonb_build_object('id',s.id,'state',case when s.state='scanning' and s.created_at<now()-interval '3 minutes' then 'expired' else s.state end,'created_at',s.created_at,'suggestion',s.suggestion)
 from public.korlix_receipt_wiz_scans s where s.receipt_id=p_receipt.id order by s.created_at desc,s.id limit 1));
$$;
create function public.korlix_receipt_wiz_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare rec public.korlix_receipt_wiz;job public.korlix_receipt_wiz_scans;result jsonb;items jsonb;links jsonb;
 used_bytes bigint;total_n integer;off integer;yr text;q text;cat text;pending boolean:=false;k uuid;dispatch boolean:=false;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'Invalid receipt request.';end if;
 perform pg_advisory_xact_lock(hashtextextended('receipt-wiz:'||p_actor::text,0));
 if p_data ? 'business_id' and not exists(select 1 from public.korlix_bookkeeping_businesses where id=(p_data->>'business_id')::uuid and owner_id=p_actor) then raise exception 'Business not found.' using errcode='P0002';end if;
 if p_data ? 'tax_workspace_id' and not exists(select 1 from public.korlix_tax_workspaces where id=(p_data->>'tax_workspace_id')::uuid and owner_id=p_actor) then raise exception 'Tax organizer not found.' using errcode='P0002';end if;
 links:=jsonb_build_object('bookkeeping',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.korlix_bookkeeping_businesses where owner_id=p_actor),'[]'),
 'tax_prep',coalesce((select jsonb_agg(jsonb_build_object('id',id,'year',tax_year) order by tax_year desc) from public.korlix_tax_workspaces where owner_id=p_actor),'[]'));
 if p_action in ('list','export') then
  off:=coalesce((p_data->>'offset')::integer,0);yr:=coalesce(p_data->>'year','');q:=lower(coalesce(p_data->>'query',''));cat:=coalesce(p_data->>'category','');pending:=coalesce((p_data->>'needs_review')::boolean,false);
  if off<0 or off>1000 or length(q)>160 or (yr<>'' and yr!~'^20[0-9]{2}$') then raise exception 'Invalid receipt filter.';end if;
  select coalesce(sum(byte_size+preview_size),0) into used_bytes from public.korlix_receipt_wiz where owner_id=p_actor;
  select count(*) into total_n from public.korlix_receipt_wiz where owner_id=p_actor
   and (yr='' or coalesce(details->>'date','')='' or left(details->>'date',4)=yr)
   and (cat='' or coalesce(details->>'category','Uncategorized')=cat) and (not pending or not reviewed)
   and (q='' or position(q in lower(filename||' '||coalesce(details->>'merchant','')||' '||coalesce(details->>'description','')||' '||coalesce(details->>'items','')))>0);
  select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]') into items from (
   select id,created_at,public.korlix_receipt_wiz_item_v1(r) item from public.korlix_receipt_wiz r where owner_id=p_actor
   and (yr='' or coalesce(details->>'date','')='' or left(details->>'date',4)=yr)
   and (cat='' or coalesce(details->>'category','Uncategorized')=cat) and (not pending or not reviewed)
   and (q='' or position(q in lower(filename||' '||coalesce(details->>'merchant','')||' '||coalesce(details->>'description','')||' '||coalesce(details->>'items','')))>0)
   order by created_at desc,id limit case when p_action='export' then 1000 else 30 end offset off
  )x;
  return jsonb_build_object('receipts',items,'total',total_n,'offset',off,'used_bytes',used_bytes,'max_bytes',262144000,'max_receipts',1000,'integrations',links,'daily_scan_limit',100,'scans_today',coalesce((select attempts from public.korlix_receipt_wiz_usage where owner_id=p_actor and day=(now() at time zone 'UTC')::date),0));
 end if;
 if p_action='reserve' then
  k:=(p_data->>'request_key')::uuid;
  select * into rec from public.korlix_receipt_wiz where owner_id=p_actor and request_key=k;
  if found and rec.sha256 is distinct from p_data->>'sha256' then raise exception 'This upload key belongs to another file.' using errcode='40001';end if;
  if not found then select * into rec from public.korlix_receipt_wiz where owner_id=p_actor and sha256=p_data->>'sha256';end if;
  if rec.id is null then
   select count(*),coalesce(sum(byte_size+preview_size),0) into total_n,used_bytes from public.korlix_receipt_wiz where owner_id=p_actor;
   if total_n>=1000 or used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>262144000 then raise exception 'Your receipt vault is full (1,000 receipts or 250 MB). Export and remove unneeded receipts to make room.' using errcode='54000';end if;
   insert into public.korlix_receipt_wiz(owner_id,request_key,filename,mime_type,byte_size,sha256,preview_size,preview_sha256,pages)
   values(p_actor,k,p_data->>'filename',p_data->>'mime_type',(p_data->>'byte_size')::integer,p_data->>'sha256',(p_data->>'preview_size')::integer,p_data->>'preview_sha256',(p_data->>'pages')::integer) returning * into rec;dispatch:=true;
  elsif rec.state='deleting' then raise exception 'Finish deleting this receipt before uploading it again.' using errcode='40001';
  elsif rec.state='uploading' and rec.upload_until<now() then
   update public.korlix_receipt_wiz set upload_token=gen_random_uuid(),upload_until=now()+interval '2 minutes' where id=rec.id returning * into rec;dispatch:=true;
  end if;
 else
  select * into rec from public.korlix_receipt_wiz where id=p_id and owner_id=p_actor for update;
  if not found then raise exception 'Receipt not found.' using errcode='P0002';end if;
  if p_action='ready' then
   if rec.state<>'uploading' or rec.upload_token is distinct from (p_data->>'upload_token')::uuid then raise exception 'This upload was superseded. Refresh its status.' using errcode='40001';end if;
   update public.korlix_receipt_wiz set state='ready',updated_at=now() where id=rec.id returning * into rec;
  elsif p_action='save' then
   if rec.state<>'ready' or rec.version is distinct from (p_data->>'version')::integer then raise exception 'This receipt changed. Refresh before saving your edits.' using errcode='40001';end if;
   if jsonb_typeof(p_data->'details') is distinct from 'object' then raise exception 'Check receipt details.';end if;
   update public.korlix_receipt_wiz set details=p_data->'details',reviewed=coalesce((p_data->>'reviewed')::boolean,false),version=version+1,updated_at=now() where id=rec.id returning * into rec;
  elsif p_action='scan_begin' then
   if rec.state<>'ready' then raise exception 'Wait for this receipt to finish saving.' using errcode='40001';end if;
   k:=(p_data->>'request_key')::uuid;
   select * into job from public.korlix_receipt_wiz_scans where owner_id=p_actor and request_key=k;
   if found then
    if job.receipt_id<>rec.id then raise exception 'That scan key belongs to another receipt.' using errcode='40001';end if;
   else
    update public.korlix_receipt_wiz_scans set state='expired',finished_at=now() where owner_id=p_actor and state='scanning' and created_at<now()-interval '3 minutes';
    if exists(select 1 from public.korlix_receipt_wiz_scans where owner_id=p_actor and state='scanning') then raise exception 'A receipt is already scanning. Refresh its status.' using errcode='40001';end if;
    if coalesce((select attempts from public.korlix_receipt_wiz_usage where owner_id=p_actor and day=(now() at time zone 'UTC')::date),0)>=100 then raise exception 'You used today''s 100 free AI scans. You can still save receipts and enter details; scanning resets at midnight UTC.' using errcode='54000';end if;
    insert into public.korlix_receipt_wiz_usage(owner_id,day,attempts) values(p_actor,(now() at time zone 'UTC')::date,1) on conflict(owner_id,day) do update set attempts=korlix_receipt_wiz_usage.attempts+1;
    insert into public.korlix_receipt_wiz_scans(owner_id,receipt_id,request_key,receipt_version) values(p_actor,rec.id,k,rec.version) returning * into job;dispatch:=true;
   end if;
  elsif p_action='scan_finish' then
   select * into job from public.korlix_receipt_wiz_scans where id=(p_data->>'scan_id')::uuid and owner_id=p_actor and receipt_id=rec.id for update;
   if not found then raise exception 'Scan not found.' using errcode='P0002';end if;
   if job.state='scanning' then
    update public.korlix_receipt_wiz_scans set state=case when p_data->>'failed'='true' then 'failed' else 'ready' end,suggestion=p_data->'details',finished_at=now() where id=job.id returning * into job;
    if job.state='ready' and rec.state='ready' and rec.version=job.receipt_version and not rec.reviewed then
     update public.korlix_receipt_wiz set details=job.suggestion,version=version+1,updated_at=now() where id=rec.id returning * into rec;
    end if;
   end if;
  elsif p_action='delete_begin' then
   if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirm removal from all receipt inboxes.';end if;
   if rec.state='uploading' and rec.upload_until>=now() then raise exception 'This receipt is still uploading. Refresh in two minutes.' using errcode='40001';end if;
   if exists(select 1 from public.korlix_receipt_wiz_scans where receipt_id=rec.id and state='scanning' and created_at>=now()-interval '3 minutes') then raise exception 'Wait for this scan to finish before removing it.' using errcode='40001';end if;
   update public.korlix_receipt_wiz set state='deleting' where id=rec.id returning * into rec;
  elsif p_action='delete_finish' then
   if rec.state<>'deleting' then raise exception 'Confirm removal first.';end if;
   delete from public.korlix_receipt_wiz where id=rec.id;return jsonb_build_object('deleted',true);
  elsif p_action<>'get' then raise exception 'Unknown receipt operation.';
  end if;
 end if;
 result:=jsonb_build_object('receipt',public.korlix_receipt_wiz_item_v1(rec),'integrations',links,'dispatch',dispatch,
  'object_path',p_actor::text||'/'||rec.id::text||'/original','preview_path',case when rec.preview_size>0 then p_actor::text||'/'||rec.id::text||'/preview.webp' else null end);
 if p_action='reserve' then result:=result||jsonb_build_object('upload_token',rec.upload_token);end if;
 if p_action in ('scan_begin','scan_finish') then result:=result||jsonb_build_object('scan_id',job.id);end if;
 if p_action='save' and coalesce(rec.details->>'merchant','')<>'' and coalesce(rec.details->>'date','')<>'' and coalesce(rec.details->>'total','')<>'' then
  result:=result||jsonb_build_object('possible_duplicate',exists(select 1 from public.korlix_receipt_wiz r where r.owner_id=p_actor and r.id<>rec.id and r.state='ready' and lower(r.details->>'merchant')=lower(rec.details->>'merchant') and r.details->>'date'=rec.details->>'date' and nullif(r.details->>'total','')::numeric=nullif(rec.details->>'total','')::numeric and r.details->>'currency'=rec.details->>'currency'));
 end if;
 return result;
end $$;
revoke all on function public.korlix_receipt_wiz_v1(uuid,text,uuid,jsonb),public.korlix_receipt_wiz_item_v1(public.korlix_receipt_wiz) from public,anon,authenticated;
grant execute on function public.korlix_receipt_wiz_v1(uuid,text,uuid,jsonb),public.korlix_receipt_wiz_item_v1(public.korlix_receipt_wiz) to service_role;
