# Improve My Picture refresh — October 2, 2026

The existing Improve my picture entry now has colorful photo artwork and opens a theme-aware studio with a soft gradient header, six color-coded treatments, and a guided photo / treatment / instructions flow. Light and dark themes retain their selected palette. Controls adapt to narrow screens and enlarged text.

Color & lighting adds original, vivid, warm, cool, cinematic and black-and-white looks, plus original, bright, soft, golden-hour and studio lighting. The client sends `look` and `lighting` to the existing `/api/image/improve` endpoint. Defaults remain `original`. Suggestions append editable instructions without replacing the user's draft. Preservation stays enabled by default, and finish/output shape remain available in an expandable panel.

Each successful edit keeps its source image and options. Users can select an earlier version, save it, compare its actual source with the result, view the original, or refine it. Refining no longer deletes the earlier result. History retains up to six versions and prunes older versions toward a 64 MB unique-buffer budget; the original and newest edit remain available even when their combined size exceeds the budget. Versions are held only in this open workspace and are cleared when changing photos or leaving. Save desired PNGs before leaving.

The studio is tied to the JWT issuer, account and login-session ID. Normal token refresh keeps the workspace open. Logout, account changes, or a new login invalidate the workspace, unmount private photo state and discard late edit responses. Opening the studio stops microphone/character speech and prevents duplicate routes. Invalid sessions open a clear sign-in message. The client handles non-JSON authentication failures and interrupted connections, and checks the complete PNG signature. The backend additionally fully decodes PNG pixels before success/history/credit updates.

## Validation

- 81 focused frontend and regression tests passed across studio controls, client errors, session ownership, shared themes, Virtual Closet, home input and action buttons.
- The visual test was rerun after adding explicit expanded-color and side-by-side checks. Phone (390 px) and desktop (1440 px) fixtures were rendered and inspected in signature blue, white and pink themes. UI tests also cover 2× text at 390 and 1200 px.
- All changed picture-studio Dart files and tests pass analysis. Existing main.dart analysis warnings remain; no new errors were found.
- Corresponding backend release passed 17 picture and 12 chat-quality tests. Models, access tiers, credit prices and provider timeouts are unchanged.

Tests use local synthetic images and injected providers. They establish workflow and validation behavior, not subjective photo quality or a live provider generation. Actual camera capture and saving should also be checked on the user's target device. A live signed-in photo edit remains the final quality check; no real user photo or paid generation was used for this release.
