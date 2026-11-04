# COPY Box data-handling evidence

This evidence map records the source-backed inventory, initial published Apple
answers, and subsequent corrections/drafts. It does not establish that the
current declarations are complete or that operational deletion has been tested.
It describes the independent COPY Box client, rather than every feature in the
KORLIX AI hub. Optional online features still collect data and must be considered
when completing the app's privacy forms.

## Source anchors

Paths below are relative to the repository root. Function names identify the
relevant behavior without depending on changing line numbers.

| Anchor | Evidence |
| --- | --- |
| `apps/korlix_copy_box/lib/copybox_store.dart` | `CopyBoxStore`, snapshot encoding/decoding, local persistence and backup data |
| `apps/korlix_copy_box/lib/copybox_auth.dart` | `authenticate`, `_ensureDevice`, `deviceHeaders`, `headers`, `rewrite`, `reportOutput`, `requestAccountDeletion` |
| `apps/korlix_copy_box/lib/copybox_auth_screen.dart` | Signup age bands, policy acknowledgment and parent/guardian declaration |
| `apps/korlix_copy_box/lib/copybox_home.dart` | First-use AI disclosure, separate account workspace, backup/sharing, Settings and account-deletion confirmation |
| `packages/korlix_auth_core/lib/auth/korlix_token_store.dart` | Native credentials in platform secure storage, with COPY Box namespace supplied by the client |
| `packages/korlix_auth_core/lib/privacy/korlix_third_party_ai_consent.dart` | Provider/category consent stored by account on this device |
| `apps/korlix_copy_box/pubspec.yaml` and `pubspec.lock` | Shipping dependency inventory; no advertising or analytics SDK declared by this client. Shared authentication routes also collect the first-party analytics described below. |
| Backend `server.js` at `92cad91d290d4ac93d273960c1144798f3afd14f` | `device_sessions`, `saveGenerationHistory`, account deletion request route and report persistence/delivery |
| Backend `korlix_signup_eligibility.mjs` at the same snapshot | Signup declaration saved in account user metadata |
| Backend `security/report_submission.mjs` at the same snapshot | Server adds verified identity and request metadata to a support report |
| `backend/server.js` at deployed `bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb` | `createOnboardingMeasurement`; `/api/auth/signup` and `/api/auth/signin` call `observeAuth('signup'/'signin')` |
| `backend/onboarding/measurement.mjs` at that deployed commit | `installationContext`, `record`, `observeAuth`, `write`, and `summary` for authentication/onboarding analytics |
| Live database schema/function metadata, read-only inspection | `public.korlix_onboarding_events` columns and the `korlix_onboarding_summary` definition; no event rows or mutating RPC invoked |

The backend snapshot was inspected under
`origin/release/k135z-backend-render-20260919`. Confirm its relationship to the
deployed API before finalizing any declaration. The final app source for this
handoff is `d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`. No customer records or
production secrets were needed for this inventory.

### Deployed-source verification on November 4, 2026

Render identified primary API service `srv-d8csvkkp3tds73emfikg` and live deploy
`dep-dbksjk49v7es73f8krpg` at commit
`bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb`. A separate read-only inspection of
that exact deployed source confirmed the material COPY Box data flows:

- `backend/server.js` uses OpenAI for `/api/generate` and calls
  `saveGenerationHistory` after an authenticated text result. The saved record
  includes account ID, character ID, prompt, response, language, result type,
  search indicator and credits used.
- `backend/chat_memory/memory.mjs` applies the COPY Box memory flags to long-term
  memory, independently of generation-history persistence.
- The authenticated report route, `backend/security/report_submission.mjs` and
  `backend/security/ai_report_persistence.mjs` attach verified identity/request
  metadata and persist the report before acknowledgment and optional Resend
  delivery.
- `korlix_request_account_deletion` in
  `supabase/migrations/20261007113219_support_intake_and_default_privileges.sql`
  creates or returns a request with `status = 'requested'`; that function does
  not erase account data.

That source inspection established the implemented flows without establishing
successful live-account testing or completed operational deletion. The later
metadata checks below verify the onboarding structures, and the provider audit
resolves standard service-provider roles. No customer event rows or secret
values were needed for this data-handling inventory.

### Later authentication/onboarding analytics verification

The exact deployed
[authentication routes](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb/backend/server.js)
and [measurement module](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb/backend/onboarding/measurement.mjs)
establish analytics collection during COPY Box sign-up and sign-in. The current
client's `_ensureDevice`, `deviceHeaders`, and `headers` persist and send a
`korlix_copybox_` installation identifier and platform; that identifier satisfies
the measurement module's accepted `korlix_` prefix. `installationContext` hashes
it with SHA-256. `observeAuth`, `record`, and `write` record authentication
attempts, rejection/error categories, accepted sign-up and successful sign-in.
Records include a hashed installation identifier, platform, event time and
event name, with account ID after successful sign-in.

A separate metadata-only inspection confirmed that
`public.korlix_onboarding_events` exists with `recorded_at`, `installation_hash`,
`platform`, `source`, `event_name`, `user_id`, `new_setup`, and `error_code`
columns. The inspected `korlix_onboarding_summary` definition joins successful
authentication IDs with generation-history existence to report authentication,
onboarding and use of AI features. No onboarding event/customer rows or mutating
RPC were read or invoked for this inspection.

This supports **Analytics** as an additional purpose for Apple **User ID,
Device ID, and Product Interaction**, and Google **User IDs, Device or other IDs,
and App interactions**. It does not extend that purpose to account email, age
band, prompt/report text, or guest writing/app-open telemetry. The inspected
flow does not introduce an advertising or tracking purpose; the existing
no-tracking conclusion remains in place.

The inspected pruning definition targets events older than 90 days, with
opportunistic cleanup triggered by writes at most hourly and bounded batches.
This is a source-level cleanup mechanism, not a guaranteed 90-day deletion
deadline or proof of completed operational erasure.

## Data flow inventory

| Feature | Data and destination | Persistence or limit | User control |
| --- | --- | --- | --- |
| Local writing | Box title, body, folder, color, favorite flag, order, versions and trash remain in app-local preferences. | Current workspace; up to 20 retained replacement versions per box. COPY Box does not encrypt local text. | No sign-in required; edit, trash, restore, permanently empty trash, export. |
| Local search/appearance | Search is evaluated locally; appearance and AI-consent choices are device preferences. | Appearance/consent settings persist locally. | User changes appearance and chooses whether to request AI. |
| Import/export/share | User-selected JSON or text files are read locally. Exports and system sharing include the content the user chooses; a full backup includes history and trash. | Exported files are readable text and can outlive the app. Destination providers have their own storage behavior. | File picker, preview and confirmation; explicit export/share actions. There is no automatic box synchronization. |
| Account creation/sign-in/reset | Email and password are sent to the KORLIX API; authentication uses the shared account service. Signup also sends age band, policy acknowledgments, parent-permission declaration and policy version. | Account records persist; signup declarations are saved as user metadata. Native access/refresh tokens use platform secure storage. | Account is optional for local writing. Existing KORLIX users use the same credentials. |
| Installation/session management | A random persistent installation ID, app label and platform are sent in requests. Authenticated requests carry the account token. | Backend `device_sessions` associates the installation with user ID, active status and last-seen time. The ID is not an advertising ID. | Sent when using online account features; signing out clears local credentials and requests device-session revocation. |
| Authentication/onboarding analytics | Sign-up/sign-in event names, hashed installation ID, platform, event time, applicable error category, and account ID after successful sign-in go to KORLIX. | Stored in `korlix_onboarding_events`; summary logic measures authentication completion and use of AI features. Opportunistic pruning does not establish a fixed erasure deadline. | Occurs with online authentication events; local writing remains available without an account. |
| AI refinement | The selected box's full text, writing action and system instruction go to the KORLIX API and OpenAI. | The backend saves account ID, prompt, generated response, language, result type, search indicator and credits used in `generation_history`. This is not transient-only processing. | Explicit provider/content consent precedes the request. Keeping the original or deleting a local box does not remove account AI history. |
| AI output report | Reason, optional details and an output excerpt go to KORLIX. The server adds account ID/email, installation ID, platform, IP address, user agent and timestamps. | Persisted support report; the backend can notify support through Resend as a service provider. Operational retention and deletion fulfilment remain separate from provider classification. | In-app report form explains the content submission; sending requires an explicit action. |
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
| Account identity | Identifiers → User ID; linked to user | Personal info → User IDs | Account access, allowances, requests, and authentication/onboarding analytics |
| Persistent installation identifier | Identifiers → Device ID; linked after authentication | Device or other IDs | Session/device management, security, and authentication/onboarding analytics using a hashed identifier |
| Self-declared age band and signup declarations | Other Data → Other Data Types; linked to user, subject to current console categories | Personal info → Other info | Eligibility, account management and compliance |
| Submitted AI text/instruction and retained result | User Content → Other User Content; linked to user | App activity → Other user-generated content | Requested writing functionality and account history |
| Report reason/details/output excerpt | User Content → Customer Support; linked to user | App activity → Other user-generated content | Support, safety and abuse handling |
| Recorded AI usage, session last-seen, and authentication/onboarding events | Usage Data → Product Interaction; linked to user | App activity → App interactions | Allowance enforcement, session operation, and authentication/onboarding/AI-use analytics |
| Support-report IP and user agent; operational request logs | Include in the relevant identifier/other-data or diagnostic category after confirming their actual use | Classify retained identifiers/technical data according to actual purpose and live logging | Security/support; verify whether diagnostics or location inference occurs before selecting those additional labels |

For Apple, retain **App Functionality** for authentication, editing assistance,
session security and customer support, and add **Analytics** to the three
identified categories above. For Google, apply **Analytics** to the matching
three types alongside **App functionality**, **Account management**, or **Fraud
prevention, security, and compliance** only where the actual use supports that
purpose. The Google per-type usage answers have not yet been entered. Do not
extend advertising, analytics or personalization purposes to unrelated data
types merely because another KORLIX feature uses them.

The online features are optional relative to local writing. This can support
Google's optional-collection answers for the relevant data types, while their
requirements within an account feature should remain clear. Apple's optional
disclosure exception is a separate test; recurring AI requests after a remembered
consent should be disclosed. Generic text fields do not require asserting that
the app specifically collects every sensitive category a user could type.

See the official [Apple privacy guidance](https://developer.apple.com/app-store/app-privacy-details/)
and [Google Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
for the category definitions and distinction between optional use and disclosure.

## Apple publication and completed Analytics correction — November 4, 2026

App Store Connect app `6830765098` initially published details for seven data types:
Email Address, Customer Support, Other User Content, User ID, Device ID,
Product Interaction, and Other Data Types. That initial version had every data type configured for
**App Functionality**, **linked to the user: Yes**, and **used for tracking: No**.
The exact deployed-source review at
`bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb` supports the no-tracking conclusion
for the COPY Box data flows. The earlier generic request to verify tracking
practices is resolved for this release scope; it is not a remaining gate.
This does not change the separate retention/deletion checks or the precise UGC
sharing setting below, and does not support a blanket “no data collected” answer.

The privacy policy URL is saved. The user explicitly approved the final
publication attestation, which covers response accuracy, compliance, and prompt
updates. The final Publish confirmation was then accepted. App Store Connect
explicitly displayed **Published by Ricardo Bailey** for that initial publication.
Those initial classifications are retained as historical evidence and have now
been superseded by the approved Analytics correction below. The separately approved Paid Apps Agreement
was accepted after secure second-factor verification, and Business Agreements
shows **Active** for **November 4, 2026–June 22, 2027**.

After explicit user approval, the source-supported correction was **published**
for **User ID, Device ID, and Product Interaction**, each using **App Functionality
plus Analytics**, linked to the user and not used for tracking. The remaining
four types—Email Address, Customer Support, Other User Content, and Other Data
Types—retain App Functionality. Fresh published-page readback confirms
**Published by Ricardo Bailey**, exactly **three Analytics rows**, all **seven
types linked**, and no Data Not Linked or tracking preview sections.

The first User ID publication exposed a mixed linkage default for the new
purpose. It was reopened, explicitly set to linked-to-user Yes, republished,
and verified. Device ID and Product Interaction had linkage applied explicitly
to the added purpose before publication. This intermediate issue is resolved;
the current per-type map in [release-status.json](../release-status.json)
records the corrected declaration, while its initial snapshot preserves the
earlier uniform-purpose publication.

The Apple age questionnaire was inspected and cancelled without saving. Built-in app
capability evidence does not establish the frequency of generated AI content:
the deployed general `/api/generate` route has no COPY Box topic/output filter.
Live-account evaluation is still needed for those content-frequency answers.
The user explicitly confirmed the necessary third-party content rights. **Yes**
was selected, Done and main Save completed, and the page confirmed the saved
necessary-rights answer. The earlier unselected modal is historical; no further
content-rights input is outstanding in this checkpoint.

## Google Data safety draft and completed IARC rating — later November 4 update

The latest Data safety draft is saved at **Step 4**, with **Email address, User
IDs, Other info, App interactions, Other user-generated content, and Device or
other IDs** selected. **Encryption in transit: Yes** and **data-only deletion
requests: Yes** are saved, with
`https://www.korlixdeveloper.com/delete-account.html` used for both the account
deletion and data-only request URLs. The combined collection/sharing answer
remains Yes and account creation remains Username and password.

The latest outer Save draft confirmed **Your changes have been saved**, with
**5 of 6 usage rows complete**: Personal info 3/3, App interactions Completed,
and Device or other IDs 1/1. Each saved row is **Collected Yes**, **Shared No**
under the service-provider exception, **non-ephemeral**, and **optional** relative
to guest writing. Their saved purposes are:

| Saved data type | Saved collection purposes |
| --- | --- |
| Email address | App functionality; Account management; Fraud prevention, security, and compliance |
| User IDs | App functionality; Account management; Fraud prevention, security, and compliance; Analytics |
| Other info | App functionality; Account management; Fraud prevention, security, and compliance |
| App interactions | App functionality; Analytics; Fraud prevention, security, and compliance |
| Device or other IDs | App functionality; Account management; Fraud prevention, security, and compliance; Analytics |

**Other user-generated content remains Not started** with no usage answers
entered. Next is disabled and preview has not been reached. Its precise
remaining sharing fact is the OpenAI API inputs/outputs model-improvement opt-in
described below. The earlier 0-of-6 snapshot is retained as history. No final
Data safety declaration or publication is complete. The data-only deletion
answer describes an available request route; it does not establish completed
deletion fulfilment.

Government apps was answered **No**, saved, and confirmed on a fresh page.
Target audience is blocked by incomplete Google Sign in details. After explicit
user approval, the IARC agreement was accepted with the public support contact
and **All Other App Types**. All **27 source-backed capability questions** were
reviewed and questionnaire Save succeeded; no frequency questions were presented.
Fresh results show **Completed**, with console display **Submitted Nov 4, 2026,
3:17 PM**; no timezone is inferred. Certificate ID is `-`.

The results are ClassInd 14+ (Brazil), ESRB Teen (North America), PEGI Parental
Guidance (Europe), USK 12+ (Germany), IARC 12+ (rest of world), and 12+ for Russia
and South Korea. The exact answers are retained in
[release-status.json](../release-status.json). This completed the rating
questionnaire, not app review or release. Apple content-frequency questions
remain a separate incomplete form.

## Provider-role audit and the remaining UGC sharing setting

The audit applies Google's service-provider exception to ordinary Supabase,
Render, Resend, and default OpenAI API processing, based on the implemented flows
and their standard processing terms. Explicit OS share/export actions fit the
user-initiated-transfer exception. These exceptions classify the transfers for
Google's Sharing answer; collected data still requires disclosure. See
[Google Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en),
the [Supabase DPA](https://supabase.com/legal/customer-resources/data-processing-addendum),
[Render DPA](https://render.com/dpa), and
[Resend DPA](https://resend.com/legal/dpa) / [GDPR account coverage](https://resend.com/security/gdpr).

The [OpenAI DPA](https://openai.com/policies/data-processing-addendum/) and
[Services Agreement, section 4.2](https://openai.com/policies/services-agreement/)
support the ordinary API processor role. The API
[inputs/outputs sharing controls](https://help.openai.com/en/articles/10306912-sharing-feedback-evaluation-and-fine-tuning-data-and-api-inputs-and-outputs-with-openai)
document model-improvement opt-in as disabled by default. The active API
organization/project setting has not been observed, so the default alone cannot
settle the untouched UGC row's Sharing answer. That specific opt-in is the
remaining provider-sharing fact; the audit introduces no new DPA-signing or
zero-data-retention proof gate.

The inspected native client does not send tier, profile, or persona fields. The
server independently adds existing coarse tier/persona/language context to the
OpenAI prompt payload. It does not forward structured account identity, email,
device, age, policy-declaration or onboarding-event fields in that payload. The
Other info conclusion is limited to native age/policy/parent declarations, not
a claim that the API receives only raw text. On that basis the five supported
identity/declaration/interaction rows can use Collected Yes and Shared No;
all six selected types are non-ephemeral and optional relative to guest writing.
UGC's usage row remains wholly unanswered pending the exact opt-in setting.

## Remaining privacy facts and operational limits

- **UGC sharing:** Confirm only the active OpenAI API inputs/outputs
  model-improvement opt-in before completing this sharing classification.
  Standard provider and user-initiated-transfer roles are resolved above;
  relevant partner collection remains included in the inventory.
- **Encryption in transit:** The saved Google draft answers Yes for the defined
  device-to-server transfer. The inspected release client uses HTTPS for its
  account/API requests, and the verified signed Android bundle disables cleartext
  traffic. That source and artifact evidence supports this answer. The specific
  UGC opt-in and operational deletion remain separate questions; local writing
  and exported backups remain unencrypted by COPY Box.
- **Retention and deletion:** Verify actual history/report/session retention and
  deletion fulfilment with the operational service. Do not promise immediate
  erasure or a fixed time period that has not been established. Deleting boxes,
  uninstalling, signing out and requesting shared-account deletion have different
  effects.
- **Additional logs:** Support reports demonstrably include IP/user agent.
  Confirm any other server/hosting logs, retention, diagnostics and geolocation
  processing. No native location permission does not prove that IP-derived
  location is never processed.
- **Review access and age rating:** Scoped read-only checks confirmed the enabled
  reviewer account, verified email, effective Ultra entitlement and available
  AI/device capacity. Apple now shows saved, populated credential fields without
  the password value being read or captured. Actual COPY Box login/AI testing
  remains outstanding. The inspected backend counts active
  installation IDs across the shared account; ordinary Basic/Pro defaults allow
  one, Ultra/Enterprise two, with existing override/unlimited exceptions. COPY
  Box has its own installation ID, so an account already at its limit can reject
  a new sign-in. Complete the intended review-device acceptance and content/age
  questions against actual behavior; signup
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
account deletion and correct Settings path are explicit. The original four-page
base is merged as `da283a8dfe7b51f68ad7b581b8555f017cac3c54` but remains undeployed.
The required analytics paragraph was reviewed in
[PR 44](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/44), source
`a214334239b07875cef2818541e30a15d2271787`, with exact parent da283. It changes
only `website/privacy-policy.html` and is now merged as
**`b95ce8390e03b4a31a43b592e0d3dd980823f292`**, with a tree matching the reviewed
source. PR 44 is closed/merged, no longer Draft. This is the exact complete
website publication target; it is **not deployed**. No website deployment,
new browser-authentication attempt, or configuration change occurred. A separate
backend trigger for reviewed routing fix `901ca58c95ba7a16abf56e20361f7f021924df3e`
was attempted and rejected by automatic approval review; no deployment was
created. Read-only verification confirms both live commits unchanged. The
configured website branch was not altered or deployed because its unrelated
policy/Flutter inputs would affect published output. The wording introduces no
fixed deletion deadline.
