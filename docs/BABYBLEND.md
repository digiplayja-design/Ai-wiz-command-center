# KORLIX BabyBlend

BabyBlend imagines one fictional, fully clothed child portrait from two consenting adults' photos. It is creative entertainment, not a genetic prediction, parentage assessment or medical tool. KORLIX is the AI creator; NOVA remains exclusive to AI voice.

## User flow

Open BabyBlend from home quick actions or the tools menu. Add a clear photo of one adult for Person 1 and a different adult photo for Person 2. Choose Baby, Toddler or Child and Natural photo, Studio or Artistic. Confirm permission to use both photos, then Create BabyBlend. The existing OpenAI sharing consent is checked before generation. Creation requires Ultra Premium or Enterprise and uses one credit per completed, saved portrait. Failed or refused generations do not charge.

Replacing either reference preserves the other. Upload retries retain their request key while the selection dialog remains open. A lost generation response can be retried with the same key. Reopening BabyBlend finds a running job without dispatching another generation. Source photos cannot be removed while their job is running. Use My portraits to download or remove portraits and manage references. Removing a reference does not remove existing portraits. Downloaded copies remain outside KORLIX's control.

## Architecture and privacy

Authenticated `/api/babyblend` routes enforce ownership on every action. `korlix_babyblend_assets` and `korlix_babyblend_jobs` use RLS with all client grants revoked. The service-only, security-invoker `korlix_babyblend_v1` RPC serializes each account's mutations. The private `korlix-babyblend` bucket has an explicit restrictive policy blocking anon/authenticated access even if another permissive storage policy exists. Preview URLs expire in ten minutes; authenticated downloads recheck ownership and stored byte hashes. No URLs, photos, model prompts or personal information are written to application logs.

References are decoded and normalized to JPEG with a maximum dimension of 2048, plus a small thumbnail. Original uploads and embedded EXIF are not retained. Inputs accept JPG, PNG and WEBP up to 15 MB. Accounts can retain ten references, fifty portraits and 300 MB; space is reserved before rendering. Incomplete uploads remain visible for removal or retry after their three-minute lease. Two uploads and two generations can run per server process; one generation per account and twelve starts/hour are enforced in the database. Interrupted jobs fail after twelve minutes on the next request.

Two normalized references go to OpenAI only after the creation request. `gpt-6-astra` with `xhigh` reasoning checks that each reference contains one clear adult and prepares a constrained creative description. The existing Picture Studio image configuration selects the provider model and highest supported quality, normally `gpt-image-2.5-sunburst`/`max`; existing overrides are respected. Rendering uses both references in one image edit, portrait 1024×1536 PNG. No freeform prompts, genetic scoring or sensitive-trait controls are supplied. Provider refusals and malformed images fail safely with no automatic paid retry.

A generated asset remains unavailable until the database transaction marks it ready, completes its job and increments the existing usage counter once. Replaying a completed request returns the same result. Files use stable private object paths and SHA-256 integrity checks. Failed object deletion is recoverable from the gallery. Account changes immediately clear private screen state and invalidate in-flight client responses; a refreshed token for the same session remains valid.

## Operations

Apply the additive BabyBlend migration before deploying the backend, then deploy the frontend. No new environment variables or services are required. The health endpoint exposes `babyBlend` capability/model settings. For account erasure, remove that account's objects from `korlix-babyblend` before deleting the auth user; foreign keys clean up database rows. Routine per-photo removal uses the authenticated feature route so both objects and the asset record are removed together. Job receipts are retained for charge-once semantics until account erasure.

Rollback the application commits if necessary; keep additive tables and the private bucket to avoid deleting saved user data. Jobs interrupted by a restart become retryable failures rather than automatic duplicate provider calls.

## Verification

Backend tests exercise the real SQL migration in PGlite with authenticated HTTP routes, private storage fixtures, denied foreign access, duplicate requests, failed image storage, refused/invalid provider output, stale jobs, deletion recovery, model request configuration and billing. Flutter tests cover consent, upload and generation retry keys, reference replacement, navigation recovery, private downloads, account changes, and 320/390/1440 px layouts at increased text size. Existing image/closet/FieldProof regressions and the production Flutter web build are release gates.

Provider calls in tests are fixtures. Production health, unauthenticated-route protection, migration policies and released frontend assets are verified after deployment. The owner's first signed-in two-photo generation is the remaining live-provider acceptance check; deployment verification does not impersonate an owner or spend their credits.
