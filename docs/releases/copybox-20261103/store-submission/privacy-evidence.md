# COPY Box data-handling evidence

This is a prepared evidence map for the store declarations, not a submitted
declaration or a claim that operational retention and deletion have been tested.
It describes the independent COPY Box client, rather than every feature in the
KORLIX AI hub. Optional online features still collect data and must be considered
when completing the app's privacy forms.

## Source anchors

Paths below are relative to the repository root. Function names identify the
relevant behavior without depending on changing line numbers.

| Anchor | Evidence |
| --- | --- |
| `apps/korlix_copy_box/lib/copybox_store.dart` | `CopyBoxStore`, snapshot encoding/decoding, local persistence and backup data |
| `apps/korlix_copy_box/lib/copybox_auth.dart` | `authenticate`, `_ensureDevice`, `deviceHeaders`, `rewrite`, `reportOutput`, `requestAccountDeletion` |
| `apps/korlix_copy_box/lib/copybox_auth_screen.dart` | Signup age bands, policy acknowledgment and parent/guardian declaration |
| `apps/korlix_copy_box/lib/copybox_home.dart` | First-use AI disclosure, separate account workspace, backup/sharing, Settings and account-deletion confirmation |
| `packages/korlix_auth_core/lib/auth/korlix_token_store.dart` | Native credentials in platform secure storage, with COPY Box namespace supplied by the client |
| `packages/korlix_auth_core/lib/privacy/korlix_third_party_ai_consent.dart` | Provider/category consent stored by account on this device |
| `apps/korlix_copy_box/pubspec.yaml` and `pubspec.lock` | Shipping dependency inventory; no advertising or analytics SDK declared by this client |
| Backend `server.js` at `92cad91d290d4ac93d273960c1144798f3afd14f` | `device_sessions`, `saveGenerationHistory`, account deletion request route and report persistence/delivery |
| Backend `korlix_signup_eligibility.mjs` at the same snapshot | Signup declaration saved in account user metadata |
| Backend `security/report_submission.mjs` at the same snapshot | Server adds verified identity and request metadata to a support report |

The backend snapshot was inspected under
`origin/release/k135z-backend-render-20260919`. Confirm its relationship to the
deployed API before finalizing any declaration. The final app source for this
handoff is `d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`. No customer records or
production secrets were needed for this inventory.

## Data flow inventory

| Feature | Data and destination | Persistence or limit | User control |
| --- | --- | --- | --- |
| Local writing | Box title, body, folder, color, favorite flag, order, versions and trash remain in app-local preferences. | Current workspace; up to 20 retained replacement versions per box. COPY Box does not encrypt local text. | No sign-in required; edit, trash, restore, permanently empty trash, export. |
| Local search/appearance | Search is evaluated locally; appearance and AI-consent choices are device preferences. | Appearance/consent settings persist locally. | User changes appearance and chooses whether to request AI. |
| Import/export/share | User-selected JSON or text files are read locally. Exports and system sharing include the content the user chooses; a full backup includes history and trash. | Exported files are readable text and can outlive the app. Destination providers have their own storage behavior. | File picker, preview and confirmation; explicit export/share actions. There is no automatic box synchronization. |
| Account creation/sign-in/reset | Email and password are sent to the KORLIX API; authentication uses the shared account service. Signup also sends age band, policy acknowledgments, parent-permission declaration and policy version. | Account records persist; signup declarations are saved as user metadata. Native access/refresh tokens use platform secure storage. | Account is optional for local writing. Existing KORLIX users use the same credentials. |
| Installation/session management | A random persistent installation ID, app label and platform are sent in requests. Authenticated requests carry the account token. | Backend `device_sessions` associates the installation with user ID, active status and last-seen time. The ID is not an advertising ID. | Sent when using online account features; signing out clears local credentials and requests device-session revocation. |
| AI refinement | The selected box's full text, writing action and system instruction go to the KORLIX API and OpenAI. | The backend saves account ID, prompt, generated response, language, result type, search indicator and credits used in `generation_history`. This is not transient-only processing. | Explicit provider/content consent precedes the request. Keeping the original or deleting a local box does not remove account AI history. |
| AI output report | Reason, optional details and an output excerpt go to KORLIX. The server adds account ID/email, installation ID, platform, IP address, user agent and timestamps. | Persisted support report; the backend can notify support through Resend. Exact retention and provider configuration require operational confirmation. | In-app report form explains the content submission; sending requires an explicit action. |
| Account deletion request | Authenticated account identity and the request reason go to KORLIX. | A request row is inserted for processing. Source proves initiation, not completion of erasure. | Settings confirmation explains the shared account scope and remaining local copies. Public email route also exists. |

The AI request sets `mainChatMemory: false` and `disableAccountMemory: true`.
Those flags do not bypass generation-history storage and must not be described
as a no-retention setting.

## Proposed store data-type mapping

These mappings follow the observed client/backend behavior. Confirm the exact
labels shown in each console and any additional collection by the live service.
The inventory does not support selecting a blanket “no data collected” answer.

| Observed data | Apple proposed label | Google Play proposed label | Purpose supported by source |
| --- | --- | --- | --- |
| Account email | Contact Info → Email Address; linked to user | Personal info → Email address | Account management, authentication and support |
| Account identity | Identifiers → User ID; linked to user | Personal info → User IDs | Account access, allowances, account requests |
| Persistent installation identifier | Identifiers → Device ID; linked after authentication | Device or other IDs | Session/device management and security |
| Self-declared age band and signup declarations | Other Data → Other Data Types; linked to user, subject to current console categories | Personal info → Other info | Eligibility, account management and compliance |
| Submitted AI text/instruction and retained result | User Content → Other User Content; linked to user | App activity → Other user-generated content | Requested writing functionality and account history |
| Report reason/details/output excerpt | User Content → Customer Support; linked to user | App activity → Other user-generated content | Support, safety and abuse handling |
| Recorded AI usage and session last-seen events | Usage Data → Product Interaction or Other Usage Data; linked to user | App activity → App interactions or Other actions | Allowance enforcement and session operation; select the exact matching category in the live form |
| Support-report IP and user agent; operational request logs | Include in the relevant identifier/other-data or diagnostic category after confirming their actual use | Classify retained identifiers/technical data according to actual purpose and live logging | Security/support; verify whether diagnostics or location inference occurs before selecting those additional labels |

For Apple, the supported purpose is **App Functionality** for authentication,
editing assistance, session security and customer support. For Google, use
**App functionality**, **Account management**, and **Fraud prevention, security,
and compliance** only where that row's actual use supports them. Do not add
advertising, analytics, or personalization purposes merely because another
KORLIX product uses them.

The online features are optional relative to local writing. This can support
Google's optional-collection answers for the relevant data types, while their
requirements within an account feature should remain clear. Apple's optional
disclosure exception is a separate test; recurring AI requests after a remembered
consent should be disclosed. Generic text fields do not require asserting that
the app specifically collects every sensitive category a user could type.

See the official [Apple privacy guidance](https://developer.apple.com/app-store/app-privacy-details/)
and [Google Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
for the category definitions and distinction between optional use and disclosure.

## Answers that require operational confirmation

- **Processor transfers and sharing:** KORLIX sends selected text to OpenAI and
  support reports may pass through Resend and hosting/database services. Verify
  current contracts and configuration before using Google's service-provider
  or user-directed-transfer exclusions. Apple still requires relevant partner
  collection to be considered. “No sharing” must not mean “no outbound transfer.”
- **Tracking:** No tracking SDK or advertising-ID access is present in the COPY
  Box client, and its iOS manifest declares no tracking. Verify backend/partner
  practices before the final no-tracking attestation.
- **Encryption in transit:** The default API and policy endpoints use HTTPS.
  Verify production transport and every applicable provider path before
  affirming that all collected data is encrypted in transit. This is separate
  from the explicit statement that local writing and backups are unencrypted by
  COPY Box.
- **Retention and deletion:** Verify actual history/report/session retention and
  deletion fulfilment with the operational service. Do not promise immediate
  erasure or a fixed time period that has not been established. Deleting boxes,
  uninstalling, signing out and requesting shared-account deletion have different
  effects.
- **Additional logs:** Support reports demonstrably include IP/user agent.
  Confirm any other server/hosting logs, retention, diagnostics and geolocation
  processing. No native location permission does not prove that IP-derived
  location is never processed.
- **Review access and age rating:** Confirm the supplied test login works and has
  AI allowance and available device capacity. The inspected backend counts active
  installation IDs across the shared account; ordinary Basic/Pro defaults allow
  one, Ultra/Enterprise two, with existing override/unlimited exceptions. COPY
  Box has its own installation ID, so an account already at its limit can reject
  a new sign-in. Verify the dedicated review account's capacity for the intended
  review devices. Complete content/age questions against actual behavior; signup
  eligibility alone does not supply a store rating.

## Public-page reconciliation

The public pages below were retrieved successfully during the November 3, 2026
preparation:

- [Privacy](https://www.korlixdeveloper.com/privacy-policy.html)
- [Terms](https://www.korlixdeveloper.com/terms.html)
- [Deletion](https://www.korlixdeveloper.com/delete-account.html)
- [Support](https://www.korlixdeveloper.com/support.html)

Those versions principally named KORLIX AI and Messenger and described broad
platform features. [public-page-additions.md](public-page-additions.md) supplies scoped
COPY Box wording so the local-only workspace, AI history retention, shared
account deletion and correct Settings path are explicit. The draft does not
replace the existing retention policy or assert that any public page was changed.
