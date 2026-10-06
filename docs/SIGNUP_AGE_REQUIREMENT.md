# Signup age requirement

Policy version: `2026-10-06`. Minimum account age: 16.

The sign-in and signup screens show the 16+ notice and public Terms of Use and
Privacy Policy links. Web links use the serving origin; installed apps use
`https://www.korlixdeveloper.com`. A failed policy launch leaves the form intact
and displays the address.

New signup has no preselected age or policy agreement. Users select Under 16,
16–17, or 18 or older. Under-16 selections cannot create an account, including
through the password keyboard action. Ages 16–17 also require an unchecked
parent/guardian permission declaration. Changing age or starting a new signup
resets acknowledgments. The ordinary email confirmation flow remains in place.

The frontend sends `signup_eligibility` with `age_band`, `terms_accepted`,
`privacy_acknowledged`, `parent_permission`, and `policy_version` to the existing
`/api/auth/signup` endpoint. The backend independently validates these fields
before calling the account provider. It saves a normalized
`korlix_signup_declaration` in Supabase signup user metadata, with a server
timestamp, policy version, minimum age, and `method: self_declaration`.
Unexpected supplied metadata, dates of birth, and client timestamps are not
copied into that declaration.

This is self-declaration, not identity verification or verified parental consent.
Supabase user metadata is user-editable and is not an immutable legal receipt or
an authorization claim. No role or feature access is granted using this metadata.
This change validates KORLIX's signup endpoint; it does not add a Supabase Auth
before-user-created hook or retrofit age checks to existing accounts. A service-
wide age assurance rollout must cover those paths separately.

Terms, Privacy Policy, Child Safety Standards, AI Safety Policy, and the public
homepage now describe the 16+ minimum. The policy for users aged 16–17 requires
parent/guardian permission. Protections against exploitation and sexualized
minor content still cover everyone under 18. Existing reporting, blocking,
feature-specific AI-sharing permissions, and adult-only BabyBlend references
remain applicable. No verified-guardian system or separate teen advertising /
Social privacy mode is claimed by this update; regional and feature-specific
requirements need their own review.

## Deployment and verification

Frontend: `release/k135z-frontend-20260919`.
Backend: `release/k135z-backend-render-20260919`.

Publish the web frontend first, then deploy backend enforcement. Existing sign-in
does not require new fields. Older installed builds cannot supply the new signup
declaration; the API directs them to update or use the website for new accounts.
Publish a new iOS/Android build to bring this screen to installed apps. App Store
and Google Play age-rating settings are not changed by a web deployment.

Validation: 35 Flutter tests cover signup restrictions, keyboard submission,
guardian permission, policy links, email confirmation, remembered login,
phone/tablet layouts, large text and keyboard layouts. Fifteen backend handler
tests cover invalid/missing declarations without provider calls, eligible teen
and adult requests, normalized metadata, provider failure, and session handling.
The new signup widget analyzes cleanly; the existing main file has unrelated
analyzer warnings and deprecation notices. Visual captures of actual auth screens
are reviewed in dark/light phone layouts and on a tablet.
