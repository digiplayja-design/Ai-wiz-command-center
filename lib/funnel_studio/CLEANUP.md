# K149 inquiry cleanup

The Leads inbox offers **Delete inquiry** for one record and **Clean up old
inquiries** for a manually reviewed age-based batch. The default cutoff is 90
days ago in UTC; owners can change it and choose Won, Lost or both. Current inbox
filters do not limit batch cleanup. There is no automatic retention schedule.

The dialog previews the exact names, emails, received times, stages and local
history to be removed, plus protected-record counts/reasons. A batch is at most
100 eligible records. Active follow-ups/sequences and recorded email activity
prevent deletion. Owners must type DELETE and press the delete button. The
ten-minute server review binds the exact current records and owner; changes
require another preview. Deletion never cancels or stops a message.

CRM contacts and Email Center records are retained. Inquiry totals and derived
campaign/stage counts decrease. This is permanent inquiry cleanup, including
private notes and listed resolved local history; it is not full data erasure
across CRM and email systems.

Changing criteria clears the review and confirmation. Pending deletion disables
repeat actions and dialog close. Failed/unconfirmed results clear approval,
require a fresh preview, and refresh the inbox on close. Confirmed deletion
refreshes page one using the applied inbox filters. Access denial clears private
identity/details in both dialog and underlying inbox. The service can recognize
an identical signed retry; the UI does not automatically repeat a deletion.

Backend migration and routes must deploy first. Revert frontend/backend app
commits for rollback while retaining the K149 database replay protection.
No production inquiries are deleted during deployment.

Automated widget checks cover preview versus mutation, exact confirmation,
criteria changes, protected records, pending actions, uncertain results,
access denial, malformed responses and 1440/390/320 px layouts. The 320 px
case uses 1.3x text. Run with KORLIX_FLUTTER_ROOT pointing to the Flutter SDK so
real fonts load. User hands-on acceptance remains deferred until the final pass.
