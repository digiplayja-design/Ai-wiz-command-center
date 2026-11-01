-- Dedicated store-review allowance: 60 minutes per UTC calendar month.
-- No fabricated receipts, customer billing switch, or shared account role changes.
create table public.korlix_brain_review_access (
 user_id uuid primary key references public.korlix_brain_billing_accounts(user_id) on delete cascade,
 enabled boolean not null default true,
 reason text not null check(length(reason) between 12 and 500),
 authorized_by text not null check(length(authorized_by) between 3 and 200),
 created_at timestamptz not null default now()
);
alter table public.korlix_brain_review_access enable row level security;
revoke all on public.korlix_brain_review_access from public,anon,authenticated;
grant select,insert,update on public.korlix_brain_review_access to service_role;
comment on table public.korlix_brain_review_access is 'Operations-managed store review accounts only. Not a subscription or verified purchase. Disable access to revoke remaining review minutes.';

alter table public.korlix_brain_minute_grants alter column purchase_key drop not null;
alter table public.korlix_brain_minute_grants drop constraint korlix_brain_minute_grants_kind_check;
alter table public.korlix_brain_minute_grants add constraint korlix_brain_minute_grants_kind_check check(kind in ('subscription','consumable','review'));
alter table public.korlix_brain_minute_grants add constraint korlix_brain_grant_source_check check(
 (kind='review' and purchase_key is null and seconds=3600 and expires_at is not null)
 or (kind in ('subscription','consumable') and purchase_key is not null)
);

create or replace function public.korlix_brain_billing_command(p_actor uuid,p_action text,p jsonb default '{}')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 t timestamptz:=clock_timestamp(); old public.korlix_brain_purchases; s public.korlix_brain_voice_sessions;
 g public.korlix_brain_minute_grants; part jsonb; allocations jsonb:='[]';
 cap integer:=3600; amount integer; available integer; elapsed integer; consumed integer; remaining integer;
 subscription_seconds integer; gas_seconds integer; review_seconds integer; active_subscription boolean; expires timestamptz;
 review_enabled boolean; review_month timestamptz:=date_trunc('month',t at time zone 'UTC') at time zone 'UTC';
begin
 if p_action='due' then
   return coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.korlix_brain_purchases where next_sync_at<=t order by next_sync_at limit 50)x),'[]');
 end if;
 if p_action='stale_sessions' then
   return coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.korlix_brain_voice_sessions where (state<>'ended' and (deadline<=t or last_seen_at<t-interval '45 seconds')) or (state='ended' and call_id is not null and not provider_stopped) limit 100)x),'[]');
 end if;
 if p_actor is null then raise exception 'BILL401: Sign in to use your minutes.';end if;
 insert into public.korlix_brain_billing_accounts(user_id) values(p_actor) on conflict do nothing;
 perform 1 from public.korlix_brain_billing_accounts where user_id=p_actor for update;
 -- Review access is server-managed, account-bound, and never a store purchase.
 select coalesce((select enabled from public.korlix_brain_review_access where user_id=p_actor),false) into review_enabled;
 if review_enabled then
   insert into public.korlix_brain_minute_grants(grant_key,user_id,kind,seconds,expires_at)
   values('review:'||p_actor::text||':'||to_char(review_month at time zone 'UTC','YYYY-MM'),p_actor,'review',3600,
     (review_month at time zone 'UTC'+interval '1 month') at time zone 'UTC')
   on conflict(grant_key) do nothing;
 else
   update public.korlix_brain_minute_grants set revoked=true where user_id=p_actor and kind='review' and not revoked;
 end if;

 if p_action='apply' then
   if p->>'provider' not in('apple','google') or p->>'kind' not in('subscription','consumable') or
     coalesce(p->>'purchase_key','')!~'^[a-f0-9]{64}$' or length(coalesce(p->>'grant_key',''))<6 or
     (p->>'seconds')::integer not in(3600,7200,10800) or
     (p->>'kind'='subscription' and ((p->>'seconds')::integer<>3600 or p->>'expires_at' is null)) then
     raise exception 'BILL400: Invalid verified purchase.';
   end if;
   select * into old from public.korlix_brain_purchases where purchase_key=p->>'purchase_key' for update;
   if found and (old.user_id<>p_actor or old.product_id<>p->>'product_id' or old.provider<>p->>'provider') then raise exception 'BILL409: This store purchase is already linked to another account or product.';end if;
   if old.observed_at is null or old.observed_at<=(p->>'observed_at')::timestamptz then
     insert into public.korlix_brain_purchases(purchase_key,user_id,provider,provider_token,product_id,kind,active,revoked,expires_at,test_purchase,observed_at,next_sync_at)
     values(p->>'purchase_key',p_actor,p->>'provider',p->>'provider_token',p->>'product_id',p->>'kind',(p->>'active')::boolean,(p->>'revoked')::boolean,(p->>'expires_at')::timestamptz,(p->>'test_purchase')::boolean,(p->>'observed_at')::timestamptz,t+interval '10 minutes')
     on conflict(purchase_key) do update set active=excluded.active,revoked=excluded.revoked,expires_at=excluded.expires_at,observed_at=excluded.observed_at,next_sync_at=excluded.next_sync_at;
     if (p->>'revoked')::boolean or not (p->>'active')::boolean then
       update public.korlix_brain_minute_grants set revoked=true where purchase_key=p->>'purchase_key';
     elsif (p->>'active')::boolean then
       -- A stable verified transaction/order key makes retries and restores idempotent.
       insert into public.korlix_brain_minute_grants(grant_key,purchase_key,user_id,kind,seconds,expires_at)
       values(p->>'grant_key',p->>'purchase_key',p_actor,p->>'kind',(p->>'seconds')::integer,(p->>'expires_at')::timestamptz)
       on conflict(grant_key) do update set expires_at=excluded.expires_at,revoked=false
         where public.korlix_brain_minute_grants.purchase_key=excluded.purchase_key and public.korlix_brain_minute_grants.user_id=excluded.user_id;
       if exists(select 1 from public.korlix_brain_minute_grants where grant_key=p->>'grant_key' and user_id<>p_actor) then raise exception 'BILL409: These minutes belong to another account.';end if;
     end if;
   end if;
 elsif p_action='retry_later' then
   update public.korlix_brain_purchases set next_sync_at=t+interval '5 minutes' where purchase_key=p->>'purchase_key' and user_id=p_actor;
 elsif p_action='purchases' then
   return coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.korlix_brain_purchases where user_id=p_actor order by observed_at desc limit 100)x),'[]');
 elsif p_action='reserve' then
   if exists(select 1 from public.korlix_brain_voice_sessions where user_id=p_actor and state<>'ended') then raise exception 'BILL409: End the other Live Conversation before starting a new one.';end if;
   for g in select * from public.korlix_brain_minute_grants where user_id=p_actor and not revoked and (expires_at is null or expires_at>t) and seconds>used_seconds+reserved_seconds order by expires_at nulls last,created_at for update loop
     amount:=least(cap,g.seconds-g.used_seconds-g.reserved_seconds);
     -- Do not reserve subscription seconds beyond that period's actual expiry.
     if g.expires_at is not null then amount:=least(amount,greatest(0,floor(extract(epoch from g.expires_at-t))::integer));end if;
     if amount>0 then
       allocations:=allocations||jsonb_build_array(jsonb_build_object('key',g.grant_key,'seconds',amount));
       update public.korlix_brain_minute_grants set reserved_seconds=reserved_seconds+amount where grant_key=g.grant_key;
       cap:=cap-amount;
     end if;
     exit when cap=0;
   end loop;
   if cap=3600 then raise exception 'BILL402: Your Live minutes have run out. Open Plan & AI GAS to add more.';end if;
   insert into public.korlix_brain_voice_sessions(user_id,allocations,max_seconds)values(p_actor,allocations,3600-cap)returning * into s;
   return jsonb_build_object('sessionId',s.id,'maxSessionSeconds',s.max_seconds,'maxResponses',10000,'remainingSeconds',s.max_seconds,'allowed',true);
 elsif p_action in('start','usage','end','session','stopped') then
   select * into s from public.korlix_brain_voice_sessions where id=(p->>'sessionId')::uuid and user_id=p_actor for update;
   if not found then raise exception 'BILL404: Voice session not found.';end if;
   if p_action='session' then return to_jsonb(s);end if;
   if p_action='stopped' then update public.korlix_brain_voice_sessions set provider_stopped=true where id=s.id;return jsonb_build_object('stopped',true);end if;
   if p_action='start' then
     if s.state<>'pending' or s.deadline<=t or coalesce(p->>'callId','')!~'^rtc_[a-zA-Z0-9_-]{1,160}$' then raise exception 'BILL409: This voice connection expired. Please reconnect.';end if;
     update public.korlix_brain_voice_sessions set state='active',call_id=p->>'callId',started_at=t,last_seen_at=t,deadline=t+make_interval(secs=>s.max_seconds) where id=s.id;
     return jsonb_build_object('started',true);
   end if;
   if s.state<>'ended' then
     elapsed:=case when s.started_at is null then 0 else least(s.max_seconds,greatest(s.charged_seconds,ceil(extract(epoch from least(t,s.deadline)-s.started_at))::integer))end;
     remaining:=elapsed;
     for part in select value from jsonb_array_elements(s.allocations) loop
       amount:=(part->>'seconds')::integer;
       consumed:=least(amount,remaining);
       select * into g from public.korlix_brain_minute_grants where grant_key=part->>'key' for update;
       -- Each call reserves a disjoint slice; elapsed time is cumulative.
       available:=least(amount,greatest(0,s.charged_seconds-(elapsed-remaining)));
       update public.korlix_brain_minute_grants set used_seconds=used_seconds+consumed-available,reserved_seconds=reserved_seconds-consumed+available where grant_key=g.grant_key;
       remaining:=remaining-consumed;
     end loop;
     update public.korlix_brain_voice_sessions set charged_seconds=elapsed,last_seen_at=t where id=s.id;
     if p_action='end' or t>=s.deadline or exists(select 1 from public.korlix_brain_minute_grants where grant_key in(select value->>'key' from jsonb_array_elements(s.allocations)) and revoked) then
       remaining:=elapsed;
       for part in select value from jsonb_array_elements(s.allocations) loop
         amount:=(part->>'seconds')::integer;consumed:=least(amount,remaining);
         update public.korlix_brain_minute_grants set reserved_seconds=reserved_seconds-(amount-consumed) where grant_key=part->>'key';remaining:=remaining-consumed;
       end loop;
       update public.korlix_brain_voice_sessions set state='ended',ended_at=t where id=s.id;
     end if;
   end if;
   return (select jsonb_build_object('allowed',state<>'ended','limitReached',state='ended','chargedSeconds',charged_seconds,'sessionId',id) from public.korlix_brain_voice_sessions where id=s.id);
 elsif p_action<>'snapshot' then raise exception 'BILL400: Unknown billing action.';
 end if;
 select coalesce(sum(greatest(0,seconds-used_seconds-reserved_seconds))filter(where kind='subscription'),0),
   coalesce(sum(greatest(0,seconds-used_seconds-reserved_seconds))filter(where kind='consumable'),0),
   coalesce(sum(greatest(0,seconds-used_seconds-reserved_seconds))filter(where kind='review'),0)
 into subscription_seconds,gas_seconds,review_seconds from public.korlix_brain_minute_grants where user_id=p_actor and not revoked and(expires_at is null or expires_at>t);
 select coalesce(bool_or(active and not revoked and expires_at>t),false),max(expires_at)filter(where active and not revoked) into active_subscription,expires from public.korlix_brain_purchases where user_id=p_actor and kind='subscription';
 return jsonb_build_object('subscriptionActive',active_subscription,'renewsAt',expires,'includedSeconds',subscription_seconds+review_seconds,'gasSeconds',gas_seconds,'remainingSeconds',subscription_seconds+review_seconds+gas_seconds,'reviewAccess',review_enabled,'reviewSeconds',review_seconds);
end $$;
revoke all on function public.korlix_brain_billing_command(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.korlix_brain_billing_command(uuid,text,jsonb) to service_role;
