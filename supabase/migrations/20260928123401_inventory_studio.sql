-- Owner-private inventory. The backend authenticates the actor; RPCs are service-role only.
create table public.korlix_inventory_records (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in('product','location','partner','order')),
 data jsonb not null check(jsonb_typeof(data)='object'), revision integer not null default 1,
 archived boolean not null default false, photo_path text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(owner_id,id)
);
create unique index korlix_inventory_sku on public.korlix_inventory_records(owner_id,upper(data->>'sku')) where kind='product' and not archived;
create index korlix_inventory_owner_kind on public.korlix_inventory_records(owner_id,kind,archived,updated_at desc);
create table public.korlix_inventory_stock (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 product_id uuid not null, location_id uuid not null,
 bin text not null default '', serial text not null default '', batch text not null default '', expiry date,
 quantity numeric(18,4) not null default 0 check(quantity>=0 and quantity<=999999999), reserved numeric(18,4) not null default 0 check(reserved>=0 and reserved<=quantity),
 unit_cost numeric(18,4) not null default 0 check(unit_cost>=0), check(serial='' or quantity in(0,1) and reserved in(0,1)), revision integer not null default 1,
 updated_at timestamptz not null default now(),
 foreign key(owner_id,product_id) references public.korlix_inventory_records(owner_id,id),
 foreign key(owner_id,location_id) references public.korlix_inventory_records(owner_id,id)
);
create unique index korlix_inventory_serial on public.korlix_inventory_stock(owner_id,product_id,lower(serial)) where serial<>'';
create index korlix_inventory_stock_owner on public.korlix_inventory_stock(owner_id,product_id,location_id);
create index korlix_inventory_stock_expiry on public.korlix_inventory_stock(owner_id,expiry) where expiry is not null;
create table public.korlix_inventory_events (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 record_id uuid not null, action text not null, detail jsonb not null, created_at timestamptz not null default now()
);
create index korlix_inventory_events_owner on public.korlix_inventory_events(owner_id,created_at desc,id);
create table public.korlix_inventory_requests (
 owner_id uuid not null references auth.users(id) on delete cascade, id uuid not null,
 request_hash text not null, result jsonb not null, created_at timestamptz not null default now(),primary key(owner_id,id)
);
create index korlix_inventory_requests_owner_time on public.korlix_inventory_requests(owner_id,created_at desc);
create table public.korlix_inventory_vision (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 request_hash text not null, mode text not null check(mode in('picture','serial')),
 state text not null check(state in('preparing','ready','failed')), result jsonb not null default '{}',
 usage_id uuid references public.usage_counters(id) on delete set null, charged boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index korlix_inventory_vision_owner on public.korlix_inventory_vision(owner_id,created_at desc);
alter table public.korlix_inventory_records enable row level security;
alter table public.korlix_inventory_stock enable row level security;
alter table public.korlix_inventory_events enable row level security;
alter table public.korlix_inventory_requests enable row level security;
alter table public.korlix_inventory_vision enable row level security;
revoke all on public.korlix_inventory_records,public.korlix_inventory_stock,public.korlix_inventory_events,public.korlix_inventory_requests,public.korlix_inventory_vision from public,anon,authenticated;
grant select,insert,update,delete on public.korlix_inventory_records,public.korlix_inventory_stock,public.korlix_inventory_events,public.korlix_inventory_requests,public.korlix_inventory_vision to service_role;

create function public.korlix_inventory_v1(p_actor uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare r public.korlix_inventory_records; pr public.korlix_inventory_records; s public.korlix_inventory_stock; target public.korlix_inventory_stock;
 req public.korlix_inventory_requests; job public.korlix_inventory_vision;
 result jsonb; v jsonb; line jsonb; lines jsonb; total bigint; a text; k text; h text; uid uuid; rid uuid; loc uuid;
 order_currency text; order_lines jsonb;
 qty numeric; before_qty numeric; after_qty numeric; cost numeric; n integer; complete boolean;
begin
 if p_actor is null then raise exception 'Sign in to use Inventory.' using errcode='42501';end if;
 -- One owner lock serializes mutations, stock reservations and idempotency checks.
 if p_action not in('search','workspace','item','events','export') then perform pg_advisory_xact_lock(hashtextextended('inventory:'||p_actor::text,0));end if;
 if p_action='workspace' then
  return jsonb_build_object('version',1,'locations',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.data->>'name') from korlix_inventory_records x where owner_id=p_actor and kind='location' and not archived),'[]'),
   'partners',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.data->>'name') from korlix_inventory_records x where owner_id=p_actor and kind='partner' and not archived),'[]'),
   'orders',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by updated_at desc) from (select * from korlix_inventory_records where owner_id=p_actor and kind='order' and not archived order by updated_at desc limit 200)x),'[]'),
   'summary',jsonb_build_object('products',(select count(*) from korlix_inventory_records where owner_id=p_actor and kind='product' and not archived),'locations',(select count(*) from korlix_inventory_records where owner_id=p_actor and kind='location' and not archived),'units',coalesce((select sum(quantity) from korlix_inventory_stock where owner_id=p_actor),0),'reserved',coalesce((select sum(reserved) from korlix_inventory_stock where owner_id=p_actor),0),
   'value',coalesce((select jsonb_agg(to_jsonb(z)) from (select p.data->>'currency' currency,sum(invs.quantity*invs.unit_cost) amount from korlix_inventory_stock invs join korlix_inventory_records p on p.id=invs.product_id where invs.owner_id=p_actor group by p.data->>'currency')z),'[]')));
 end if;
 if p_action='search' then
  with items as (
   select p.id,p.data,p.revision,p.photo_path,p.updated_at,
     coalesce(sum(invs.quantity),0) quantity,coalesce(sum(invs.reserved),0) reserved,
     coalesce(sum(invs.quantity-invs.reserved) filter(where invs.expiry is null or invs.expiry>=current_date),0) available,
     coalesce(sum(invs.quantity) filter(where invs.expiry<current_date),0) expired,
     count(distinct invs.location_id) locations
   from korlix_inventory_records p
   left join korlix_inventory_stock invs on invs.product_id=p.id and invs.owner_id=p_actor and
    ((coalesce(p_data->>'scope','international')='international') or exists(select 1 from korlix_inventory_records l where l.id=invs.location_id and l.owner_id=p_actor and l.data->>'country'=p_data->>'country' and (p_data->>'scope'='nationwide' or lower(l.data->>'region')=lower(p_data->>'region')))) and
    ((p_data->>'location_id') is null or invs.location_id=(p_data->>'location_id')::uuid)
   where p.owner_id=p_actor and p.kind='product' and not p.archived
    and (coalesce(p_data->>'q','')='' or not exists(select 1 from regexp_split_to_table(lower(trim(p_data->>'q')),'\s+') word where strpos(lower(concat_ws(' ',p.data->>'name',p.data->>'sku',p.data->>'barcode',p.data->>'brand',p.data->>'category',p.data->>'aliases',p.data->>'description')),word)=0 and not exists(select 1 from korlix_inventory_stock sx where sx.owner_id=p_actor and sx.product_id=p.id and (coalesce(p_data->>'scope','international')='international' or exists(select 1 from korlix_inventory_records lx where lx.id=sx.location_id and lx.owner_id=p_actor and lx.data->>'country'=p_data->>'country' and (p_data->>'scope'='nationwide' or lower(lx.data->>'region')=lower(p_data->>'region')))) and ((p_data->>'location_id') is null or sx.location_id=(p_data->>'location_id')::uuid) and (strpos(lower(sx.serial),word)>0 or strpos(lower(sx.batch),word)>0))))
   group by p.id
  ), filtered as (select * from items where (coalesce(p_data->>'scope','international')='international' and (p_data->>'location_id') is null or locations>0) and
   (coalesce(p_data->>'filter','all')='all' or p_data->>'filter'='low' and available<=coalesce((data->>'reorder')::numeric,0) or p_data->>'filter'='available' and available>0 or p_data->>'filter'='expired' and expired>0))
  select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce(jsonb_agg(to_jsonb(z) order by lower(z.data->>'name'),z.id),'[]'),'offset',coalesce((p_data->>'offset')::int,0),'scope',coalesce(p_data->>'scope','international'),'country',p_data->>'country','region',p_data->>'region') into result
  from (select * from filtered order by lower(data->>'name'),id offset greatest(0,coalesce((p_data->>'offset')::int,0)) limit 40)z;
  return result;
 end if;
 if p_action='events' then
  return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(z)-'owner_id' order by z.created_at desc,z.id) from (select * from korlix_inventory_events where owner_id=p_actor and (p_id is null or record_id=p_id) order by created_at desc,id offset greatest(0,coalesce((p_data->>'offset')::int,0)) limit 100)z),'[]'));
 end if;
 if p_action='export' then
  return jsonb_build_object('products',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.data->>'sku') from korlix_inventory_records x where owner_id=p_actor and kind='product' and not archived),'[]'),'stock',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id') from korlix_inventory_stock x where owner_id=p_actor),'[]'),'locations',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id') from korlix_inventory_records x where owner_id=p_actor and kind='location'),'[]'));
 end if;
 if p_action='item' then
  select * into r from korlix_inventory_records where owner_id=p_actor and id=p_id and not archived;
  if not found then raise exception 'Item not found.' using errcode='P0002';end if;
  return jsonb_build_object('item',to_jsonb(r)-'owner_id','stock',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.expiry nulls last,x.id) from korlix_inventory_stock x where owner_id=p_actor and product_id=p_id),'[]'));
 end if;
 if p_action like 'vision_%' then
  for job in select * from korlix_inventory_vision where owner_id=p_actor and state='preparing' and created_at<now()-interval '4 minutes' for update loop
   if job.charged then update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-1),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=job.usage_id and user_id=p_actor;end if;
   update korlix_inventory_vision set state='failed',charged=false,updated_at=now() where id=job.id;
  end loop;
  if p_action='vision_recover' then return jsonb_build_object('recovered',true);end if;
  select * into job from korlix_inventory_vision where owner_id=p_actor and id=p_id for update;
  if p_action in('vision_lookup','vision_start') then
   if found then
    if job.request_hash is distinct from p_data->>'request_hash' then raise exception 'Start a new request for a different picture.' using errcode='40001';end if;
    return (to_jsonb(job)-'owner_id'-'usage_id'-'request_hash')||jsonb_build_object('replayed',true);
   end if;
   if p_action='vision_lookup' then raise exception 'Scan not found.' using errcode='P0002';end if;
   if exists(select 1 from korlix_inventory_vision where owner_id=p_actor and state='preparing') then raise exception 'A picture search is still running.' using errcode='40001';end if;
   if (select count(*) from korlix_inventory_vision where owner_id=p_actor and created_at>now()-interval '1 hour')>=20 then raise exception 'Please wait before scanning more pictures.' using errcode='54000';end if;
   uid:=(p_data->>'usage_id')::uuid;
   update usage_counters set credits_used=coalesce(credits_used,0)+1,standard_generations=coalesce(standard_generations,0)+1,updated_at=now() where id=uid and user_id=p_actor and coalesce(credits_used,0)<(p_data->>'credit_limit')::int and coalesce(standard_generations,0)+coalesce(live_search_generations,0)+coalesce(pdf_generations,0)<(p_data->>'request_limit')::int;
   if not found then raise exception 'Your generation allowance is unavailable.' using errcode='54000';end if;
   insert into korlix_inventory_vision(id,owner_id,request_hash,mode,state,usage_id) values(p_id,p_actor,p_data->>'request_hash',p_data->>'mode','preparing',uid) returning * into job;
  else
   if not found then raise exception 'Scan not found.' using errcode='P0002';end if;
   if p_action='vision_finish' and job.state='preparing' then update korlix_inventory_vision set state='ready',result=p_data->'result',updated_at=now() where id=job.id returning * into job;
   elsif p_action='vision_fail' and job.state='preparing' then
    if job.charged then update usage_counters set credits_used=greatest(0,coalesce(credits_used,0)-1),standard_generations=greatest(0,coalesce(standard_generations,0)-1),updated_at=now() where id=job.usage_id and user_id=p_actor;end if;
    update korlix_inventory_vision set state='failed',charged=false,updated_at=now() where id=job.id returning * into job;
   elsif p_action not in('vision_get','vision_finish','vision_fail') then raise exception 'Unknown scan action.';end if;
  end if;
  return to_jsonb(job)-'owner_id'-'usage_id'-'request_hash';
 end if;
 if p_action='photo' then
  update korlix_inventory_records set photo_path=p_data->>'path',revision=revision+1,updated_at=now() where id=p_id and owner_id=p_actor and kind='product' and not archived and revision=(p_data->>'revision')::int returning * into r;
  if not found then raise exception 'This item changed. Refresh before saving a photo.' using errcode='40001';end if;
  return to_jsonb(r)-'owner_id';
 end if;
 if p_action<>'mutate' then raise exception 'Unknown inventory action.';end if;
 rid:=(p_data->>'request_key')::uuid; h:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 select * into req from korlix_inventory_requests where owner_id=p_actor and id=rid;
 if found then
  if req.request_hash<>h then raise exception 'Use a new request for a different change.' using errcode='40001';end if;
  return req.result||jsonb_build_object('replayed',true);
 end if;
 if (select count(*) from korlix_inventory_requests where owner_id=p_actor and created_at>now()-interval '1 hour')>=1000 then raise exception 'Please wait before making more changes.' using errcode='54000';end if;
 a:=p_data->>'action'; k:=p_data->>'kind'; p_id:=(p_data->>'id')::uuid;
 if a='save' then
  v:=p_data->'value';select * into r from korlix_inventory_records where id=p_id and owner_id=p_actor for update;
  if found then
   if r.archived or r.kind<>k or r.revision is distinct from (p_data->>'revision')::int then raise exception 'This record changed. Refresh before saving.' using errcode='40001';end if;
   if k='product' and v->>'tracking' is distinct from r.data->>'tracking' and exists(select 1 from korlix_inventory_stock where product_id=p_id) then raise exception 'Tracking cannot change after a stock position is created.';end if;
   if k='order' and r.data->>'status'<>'draft' then raise exception 'Only draft orders can be edited.';end if;
   if k='product' and v->>'currency' is distinct from r.data->>'currency' and exists(select 1 from korlix_inventory_stock where product_id=p_id) then raise exception 'Currency cannot change after stock is created.';end if;
  elsif (p_data->>'revision')::int<>0 then raise exception 'Record not found.' using errcode='P0002';end if;
  if not found and (select count(*) from korlix_inventory_records where owner_id=p_actor and kind=k and not archived)>=(case k when 'product' then 10000 when 'order' then 200 else 500 end) then raise exception 'This workspace has reached its record limit. Archive unused records.' using errcode='54000';end if;
  if k='order' then
   v:=v||jsonb_build_object('status','draft');
   if v->>'partner_id' is not null and not exists(select 1 from korlix_inventory_records where id=(v->>'partner_id')::uuid and owner_id=p_actor and kind='partner' and not archived and data->>'type'=case when v->>'type'='purchase' then 'supplier' else 'customer' end) then raise exception 'Choose a matching supplier or customer.';end if;
   order_lines:='[]';order_currency:=null;
   for line in select * from jsonb_array_elements(v->'lines') loop
    if (line->>'quantity')::numeric<=0 or not exists(select 1 from korlix_inventory_stock where id=(line->>'stock_id')::uuid and owner_id=p_actor) then raise exception 'Choose valid stock positions and positive quantities.';end if;
    select * into s from korlix_inventory_stock where id=(line->>'stock_id')::uuid and owner_id=p_actor;
    select * into pr from korlix_inventory_records where id=s.product_id and owner_id=p_actor and not archived;
    if not found then raise exception 'Choose an active order item.';end if;
    if s.serial<>'' and ((line->>'quantity')::numeric<>1 or exists(select 1 from jsonb_array_elements(order_lines) ol where ol->>'stock_id'=line->>'stock_id')) then raise exception 'Order exactly one unit for each serial number.';end if;
    if order_currency is not null and order_currency<>pr.data->>'currency' then raise exception 'Use a separate order for each currency.';end if;
    order_currency:=pr.data->>'currency';
    order_lines:=order_lines||jsonb_build_array(line||jsonb_build_object('product_name',pr.data->>'name','sku',pr.data->>'sku','currency',order_currency,'serial',s.serial,'location_name',(select data->>'name' from korlix_inventory_records where id=s.location_id and owner_id=p_actor)));
   end loop;
   v:=v||jsonb_build_object('lines',order_lines,'currency',order_currency);
  end if;
  insert into korlix_inventory_records(id,owner_id,kind,data) values(p_id,p_actor,k,v) on conflict(id) do update set data=excluded.data,revision=korlix_inventory_records.revision+1,updated_at=now() where korlix_inventory_records.owner_id=p_actor returning * into r;
  if not found then raise exception 'Record not found.' using errcode='P0002';end if;
  result:=jsonb_build_object('record',to_jsonb(r)-'owner_id');
 elsif a='archive' then
  select * into r from korlix_inventory_records where id=p_id and owner_id=p_actor and not archived for update;
  if not found then raise exception 'Record not found.' using errcode='P0002';end if;
  if r.revision is distinct from (p_data->>'revision')::int then raise exception 'Refresh before archiving.' using errcode='40001';end if;
  if exists(select 1 from korlix_inventory_stock where owner_id=p_actor and (product_id=p_id or location_id=p_id) and (quantity<>0 or reserved<>0)) or r.kind='order' and r.data->>'status' in('open','partial') then raise exception 'Resolve stock and open orders before archiving.';end if;
  if r.kind in('product','location','partner') and exists(select 1 from korlix_inventory_records ord where ord.owner_id=p_actor and ord.kind='order' and not ord.archived and ord.data->>'status' in('open','partial') and ((ord.data->>'partner_id')::uuid=p_id or exists(select 1 from jsonb_array_elements(ord.data->'lines') ln join korlix_inventory_stock st on st.id=(ln->>'stock_id')::uuid where st.owner_id=p_actor and (st.product_id=p_id or st.location_id=p_id)))) then raise exception 'Close the related open orders before archiving.';end if;
  update korlix_inventory_records set archived=true,revision=revision+1,updated_at=now() where id=p_id;
  result:=jsonb_build_object('archived',true);
 elsif a='import' then
  if (select count(*) from korlix_inventory_records where owner_id=p_actor and kind='product' and not archived)+jsonb_array_length(p_data->'products')>10000 then raise exception 'Product limit reached.' using errcode='54000';end if;
  for v in select * from jsonb_array_elements(p_data->'products') loop
   insert into korlix_inventory_records(id,owner_id,kind,data)values((v->>'id')::uuid,p_actor,'product',v->'value');
  end loop;
  result:=jsonb_build_object('imported',jsonb_array_length(p_data->'products'));
 elsif a='stock' then
  select * into pr from korlix_inventory_records where id=(p_data->>'product_id')::uuid and owner_id=p_actor and kind='product' and not archived;
  if not found or not exists(select 1 from korlix_inventory_records where id=(p_data->>'location_id')::uuid and owner_id=p_actor and kind='location' and not archived) then raise exception 'Choose an active item and location.';end if;
  if pr.data->>'tracking'='serial' and coalesce(p_data->>'serial','')='' or pr.data->>'tracking'<>'serial' and coalesce(p_data->>'serial','')<>'' then raise exception 'Serial number does not match this item tracking method.';end if;
  if pr.data->>'tracking'='batch' and coalesce(p_data->>'batch','')='' then raise exception 'Enter a batch identifier.';end if;
  if (select count(*) from korlix_inventory_stock where owner_id=p_actor)>=50000 then raise exception 'Stock-position limit reached.' using errcode='54000';end if;
  insert into korlix_inventory_stock(id,owner_id,product_id,location_id,bin,serial,batch,expiry,unit_cost)values(p_id,p_actor,pr.id,(p_data->>'location_id')::uuid,p_data->>'bin',p_data->>'serial',p_data->>'batch',nullif(p_data->>'expiry','')::date,(p_data->>'unit_cost')::numeric) returning * into s;
  result:=jsonb_build_object('stock',to_jsonb(s)-'owner_id');
 elsif a='move' then
  select * into s from korlix_inventory_stock where owner_id=p_actor and id=p_id for update;
  if not found then raise exception 'Stock position not found.' using errcode='P0002';end if;
  if s.revision is distinct from (p_data->>'revision')::int then raise exception 'Stock changed. Refresh before continuing.' using errcode='40001';end if;
  if not exists(select 1 from korlix_inventory_records where id=s.product_id and owner_id=p_actor and not archived) or not exists(select 1 from korlix_inventory_records where id=s.location_id and owner_id=p_actor and not archived) then raise exception 'This item or location is archived.';end if;
  qty:=(p_data->>'quantity')::numeric;cost:=(p_data->>'unit_cost')::numeric;before_qty:=s.quantity;
  if k in('receive','return_in') then after_qty:=s.quantity+qty;
   if after_qty>0 then s.unit_cost:=(s.quantity*s.unit_cost+qty*cost)/after_qty;end if;
  elsif k in('issue','return_out','transfer') then after_qty:=s.quantity-qty;
  elsif k='count' then after_qty:=qty;
  else raise exception 'Unknown stock movement.';end if;
  if after_qty<s.reserved or after_qty<0 or after_qty>999999999 then raise exception 'Insufficient available stock, or quantity exceeds the limit.';end if;
  if s.serial<>'' and after_qty not in(0,1) then raise exception 'A serial number represents exactly one unit.';end if;
  if k in('issue','transfer') and s.expiry<current_date then raise exception 'Expired stock cannot be issued or transferred. Use a documented return or count adjustment.';end if;
  if k='transfer' then
   loc:=(p_data->>'target_location_id')::uuid;
   if loc=s.location_id or not exists(select 1 from korlix_inventory_records where id=loc and owner_id=p_actor and kind='location' and not archived) then raise exception 'Choose another active location.';end if;
   if s.serial<>'' then
    update korlix_inventory_stock set location_id=loc,bin='',revision=revision+1,updated_at=now() where id=s.id returning * into target;
    result:=jsonb_build_object('stock',to_jsonb(target)-'owner_id');
   else
    insert into korlix_inventory_stock(id,owner_id,product_id,location_id,bin,batch,expiry,quantity,unit_cost)values((p_data->>'target_id')::uuid,p_actor,s.product_id,loc,'',s.batch,s.expiry,qty,s.unit_cost) returning * into target;
   end if;
  end if;
  if not(k='transfer' and s.serial<>'') then update korlix_inventory_stock set quantity=after_qty,unit_cost=s.unit_cost,revision=revision+1,updated_at=now() where id=s.id returning * into s;result:=jsonb_build_object('stock',to_jsonb(s)-'owner_id');end if;
  v:=jsonb_build_object('kind',k,'product_id',s.product_id,'stock_id',s.id,'quantity',qty,'before',before_qty,'after',case when k='transfer' and s.serial<>'' then before_qty else after_qty end,'location_id',s.location_id,'target_location_id',loc,'target_stock_id',target.id,'unit_cost',s.unit_cost,'reference',p_data->>'reference','note',p_data->>'note');
 elsif a in('order_open','order_cancel','order_process') then
  select * into r from korlix_inventory_records where id=p_id and owner_id=p_actor and kind='order' and not archived for update;
  if not found then raise exception 'Order not found.' using errcode='P0002';end if;
  if r.revision is distinct from (p_data->>'revision')::int then raise exception 'Order changed. Refresh before continuing.' using errcode='40001';end if;
  lines:=r.data->'lines';
  if a='order_open' then
   if r.data->>'status'<>'draft' then raise exception 'Only draft orders can be opened.';end if;
   for line in select * from jsonb_array_elements(lines) loop
    select * into s from korlix_inventory_stock where id=(line->>'stock_id')::uuid and owner_id=p_actor for update;
    if not found or not exists(select 1 from korlix_inventory_records where id=s.product_id and not archived) or not exists(select 1 from korlix_inventory_records where id=s.location_id and not archived) then raise exception 'An order item or location is unavailable.';end if;
    qty:=(line->>'quantity')::numeric;
    if r.data->>'type'='sale' then
     if s.expiry<current_date or s.quantity-s.reserved<qty then raise exception 'An order line has insufficient unexpired available stock.';end if;
     update korlix_inventory_stock set reserved=reserved+qty,revision=revision+1,updated_at=now() where id=s.id;
    end if;
   end loop;
   r.data:=r.data||jsonb_build_object('status','open');
  elsif a='order_cancel' then
   if r.data->>'status' not in('draft','open','partial') then raise exception 'This order cannot be cancelled.';end if;
   if r.data->>'status'<>'draft' and r.data->>'type'='sale' then
    for line in select * from jsonb_array_elements(lines) loop update korlix_inventory_stock set reserved=reserved-((line->>'quantity')::numeric-(line->>'done')::numeric),revision=revision+1,updated_at=now() where id=(line->>'stock_id')::uuid and owner_id=p_actor;end loop;
   end if;
   r.data:=r.data||jsonb_build_object('status','cancelled');
  else
   if r.data->>'status' not in('open','partial') then raise exception 'Open the order before recording a receipt or shipment.';end if;
   n:=(p_data->>'line')::int;line:=lines->n;qty:=(p_data->>'quantity')::numeric;
   if line is null or qty<=0 or qty>(line->>'quantity')::numeric-(line->>'done')::numeric then raise exception 'Quantity exceeds the remaining order amount.';end if;
   select * into s from korlix_inventory_stock where id=(line->>'stock_id')::uuid and owner_id=p_actor for update;before_qty:=s.quantity;
   if not found or not exists(select 1 from korlix_inventory_records where id=s.product_id and owner_id=p_actor and not archived) or not exists(select 1 from korlix_inventory_records where id=s.location_id and owner_id=p_actor and not archived) then raise exception 'An order item or location is unavailable.';end if;
   if s.serial<>'' and qty<>1 then raise exception 'Process one whole unit for a serial number.';end if;
   if r.data->>'type'='purchase' then
    after_qty:=s.quantity+qty;cost:=(line->>'unit_price')::numeric;
    if s.serial<>'' and after_qty<>1 then raise exception 'Receive one unit for each serial number.';end if;
    update korlix_inventory_stock set quantity=after_qty,unit_cost=(quantity*unit_cost+qty*cost)/after_qty,revision=revision+1,updated_at=now() where id=s.id;
   else
    if s.expiry<current_date or s.reserved<qty or s.quantity<qty then raise exception 'Reserved stock is no longer available for shipment.';end if;
    after_qty:=s.quantity-qty;
    update korlix_inventory_stock set quantity=after_qty,reserved=reserved-qty,revision=revision+1,updated_at=now() where id=s.id;
   end if;
   lines:=jsonb_set(lines,array[n::text,'done'],to_jsonb((line->>'done')::numeric+qty));
   select not exists(select 1 from jsonb_array_elements(lines)x where (x->>'done')::numeric<(x->>'quantity')::numeric) into complete;
   r.data:=r.data||jsonb_build_object('lines',lines,'status',case when complete then 'complete' else 'partial' end);
   insert into korlix_inventory_events(owner_id,record_id,action,detail)values(p_actor,s.product_id,case when r.data->>'type'='purchase' then 'order_receive' else 'order_ship' end,jsonb_build_object('stock_id',s.id,'order_id',r.id,'quantity',qty,'before',before_qty,'after',after_qty,'location_id',s.location_id));
  end if;
  update korlix_inventory_records set data=r.data,revision=revision+1,updated_at=now() where id=r.id returning * into r;
  result:=jsonb_build_object('record',to_jsonb(r)-'owner_id');
 else raise exception 'Unknown change.';
 end if;
 insert into korlix_inventory_events(owner_id,record_id,action,detail)values(p_actor,coalesce(case when a='move' then s.product_id else p_id end,rid),a,case when a='move' then v else jsonb_build_object('kind',k,'record_id',p_id,'name',r.data->>'name') end);
 insert into korlix_inventory_requests(owner_id,id,request_hash,result)values(p_actor,rid,h,result);
 return result;
end $$;
revoke all on function public.korlix_inventory_v1(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_inventory_v1(uuid,text,uuid,jsonb) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('korlix-inventory','korlix-inventory',false,2097152,array['image/jpeg']) on conflict(id) do nothing;
