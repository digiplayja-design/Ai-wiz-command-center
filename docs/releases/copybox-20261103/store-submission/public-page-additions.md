# Prepared COPY Box additions to public pages

These scoped additions describe implemented behavior. They have been reconciled
with the currently live website source in
[pull request 43](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/43),
at commit `d810888cba620502e799a3022090e1a5f6748d9d`, merged as
`da283a8dfe7b51f68ad7b581b8555f017cac3c54`, but have not been published.
The required authentication/onboarding analytics paragraph below was reviewed in
[pull request 44](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/44),
source `a214334239b07875cef2818541e30a15d2271787`, whose exact parent is da283.
That follow-up adds only one paragraph in `website/privacy-policy.html` and is
merged as **`b95ce8390e03b4a31a43b592e0d3dd980823f292`**, with a tree verified
identical to the reviewed source. PR 44 is closed/merged and no longer Draft.
This exact reviewed website candidate remains **not deployed**. Both proposed
production deployments are now explicitly authorized, and the backend routing
fix is live. Website publication is held for incomplete Render sign-in and the
new OpenAI sharing/disclosure decision. The single secure method-choice request
did not complete; the root agent interrupted prolonged pending input, with no
success result or authenticated dashboard state verified. No website deployment
or service-setting change occurred.

The approved OpenAI account console shows input/output sharing **Enabled for all
projects** and complimentary daily-token enrollment. The production API credential
was not inspected or matched to that account; no setting changed or change was
authorized. This candidate describes inference, account history, and provider
terms without explicit general model-improvement sharing. Reconcile the exact
reviewed source with the user's decision before publication; keep Google UGC
unanswered in the 5/6 draft. See [privacy-evidence.md](privacy-evidence.md).

The proposed four-page port remains stopped because the configured branch has
unrelated Messenger/Receipt Wiz policy regressions and different Flutter inputs;
its build republishes `website/app`. No new port PR or settings change was made.
The prepared HTML below preserves existing provisions and global effective dates,
with a proposed COPY Box coverage date of November 4, 2026. Confirm the actual
publication date and preserve this text as the reviewed candidate until the
sharing/disclosure decision is resolved. Operational deletion fulfilment remains
separate from provider classification.

## Privacy Policy

Add COPY Box to the opening scope sentence and add this feature section:

### KORLIX COPY Box

KORLIX COPY Box is an independently installed writing and reusable-text app
operated by Korlix INC. You can use local writing without an account. Boxes,
titles, folders, color labels, favorites, version history and trash are stored on
your device. Guest and signed-in workspaces are separate. Signing in does not
automatically upload or synchronize your boxes to another device.

You choose when to import, export, copy or share content. A full JSON backup can
include text, version history and trash. Local boxes and exported backups are not
encrypted by COPY Box. Protect exported files and choose their destinations
carefully; copies held by another app or recipient follow that service's rules.

Optional account features use your existing KORLIX account. Sign-in and account
requests send authentication information to KORLIX. New account signup also
records the age range and policy/parent-permission declarations you provide.
COPY Box sends an app-installation identifier, platform and app label for session
and device management. Native sign-in tokens are kept in the platform's secure
storage, separately from your written boxes.

KORLIX records sign-up and sign-in events from COPY Box for analytics. These
records include a hashed app installation identifier, platform, event time and
authentication event, with an error category where relevant and your account
identifier after successful sign-in. We use these records to measure
authentication completion and use of AI features.

AI refinement requires your permission to send the selected box's full text
and your writing instruction to KORLIX and OpenAI. The backend stores the
request and generated result in your account's AI history, together with related
usage information. Keeping the original draft, removing a local box, signing out
or uninstalling COPY Box does not remove this online history. Declining the AI
request leaves local writing available. The shared retention and deletion
provisions in this policy apply to KORLIX-held account and AI records.

If you report an AI result, your chosen reason, optional details and an excerpt
of the output are sent to KORLIX. The report is associated with your verified
account and may include the app-installation identifier, platform, IP address,
user agent and request time. KORLIX stores the report for support and safety
handling and may deliver it to support using its service providers.

COPY Box Settings includes policy links, support and the shared-account deletion
request. A deletion request affects your KORLIX account across apps; it does not
remotely clear every local workspace or exported copy. Contact
support@korlixdeveloper.com about retained account AI history or other
KORLIX-held records you want addressed.

## Terms of Use

Add KORLIX COPY Box to the existing app scope and add:

### KORLIX COPY Box

COPY Box provides local writing, organization, reusable templates, backup/import
and optional AI refinement through the shared KORLIX account service. AI access
depends on an internet connection and the account's current allowances. Review
AI output before applying or using it. Ordinary writing and the AI service have
different storage behavior: boxes are stored on the device, while submitted AI
requests and results are stored in account AI history as explained in the
Privacy Policy. Export records you need before uninstalling the app or changing
devices. Backups are readable text and should be stored and shared carefully.

The existing account, eligibility, content, payment and service provisions apply
where relevant. The initial COPY Box build does not introduce a separate
subscription product or purchase flow.

## Delete Account and Data

Add COPY Box to the shared-account scope and add this path under the in-app
request section:

In KORLIX COPY Box, sign in, open Settings, and select Request KORLIX account
deletion. Review the shared-account confirmation and select Request deletion.
This creates a request for processing; its acknowledgment does not mean deletion
has been completed. The existing email route remains available if you cannot
sign in.

Add this local-data clarification:

COPY Box workspaces and exported backups can remain on your device after an
account request. Remove unwanted boxes, then empty trash to remove them from the
current workspace. Other account workspaces and exported files must be addressed
separately. Local removal does not erase retained account AI history or recall
provider requests. Identify that history when requesting deletion of
KORLIX-held records. Shared-account deletion can affect your access to other
KORLIX apps; manage any recurring subscriptions with their billing provider.

## Support and Reports

Expand the opening support sentence to include KORLIX COPY Box and add:

For COPY Box help, open Settings and select Contact support, or email
support@korlixdeveloper.com with the subject KORLIX COPY Box support. Include the
app version/build shown in Settings, your device and operating-system version,
and steps that reproduce the issue. Remove private text from screenshots and
never send passwords or sign-in codes. To report an AI draft, select Report this
output in its review dialog. If a report's confirmation is uncertain, contact
support before resubmitting it.

## Reconciliation evidence

- App behavior: the source anchors in [privacy-evidence.md](privacy-evidence.md).
- The analytics paragraph follows the exact deployed authentication/onboarding
  source and live database schema/function metadata; no customer event rows
  were accessed. It does not add claims about email/content analytics, guest
  writing telemetry, advertising, tracking, or a guaranteed deletion deadline.
- Public pages consulted during preparation: [Privacy](https://www.korlixdeveloper.com/privacy-policy.html),
  [Terms](https://www.korlixdeveloper.com/terms.html),
  [Deletion](https://www.korlixdeveloper.com/delete-account.html),
  [Support](https://www.korlixdeveloper.com/support.html).
- The existing pages already explain that deletion is a processed request and
  that retained records can differ from local copies. This addition preserves
  that distinction and does not introduce a new deletion deadline.
