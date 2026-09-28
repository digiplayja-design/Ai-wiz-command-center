# KORLIX Inventory Studio

Inventory Studio adds an owner-private stock workspace to the existing Flutter application. It uses the existing authenticated Express API, Supabase database/storage and Live Voice transport. No new hosting services or secret environment variables are required.

## Included

- Partial, case-insensitive item-name, SKU, brand, category, alias, barcode, serial and batch searches, with paginated access to every matching item.
- Statewide, nationwide and international scopes, based on the country/state recorded on the user's own locations. Geographic quantities match the selected scope.
- Item photos served with short-lived private URLs; upload, image normalization and metadata stripping.
- K-Nova Live Voice and typed inventory search. The voice tool is read-only, uses the authenticated inventory client and shows matching item cards. Existing microphone, usage, pause, stop and account-change controls remain in force.
- Photo search and serial-label transcription. OpenAI proposes search terms; users review them before searching or recording a serial. This reads visible labels, not arbitrary encoded barcode symbologies. Typed entry remains available.
- Products, suppliers, customers, warehouses/stores, bins, serials, batches and expiry.
- Receipts, issues, customer/supplier returns, transfers, stock counts, reservations and a stock-movement audit trail.
- Purchase and sales orders with multiple items, partial receipts/shipments and cancellation of remaining quantities.
- Low-stock/expired-stock filters, stock valuation by currency, CSV catalog import with preview, and CSV stock export.
- Responsive light/dark surfaces, depth/shadows, an isometric inventory illustration and item image previews. Empty workspaces are empty; demonstration stock is confined to tests.

## Controls

All endpoints authenticate with the existing requireUser helper. Inventory tables have RLS enabled and no public/authenticated direct privileges. The security-invoker RPC executes only for service_role and filters every operation by the verified actor. Composite owner foreign keys, atomic owner locks, revisions, constraints and persistent request IDs protect quantities, reservations and retry behavior.

Serialized positions hold zero or one unit. Orders cannot partially reserve or ship a serialized unit. Transfers preserve quantity and serial identity. Expired stock is visible but not available for shipping. Stocked records and records referenced by open orders cannot be archived. Audits retain reasons for adjustments.

Photo recognition uses the configured model, store:false, no tools and an explicit consent dialog. It reserves one existing generation credit atomically, refunds failed scans once, and recovers interrupted jobs after four minutes when polled or the workspace is opened again. Images are not retained by this feature after recognition. Deliberately uploaded product photos are retained privately. Live Voice uses existing plan allowances.

## Capacity and boundaries

Current limits are 10,000 active products, 500 locations/contacts per kind, 200 active orders, 50,000 stock positions, 100 lines per order and 200 new products per CSV import. Numeric quantities/costs use four decimal places. Inventory is online and private to one account; shared organization roles, external supplier/retailer catalogs, public worldwide inventory aggregation, marketplace/POS/shipping/accounting connectors, offline sync, manufacturing/BOM, automatic replenishment and hardware scanner integration are not part of this release. The app does not claim universal ERP parity or convert currencies.

## Release and rollback

1. Apply `supabase/migrations/20260928114821_inventory_studio.sql` to the existing project. This adds inventory tables/RPC and a private JPEG storage bucket; it does not alter other feature tables.
2. Publish the backend release branch and verify `/api/health` advertises inventory version 1; unauthenticated inventory routes must return 401.
3. Publish the frontend release branch. Open Utilities → Inventory Studio.
4. A rollback can redeploy the preceding frontend/backend commits. Leave the new inventory schema and user records in place; do not delete customer data as a rollback step.

## Verification

Backend tests use real PostgreSQL semantics through PGlite and the real Express routes, with fake authentication/provider I/O. They cover authorization, row grants, RLS, geographic quantities, search paging, idempotency, serials, transfers, counts, orders, expiry, CSV injection/import, image validation, recognition leases/credits and consent. Flutter tests cover responsive layouts (320, 390 and desktop), large text, forms, shared text/voice search, retry preservation, stale-account responses and actual Live Voice screen tool dispatch with fake devices. The existing Cybersecurity Defender and Live Voice lifecycle tests are included in regression checks.

The production Flutter web build must succeed. Production release checks verify deployment commit IDs, health, route authentication and database permissions. Live microphone quality, recognition accuracy on a user's physical label and a signed-in user workflow still depend on the real device, network and image quality; test fixtures do not substitute for those observations.
