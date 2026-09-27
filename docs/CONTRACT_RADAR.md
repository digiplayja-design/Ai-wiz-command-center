# KORLIX Contract Radar — first release

## Start
Open **Contract Radar** from the home quick actions or tools. Save a business name, services and service area in **Business**. Optionally add capacity, credentials and NAICS codes. In **Discover**, enter an optional focus and choose **Find opportunities**. Open each original notice, then save useful leads to **Pipeline**. Use **Paste an RFP** for corporate or other notices. In a saved opportunity, add the complete RFP text, choose **Review with Nova**, review the evidence and missing information, and copy the working draft.

## Coverage and accuracy
Discovery uses OpenAI Responses web search restricted to SAM.gov and NYC City Record. This is selective search-backed discovery, not a direct procurement API feed, exhaustive coverage, or a verified list of every open bid. Direct SAM integration requires a separate API key and is deferred. Accepted results must have an individual official notice URL present in the actual provider retrieval sources. Unsupported URLs, duplicates, awards and known past response dates are rejected. Notice classifications distinguish solicitations, sources-sought and presolicitations. Dates, summaries and relevance are search-derived: check the original notice, attachments, amendments, response time and eligibility before acting.

Other RFPs can be pasted (18,000 characters maximum); this release does not parse uploaded PDFs or fetch arbitrary URLs. Summary-only reviews are visibly marked. Requirement evidence must match an exact passage of supplied material; unsupported evidence is removed and the requirement is marked for verification. Profile qualifications are self-reported. Nova prepares drafts with missing-input placeholders; it does not verify credentials, set prices, promise awards, submit bids, contact buyers or move pipeline stages automatically. Submitted/won stages are manual records.

## Access and credits
Profiles, saved opportunities and manual pipeline management are available to signed-in users. AI discovery/review uses the existing Ultra Premium/Enterprise entitlement and consent gate, Astra at extra-high reasoning, and one existing credit per successful request. Searches with no accepted opportunities use zero credits. Failed/interrupted requests do not charge; replaying the same request does not charge or dispatch twice. This release does not create a new payment product.

## Privacy and lifecycle
All records are scoped to the backend-verified account. Three private RLS-enabled tables have no direct anonymous/authenticated access; only the service role can execute the security-invoker RPC. Client requests never select an owner. Session changes discard stale responses and clear private editor state.

Discovery sends services, service area, optional NAICS and the search focus to OpenAI/web search. Reviews send the saved profile and selected notice text or summary to OpenAI after AI consent. Requests set store:false. Profile/notice snapshots and results remain in the private Radar records. Search retrieval uses official public sources. Request bodies, RFP text and profile details are not logged by the module.

Removing a saved opportunity removes its review jobs, but its earlier discovery result can remain in search history. **Clear my radar** removes that account's profile, opportunities and job history. It does not reverse already consumed credits or request deletion from third-party provider retention. Account deletion cascades Radar records. Editing RFP text invalidates its saved review; profile updates do not rewrite historical reviews, whose profile snapshot time is displayed.

## Runtime limits and recovery
Jobs run in the existing backend process, with database-backed state. Navigating away and reopening resumes polling. A server restart can interrupt work; jobs older than eight minutes become failed without charge and can be restarted manually. There is no durable external queue or automatic retry. One active job per account, three starting/running jobs per process, 12 starts per account per hour, 100 saved opportunities, at most 100 retained job records and 12 jobs returned in the current view. Provider calls have finite deadlines and no automatic retries. Inputs and stored JSON sizes are bounded.

## API and deployment
API prefix: /api/contract-radar. GET reads the private snapshot; DELETE requires confirmed:true. PUT /profile saves the profile. POST /opportunities accepts an owned completed discovery job/index or a manual RFP; PATCH/DELETE /opportunities/:id updates/removes it. POST /jobs takes a UUID request_key, kind, consent and optional query/opportunity_id. GET /jobs/:id polls. Responses use Cache-Control:no-store.

Apply the additive contract_radar migration before deploying the backend, then deploy the frontend. Align the repository migration filename with the version returned by Supabase migration history. Existing OpenAI and database configuration is reused; no new credentials, storage buckets, scheduled workers or service plans are introduced. Backend health includes contractRadar.version=1. Roll back both services to their previous release commits if needed; leave additive tables intact to preserve user records. Never drop customer data as a rollback step.

## Verification
Automated backend tests execute the actual migration using PGlite and exercise HTTP ownership, RLS/grants, consent/access, idempotency, atomic charging, source retrieval validation, evidence checks, input validation, recovery and deletion. Flutter tests cover client auth/session guards, profile setup, consent, discovery/save/source links, pipeline/reviews, retries, failed-editor preservation, account switching and confirmation at phone/desktop sizes including larger text. Provider responses in automated tests are fixtures. A signed-in real-provider discovery and RFP review remain live acceptance checks; public health and unauthenticated rejection alone do not prove provider output quality.
