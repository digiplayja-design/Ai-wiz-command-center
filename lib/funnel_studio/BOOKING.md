# K155 · Booking routes

Page → Booking routes lets owners add up to four ordered rules, each matching
one current multiple-choice answer. Rules have an owner-facing name, public
HTTPS destination and visitor button label. The first active matching answer
selects its rule; otherwise the default booking URL is offered. Hidden questions
do not match. Incomplete or duplicate answer conditions block publication but
can be saved in a draft. Save/reload and explicit publication use the existing
version checks. NOVA copy and duplication preserve independent route objects.
Removing a source question clears its route reference, including before ID reuse.

The page preview lets owners change choice answers to inspect both conditional
questions and the selected synthetic receipt. It does not save sample answers,
submit an inquiry, navigate to a booking site or create an appointment. The
rehearsal receipt uses its first-choice scenario. Follow-up message templates
continue to use the default booking URL, not an answer-based route.

The backend saves the offered route, thank-you copy, URL and label transactionally
with each inquiry. Leads shows this historical outcome with a clear indication
that it is not a confirmed appointment; CSV appends the route name, URL and
button label. Old inquiries do not receive inferred outcomes. Link clicks and
appointment completion are not tracked in this release.

Production requires the K155 database migration and backend before this UI.
The migration is additive but guarded against intervening capture changes.
Publishing or changing individual owner funnels remains an owner action.
If reverting to K154, retain all saved snapshots and review any already-published
routes first; an older editor can strip new route fields. Prefer restoring K155.

Verification: route completeness/priority/hidden sources, independent cloning,
source deletion, editing/order/limits, draft-only save and reload, and screenshots
at 1440/390/320 px with 1.3× text at 320. Real-device acceptance remains deferred.
