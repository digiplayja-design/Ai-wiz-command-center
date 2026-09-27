# KORLIX Music Studio — usability and saved-library release

## What changed
The previous studio used a long modal form, temporary in-memory jobs/usage, a three-minute polling loop, and Play/Open track actions. Closing the dialog lost the current view and there was no way to list old jobs. Instrumental mode only added prompt text. A returned array could be called complete before its audio finished.

This release replaces that flow with a themed full-page Create / My tracks workspace:
- Song idea, My lyrics and Instrumental modes with the relevant fields visible.
- Six editable starters: reggae, dancehall, a business jingle, focus music, a personal song and a cinematic instrumental.
- Genre shortcuts; optional title, voice preference and target length under Make it yours.
- Saved drafts, protected unsaved edits and stable save retries.
- Durable job acknowledgement before waiting for the provider; accepted jobs continue at the provider while the user leaves the screen.
- Search, favorites, paging, reuse of saved ideas, explicit removal and provider-status recovery.
- Play/pause, seek, lyrics/copy, explicit audio downloads and the existing report action.
- All existing KORLIX color themes, including pure white and dark themes, remain supported.

Open the existing Music Studio button or Tools → Music Studio.

## Generation and usage
MusicAPI.ai remains the music provider. The existing Sonic integration identifier, sonic-v5, is retained; provider-side model mappings can change independently. This release does not promise a different underlying music model or instant finished audio. It makes the application acknowledgement quick and progress recoverable.

Instrumentals use make_instrumental=true. Custom lyrics use custom_mode and prompt; description mode respects the provider's 400-character combined description limit. Lyrics are bounded at 5,000 characters; tags at 1,000; working titles at 100. Target length is optional and bounded to 10–360 seconds, and is described as a target rather than an exact cut.

Only an authenticated user with the existing server-controlled Music Production access can generate. No email supplied in a request header/body is trusted for entitlement or ownership. Existing plan IDs, prices and monthly limits remain:
- music_starter_75_monthly: $25 / 75.
- music_creator_580_monthly: $120 / 580.
- music_studio_4000_monthly: $450 / 4,000.
- music_producer_10000_monthly: $950 / 10,000.
The existing environment-controlled access mechanism remains; this release does not build a new checkout, Apple purchase flow, manual license flow or entitlement grant. Native digital purchases still require the existing supported store entitlement path.

One generation request reserves one creation in the UTC calendar-month allowance. Provider acceptance marks it used. A definite rejected submission releases the reservation; a network timeout or missing acknowledgement remains uncertain and reserved. Provider failures after acceptance retain the existing accepted-request usage treatment. Removing a creation does not restore usage. Reserved and used amounts are visible.

## Reliability
A client request UUID identifies a creation. Database owner locks, payload hashes and persistent quota reservations prevent duplicate provider calls and concurrent overuse. Retrying unchanged input recovers the same request, including after an access/allowance change; edited input requires a new request.

The backend persists a submitting job before responding, then submits to the provider without tying the task to the UI lifetime. Provider submission has a 45-second deadline and is never automatically reissued. Accepted task-ID writes retry briefly; a restart or uncertain acceptance never silently resubmits a paid request. A submission not confirmed after two minutes is shown as uncertain with a support reference. This is honest uncertainty, not a guaranteed exactly-once provider API.

Jobs with saved task IDs survive backend restarts. Opening the studio and refreshing/polling retrieves provider progress. Polling occurs every 20 seconds while the screen is open, with a database 15-second polling guard. The provider continues rendering when the studio is closed; KORLIX is not running a separate continuous polling worker.

HTTP 200 or nonempty track arrays do not imply completion. Each finished track requires state=succeeded and a valid HTTPS audio URL. One ready version can be played while another is still processing; terminal mixed success is Partial. Unexpected statuses and missing final audio remain processing. Unsigned callbacks cannot overwrite results; the unused webhook route returns 410.

At most three submissions/rendering jobs are active per account. The visible library supports 2,000 creations and pages of 30. Removal is explicit and limited to finished/failed creations; uncertain requests require support review.

## Storage and privacy
The single additive migration *_music_studio_library.sql adds:
- korlix_music_jobs: owner-scoped recipe, task/status, track metadata and quota receipt.
- korlix_music_drafts: one versioned saved draft per owner.
- korlix_music_v2: security-invoker service-only RPC.

Both tables have RLS; anon/authenticated table and function grants are revoked. Backend routes authenticate with requireUser and use verified user IDs. All private responses use Cache-Control: no-store. Account changes permanently invalidate the screen client, clear private content/dialogs, stop playback and reject late downloads/responses.

MusicAPI.ai AI-sharing permission is checked in the UI before generation and consent=true is required by the backend. Drafts are saved to KORLIX, not sent to a model until generation. No extra OpenAI generation/credit action is introduced.

KORLIX stores provider-hosted audio links, not permanent private copies of the audio. Download any music that must be retained. Links may expire and media at the provider has its own access/retention behavior. The download endpoint verifies ownership and a completed track, restricts provider CDN hosts and redirects, limits audio to 64 MiB, validates the file signature, and sends a download with nosniff. Unsupported provider hosts can be opened through the explicit Open audio action; no backend unrestricted URL fetch occurs.

Removing a creation clears saved idea/lyrics/settings, task ID and track links. A minimal hashed request/usage receipt remains so removal cannot reset the allowance or replay a paid request. Account deletion cascades to drafts/jobs. Provider copies and previously downloaded/shared files are not deleted by removing a KORLIX library item.

Older jobs from the former in-memory studio cannot be reconstructed after its process has restarted. The new library applies to creations saved by this release. Earlier monthly usage was also process-local; historical missing usage cannot be reconstructed and is not fabricated.

## Tests and deployment
Backend tests execute the real migration in PGlite plus authenticated Express routes. Coverage includes identity-header spoofing, foreign owners, draft versions, concurrent duplicates, quota reservations, definite/uncertain failures, interrupted submissions, immediate acknowledgement, restart recovery, polling, partial results, paging/search/favorites, removal receipts, callback rejection and safe audio downloads.

Flutter tests exercise all three creation modes, consent denial, saved drafts, stable request retries, reopening/polling, library filters, playback/seek, downloads, account changes, private-dialog cleanup, late responses, removal and 320/390/1440 px layouts at 125% text. Actual screen captures are visually inspected, focused analysis must pass, and the release web build must succeed.

Provider calls are fixtures in automated tests. Live validation checks deployed commit/status, health capabilities, unauthenticated route rejection and released web assets/privacy text. A real signed-in owner song generation is the remaining live-provider acceptance check; the assistant does not impersonate an owner or spend their music allowance.

Deploy the migration first, then the tested backend, then the tested frontend. Both existing Render services have automatic deployment disabled. No service plan, billing entitlement, provider key, Bookkeeping record or unrelated feature setting is changed.

## Primary implementation references
Reviewed 2026-09-27:
- https://docs.musicapi.ai/sonic-instructions
- https://docs.musicapi.ai/get-sonic-music
- https://docs.musicapi.ai/doc-9411955
- https://docs.musicapi.ai/faq
- https://supabase.com/docs/guides/database/functions

Current provider docs contain differing historical model/cost statements. This release preserves KORLIX's existing model identifier and retail plans; it does not infer a new billing agreement from those pages.
