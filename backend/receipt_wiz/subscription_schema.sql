-- Receipt Wiz is an independent entitlement. It never writes a main-app tier.
create table public.korlix_receipt_billing_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 account_id text not null unique check(account_id ~ '^[0-9a-f]{64}$'),
 sync_token uuid, sync_until timestamptz,
 next_sync_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table public.korlix_receipt_purchases (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'),
 purchase_token text not null,
 user_id uuid not null references public.korlix_receipt_billing_accounts(user_id) on delete cascade,
 product_id text not null check(product_id='receipt_wiz_full'),
 state text not null, active boolean not null default false,
 expires_at timestamptz, acknowledged boolean not null default false,
 auto_renew boolean not null default false, test_purchase boolean not null default false,
 replaced_by_hash text, observed_at timestamptz not null default now()
);
create index korlix_receipt_purchases_owner on public.korlix_receipt_purchases(user_id);
create index korlix_receipt_billing_due on public.korlix_receipt_billing_accounts(next_sync_at);
create table public.korlix_receipt_monthly_usage (
 owner_id uuid not null references auth.users(id) on delete cascade,
 month date not null check(extract(day from month)=1),
 attempts integer not null default 0 check(attempts>=0), primary key(owner_id,month)
);
alter table public.korlix_receipt_billing_accounts enable row level security;
alter table public.korlix_receipt_purchases enable row level security;
alter table public.korlix_receipt_monthly_usage enable row level security;
revoke all on public.korlix_receipt_billing_accounts,public.korlix_receipt_purchases,public.korlix_receipt_monthly_usage from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_receipt_billing_accounts,public.korlix_receipt_purchases,public.korlix_receipt_monthly_usage to service_role;

-- Keep usage independent of receipt deletion, reinstall, and subscription changes.
insert into public.korlix_receipt_monthly_usage(owner_id,month,attempts)
 select owner_id,date_trunc('month',day)::date,sum(attempts)::integer
 from public.korlix_receipt_wiz_usage group by owner_id,date_trunc('month',day)::date;
alter table public.korlix_receipt_wiz_usage drop constraint korlix_receipt_wiz_usage_attempts_check;
alter table public.korlix_receipt_wiz_usage add constraint korlix_receipt_wiz_usage_attempts_check check(attempts>=0);

create function public.korlix_receipt_wiz_plan(p_actor uuid)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr jsonb; paid boolean; unlimited boolean; included boolean; cy date:=(date_trunc('month',now() at time zone 'UTC'))::date; used integer; lim integer;
begin
 if p_actor is null then raise exception 'BILL401: Sign in required.'; end if;
 pr:=public.korlix_web_billing_profile(p_actor);
 if pr is null then raise exception 'BILL401: Account not found.'; end if;
 if coalesce((pr->>'is_disabled')::boolean,false) then raise exception 'BILL403: Account is disabled.'; end if;
 unlimited:=coalesce(public.korlix_has_unlimited_access(p_actor),false);
 included:=unlimited or coalesce(pr->>'tier' in ('pro','ultra','enterprise'),false);
 paid:=included or exists(select 1 from public.korlix_receipt_purchases where user_id=p_actor
   and active and expires_at>now() and replaced_by_hash is null);
 lim:=case when unlimited then null when paid then 1000 else 20 end;
 select coalesce((select attempts from public.korlix_receipt_monthly_usage where owner_id=p_actor and month=cy),0) into used;
 return jsonb_build_object('name',case when paid then 'full' else 'free' end,'included',included,'unlimited',unlimited,
  'korlix_tier',pr->>'tier','monthly_scan_limit',lim,'scans_this_month',used,
  'scans_remaining',case when unlimited then null else greatest(lim-used,0) end,
  'resets_at',to_char(cy+interval '1 month','YYYY-MM-DD')||'T00:00:00Z',
  'max_receipts',case when unlimited then null when paid then 5000 else 100 end,
  'max_bytes',case when unlimited then null when paid then 2147483648::bigint else 262144000::bigint end);
end;
$$;

create function public.korlix_receipt_billing_command(p_actor uuid,p_action text,p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare g public.korlix_receipt_billing_accounts; r public.korlix_receipt_purchases;
 plan jsonb; hash text; blocked boolean;
begin
 if p_action='lookup' then
   select a.* into g from public.korlix_receipt_billing_accounts a where
    a.account_id=p->>'account_id' or a.user_id=(select user_id from public.korlix_receipt_purchases where token_hash=p->>'token_hash');
   return case when found then jsonb_build_object('user_id',g.user_id) else null end;
 end if;
 if p_action='due' then
   return coalesce((select jsonb_agg(x) from (select a.user_id from public.korlix_receipt_billing_accounts a
    where a.next_sync_at<=now() and (a.sync_until is null or a.sync_until<now())
     and exists(select 1 from public.korlix_receipt_purchases t where t.user_id=a.user_id and t.replaced_by_hash is null
      and t.state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'))
    order by a.next_sync_at limit 20) x),'[]'::jsonb);
 end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.'; end if;
 plan:=public.korlix_receipt_wiz_plan(p_actor);
 -- Serializes preparation and callbacks even before a billing account exists.
 perform pg_advisory_xact_lock(hashtextextended('receipt-billing:'||p_actor::text,0));
 select * into g from public.korlix_receipt_billing_accounts where user_id=p_actor for update;
 if p_action in ('snapshot','prepare') then
   blocked:=exists(select 1 from public.korlix_receipt_purchases where user_id=p_actor and replaced_by_hash is null
     and state in ('SUBSCRIPTION_STATE_PENDING','SUBSCRIPTION_STATE_ON_HOLD','SUBSCRIPTION_STATE_PAUSED'));
   if p_action='prepare' then
     if plan->>'name'='full' then raise exception 'BILL409: Receipt Wiz Full is already included in your account. No additional subscription is needed.'; end if;
     if blocked then raise exception 'BILL409: Manage or restore your existing Receipt Wiz subscription in Google Play.'; end if;
     if coalesce(p->>'account_id','') !~ '^[0-9a-f]{64}$' then raise exception 'BILL400: Invalid billing account.'; end if;
     if g.user_id is null then
       insert into public.korlix_receipt_billing_accounts(user_id,account_id) values(p_actor,p->>'account_id') returning * into g;
     elsif g.account_id<>p->>'account_id' then raise exception 'BILL409: Billing account changed.'; end if;
   end if;
   return jsonb_build_object('tier',plan->>'name','plan',plan,'account_id',g.account_id,
    'webSubscriptionActive',false,'otherStoreSubscriptionActive',(plan->>'included')::boolean,
    'canPurchase',plan->>'name'='free' and not blocked,
    'entitlement',(select jsonb_build_object('product_id',product_id,'tier','full','status',state,'expires_at',expires_at,
      'active',active and expires_at>now(),'auto_renew_status',auto_renew,'environment',case when test_purchase then 'Test' else 'Production' end)
      from public.korlix_receipt_purchases where user_id=p_actor and replaced_by_hash is null
      order by active desc, expires_at desc nulls last limit 1));
 end if;
 if g.user_id is null then raise exception 'BILL409: Restore using the KORLIX account that started this Receipt Wiz purchase.'; end if;
 if p_action='claim' then
   if g.sync_until>now() then raise exception 'BILL409: Subscription is updating. Please retry shortly.'; end if;
   update public.korlix_receipt_billing_accounts set sync_token=gen_random_uuid(),sync_until=now()+interval '90 seconds',next_sync_at=now()+interval '1 minute'
    where user_id=p_actor returning * into g;
   return jsonb_build_object('sync_token',g.sync_token,'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from
    (select purchase_token,product_id from public.korlix_receipt_purchases where user_id=p_actor and replaced_by_hash is null
      and state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED')
      order by observed_at desc limit 10) x),'[]'::jsonb));
 end if;
 if p_action='release' then
   update public.korlix_receipt_billing_accounts set sync_token=null,sync_until=null,next_sync_at=now()+case when coalesce((p->>'success')::boolean,false)
    then interval '10 minutes' else interval '1 minute' end where user_id=p_actor and sync_token::text=p->>'sync_token';
   return jsonb_build_object('ok',true);
 end if;
 if g.sync_token is null or g.sync_token::text is distinct from p->>'sync_token' or g.sync_until<now() then
   raise exception 'BILL409: Subscription changed while verifying. Please retry.';
 end if;
 hash:=p->>'token_hash';
 if p_action='acknowledged' then
   update public.korlix_receipt_purchases set acknowledged=true where user_id=p_actor and token_hash=hash;
   return jsonb_build_object('ok',true);
 end if;
 if p_action<>'apply' then raise exception 'BILL400: Unsupported billing action.'; end if;
 if coalesce(hash,'') !~ '^[0-9a-f]{64}$' or g.account_id is distinct from p->>'account_id'
    or p->>'product_id' is distinct from 'receipt_wiz_full' or p->>'tier' is distinct from 'full' then
   raise exception 'BILL409: Purchase does not match this Receipt Wiz account.';
 end if;
 select * into r from public.korlix_receipt_purchases where token_hash=hash for update;
 if found and r.user_id<>p_actor then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if p->>'linked_hash' is not null then
   if p->>'linked_hash'=hash then raise exception 'BILL409: Invalid replacement purchase.'; end if;
   if exists(select 1 from public.korlix_receipt_purchases where token_hash=p->>'linked_hash' and user_id<>p_actor) then
     raise exception 'BILL409: Linked purchase belongs to another account.';
   end if;
   if not exists(select 1 from public.korlix_receipt_purchases where token_hash=p->>'linked_hash' and user_id=p_actor) then
     raise exception 'BILL409: Restore your previous Receipt Wiz purchase first.';
   end if;
 end if;
 insert into public.korlix_receipt_purchases(token_hash,purchase_token,user_id,product_id,state,active,expires_at,acknowledged,auto_renew,test_purchase)
 values(hash,p->>'purchase_token',p_actor,p->>'product_id',p->>'state',(p->>'active')::boolean,
   (p->>'expires_at')::timestamptz,(p->>'acknowledged')::boolean,(p->>'auto_renew')::boolean,(p->>'test_purchase')::boolean)
 on conflict(token_hash) do update set state=excluded.state,active=excluded.active,expires_at=excluded.expires_at,
   acknowledged=excluded.acknowledged,auto_renew=excluded.auto_renew,observed_at=now()
   where korlix_receipt_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if (p->>'active')::boolean and r.replaced_by_hash is null and p->>'linked_hash' is not null then
   update public.korlix_receipt_purchases set replaced_by_hash=hash where token_hash=p->>'linked_hash' and user_id=p_actor;
 end if;
 plan:=public.korlix_receipt_wiz_plan(p_actor);
 return jsonb_build_object('tier',plan->>'name','active',coalesce((p->>'active')::boolean,false) and r.replaced_by_hash is null);
end;
$$;
revoke all on function public.korlix_receipt_wiz_plan(uuid),public.korlix_receipt_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_receipt_wiz_plan(uuid),public.korlix_receipt_billing_command(uuid,text,jsonb) to service_role;

-- Atomic monthly reservation and storage enforcement for the shared receipt library.
create or replace function public.korlix_receipt_wiz_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare rec public.korlix_receipt_wiz;job public.korlix_receipt_wiz_scans;result jsonb;items jsonb;links jsonb;
 used_bytes bigint;total_n integer;off integer;yr text;q text;cat text;pending boolean:=false;k uuid;dispatch boolean:=false;plan jsonb;cy date:=(date_trunc('month',now() at time zone 'UTC'))::date;monthly_used integer;
begin
 if p_actor is null then raise exception 'Sign in required.' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'Invalid receipt request.';end if;
 perform pg_advisory_xact_lock(hashtextextended('receipt-wiz:'||p_actor::text,0));
 plan:=public.korlix_receipt_wiz_plan(p_actor);
 if p_data ? 'business_id' and not exists(select 1 from public.korlix_bookkeeping_businesses where id=(p_data->>'business_id')::uuid and owner_id=p_actor) then raise exception 'Business not found.' using errcode='P0002';end if;
 if p_data ? 'tax_workspace_id' and not exists(select 1 from public.korlix_tax_workspaces where id=(p_data->>'tax_workspace_id')::uuid and owner_id=p_actor) then raise exception 'Tax organizer not found.' using errcode='P0002';end if;
 links:=jsonb_build_object('bookkeeping',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.korlix_bookkeeping_businesses where owner_id=p_actor),'[]'),
 'tax_prep',coalesce((select jsonb_agg(jsonb_build_object('id',id,'year',tax_year) order by tax_year desc) from public.korlix_tax_workspaces where owner_id=p_actor),'[]'));
 if p_action in ('list','export') then
  off:=coalesce((p_data->>'offset')::integer,0);yr:=coalesce(p_data->>'year','');q:=lower(coalesce(p_data->>'query',''));cat:=coalesce(p_data->>'category','');pending:=coalesce((p_data->>'needs_review')::boolean,false);
  if off<0 or off>1000000 or length(q)>160 or (yr<>'' and yr!~'^20[0-9]{2}$') then raise exception 'Invalid receipt filter.';end if;
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
   order by created_at desc,id limit case when p_action='export' then 5000 else 30 end offset off
  )x;
  return jsonb_build_object('receipts',items,'total',total_n,'offset',off,'used_bytes',used_bytes,'max_bytes',plan->'max_bytes','max_receipts',plan->'max_receipts','plan',plan,'integrations',links,'daily_scan_limit',100,'scans_today',coalesce((select attempts from public.korlix_receipt_wiz_usage where owner_id=p_actor and day=(now() at time zone 'UTC')::date),0));
 end if;
 if p_action='reserve' then
  k:=(p_data->>'request_key')::uuid;
  select * into rec from public.korlix_receipt_wiz where owner_id=p_actor and request_key=k;
  if found and rec.sha256 is distinct from p_data->>'sha256' then raise exception 'This upload key belongs to another file.' using errcode='40001';end if;
  if not found then select * into rec from public.korlix_receipt_wiz where owner_id=p_actor and sha256=p_data->>'sha256';end if;
  if rec.id is null then
   select count(*),coalesce(sum(byte_size+preview_size),0) into total_n,used_bytes from public.korlix_receipt_wiz where owner_id=p_actor;
   if not (plan->>'unlimited')::boolean and (total_n>=(plan->>'max_receipts')::integer or used_bytes+(p_data->>'byte_size')::integer+coalesce((p_data->>'preview_size')::integer,0)>(plan->>'max_bytes')::bigint) then raise exception 'Your receipt storage allowance is full. Existing receipts remain available. Upgrade Receipt Wiz or export and remove unneeded receipts to make room.' using errcode='54000';end if;
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
    with expired as (update public.korlix_receipt_wiz_scans set state='expired',finished_at=now() where owner_id=p_actor and state='scanning' and created_at<now()-interval '3 minutes' returning created_at), counts as (select date_trunc('month',created_at at time zone 'UTC')::date as usage_month,count(*)::integer n from expired group by 1) update public.korlix_receipt_monthly_usage u set attempts=greatest(0,u.attempts-counts.n) from counts where u.owner_id=p_actor and u.month=counts.usage_month;
    if exists(select 1 from public.korlix_receipt_wiz_scans where owner_id=p_actor and state='scanning') then raise exception 'A receipt is already scanning. Refresh its status.' using errcode='40001';end if;
    select coalesce((select attempts from public.korlix_receipt_monthly_usage where owner_id=p_actor and month=cy),0) into monthly_used;
    if not (plan->>'unlimited')::boolean and monthly_used>=(plan->>'monthly_scan_limit')::integer then raise exception 'Your monthly AI scan allowance is used. Existing receipts and manual entry remain available. Your allowance resets on the first day of the next month (UTC).' using errcode='54000';end if;
    insert into public.korlix_receipt_monthly_usage(owner_id,month,attempts) values(p_actor,cy,1) on conflict(owner_id,month) do update set attempts=korlix_receipt_monthly_usage.attempts+1;
    insert into public.korlix_receipt_wiz_usage(owner_id,day,attempts) values(p_actor,(now() at time zone 'UTC')::date,1) on conflict(owner_id,day) do update set attempts=korlix_receipt_wiz_usage.attempts+1;
    insert into public.korlix_receipt_wiz_scans(owner_id,receipt_id,request_key,receipt_version) values(p_actor,rec.id,k,rec.version) returning * into job;dispatch:=true;
   end if;
  elsif p_action='scan_finish' then
   select * into job from public.korlix_receipt_wiz_scans where id=(p_data->>'scan_id')::uuid and owner_id=p_actor and receipt_id=rec.id for update;
   if not found then raise exception 'Scan not found.' using errcode='P0002';end if;
   if job.state='scanning' then
    update public.korlix_receipt_wiz_scans set state=case when p_data->>'failed'='true' then 'failed' else 'ready' end,suggestion=p_data->'details',finished_at=now() where id=job.id returning * into job;
    if job.state='failed' then
     update public.korlix_receipt_monthly_usage set attempts=greatest(0,attempts-1) where owner_id=p_actor and month=date_trunc('month',job.created_at at time zone 'UTC')::date;
    end if;
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

