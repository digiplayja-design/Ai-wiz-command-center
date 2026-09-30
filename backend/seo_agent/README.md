# KORLIX AI SEO Agent

First release: a measured website sample, an AI improvement plan, and opt-in weekly audits. The Flutter entry is **For business → SEO Agent**. Audits and monitoring require an Ultra or Enterprise account; setup, saved reports, pausing and deletion remain accessible.

## Workflow

1. Save one business profile and a public HTTPS website without query parameters.
2. Explicitly consent to an audit. Three AI credits and one generation are reserved atomically. The queued job survives a backend restart.
3. The worker inspects up to five HTML pages, respecting the site's crawler rules, and prepares suggested topics, prioritized actions, metadata, a content outline and FAQ drafts.
4. Review the evidence and drafts. Copy content to the website editor and mark completed actions. This release never publishes to a website.
5. Optionally enable weekly monitoring. The first scheduled audit is due seven days after activation; each completed audit uses three credits. Pause stops future work and cancels queued weekly audits. An already running audit may finish. Changing the website pauses monitoring.

## Interpretation

The score summarizes checks on a small HTML sample. It is not a search-engine score, rank, traffic forecast, accessibility certification or full-site assessment. JavaScript execution, authenticated pages, external links, backlinks, live search volumes, Google index status and Core Web Vitals are outside this release. Suggested topics are ideas inferred from the measured pages and owner facts. Missing facts in content drafts require owner verification.

Google Search Console, CMS publishing, bulk content publishing and external notifications are not connected by this feature. Existing AI Visibility remains a separate linked tool for sampled AI-search answers.

## Safety and operation

- Public HTTPS/default-port URLs only. DNS answers and redirect targets are checked; TLS connections use a validated pinned address. No cookies, user credentials, scripts or external assets are sent or executed.
- Bounded response sizes, request count, page count and total crawl time. Unavailable or restrictive crawler rules stop affected reads.
- Postgres tables and RPCs are private to the service role, with RLS enabled and explicit owner checks. Browser roles cannot read them directly.
- One active audit per owner; manual idempotency keys; three attempts per hour; a maximum of sixty retained reports; atomic allowance reservation and a single refund for failure or expired work.
- Weekly work is persisted in Postgres. A nonoverlapping server timer discovers due work; database locks and lease tokens coordinate multiple processes. Tier and permission checks run again before work starts.
- A timed-out or expired running job fails and refunds rather than blindly repeating a paid provider call. Queued work can resume after restart. Monitoring pauses when the account loses access or has insufficient allowance.
- Model output is constrained to a schema, validated for lengths and sampled-page URLs, and displayed as plain text. Crawled text and business fields are untrusted data, never instructions to execute.
- No new environment variables. Uses the existing database and OpenAI configuration. Deploy the `seo_agent` migration before starting the new backend.

## Verification

Run `node --test test/seo_agent_*.test.mjs` from `backend`, plus `flutter test --no-pub test/seo_agent_test.dart` from the frontend. Tests cover the crawler boundaries, account separation, lease and refund behavior, explicit monitoring consent, and AI output validation without calling a live model or modifying a customer's site.
