create function public.korlix_magic_apple_command(p_actor uuid,p_action text,p jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare pr jsonb;existing public.korlix_magic_purchases;
begin
 if p_action='due' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select user_id,purchase_token from public.korlix_magic_purchases where provider='apple' and observed_at<now()-interval '10 minutes' and expires_at>now()-interval '1 day' order by observed_at limit 20)x),'[]');end if;
 if p_actor is null then raise exception 'BILL401: Sign in required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('magic-billing:'||p_actor::text,0));
 pr:=public.korlix_magic_plan(p_actor,true);
 if p_action='snapshot' then
  return jsonb_build_object('plan',pr,'purchases',coalesce((select jsonb_agg(jsonb_build_object('purchase_token',purchase_token)) from public.korlix_magic_purchases where user_id=p_actor and provider='apple'),'[]'),
   'entitlement',(select jsonb_build_object('product_id',product_id,'active',active and expires_at>now(),'expires_at',expires_at) from public.korlix_magic_purchases where user_id=p_actor and provider='apple' order by expires_at desc limit 1));
 end if;
 if p_action<>'apply' or p->>'account_id' is distinct from p_actor::text or coalesce(p->>'token_hash','') !~ '^[0-9a-f]{64}$' or coalesce(p->>'product_id','') not in ('magic_camera_starter','magic_camera_plus') then raise exception 'BILL409: Purchase does not match this Magic Camera account.';end if;
 select * into existing from public.korlix_magic_purchases where token_hash=p->>'token_hash' for update;
 if found and (existing.user_id<>p_actor or existing.provider<>'apple') then raise exception 'BILL409: Purchase belongs to another account.';end if;
 insert into public.korlix_magic_purchases(token_hash,purchase_token,user_id,product_id,state,active,expires_at,test_purchase,acknowledged,provider)
 values(p->>'token_hash',p->>'purchase_token',p_actor,p->>'product_id',p->>'state',(p->>'active')::boolean,(p->>'expires_at')::timestamptz,(p->>'test_purchase')::boolean,true,'apple')
 on conflict(token_hash) do update set product_id=excluded.product_id,state=excluded.state,active=excluded.active,expires_at=excluded.expires_at,observed_at=now() where korlix_magic_purchases.user_id=p_actor;
 if not found then raise exception 'BILL409: Purchase belongs to another account.';end if;
 return jsonb_build_object('active',(p->>'active')::boolean);
end $$;
revoke all on function public.korlix_magic_apple_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_magic_apple_command(uuid,text,jsonb) to service_role;
