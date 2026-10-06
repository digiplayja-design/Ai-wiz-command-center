-- Defense in depth: the browser cannot access these server-owned tables even
-- if a broad grant or permissive policy is introduced elsewhere in the future.
create policy receipt_wiz_server_only on public.korlix_receipt_wiz as restrictive for all to anon,authenticated using(false) with check(false);
create policy receipt_wiz_server_only on public.korlix_receipt_wiz_scans as restrictive for all to anon,authenticated using(false) with check(false);
create policy receipt_wiz_server_only on public.korlix_receipt_wiz_usage as restrictive for all to anon,authenticated using(false) with check(false);
