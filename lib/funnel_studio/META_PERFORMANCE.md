# K156 — Meta account performance

The existing Meta connection panel now includes a performance panel for the
selected ad account. Choose 7, 30 or 90 completed account-calendar days and tap
**Load Meta performance**. Reports are fetched on demand and remain in widget
memory. Opening the panel or changing the period does not call Meta.

The report displays the account name, ID, currency, timezone, inclusive dates,
device-local retrieval time, amount spent, impressions, clicks (all) and
expandable newest-first daily results. Currency values are formatted directly
from decimal strings; no double conversion can round or lose fractional data.
Cards stack on narrow screens and daily metrics wrap, including enlarged text.

All figures cover the selected account's entire campaign activity. They do not
attribute results to the current funnel or combine with manually entered
campaign reports. Leads, revenue, ROAS and confirmed appointments are not inferred.
Meta can revise historical reporting. Totals sum only returned daily rows;
missing days are not filled and an empty report does not display zero totals.

## State and request behavior

`FunnelMetaPerformance` uses the existing `FunnelClient` and requests
`GET /meta/performance` with `days`, `account_id` and `version`. It only enables
loading while the parent connection is ready and an account is selected.
The response must identify Meta as its source, account as its scope, and match
the requested account and connection version.

The widget clears old data on a fresh request, period change, parent connection
operation, account/version change, client change and access denial. Request
identity plus the account/version binding suppresses late responses. Failures
show the API's bounded error without retaining earlier totals. Disconnecting or
reselecting during a request cannot restore the previous report. Parent disposal
removes the shared access listener. The backend independently rechecks current
owner entitlement and connection state after remote work.

## Release and deferred acceptance

No client credentials, new configuration, database migration, stored reports,
automatic polling or ad-publishing capability is introduced. Production Meta
activation remains a separate owner-approved step. The server still reports
`ad_publishing_ready: false`.

Deploy the K156 backend before this frontend after production approval. K155 is
a compatible rollback: restore the frontend first, then the backend if needed.
No owner funnel documents need modification.

Mocked automated tests cover explicit loading, period queries, error clearing,
empty rows, late results, access loss, wrong-version responses, connection-panel
integration, disconnect and 1440/390/320 px layouts (1.3x text at 320 px).
They do not establish real Meta app approval or verify actual account spend.

Deferred user walkthrough, once Meta activation and live access are authorized:
1. Select the intended Meta account; confirm the account-wide scope and timezone.
2. Load each period and compare the same account, completed dates and metrics
   with Meta reporting. Use clicks (all), not link clicks, for the comparison.
3. Expand daily results and check narrow-screen scrolling and enlarged text.
4. Change the selected account or disconnect while a report is pending; confirm
   earlier figures disappear. Confirm failed/empty requests do not imply zero spend.

Allow 5–10 minutes for the reporting walkthrough once working Meta access exists;
platform setup/review time is separate and has not been estimated.

# K157 — Campaign comparison

Choose **Campaign comparison** in the existing performance panel, choose the
completed-day period and tap **Load campaign comparison**. No request runs on
scope/period selection. The backend fetches full-period campaign rows from the
selected Meta account. Account totals remain available with their existing
daily breakdown; campaign comparison does not add daily campaign drill-down.

The report retains account identity, currency, timezone, dates and retrieval
time. Totals sum all returned campaigns, regardless of local search or page.
Search names or IDs, sort by highest spend/impressions/clicks (all) or name,
and browse 20 rows per page. Names are selectable text and wrap on phones;
IDs distinguish identically named campaigns. Sorting decimal-string spend uses
BigInt micro-units rather than doubles. Counts and money keep K156 formatting.

`FunnelMetaCampaignResults` displays the local snapshot. The parent uses a new
request identity for each result widget so even an immediately completed reload
resets search/sort/page. Scope changes clear and invalidate pending results.
Connection changes, access denial, request failures and parent disposal keep
the same clearing and stale-response protections as account reporting.

Requests use `GET /meta/campaign-performance` with `days`, `account_id` and
`version`, and responses must match the requested campaign scope and account
binding. At most 300 campaigns (three provider pages) are supported; overflow
fails with no partial figures. The owner may try a shorter period. A blank
provider result does not imply zero spend; a search with no matches does not
change full-report totals or claim Meta returned no data.

There is no automatic mapping to funnel plans or attribution. Matching campaign
names do not verify a relationship. Manual campaign reports remain separate.
No launch, pause, budget edit, provider activation, database migration, stored
report or new permission scope is added. Deploy backend then frontend after
approval; K156 is compatible rollback, frontend first. Real Meta activation
and the owner walkthrough remain deferred.

Automated tests cover scope transitions, stale results, connection/access loss,
errors, empty reports, search/sorting/paging, reload reset, precise money sorting
and 1440/390/320 px layouts with enlarged text. Live acceptance should compare
one same-period campaign report with Meta, distinguish duplicate names by ID,
exercise searching/sorting/paging and switch account/scope during a pending
request. Allow an additional 5–10 minutes once Meta access is available; platform
setup/review time remains separate.
