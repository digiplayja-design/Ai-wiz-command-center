-- ============================================================
-- KORLIX AI BUILD 132
-- Align the 5-hour AI GAS package with Apple's $124.99
-- United States consumable price point.
--
-- This migration intentionally corrects the catalog without
-- rewriting the previously issued Build 132 foundation migration.
-- ============================================================

begin;

do $$
declare
  v_current_price integer;
begin
  select p.base_usd_cents
  into v_current_price
  from public.korlix_ai_gas_products p
  where p.sku = 'korlix_ai_gas_5h'
  for update;

  if not found then
    raise exception
      'KORLIX AI GAS 5-hour catalog row is missing.';
  end if;

  if v_current_price not in (12500, 12499) then
    raise exception
      'Unexpected KORLIX AI GAS 5-hour price: %',
      v_current_price;
  end if;

  update public.korlix_ai_gas_products
  set
    base_usd_cents = 12499,
    updated_at = now()
  where
    sku = 'korlix_ai_gas_5h'
    and display_name = '5 Hours AI GAS'
    and seconds = 18000;

  if not found then
    raise exception
      'KORLIX AI GAS 5-hour catalog identity mismatch.';
  end if;
end
$$;

commit;
