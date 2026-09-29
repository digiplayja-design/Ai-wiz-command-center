-- Run only on the isolated AI GAS test branch with zero v2 customer records.
-- All synthetic users, grants, mappings and jobs are rolled back.
begin;
set local statement_timeout='20s';
do $test$
declare
 u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); s uuid:=gen_random_uuid();
 a text:=repeat('a',64); b text:=repeat('b',64); c text:=repeat('c',64);
 d jsonb; r jsonb; j jsonb; n integer:=0; before_n bigint;
begin
 if has_function_privilege('anon','public.korlix_gas_v2_rpc(text,jsonb)','execute') or has_function_privilege('authenticated','public.korlix_gas_v2_rpc(text,jsonb)','execute') then raise exception 'TEST_CLIENT_EXECUTE_EXPOSED'; end if; n:=n+1;
 if not has_function_privilege('service_role','public.korlix_gas_v2_rpc(text,jsonb)','execute') then raise exception 'TEST_SERVICE_EXECUTE_MISSING'; end if; n:=n+1;
 if has_schema_privilege('authenticated','korlix_gas_v2','usage') or has_table_privilege('service_role','korlix_gas_v2.purchases','select') then raise exception 'TEST_PRIVATE_TABLE_EXPOSED'; end if; n:=n+1;
 if (select count(*) from pg_class x join pg_namespace y on x.relnamespace=y.oid where y.nspname='korlix_gas_v2' and x.relkind='r' and x.relrowsecurity)<>7 then raise exception 'TEST_RLS_COUNT'; end if; n:=n+1;
 if exists(select 1 from korlix_gas_v2.products where enabled or google_product_id is not null) then raise exception 'TEST_PRODUCTS_ENABLED'; end if; n:=n+1;
 if (select reference_usd_cents from korlix_gas_v2.products where seconds=18000)<>12499 then raise exception 'TEST_APPROVED_PRICE'; end if; n:=n+1;
 insert into auth.users(id) values(u),(v);
 d:=jsonb_build_object('userId',u,'tokenHash',a,'sku','korlix_ai_gas_1h','productId','synthetic_1h','isTest',true,'consumed',false,'purchasedAt',now(),'sealedToken',jsonb_build_object('v',1,'kid','synthetic','iv','AA','tag','BB','data','CC'));
 r:=public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u)); if r->>'balanceSeconds'<>'0' then raise exception 'TEST_ZERO_BALANCE'; end if; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('grant_google',d); raise exception 'TEST_DISABLED_PRODUCT_ACCEPTED'; exception when others then if sqlerrm<>'GAS_PRODUCT_UNAVAILABLE' then raise; end if; end; n:=n+1;
 update korlix_gas_v2.products set enabled=true,google_product_id='synthetic_1h' where sku='korlix_ai_gas_1h';
 r:=public.korlix_gas_v2_rpc('grant_google',d); if r->>'balanceSeconds'<>'3600' or r->>'granted'<>'true' then raise exception 'TEST_GRANT'; end if; n:=n+1;
 r:=public.korlix_gas_v2_rpc('grant_google',d); if r->>'balanceSeconds'<>'3600' or r->>'idempotent'<>'true' then raise exception 'TEST_REPLAY'; end if; n:=n+1;
 if (select count(*) from korlix_gas_v2.events where user_id=u)<>1 or (select count(*) from korlix_gas_v2.jobs where token_hash=a)<>1 then raise exception 'TEST_DOUBLE_GRANT_OR_JOB'; end if; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('grant_google',d||jsonb_build_object('userId',v)); raise exception 'TEST_CROSS_USER_ACCEPTED'; exception when others then if sqlerrm<>'GAS_PURCHASE_CONFLICT' then raise; end if; end; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('grant_google',d||jsonb_build_object('tokenHash',b,'consumed',true)); raise exception 'TEST_UNKNOWN_CONSUMED_ACCEPTED'; exception when others then if sqlerrm<>'GAS_ALREADY_CONSUMED_UNRECORDED' then raise; end if; end; n:=n+1;
 r:=public.korlix_gas_v2_rpc('debit_verified_gas',jsonb_build_object('userId',u,'eventId','use_1','sessionId',s,'seconds',1000)); if r->>'balanceSeconds'<>'2600' then raise exception 'TEST_DEBIT'; end if; n:=n+1;
 r:=public.korlix_gas_v2_rpc('debit_verified_gas',jsonb_build_object('userId',u,'eventId','use_1','sessionId',s,'seconds',1000)); if r->>'balanceSeconds'<>'2600' or r->>'idempotent'<>'true' then raise exception 'TEST_DEBIT_REPLAY'; end if; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('debit_verified_gas',jsonb_build_object('userId',u,'eventId','use_1','sessionId',gen_random_uuid(),'seconds',1000)); raise exception 'TEST_SESSION_CONFLICT_ACCEPTED'; exception when others then if sqlerrm<>'GAS_USAGE_CONFLICT' then raise; end if; end; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('debit_verified_gas',jsonb_build_object('userId',u,'eventId','use_2','sessionId',s,'seconds',2601)); raise exception 'TEST_OVERDRAFT_ACCEPTED'; exception when others then if sqlerrm<>'GAS_INSUFFICIENT_BALANCE' then raise; end if; end; n:=n+1;
 if (select sum(delta_seconds) from korlix_gas_v2.events where user_id=u)<>2600 then raise exception 'TEST_OVERDRAFT_MUTATION'; end if; n:=n+1;
 j:=public.korlix_gas_v2_rpc('claim'); if j->>'tokenHash'<>a then raise exception 'TEST_CLAIM'; end if; n:=n+1;
 if public.korlix_gas_v2_rpc('claim')<>'null'::jsonb then raise exception 'TEST_DUPLICATE_LEASE'; end if; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('finish',jsonb_build_object('tokenHash',a,'leaseId',gen_random_uuid())); raise exception 'TEST_WRONG_LEASE_ACCEPTED'; exception when others then if sqlerrm<>'GAS_LEASE_STALE' then raise; end if; end; n:=n+1;
 perform public.korlix_gas_v2_rpc('retry',j||jsonb_build_object('errorCode','GOOGLE_UNAVAILABLE')); if (select lease_id is not null or due_at<=now() from korlix_gas_v2.jobs where token_hash=a) then raise exception 'TEST_RETRY'; end if; n:=n+1;
 update korlix_gas_v2.jobs set due_at=now()-interval '1 second' where token_hash=a;
 j:=public.korlix_gas_v2_rpc('claim'); perform public.korlix_gas_v2_rpc('finish',j); if not (select done from korlix_gas_v2.jobs where token_hash=a) then raise exception 'TEST_FINISH'; end if; n:=n+1;
 r:=public.korlix_gas_v2_rpc('grant_google',d||jsonb_build_object('tokenHash',b)); if r->>'balanceSeconds'<>'6200' then raise exception 'TEST_SECOND_PACK'; end if; n:=n+1;
 r:=public.korlix_gas_v2_rpc('revoke',jsonb_build_object('tokenHash',a,'reason','refunded')); if r->>'reversedSeconds'<>'2600' or r->>'unrecoveredSeconds'<>'1000' then raise exception 'TEST_REFUND_ATTRIBUTION'; end if; n:=n+1;
 r:=public.korlix_gas_v2_rpc('balance',jsonb_build_object('userId',u)); if r->>'balanceSeconds'<>'3600' or r->>'reviewRequired'<>'true' then raise exception 'TEST_UNRELATED_PURCHASE_DAMAGED'; end if; n:=n+1;
 perform public.korlix_gas_v2_rpc('revoke',jsonb_build_object('tokenHash',a,'reason','revoked')); if (select sum(delta_seconds) from korlix_gas_v2.events where user_id=u)<>3600 then raise exception 'TEST_DOUBLE_REFUND'; end if; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('grant_google',d); raise exception 'TEST_REGRANT_REVOKED'; exception when others then if sqlerrm<>'GAS_PURCHASE_REVOKED' then raise; end if; end; n:=n+1;
 begin perform public.korlix_gas_v2_rpc('debit_verified_gas',jsonb_build_object('userId',u,'eventId','after_refund','sessionId',s,'seconds',1)); raise exception 'TEST_REVIEW_BYPASS'; exception when others then if sqlerrm<>'GAS_BILLING_REVIEW_REQUIRED' then raise; end if; end; n:=n+1;
 perform public.korlix_gas_v2_rpc('revoke',jsonb_build_object('tokenHash',c,'reason','revoked'));
 begin perform public.korlix_gas_v2_rpc('grant_google',d||jsonb_build_object('tokenHash',c)); raise exception 'TEST_EARLY_REVOCATION_IGNORED'; exception when others then if sqlerrm<>'GAS_PURCHASE_REVOKED' then raise; end if; end; n:=n+1;
 if (select sum(delta_seconds) from korlix_gas_v2.events where user_id=u)<>(select sum(remaining_seconds) from korlix_gas_v2.purchases where user_id=u) then raise exception 'TEST_LEDGER_CONSERVATION'; end if; n:=n+1;
 if (select sum(seconds) from korlix_gas_v2.allocations where user_id=u)<>1000 then raise exception 'TEST_ALLOCATION_CONSERVATION'; end if; n:=n+1;
 perform set_config('korlix.gas2_test_result',jsonb_build_object('passed',n,'failed',0,'mode','isolated_database_transaction_rolled_back')::text,true);
end $test$;
select current_setting('korlix.gas2_test_result')::jsonb as result;
rollback;
