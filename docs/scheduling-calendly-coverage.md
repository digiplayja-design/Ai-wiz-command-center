# Calendly comparison and completion gates

Reviewed official Calendly scheduling and pricing pages on 2026-09-30. This is an implementation checklist, not a claim that KORLIX already matches or exceeds every Calendly capability. Providers' plans and features can change.

| Area | KORLIX connected release | Remaining gate |
| --- | --- | --- |
| Personal booking pages | Native one-to-one and group pages; manual location/link | Custom domains, broader page styling and embed widgets |
| Availability | Time zones, DST, split hours, overrides, buffers, limits; Google/Microsoft OAuth, multi-calendar checks, host calendar updates | Provider setup and real-account acceptance; incremental/push sync |
| Booking management | Cancel, reschedule, ICS, statuses, CSV; queued host calendar updates | Guest calendar invitations and external cancellation reconciliation |
| Workflows | Opt-in email confirmations/changes/reminder; durable queue | Live inbox acceptance, delivery webhooks, suppression, SMS and richer workflows |
| Teams | Consented team membership, round-robin and collective hosts, shared conflict locks, fairness tests | Organization-wide administration, richer assignment policies and real-provider acceptance |
| Routing | Intake questions; share link through KORLIX Funnel Studio | Conditional qualification, ownership routing, form embeds and CRM assignment |
| Polls and flexible links | Not implemented | Meeting polls, one-off/single-use links and ad hoc slots |
| Meetings | Host-provided video link or location | Google Meet, Zoom and Teams creation, authorization and cancellation cleanup |
| Payments | Stripe Standard OAuth, direct USD card checkout, verified payment holds, webhooks, full refunds | Credentials, real test-mode acceptance; tax, partial refunds and multicurrency |
| Integrations | Links to existing KORLIX modules | Automatic contact sync, event webhooks, third-party API and integration coverage |
| Reporting/admin | Small host dashboard and audit log | Team analytics, organization roles, SSO/SCIM, retention and admin export |
| AI scheduling/notetaking | Reviewed drafts, availability changes, real slot search, cancellation and rescheduling | Live model acceptance; autonomous negotiation, conferencing/recording consent, summaries and handoff |
| Quality | 136 passing local database/HTTP/Flutter tests plus desktop/mobile browser flows | Real-provider acceptance, load testing, accessibility audit and production SLOs |

Calendly currently advertises calendar connections, team scheduling, routing, integrations, payments and AI capabilities. Matching a first screen does not establish parity. KORLIX's proposed advantage is the full flow from discovery and Social/Funnel activity through scheduling, contact context and authorized follow-up inside one product. Those automatic cross-product actions need explicit implementation and testing before they can be advertised.

Sources: [Calendly scheduling](https://calendly.com/scheduling), [pricing and plan comparison](https://calendly.com/pricing), [payments](https://calendly.com/payments), [Resend idempotency behavior](https://resend.com/docs/dashboard/emails/idempotency-keys).
