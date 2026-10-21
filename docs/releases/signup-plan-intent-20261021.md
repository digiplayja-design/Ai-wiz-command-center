# Signup plan preference — 21 October 2026

Source base: `92cad91d290d4ac93d273960c1144798f3afd14f` on `release/k135z-backend-render-20260919`.

The new registration screen asks users to choose Ultra, Pro or Basic. The signup handler now validates `signup_plan` and saves `korlix_signup_plan` as user metadata so that the choice can follow email confirmation onto another device. Older clients default to Basic.

This metadata is an editable UI preference. It never grants a tier, credits, trial access, or subscription entitlement. Existing email-confirmation, age/policy checks, device-session registration, Apple/Google verification and billing ownership remain authoritative. There is no schema migration or new secret.

Validation: `node --test backend/test/signup_eligibility.test.mjs` — 20 tests passed; `node --check backend/korlix_signup_eligibility.mjs` passed.

This branch is prepared for release; it does not deploy itself. Deploy the signup handler before distributing the corresponding frontend if cross-device continuation is required. Same-device continuation also has a local preference fallback. The three-day offers themselves must be configured in App Store Connect and Google Play Console; changing signup metadata cannot create a trial.
