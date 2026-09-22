# K150 guided inquiry forms

The Page editor's **Inquiry form** selector offers **Single page** and
**Guided · three steps**. Existing documents default to Single page. Saving a
draft does not change the live page; publication remains a separate confirmation.
NOVA copy generation and draft duplication preserve the selected form style.

Guided visitors enter contact details, provide their request and consent, then
review everything before the final send. Back/edit keeps their details and
requires consent again at the request step. Only final submission creates an
inquiry or its configured follow-up tasks. Intermediate progress creates no
partial leads and does not send messages.

The owner preview has contact/request/review chips. These use sample details
and make no network requests or unsaved edits. The public form uses server-rendered
HTML steps and native POST buttons; JavaScript is not required. Existing form
expiry, current publication, owner entitlement and request-id replay protections
remain. A signed final review prevents changed hidden fields from bypassing it.

Rehearsal describes the selected visitor journey but remains a simulation, not
a claim that the browser flow or delivery was exercised. Desktop, phone and
enlarged-text layouts are covered by automated widget checks. User hands-on
tests stay deferred until the end.

Deploy the supporting backend before this UI. No database migration is needed.
Rollback both app versions to K149 to restore single-page forms, retaining all
data and replay protections. Open guided forms require a reload after rollback.
