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
