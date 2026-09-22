# K148 · Lead management

In **Leads**, choose **Manage lead** to assign New, In review, Qualified, Won or
Lost and save a private note of up to 4,000 characters. The editor fetches the
latest saved details before editing. Concurrent changes require an explicit
reload; unsaved edits are preserved until the owner chooses to discard them.
Access loss clears the editor and the inbox. A pending save cannot be repeated.

These stages are owner-entered organization labels. They do not change CRM
permissions, pause existing follow-ups, enroll sequences or record revenue.
The editor displays saved scheduled and delivery-review counts so the owner can
manage outstanding replies in Follow-ups. Those counts are a point-in-time read.

Stage counts cover the applied search, source and UTC dates before narrowing to
one status. Apply filters to update the result set and export together. Saving
details refreshes the first page with the already-applied filters; an edited
lead can disappear from the current status filter. Unapplied filter text stays
unapplied. Changing a status filter invalidates older pagination cursors.

CSV appends owner-set status, private note and metadata-update time after the
existing columns. Private notes therefore leave the app when the owner exports
them. Formula-like values are exported as text. Existing export limits apply.
Statuses and notes use current saved values; the receipt-time cutoff used for
paging is not a historical snapshot of edits.

Existing inquiries initially show New with an empty note. Deployment does not
infer earlier sales outcomes or start any follow-up action. Visitors cannot
submit owner metadata or read notes through public page/form endpoints.

Deploy the K148 migration, backend and frontend in that order. Keep the added
columns, functions and notes on rollback. Revert frontend/backend commits to
hide this feature without deleting saved data. Meta activation and the user's
hands-on acceptance checks remain deferred until the end of development.
