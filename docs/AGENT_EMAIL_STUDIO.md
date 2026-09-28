# Agent and Email Studio — 2026-09-28

Agent Studio now offers capability filtering, name/memory sorting, pins for the
current Studio session, richer profiles, and editable task-brief starting points.
Profiles work for built-in and custom agents. Copying a brief does not run it.
An agent's workflow shortcut opens an editable two-step draft with the selected
agent and a general review step. The existing save, credit, run, review, approval,
and account boundaries still apply. Workflow draft selection is consumed once.

The in-app Email Studio adds draft-state filters, searches across recipients,
drafts, rules, and delivery activity, a review-queue shortcut, rule previews, and
explicitly confirmed rule pause/resume. Requests check the originating client
account both before the request and after its response. Partial load failures
prevent sending from stale status. No internal runner or provider webhook is
exposed to the app.

The standalone Email Center at `/nova-email/` uses a sculpted, responsive visual
system and a unified work queue for drafts, recipients, rules, and activity.
Search supports multiple partial terms, with state filters, ordering, and paged
display of the records loaded from existing public endpoints. Up to 100 records
per queue are loaded; this is not a full-mailbox search. Dates use the device's
time zone and scheduled rule details also show their configured schedule zone.

Summary cards distinguish drafts awaiting review, draft failures, enabled rules,
and delivery issues recorded within the last 24 hours. A separate readiness panel
shows sending controls, daily limits, and the earliest next run in loaded rules.
It does not guarantee provider delivery or imply that an enabled rule is running.

Rule and recipient details include confirmed rule pause/resume, copying an
address, recipient suppression with a required reason, and reuse of a rule's
message as a new draft. Reuse clears recipient selection and the transactional
confirmation. Draft review, editing, approval nonce handling, sending, deletion,
template management, and schedule management continue through their existing
controls. No bulk send or immediate automation runner was added.

Email Center refreshes bind results to the initiating account, session, agent,
and refresh generation. Failed panels show unavailable data, not invented zero
counts. Changing scope hides old queue rows, and resetting the email session
clears loaded email data. Untrusted record content is escaped before display.

Validation covers responsive Flutter layouts, profile briefs, agent-led workflow
planning without automatic saves/runs, filtered queues, confirmed PATCH-only
rule changes, existing voice/schedule authorization flows, queue pagination,
restricted recipient classification, stale-data handling, and HTML escaping.
Production email sends and scheduler executions are not part of release tests.
