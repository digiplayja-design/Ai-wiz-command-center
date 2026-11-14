# COPY Box Apple age-rating draft — November 5, 2026

**Status: source-backed draft only. No Apple questionnaire answer or rating was
changed or saved during this follow-up.** App source was inspected at
`35459c62b07ea8d10dd21b85ddd920eabcb5a623`; the deployed backend source is
`901ca58c95ba7a16abf56e20361f7f021924df3e`. The prior signed iOS and Android
build/source identities remain unchanged.

## Capability and control draft

The meanings below follow Apple's [age-rating definitions][definitions]. These
are draft classifications of the implemented COPY Box features, not submitted
console answers or a compliance determination.

| Topic | Draft answer or qualification | Source evidence |
| --- | --- | --- |
| Messaging and Chat | **No** user-to-user communication. AI text editing is not an in-app conversation between users. | `CopyBoxHome` and `CopyBoxAuthController.rewrite`; [home][home], [auth][auth] |
| Social Media | **No**. No feed, public discovery, likes, comments, or redistribution to an in-app audience. | Native home/card routes and private workspace; [home][home], [app][app] |
| User-Generated Content capability | **No** broad distribution within the intended app experience. Private boxes and the operating-system share sheet do not create an in-app public feed. | `_shareText`, `_shareBackup`, local/account workspace scope; [home][home] |
| Unrestricted Web Access | **No**. Fixed policy/support/deletion links open outside the app; no embedded arbitrary-web browser. | `_openUrl` uses `LaunchMode.externalApplication`; the exact COPY Box markers also suppress backend search/file routing; [home][home], [route][route] |
| Advertising | **No**. No ad placements or advertising SDK in the inspected native UI/dependency inventory. | [Dependencies][deps]; existing saved Google No Ads declaration |
| Parental Controls | **No** parent-management tools. The minor's permission checkbox is a declaration, not a guardian dashboard, parental PIN, content restriction, or usage limit. | `_submit` and signup checkbox; [signup UI][signup-ui] |
| Age Assurance | **Leave unresolved pending the exact control wording; do not claim verified age.** Only a self-declared signup-age gate is evidenced. Do not infer independent assurance from that checkbox. | No Declared Age Range API, ID verification, age estimation, or independent guardian verification in the inspected implementation. Backend records `method: self_declaration`; [signup validator][signup-backend] |
| AI-generated content | **Present: optional generated text.** Actions are Polish, Shorten, Summarize, Professional email, Action items, and Meeting notes. Results are plain text reviewed before applying. | `rewrite`, `_ai`, `CopyBoxAiReview`; [auth][auth], [home][home], [review UI][review] |
| Mature-content filtering | **No COPY Box-specific topic/output filter established.** The special backend policy suppresses tool routing. Reporting is offered after displaying the draft; provider refusal behavior was not tested. | `rewrite` checks validity/size then returns text; review renders the result; [auth][auth], [review UI][review], [route][route] |

The age-rating UGC capability above is separate from Google Data safety's
**Other user-generated content** data type. Its existing draft remains unchanged.
It is also not an exemption from [App Review Guideline 1.2][guidelines], whose
current scope includes AI content creation apps and related safeguards. The
report-output mechanism is evidenced; this source map does not determine full
moderation/reporting compliance or introduce an implementation change.

## Sensitive-content frequencies remain unanswered

Do **not** default the sensitive-content questions to None. Apple's
[age-rating update][ai-frequency] explicitly says to consider AI assistants and
chatbots when assessing sensitive-content frequency. The bundled templates are
ordinary work/business writing, but users may supply arbitrary text for AI
transformation. Source inspection does not establish None, Infrequent, or Frequent
for generated content. No new runtime test or mature-content filtering guarantee
is claimed here. The completed Google IARC capability answers are not a substitute
for Apple's separate frequency questions.

## Existing minimum age and the later override step

Both the native signup flow and production validator reject Under 16 signup and
require a self-declared parent/guardian permission for ages 16–17. This is a
signup gate: guest writing and existing-account sign-in do not pass through it.
The [currently deployed Terms source][live-terms] also states a minimum age of 16
to create an account or use KORLIX, with parent/guardian permission at 16–17.

First answer the questionnaire truthfully and obtain Apple's calculated rating.
Then apply the [higher-rating override guidance][set-rating] so the result does
not fall below the existing **16+** policy, if an override is needed. Do not lower
a higher calculated rating. No calculated rating or override has been saved.

## Continuation limits

Apple verification stopped after the secure SMS-code request returned declined;
no questionnaire was opened or saved in that session. The source-backed controls
can be resumed after successful sign-in, while frequency and Age Assurance wording
remain to be assessed. No new authentication request or retry is scheduled here.
Google Data safety remains 5/6, with UGC unanswered and production OpenAI sharing
association unverified. Existing completed declarations and device-test status
are unchanged. See the [continuation record](../continuation-20261104.md).

[definitions]: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
[set-rating]: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
[ai-frequency]: https://developer.apple.com/news/?id=ks775ehf
[guidelines]: https://developer.apple.com/app-store/review/guidelines/#user-generated-content
[home]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/lib/copybox_home.dart
[app]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/lib/copybox_app.dart
[auth]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/lib/copybox_auth.dart
[signup-ui]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/lib/copybox_auth_screen.dart
[signup-backend]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/901ca58c95ba7a16abf56e20361f7f021924df3e/backend/korlix_signup_eligibility.mjs
[route]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/901ca58c95ba7a16abf56e20361f7f021924df3e/backend/server.js
[review]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/lib/copybox_dialogs.dart
[deps]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/35459c62b07ea8d10dd21b85ddd920eabcb5a623/apps/korlix_copy_box/pubspec.yaml
[live-terms]: https://github.com/digiplayja-design/Ai-wiz-command-center/blob/e38d6b73a37ff812a29da3b64027a35e01979c34/website/terms.html
