create function public.korlix_magic_billing_command(p_actor uuid,p_action text,p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public as $$
declare g public.korlix_magic_billing_accounts; r public.korlix_magic_purchases;
 plan jsonb; hash text; blocked boolean;
begin
 if p_action='lookup' then
   select a.* into g from public.korlix_magic_billing_accounts a where
    a.account_id=p->>'account_id' or a.user_id=(select user_id from public.korlix_magic_purchases where token_hash=p->>'token_hash');
   return case when found then jsonb_build_object('user_id',g.user_id) else null end;
 end if;
 if p_action='due' then
   return coalesce((select jsonb_agg(x) from (select a.user_id from public.korlix_magic_billing_accounts a
    where a.next_sync_at<=now() and (a.sync_until is null or a.sync_until<now())
     and exists(select 1 from public.korlix_magic_purchases t where t.user_id=a.user_id and t.provider='google' and t.replaced_by_hash is null
      and t.state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'))
    order by a.next_sync_at limit 20) x),'[]'::jsonb);
 end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.'; end if;
 plan:=public.korlix_magic_plan(p_actor,true);
 -- Serializes preparation and callbacks even before a billing account exists.
 perform pg_advisory_xact_lock(hashtextextended('magic-billing:'||p_actor::text,0));
 select * into g from public.korlix_magic_billing_accounts where user_id=p_actor for update;
 if p_action in ('snapshot','prepare') then
   blocked:=exists(select 1 from public.korlix_magic_purchases where user_id=p_actor and replaced_by_hash is null
     and state in ('SUBSCRIPTION_STATE_PENDING','SUBSCRIPTION_STATE_ON_HOLD','SUBSCRIPTION_STATE_PAUSED'));
   if p_action='prepare' then
     if plan->>'name'<>'free' then raise exception 'BILL409: Magic Camera Full is already included in your account. No additional subscription is needed.'; end if;
     if blocked then raise exception 'BILL409: Manage or restore your existing Magic Camera subscription in Google Play.'; end if;
     if coalesce(p->>'account_id','') !~ '^[0-9a-f]{64}$' then raise exception 'BILL400: Invalid billing account.'; end if;
     if g.user_id is null then
       insert into public.korlix_magic_billing_accounts(user_id,account_id) values(p_actor,p->>'account_id') returning * into g;
     elsif g.account_id<>p->>'account_id' then raise exception 'BILL409: Billing account changed.'; end if;
   end if;
   return jsonb_build_object('tier',plan->>'name','plan',plan,'account_id',g.account_id,
    'webSubscriptionActive',false,'otherStoreSubscriptionActive',(plan->>'included')::boolean,
    'canPurchase',plan->>'name'='free' and not blocked,
    'entitlement',(select jsonb_build_object('product_id',product_id,'tier',case when product_id='magic_camera_plus' then 'plus' else 'starter' end,'status',state,'expires_at',expires_at,
      'active',active and expires_at>now(),'auto_renew_status',auto_renew,'environment',case when test_purchase then 'Test' else 'Production' end)
      from public.korlix_magic_purchases where user_id=p_actor and replaced_by_hash is null
      order by active desc, expires_at desc nulls last limit 1));
 end if;
 if g.user_id is null then raise exception 'BILL409: Restore using the KORLIX account that started this Magic Camera purchase.'; end if;
 if p_action='claim' then
   if g.sync_until>now() then raise exception 'BILL409: Subscription is updating. Please retry shortly.'; end if;
   update public.korlix_magic_billing_accounts set sync_token=gen_random_uuid(),sync_until=now()+interval '90 seconds',next_sync_at=now()+interval '1 minute'
    where user_id=p_actor returning * into g;
   return jsonb_build_object('sync_token',g.sync_token,'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from
    (select purchase_token,product_id from public.korlix_magic_purchases where user_id=p_actor and provider='google' and replaced_by_hash is null
      and state not in ('SUBSCRIPTION_STATE_EXPIRED','SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED')
      order by observed_at desc limit 10) x),'[]'::jsonb));
 end if;
 if p_action='release' then
   update public.korlix_magic_billing_accounts set sync_token=null,sync_until=null,next_sync_at=now()+case when coalesce((p->>'success')::boolean,false)
    then interval '10 minutes' else interval '1 minute' end where user_id=p_actor and sync_token::text=p->>'sync_token';
   return jsonb_build_object('ok',true);
 end if;
 if g.sync_token is null or g.sync_token::text is distinct from p->>'sync_token' or g.sync_until<now() then
   raise exception 'BILL409: Subscription changed while verifying. Please retry.';
 end if;
 hash:=p->>'token_hash';
 if p_action='acknowledged' then
   update public.korlix_magic_purchases set acknowledged=true where user_id=p_actor and token_hash=hash;
   return jsonb_build_object('ok',true);
 end if;
 if p_action<>'apply' then raise exception 'BILL400: Unsupported billing action.'; end if;
 if coalesce(hash,'') !~ '^[0-9a-f]{64}$' or g.account_id is distinct from p->>'account_id'
    or coalesce(p->>'product_id','') not in ('magic_camera_starter','magic_camera_plus') or p->>'tier' is distinct from (case when p->>'product_id'='magic_camera_plus' then 'plus' else 'starter' end) then
   raise exception 'BILL409: Purchase does not match this Magic Camera account.';
 end if;
 select * into r from public.korlix_magic_purchases where token_hash=hash for update;
 if found and r.user_id<>p_actor then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if p->>'linked_hash' is not null then
   if p->>'linked_hash'=hash then raise exception 'BILL409: Invalid replacement purchase.'; end if;
   if exists(select 1 from public.korlix_magic_purchases where token_hash=p->>'linked_hash' and user_id<>p_actor) then
     raise exception 'BILL409: Linked purchase belongs to another account.';
   end if;
   if not exists(select 1 from public.korlix_magic_purchases where token_hash=p->>'linked_hash' and user_id=p_actor) then
     raise exception 'BILL409: Restore your previous Magic Camera purchase first.';
   end if;
 end if;
 insert into public.korlix_magic_purchases(token_hash,purchase_token,user_id,product_id,state,active,expires_at,acknowledged,auto_renew,test_purchase)
 values(hash,p->>'purchase_token',p_actor,p->>'product_id',p->>'state',(p->>'active')::boolean,
   (p->>'expires_at')::timestamptz,(p->>'acknowledged')::boolean,(p->>'auto_renew')::boolean,(p->>'test_purchase')::boolean)
 on conflict(token_hash) do update set state=excluded.state,active=excluded.active,expires_at=excluded.expires_at,
   acknowledged=excluded.acknowledged,auto_renew=excluded.auto_renew,observed_at=now()
   where korlix_magic_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase already belongs to another account.'; end if;
 if (p->>'active')::boolean and r.replaced_by_hash is null and p->>'linked_hash' is not null then
   update public.korlix_magic_purchases set replaced_by_hash=hash where token_hash=p->>'linked_hash' and user_id=p_actor;
 end if;
 plan:=public.korlix_magic_plan(p_actor,true);
 return jsonb_build_object('tier',plan->>'name','active',coalesce((p->>'active')::boolean,false) and r.replaced_by_hash is null);
end;
$$;
revoke all on function public.korlix_magic_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_billing_command(uuid,text,jsonb) to service_role;

