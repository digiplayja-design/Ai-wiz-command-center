# Social last-login and Auto Dump policy update — October 8, 2026

This focused update accompanies the Social last-login display and Auto Dump
audience choices. It supersedes the self-only Auto Dump description in the
historical [October 7 review](LEGAL_PRIVACY_REVIEW_2026-10-07.md). It does not
change or re-certify that review's other conclusions.

## Published-document source changes

The authoritative policy sources are the frontend `website/` HTML files. The
Render build publishes that directory directly; no policy generator was found
in the committed scripts or executable sources. These five pages now carry an
October 8, 2026 effective or updated date:

- `website/privacy-policy.html`
- `website/terms.html`
- `website/delete-account.html`
- `website/community-guidelines.html`
- `website/legal.html`

## Behavior described

- Last login comes from the authentication service's latest successful KORLIX
  account sign-in. It is separate from recent Social activity and message-read
  status. The existing presence preference, labeled **Show online status and
  last login**, controls both indicators; authorized Social profile paths,
  discovery rules and blocks still apply. The setting does not delete
  authentication or security records.
- **Only for me** is the default Auto Dump scope and can apply to a sent or
  received message. **For everyone** is available only for the sender's own
  message. Its scope is both direct-chat participants or all participants in
  the relevant group conversation.
- Expiry restricts server-side conversation visibility and new attachment
  access even when the scheduling app is closed. Loaded or offline screens may
  retain a previous copy until refresh.
- Auto Dump does not physically erase stored message or attachment records.
  Existing report snapshots and applicable retention/backup handling remain.
  Screenshots, downloads, exports, already delivered notifications and copies
  shared elsewhere cannot be recalled. Previously issued temporary attachment
  links can remain usable until they expire.
- The pages retain separate account/selected-data deletion request routes and
  do not promise secure destruction or guaranteed confidentiality.

## Validation and release boundary

All five changed HTML pages passed structure, unique-anchor, relative-link,
effective-date and UI-label checks. `git diff --check` passed. Existing
third-party AI disclosure text and markers were preserved.

These checks verify document consistency, not a live deployment. Runtime tests,
migration application, frontend/backend publication and live verification must
be recorded with the feature release. Website edits do not update native app
builds or store privacy metadata automatically.

## Feature verification

Backend commit `0ba550c1` adds the guarded migration and regression coverage;
the existing authenticated API routes already support the new RPC payload.
The backend Social gate passed 137 tests. After adding the shared schedule's
sender index, the 13 focused scope/media tests passed again. The real database
function baselines and existing service-role auth permissions matched the
migration prerequisites.

The Flutter changes passed 52 focused tests covering scope selection,
cancellation, retry identity, server-clock expiry, cached messages/replies,
media, truck animation and timestamp visibility. Changed-file analysis and
patch whitespace checks passed. No dependency version changed. The Render
release gate now includes Auto Dump, truck, presence and attachment-lifetime
tests alongside the existing account/privacy checks.

These are automated checks with synthetic accounts and fixtures, not a
two-member signed-in production device test. Publication and live verification
are recorded separately after the release completes.

Supabase applied this unchanged SQL as migration
`20261008204002_korlix_social_last_login_dump_scope`. The repository migration
filename is aligned to that production history version. Read-only production
assertions verified service-role execution, timestamp/preference matching,
new metadata, RLS and browser-role denial. The security advisor returned no
WARNING or ERROR findings; the service-only table has the expected INFO notice
for RLS with no browser policies.

## Production publication — October 8, 2026

Frontend feature commit `db66bacd0cc26c10271a20ac3f5d5ce59fbc12fc` was published
by Render deployment `dep-db400qeb7d7c739rjsk0`, which reached `live` at
2026-10-08 20:46:25 UTC (4:46:25 PM Eastern). The release gate passed all
220 Flutter tests. The backend branch is at
`97267ccd3469773c05129d3ee4dbf53a80950a83`, including the migration-history
filename alignment; no backend runtime deployment was needed.

Public HTTP checks after publication returned 200 for the canonical `/app/`,
its Flutter bootstrap and `main.dart.js`, and all five policy pages. The live
compiled app contains the new last-login label, both dump audience options,
and shared-schedule handling. Each live policy page contains the October 8
update, last-login disclosure and both audience labels. The backend health
endpoint returned 200 and reported healthy.

The production migration and public release are verified. A signed-in,
two-member production device test has not been performed. Native app builds
and app-store privacy submissions were not part of this web release.
