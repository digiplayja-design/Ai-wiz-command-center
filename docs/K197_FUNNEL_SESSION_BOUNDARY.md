# K197 — Funnel Studio session boundary

## Problem and result

The app already broadcasts in-memory session changes through `kKorlixAuthRevision`, but Funnel Studio did not subscribe. Its header builder could start using a later account's token while the existing studio and child dialogs still displayed the previous account's draft or campaign. K196 discarded results after client replacement or backend access denial; neither event was guaranteed just by changing the app session.

The main app now creates one FunnelClient for the route and binds it to that existing signal. Sign-out, a different user, a new login session for the same user, or a different token issuer invalidates that client permanently. The studio clears its private state and closes all routes above it, including campaign editors, reports, lead dialogs and nested confirmations. The owner sees **Session changed** and is asked to sign in again and reopen the studio. The old client cannot reactivate when the original account returns.

The client checks the current session and the captured request headers immediately before HTTP dispatch, and checks again before returning a response. JSON requests and multipart uploads share the guard. A session change without a notification is caught at these request boundaries. Late responses cannot return old private content to the new session. A write already dispatched can still complete on the server; it is not recalled or retried automatically. Disposing a client detaches the listener, rejects further requests and drops pending results.

Routine refresh within the same issuer/user/session keeps the client active, uses the refreshed authorization header on new requests and preserves unsaved edits. The client retains only a serialized issuer, subject and session ID as its comparison key, not the bearer token, email or editable user metadata. Missing or malformed session claims stop a bound client before dispatch.

The decoded claims are a UI lifetime key, **not authentication, authorization, signature validation or Enterprise entitlement proof**. The existing backend still verifies the token and ownership/entitlement for each request. No server authorization path is changed. The production entry point supplies the session signal; standalone clients may omit it for existing isolated component uses.

## Documentation basis

The current [Supabase session documentation](https://supabase.com/docs/guides/auth/sessions) identifies `session_id` as the access-token claim identifying a login session. The [JWT guide](https://supabase.com/docs/guides/auth/jwts) describes token renewal and the issuer/subject claims, and distinguishes decoding from signature verification. The changelog index was checked on September 25, 2026; no relevant hosted-session claim change was identified. No SDK dependency, Supabase configuration or API contract changes are needed here.

## Verification

New automated regressions cover refresh with new token material, immediate sign-out, owner/session/issuer changes, permanent invalidation, malformed claims, missing notification, mismatched captured headers, delayed GET/PUT/upload responses, stale network errors, disposed-client cleanup, unsaved draft preservation, publish-confirmation closure, child campaign editor/review/report closure, and opening without a usable session. Synthetic tokens and mocked HTTP handlers are local test fixtures only.

**596 funnel Flutter tests passed, including 20 new session regressions.** The entire existing funnel suite was checked because all its API screens share FunnelClient. Changed-file analysis reported no issues. A JavaScript web release build verifies the main app integration. Exact source trees, build, deployment and HTTP evidence are recorded in the K197 checkpoint.

## Scope and limits

This is a frontend change. The existing K196 backend, database, provider gates and service environment are unchanged; no migration is required. Rollback the frontend to K196 commit `02255ee98fd99f180fbb5ce50a77b63aeab51fda` if necessary.

This does not add cross-tab storage synchronization, remote-session revocation polling, proactive token-expiry enforcement or cancellation of committed server work. An externally changed session that produces neither the app signal nor another funnel request is outside this guard. Backend 401/403 handling remains in place.

Meta setup, real Google/Meta authorization, provider actions and owner hands-on A–G acceptance remain deferred. No production test page, contact, inquiry, campaign, upload, spend or outreach is created. Automated widget tests do not establish physical-device or real-provider acceptance.

Estimated remaining connected-funnel work remains **6–18 working hours**, plus external provider approval delays. The estimate is provisional while provider setup and final owner/device acceptance are deferred.
