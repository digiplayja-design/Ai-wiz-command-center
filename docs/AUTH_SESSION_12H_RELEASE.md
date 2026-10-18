# KORLIX sign-in persistence and the 12-hour request

## Goal and release status

Ricardo requested a 12-hour session timeout because people are being asked to
sign in too frequently. The intended experience is to stay signed in while using
KORLIX, including after ordinary screen locks, app switching and temporary
connection problems.

**The live Korlix AI project now has a twelve-hour inactivity timeout.** On
October 18, 2026, the owner completed secure dashboard sign-in. The setting was
saved and verified after a full reload of Authentication → Sessions.

| Setting | Before | Verified after saving |
| --- | --- | --- |
| Inactivity timeout | 0 (never) | 12 hours |
| Absolute session time-box | 0 (never) | 0 (never) |
| Access-token expiry | 3,600 seconds | 3,600 seconds |
| Enforce single session | Off | Off |
| Refresh-token compromise detection | On | On |
| Refresh-token reuse interval | 10 seconds | 10 seconds |

The previous policy did not impose the frequent sign-ins: the app's incomplete
access-token refresh handling did. The twelve-hour cap implements the requested
timeout; the app fix is still required to prevent unintended earlier sign-outs.
This server setting is live, while the client changes require a new app release.
No signing secrets, database migration or backend deployment were involved.

Application commit `d6e9251f433a6959fa03be42190b1ad9ca4697ea` passed
[validation run 39145471909](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/39145471909):
56 onboarding/auth, 60 session/transport/Copilot, 24 billing, 16 home navigation,
86 voice/plan and 347 Social/token-store tests (589 total), plus the separate
build-mode layout check. One existing optional visual capture was skipped.
Focused analysis has no errors or warnings; 25 existing style informational
messages remain nonfatal. Both Android debug variants and the unsigned iOS
simulator build passed. This is automated validation, not a twelve-hour device
test or store publication.

## Choose the session control that matches the goal

Supabase distinguishes these controls:

| Control | Twelve-hour behavior |
| --- | --- |
| Session time-box | Requires a new sign-in after twelve hours from session creation, even for an active user. |
| Inactivity timeout | Expires a session that has not refreshed for twelve hours. This is not measured from the last tap, chat message or keyboard action. |
| Access-token expiry | Governs an individual JWT. Keep the ordinary one-hour value and refresh it automatically. |

Supabase checks session limits at refresh, so an existing access token can remain
valid until its own expiry. Limits are available on Pro plans and above. The
documented default session lifetime is unlimited until sign-out or another
termination event. [Supabase session documentation](https://supabase.com/docs/guides/auth/sessions)

**Selected behavior:** twelve-hour inactivity, with no absolute session time-box
and ordinary one-hour access tokens. This avoids forcing an actively refreshing
session to sign in every twelve hours. Inactivity is measured by Supabase from
the last session refresh, not the last touch; normal foreground refresh can keep
an open application active. The owner was informed of this interpretation before
the setting was saved.
In duration fields, twelve hours equals 43,200 seconds and one hour equals 3,600
seconds. Confirm the dashboard's displayed units before saving. If the requirement
is specifically a maximum twelve hours per sign-in, use the time-box instead and
expect active users to sign in again. Do not describe these two policies as the
same behavior.

Do not enable a single-session restriction as part of this change: KORLIX already
has its own plan-based device limits, and Ricardo uses multiple devices.

## What the code review found

The backend's main-account device records have active/revoked status and a
`last_seen_at` timestamp, but no age-based expiry check. `/api/auth/refresh`
delegates token rotation to Supabase and returns the provider's expiry unchanged.
The separate one-hour App Studio portal sessions are unrelated to KORLIX login.

The existing frontend refresh path treated every HTTP error as a lost session,
including temporary service failures. The shared authenticated-header builder
also requested refresh on every invocation. These are concrete sources of
unnecessary refresh traffic and sign-in prompts; changing a server timeout alone
does not correct them.

The new client coordinator refreshes near expiry, on foreground resume and before
protected requests. Concurrent callers share a single refresh. Temporary failures
retain credentials, with bounded retry delay; an expired bearer waits for renewal.
The explicit HTTP factory covers feature clients and multipart uploads without
depending on the Dart zone of a Flutter callback. Safe reads can retry once;
mutation requests are not automatically replayed. Feature-specific authorization
errors, such as an incorrect Vault password, retain their original response.

Token rotation preserves the existing login identity and active Social, Rici and
Copilot state. Logout immediately persists a signed-out marker, including while a
secure-storage write is blocked, and stale refresh results cannot restore an old
account. Foreground refresh timers stop when the app is backgrounded.

The separate Android bubble engine still reads credentials without rotating them.
If its access token expires while the main engine is suspended, opening KORLIX is
required for renewal. This update does not promise twelve hours of bubble-only
operation. Sign-in waits for ordinary device sign-out cleanup; the backend's
existing device-only revocation can still race a new login if that cleanup
outlives the network timeout. Session-specific server revocation is a separate
hardening item.

## Refresh response contract and error handling

The current backend response contains an `error` message but does not forward
Supabase's machine-readable error code. Provider errors use `error.status || 400`;
therefore a retryable provider transport error with status zero can appear as HTTP
400. Status alone must not trigger destructive local credential clearing.

| Evidence | Client treatment |
| --- | --- |
| Explicit invalid/revoked refresh token, expired/missing session, deleted/banned account, or confirmed revoked device | End that session and show the appropriate sign-in or account-access message. |
| Network failure, request timeout, rate limit, refresh conflict, HTTP 408/409/429/5xx | Preserve credentials and retry with bounded backoff; do not fabricate a successful refresh. |
| Unknown HTTP 400/403/422, malformed JSON, or a success response missing token fields | Preserve credentials and show a recoverable service error until invalidation is confirmed. |

When machine codes are available, terminal examples include
`refresh_token_not_found`, `refresh_token_already_used`, `session_expired`,
`session_not_found`, `user_banned` and `user_not_found`. `conflict`,
`request_timeout` and `over_request_rate_limit` are recoverable. Legacy message
matching should be narrow; generic words such as “token”, “session” or
“unauthorized” are insufficient. [Supabase Auth error codes](https://supabase.com/docs/guides/auth/debugging/error-codes)

Verified backend device-denial messages are:

* `This account is disabled. Contact support.`
* `This device is not authorized for this account. Please sign in again.`
* `This device is no longer authorized. Please sign in again.`

Keeping credentials during an outage does not authorize an expired token or
bypass backend account/device checks. Explicit sign-out, account switching,
revocation and disabled-account handling must remain effective immediately in the
client. Never disable refresh-token reuse protection to mask concurrent refreshes.

## Activation and verification

1. Live policy verified: twelve-hour inactivity, no time-box, one-hour JWT expiry,
   single-session restriction off, and refresh reuse detection unchanged.
2. Build the new client using `docs/CODESPACE_SOCIAL_RELEASE.md`; its private port
   8790 download and iPad **Save to Files** workflow remain available.
3. Verify the client candidate with a valid token, near-expiry token, simultaneous
   requests, transient failures, malformed responses, explicit revocation, logout
   during refresh and account switching during refresh.
4. Test signed Android and iOS builds through lock/unlock and app backgrounding,
   then verify policy expiry across the chosen twelve-hour boundary. A successful
   short test does not prove twelve-hour persistence.
5. Report the result separately: client changes tested, live Auth settings saved,
   and signed-device behavior verified. Do not mark the policy active from source
   code or build success alone.

Official session and error-code documentation checked October 18, 2026.
