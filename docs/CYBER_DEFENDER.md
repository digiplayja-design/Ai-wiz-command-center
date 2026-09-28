# KORLIX Cybersecurity Defender v1

Defender helps a signed-in user assess suspicious text, strengthen routine security habits and follow recovery steps. NOVA remains the voice brand; the review agent is KORLIX.

## Included

- Free quick checks for messages and links: credential requests, unusual payment patterns, remote-access requests, urgency, changed bank instructions and URL structure. Paste up to 12,000 characters and 25 links. An optional known official domain enables exact/subdomain-boundary comparison.
- Optional deeper review using the existing configured `gpt-6-astra` / `xhigh` Responses API. Explicit third-party AI consent, one generation credit, `store:false`, strict structured output, no tools, no automatic provider retries, 180-second provider timeout.
- Eight personal habits plus four business habits. Progress is self-reported, not a measured protection score.
- Four free incident guides: clicked link, exposed password/code, payment loss and device warning. Actions are reviewed static text, not model-generated instructions.
- Up to 50 private reports, action checklists, plain-text export and confirmed deletion.

## Boundaries

This is text-based guidance, not antivirus, endpoint protection, a penetration test, breach monitoring or an inbox/network scanner. It never fetches pasted destinations, resolves DNS, follows redirects, executes commands, downloads files or sends reports/messages. Suspicious hostnames are displayed as defanged plain text. Only fixed FTC/CISA guidance links can be launched.

Heuristics can miss attacks and produce false positives. English-language wording rules are limited; the optional model review can examine other language context but cannot verify authenticity. HTTPS, a matching domain and an absence of warning signs do not prove safety. AI concern can elevate a quick-check label but cannot downgrade it. AI observations can be mistaken; original messages, headers, redirects and attachments are not independently verified.

## Privacy and authorization

Every route uses the existing verified `requireUser` gate; user identity never comes from body fields or display headers. `Cache-Control: no-store` applies to all responses. Two RLS-enabled private tables and a SECURITY INVOKER RPC are accessible only to `service_role`; direct anon/authenticated table and RPC permissions are revoked. The RPC scopes every record to the verified actor. Foreign IDs yield 404.

Original pasted text stays in request/process memory only and is never written to Defender tables or its logs. For AI checks it is sent to OpenAI after consent. Reports retain generic rule findings, destination hostnames, safe metadata, an input fingerprint, model-generated observations and user progress. Model instructions prohibit reproducing identities or secrets; URL/email output scrubbing is defense in depth, not a guarantee that generated text contains no sensitive information. Users should remove secrets and personal details before submission and review exports before sharing. Do not log request bodies in infrastructure added later.

Deleting a report clears its findings, review, details and progress. A minimal tombstone retains ID, owner, input hash, timestamps and usage bookkeeping to prevent accidental request replay. Account deletion cascades Defender data. Session changes clear the visible workspace and reject late responses; token refresh within the same verified session remains valid.

## Reliability and usage

Creation uses an input-bound UUID, and revisions plus event IDs protect checklist updates. Unknown network outcomes retain the exact request for explicit retry. No automatic mutation retry creates another charge. Usage is reserved atomically with the report under a per-owner transaction lock and owner-bound usage row lock. Quick checks and guides cost no generation credits. One active AI review per owner, three local active/starting reviews, 12 AI reviews/hour, 60 reports/hour including deletion tombstones, 50 retained reports maximum.

A durable quick result is returned before AI work. Failed/refused/invalid provider responses refund once and preserve quick findings. Interrupted jobs older than eight minutes recover on the owner's next list/get/action; late completion cannot overwrite a recovered job. Background review work is in-process, not a durable queue. A server restart can interrupt work; it is not automatically resubmitted. Progress and quick findings remain durable. Pending review deletion is blocked until completion or timeout recovery.

## Deployment and verification

Apply `supabase/migrations/20260928014105_cyber_defender.sql`, deploy the existing backend, then the existing frontend. No new services, secrets, storage buckets or subscription changes. Health reports `cyberDefender.version=1`. Unauthenticated routes must return 401.

`node --test backend/test/cyber_defender.test.mjs` runs real Express requests and PostgreSQL behavior through PGlite, using synthetic users and stubbed AI. It covers ownership, role grants/RLS, input bounds, URL parsing, response contracts, idempotency, charges/refunds, stale recovery, limits, deletion and export. No real provider calls or owner credits are used. Live authenticated acceptance testing remains a user check after deploy.

## Guidance sources (reviewed 2026-09-28)

- FTC: https://consumer.ftc.gov/articles/how-recognize-avoid-phishing-scams
- FTC: https://consumer.ftc.gov/articles/what-do-if-you-were-scammed
- CISA: https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business
- CISA: https://www.cisa.gov/stopransomware/ransomware-guide

FTC reporting links are US-specific; the product instructs users elsewhere to use their official local service. Recovery and refunds are not guaranteed. Revisit guidance and detection rules as scams and provider recovery processes change.
