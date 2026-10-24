# KORLIX POS — first working practice build

Ricardo requested a KORLIX point-of-sale system and selected both retail/services and restaurants/food, available both independently and inside KORLIX AI. This first build implements a reusable Flutter practice workspace and a standalone Flutter shell. It does not process payments or write production business records.

## Working in this build

- Retail/service catalog, categories, search and keyboard-wedge barcode entry (type/scan a sample SKU such as `KX1001`, then Enter).
- Restaurant menu, priced options, takeaway/dine-in, 12 sample tables, notes, pay-now or send-to-kitchen/pay-later orders.
- Kitchen queue with preparing, ready and served states independent of payment state.
- Cash checkout simulation, change, optional restaurant tips, discounts and explicit sample tax rates. All money uses integer cents; discount and tax round half up per line.
- Stock availability, oversell prevention, stock deduction once per order, product editing, full cash refund/cancellation with a reason and an explicit restock choice.
- Immutable historical price snapshots, receipt text/copy, CSV text/copy with spreadsheet formula escaping, daily cash and refund totals, open checks and low-stock display.
- Device-local practice persistence. A failed write restores the prior transaction state; concurrent in-process mutations are rejected. Restore errors preserve the saved value. Reset is explicitly confirmed.
- Responsive desktop, tablet, phone and short landscape layouts. The hosted preview and native shells use the same shared screen and transaction model.

## Access and integration status

`packages/korlix_pos_core` contains the shared model and UI. `apps/korlix_pos` is the independent Flutter web/Android/iOS shell. Android/iOS project scaffolds are prepared, but no native binary was built, signed, installed or submitted to a store.

The KORLIX AI Business catalog has an opt-in `KORLIX POS · Practice` route controlled by `--dart-define=KORLIX_POS_PRACTICE=true`. Default production builds do not expose it. The embedded screen responds to hub session changes by closing its workspace. This is a session-bound preview route, not a new live POS entitlement. No KORLIX AI or Receipt Wiz production deployment was made.

The hosted practice app is owner-private and does not ask for KORLIX credentials. Shared KORLIX sign-in, separate companion session allowances, staff authorization and production records still require backend implementation. Existing Receipt Wiz companion sessions are expressly scoped to receipt routes; reusing that identity label or broadening its permissions would be incorrect.

Practice data is stored only in this device/browser. It is not merchant cloud storage, multi-register synchronization, a backup, an offline payment queue or a financial ledger. Use one tab at a time. No API keys, customer data or payment credentials are included. USD and tax selectors are sample settings, not a merchant-country selection or tax calculation service.

## Production implementation decisions

1. **Merchant workspaces and staff:** introduce business/location/register membership, cashier/manager/owner permissions, shifts, cash drawer counts, audit events and POS-scoped companion sessions. Each server action must derive the actor from verified auth and check membership; never trust a posted owner UUID or client role.
2. **Authoritative sales:** use database transactions with row locks for stock, server pricing/tax snapshots, a stable per-register idempotency key, explicit order/payment/refund state transitions and a transactional integration outbox. Multi-register oversell protection cannot be supplied by this local practice model.
3. **Payments:** confirm merchant country, currency, payment provider and reader/tap-to-pay hardware before integrating. Merchant sales are separate from KORLIX software subscriptions. Keep raw card data out of KORLIX storage and use processor-confirmed server events to settle card orders. No merchant accounts, charges, refunds, transfers or payout settings were created or changed.
4. **Hardware and operating workflows:** select receipt printer/scanner/cash-drawer models and connectivity; implement actual print jobs, retry/reprint markers and end-of-shift reconciliation. Card terminals, printer discovery, kitchen printer routing, table transfers, split bills/tenders, partial returns, recipe-level ingredients and modifier-management tools are not implemented in this practice build.
5. **Business connections:** connect stock events to Inventory Studio and record POS sales as revenue in Bookkeeping. Receipt Wiz currently handles receipt capture/expense evidence; a sales receipt must not be inserted as a duplicate business expense. Add explicit source IDs and replay-safe posting. Preserve current Enterprise access policies for the connected business tools.
6. **Plans and launch:** POS subscription pricing, included tiers, first merchant countries and rollout platforms remain undecided. The Receipt Wiz $8.99 plan is not a POS pricing decision. Pilot with a test merchant, validate physical hardware, reconcile payment/refund totals, and perform account-isolation and failure-recovery checks before live merchant use.

## Verification

Core tests cover cent arithmetic, input rejection, rounding, stock limits, underpayment rollback, duplicate settlement, failed persistence, mode isolation, priced modifiers, kitchen/payment independence, once-only refunds/restocking, cross-day refunds, historical price snapshots, persistence restoration and CSV escaping. Widget checks cover desktop/tablet/phone/landscape, retail checkout, restaurant kitchen flow and embedded-session closure. All 24 core/widget tests passed, including phone navigation with 125% text size. Static analysis passed for the shared package and hub entry/catalog. The self-contained web build succeeded. Browser QA verified the retail cash receipt and change, priced restaurant options, unpaid kitchen submission and persisted preparing status after a reload. No native-device or live payment test was performed.

No production readiness is implied by the private practice preview.

## Private preview published

- URL: https://korlix-pos-practice.silkyhinny128.chatgpt.site
- Audience: owner-private; the hosting access gate uses ChatGPT sign-in. This is separate from the future shared KORLIX login.
- Source runtime commit: `faf18d63d5e95a499ecf159dd06a40f7c3d4cfc8`.
- Sites project: `appgprj_6add32010b94819180e46f871aa8e80c`.
- Sites source commit: `bf171492cfc8c7921c63edca4f90e0d3ca55bbb1`.
- Saved version: `appgprj_6add32010b94819180e46f871aa8e80c~appgver_61cf3a0184cc8191a4b1e908bcd541a1`.
- Deployment: `appgdep_6add36488ca88191b5abdb42607f23d2`, succeeded on 24 October 2026.
- The final browser visit reached the expected private ChatGPT access gate. Functional browser QA was performed on the same locally built assets before publication. Native store publication and merchant production use remain pending.
