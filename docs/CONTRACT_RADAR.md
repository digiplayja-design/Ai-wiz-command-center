# KORLIX Contract Radar

## Finding and reviewing work

Save your business profile and select a search region. On-demand **Official web search** uses your services, service area, NAICS codes and optional focus. It returns up to 12 source-linked notices. **Direct SAM.gov** searches a structured federal feed without AI credits when the server connection is configured. Both paths keep the original notice link visible; verify closing times, eligibility, documents and amendments there before bidding.

| Region | Official web search sources | Automatic feed |
| --- | --- | --- |
| United States | SAM.gov, NYC City Record, New York State OGS | SAM.gov when configured |
| Canada | CanadaBuys tender notices | None; use on-demand web search |
| United Kingdom | Find a Tender, Contracts Finder | None; use on-demand web search |
| Jamaica | GOJEP, Ministry of Health tender notices | None; some GOJEP records need browser access |

Coverage is selective, not a complete national, state or local procurement feed. Official web results require individual notice URLs actually retrieved by the provider and permitted for the selected region. The backend rejects unsupported sites, duplicate results, known past deadlines and awards. Sources-sought and presolicitations are labelled leads rather than open bids.

Save useful leads to the pipeline. Corporate and other RFPs can be pasted or imported from a PDF. PDF extraction accepts one file up to 5 MiB and 60 pages, returning up to 18,000 characters and an explicit truncation warning. Review the extracted text before saving. Scanned, encrypted or unreadable PDFs are rejected with a readable explanation; there is no OCR. Extraction is private, does not invoke AI and does not retain the raw upload. Only text you subsequently save becomes part of the opportunity.

**Review with KORLIX** remains an explicit consented action. It prepares a requirements checklist, missing-information questions and a working draft. Requirement evidence must match exact supplied passages. Summary-only reviews are labelled; a feed listing is not a full RFP. Credentials remain self-reported, missing facts become placeholders, and nothing is submitted or sent to a buyer automatically.

## Daily monitoring and alerts

Monitoring starts off for every account. In **Monitoring**, select a time zone, local digest time and reminders at 30, 14, 7, 3, 1 or 0 days before a saved deadline (up to five choices). Enable daily monitoring to receive an **in-app** digest and deadline alerts. No email or push delivery is implied.

Up to five saved SAM.gov searches can run daily. Each search checks up to 100 feed records; results remain in the monitoring screen. Up to ten saved SAM.gov notices are checked per daily run, prioritizing those least recently checked. A changed title, response date, status, published/modified date or attachment-link metadata produces a **notice details changed** alert. The system does not download attachments or compare their contents, and the public API exposes the latest version rather than a complete amendment history. If a check fails or a notice cannot be retrieved, its earlier snapshot is retained with a warning. Verify the original source.

Deadline alerts use the most recent available SAM snapshot, or the saved deadline for other opportunities. They follow the account's local calendar date, not an inferred exact closing time. Won, closed and submitted items do not receive deadline reminders. Monitoring works for saved deadlines even without a SAM key. Missing configuration, failures and request limits are visible; the worker never silently switches to billable AI discovery.

The daily worker persists leases, results and unique event keys in Postgres. It polls once per minute, handles at most three accounts per tick, limits each account's processing window to eight minutes and recovers abandoned ten-minute leases. Settings changes cancel stale work before results are committed. A completed local-calendar-day digest is not repeated. One retained event per notice revision/deadline prevents duplicate alerts. Read/clear actions affect only the owner; cleared alerts retain their deduplication key until the 180-day history cleanup.

## Access, credits and privacy

Manual records, PDF extraction, direct feed searches and monitoring are available to signed-in users. They use no AI credits. AI discovery/review retains the existing Ultra Premium/Enterprise entitlement, sharing consent and one-credit charge per successful request. Empty searches and failed/interrupted requests do not charge. Idempotent AI retries do not dispatch or charge twice.

All database actors come from verified backend authentication, never client owner fields. All eight Radar tables have RLS enabled and deny direct anonymous/authenticated access. Service-only security-invoker RPCs enforce ownership. No service keys are exposed to clients. Raw PDFs are processed inside a bounded worker thread, with no arbitrary URL fetching, and discarded after extraction. Request bodies, RFP text, profiles and API keys are not logged by the module.

Discovery sends services, service area, NAICS and focus to OpenAI/web search. Reviews send the selected business profile and notice text/summary only after consent, with `store:false`. Historical review snapshots remain private. Account deletion cascades Radar records. Removing an opportunity removes its watches and review jobs. **Clear my radar** atomically removes the profile, opportunities, jobs, monitoring settings, searches and alerts; already consumed credits are not reversed. Daily rate counters remain until their normal cleanup.

## Limits and provider setup

Existing limits remain: 100 saved opportunities, one active AI job per account, three AI jobs per process, 12 AI starts/account/hour and eight-minute interruption recovery. Inputs and database JSON are bounded.

Direct searches and saves share a durable limit of 40 user actions per UTC day (each search can use two provider requests). Automatic monitoring separately reserves at most 20 provider requests per owner per UTC day, including retries: two reserved per search and one per notice check. A 429 response starts a shared-process SAM cooldown honoring `Retry-After`, bounded to 30 seconds–24 hours and defaulting to one hour. The provider's shared-key quota may be lower; requests can therefore remain unavailable until it resets. There are no automatic API retries within a request.

Set **SAM_GOV_API_KEY** (or legacy alias **SAM_API_KEY**) on the backend to enable the direct connection. The key is server-only and used only with `https://api.sam.gov/opportunities/v2/search`. Redirects are rejected; response size is capped at 2 MiB and requests time out after 20 seconds. A configured status does not prove that the credential is valid or the provider has remaining quota. No new Google billing product is introduced. Existing AI usage rules still apply to explicit AI actions.

## API and deployment

Prefix: `/api/contract-radar`, all authenticated responses `Cache-Control: no-store`.

- Existing profile, pipeline and AI-job endpoints remain compatible. Profile adds `geography: us | ca | uk | jm`; omitted values default to US for legacy accounts.
- `POST /documents`: multipart `file`, returns extraction preview only.
- `POST /direct-search`: `{query, naics, state}`. `POST /direct-search/save`: `{request_key, notice_id}`, re-fetches and saves a validated official notice.
- `GET /monitor`: capabilities, settings, searches and alerts.
- `PUT /monitor/settings`: `{version, enabled, timezone, digest_time, deadline_days}`. Stale versions return 409.
- `POST /monitor/searches`: `{request_key, name, query, naics, state, enabled}`. Delete with `DELETE /monitor/searches/:id`.
- `POST /monitor/alerts/:id/read`, `POST /monitor/alerts/read-all`, and `DELETE /monitor/alerts` with `{confirmed:true}`.

Apply `20261004013602_contract_radar_monitoring.sql` after the original Radar migration and before deploying the backend. It preserves the existing core RPC, wrapping it to clear monitoring atomically with existing records. Register with `autoStartMonitor:true`; stop `monitor.stop()` on shutdown. No new dependency, bucket, paid worker or service plan is needed. Roll back application releases if required, leaving additive data intact.

## Verification and sources

27 automated backend tests use actual PGlite migrations, Express requests and PDF extraction. Fixtures verify ownership, RLS/grants, consent/charging, source validation, PDF limits, daily deduplication, leases, stale settings, quotas, cooldown and pagination. No live AI call, authenticated SAM request, email or buyer contact was made during testing. Real-provider acceptance remains necessary after a SAM key is configured.

Official references checked during implementation:

- [GSA Opportunities public API](https://open.gsa.gov/api/get-opportunities-public-api/)
- [New York State OGS bid calendar](https://ogs.ny.gov/procurement/bid-opportunities)
- [CanadaBuys tender opportunities](https://canadabuys.canada.ca/en/tender-opportunities)
- [GOV.UK Find a Tender](https://www.gov.uk/find-tender) and [Contracts Finder](https://www.gov.uk/contracts-finder)
- [GOJEP](https://www.gojep.gov.jm/epps/home.do) and [Jamaica Ministry of Health tenders](https://www.moh.gov.jm/tenders/)
- Installed `pdf-parse` 2.4.5 official README (`PDFParse.getInfo`, `getText`, `destroy`); existing pinned dependency reused.
