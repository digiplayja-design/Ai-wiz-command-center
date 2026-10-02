# KORLIX Business Directory and Verified Business

## Release scope

Public directory: `https://www.korlixdeveloper.com/business-directory/`
Owner/admin entry: KORLIX app → Utility / For business → Business Directory.

Any permanent signed-in account can submit free listings; no Enterprise/paid plan check. Up to ten locations per owner. Public browsing does not require sign-in. Basic listing fields include business name, category/nature, description, public phone/email, address or service area, city/country, company photos, hours, website/social link, languages and accessibility. Owner name stays private unless separately entered as public contact name. Favorites are browser-local, capped at 50; search and public cards use only approved snapshots.

Owners save drafts, upload photos (automatically selected), preview/consent and submit. Administrators publish or request changes. Public pages retain the previous approved snapshot during edits; hiding removes the listing from public browsing. Uploads remain in a private bucket; public photo routes check the approved photo IDs and current visibility. Verification files can never be used as public photos. Unused files can be removed; removing proof requires re-review. Reports enter the admin review queue. Upload limits: 5 MB/file, 20 photo uploads and 5 private evidence uploads per location; public gallery shows 3 photos for free and 12 for an active verified member.

## Verification and paid membership

Review first, pay second. Owner submits an explanation and optional evidence. Authorized reviewers independently check business email, phone and ownership evidence; all three checks and a note are required for approval. Sole proprietors can supply suitable alternative evidence; government registration is not the only path. The badge states owner/business connection, not guaranteed quality, licensing or insurance. Review notes must document methods/results without copying unnecessary personal identifiers.

Prices: USD 4.99/month or 49.00/year, recurring until canceled. Price and interval are server-controlled. Only owners of reviewed published businesses may start checkout. Membership includes badge eligibility, 12-photo gallery, expiring offers/announcements and approximate 30-day views/contact-click analytics. Free listing remains available after cancellation. Sponsored ranking is not implemented; payment does not change ordinary search ranking.

Badge requires approved verification + LIVE active paid membership + future paid-through date + no refund/dispute hold. Test-mode payments never display public badges. Identity/contact changes invalidate verification immediately. Cancellation of renewal preserves the paid period; delinquency, expiry and revoked verification remove eligibility. Refund/dispute events hold the badge; a new paid invoice can clear the invoice-bound hold. Counts are deduplicated/rate-limited signals, not unique visitors or confirmed leads.

## Payment configuration (Render backend)

No secrets are committed. Checkout fails closed until both are set:

- `KORLIX_DIRECTORY_STRIPE_SECRET_KEY`: Stripe account secret/restricted API key with Checkout, subscriptions, invoices, charges, customers and customer-portal access needed by this integration.
- `KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET`: signing secret for `/api/directory/billing/webhook` on the existing backend.

Endpoint: `https://chee-chai-chee-backend.onrender.com/api/directory/billing/webhook`
Pinned Stripe API version: `2025-09-30.clover`.

Subscribe to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`, `invoice.payment_action_required`, `invoice.marked_uncollectible`, `charge.refunded`, `charge.dispute.created`. Matching test/live mode is enforced. No Connect account header: these are KORLIX's own memberships, separate from appointment merchants. Dynamic recurring Checkout prices use the approved fixed amounts. Configure the Stripe customer portal for payment-method/invoice management and cancellation; the in-app Cancel renewal action also works independently of portal configuration.

Use Stripe test mode first, then matching live key and webhook secret. Do not make a real charge for release testing. A hosted Checkout success redirect is not payment proof: signed webhooks / authenticated provider retrieval reconcile the actual subscription, line price, currency, quantity, paid invoice and period. Checkout uses a durable generation/idempotency key; expired sessions must be reconciled before opening another. Changing an open checkout's billing interval is rejected. Stripe credentials and webhook setup require payment-account access; connecting the optional Stripe integration can assist with account setup.

## Reviewer access

`KORLIX_DIRECTORY_ADMIN_USER_IDS`: comma-separated Supabase user UUIDs explicitly authorized as directory reviewers. If unset, the existing server-configured application owner `KORLIX_VAPI_NOVA_OWNER_UID` is used. Client metadata, paid tier, quota allowlists and client-supplied admin flags never grant review access. `/api/directory/health` exposes readiness booleans only, not IDs or secrets. Admin desk appears only when `/me` confirms reviewer access. Add additional reviewers using the dedicated allowlist.

## Data, retention and operations

Six service-only RLS tables: businesses, assets, memberships, reports, audit and metrics. Invoker functions are revoked from PUBLIC/anon/authenticated. Verified actor IDs and reviewer status come from server-authenticated users. Optimistic versions reject stale edits/reviews. Public projection excludes owner ID/name, proof, review notes, Stripe references and unpublished content. Private files use authenticated byte downloads. Generated public JPEGs strip input metadata through re-encoding. PDF proof downloads use attachment disposition and nosniff.

Application signout clears private forms and ignores late account-bound responses. Directory data syncs through Supabase; public favorites alone are local. Failed form submissions retain an in-memory recovery draft until account change/close. Do not treat this as an offline backup.

Account deletion is currently the application's existing support-reviewed delete-request workflow. Before fulfilling a request: cancel directory subscriptions in Stripe, hide listings, delete associated Storage objects/evidence, then remove database/account records. Database foreign-key cascades do not delete Stripe subscriptions or Storage objects. Handle refund requests and evidence-removal support requests through the published support contact. Review the queue regularly; no fake approval or automated email/phone contact is performed by deployment.

## Validation

Backend: `node --test backend/test/directory.test.mjs backend/test/directory_routes.test.mjs`
Flutter: `flutter test --no-pub test/directory`
Public browser QA uses only synthetic intercepted fixtures; no demonstration business is published.
Release checks: migration privileges and security advisors, backend health/public anonymous search/private 401, deployed static pages and web build, exact release commits, error logs.

Not included in this release: customer reviews, booking, sponsored placements, automated identity-vendor checks, QR-code generation, or KORLIX-assisted listing descriptions. These can be added without changing the free-listing model.
