# KORLIX Social

Native Flutter entry: **For personal use → KORLIX Social**. This release adds opt-in member profiles, approval-based connections, private text conversations, and category forums. It uses the existing KORLIX account, backend, and Supabase project; there are no new paid services or AI calls.

## Permissions and behavior

- `requireUser` verifies the access token with Supabase Auth. Anonymous and unconfirmed accounts cannot use Social. Actor identity always comes from that verified user, never a body or query parameter.
- All Social tables have RLS and explicitly deny browser roles. The security-invoker RPC and helpers are executable only by `service_role`. Deploy the migration before the backend.
- Auth user IDs/emails are not returned in member cards. Social uses separate random profile IDs. Joining requires community-rule agreement. Discovery defaults on during explicit signup; online visibility defaults off.
- Online means activity within Social in the last 90 seconds. The UI heartbeats every 30 seconds while foregrounded, refreshes directory/connections every 15 seconds, and polls the open conversation every 4 seconds. This is bounded polling, not WebSocket presence or push notifications.
- A recipient must accept a pending follow before either party can message. Pair locks serialize connection changes, blocks, reads and sends. Blocking removes the connection; unblocking never restores consent. Removing a connection closes access to chat history until another request is accepted.
- Blocked members' forum content is hidden in both directions. Posts are member-visible, even when a profile is hidden from People. Deleting a topic closes the entire discussion. Messages, topics and replies have stable request IDs for safe retries.
- Reports include the selected content snapshot. Only the recipient can report a private message, and moderators see only the reported snapshot. Moderator actions are recorded with actor, decision and timestamp. Moderator assignment cannot come from client metadata.
- Limits are durable and transactional: 60 messages/minute, 20 follow requests/hour, 10 topics/hour, 60 replies/hour, 20 reports/day. Lists have bounded pages; messages/replies use sequence cursors. Directory/topics use offset pagination and literal partial search.

## Moderator setup

No account is automatically made a moderator. The project owner must explicitly assign a **verified KORLIX account** using the Supabase SQL editor, then that account joins Social and reopens it to see **Social settings → Moderation reports**:

```sql
-- Replace the placeholder only with the account selected by the owner.
insert into public.korlix_social_moderators(user_id)
select id from auth.users
where lower(email) = lower('SELECTED_MODERATOR_EMAIL')
  and email_confirmed_at is not null
on conflict do nothing;
```

Before broad community promotion, assign a moderator and establish a report review process. There is no automatic report adjudication. Suspension restoration and unlocking are owner operations in the database in v1. Ordinary users can edit/remove their own content and unblock members in the UI.

## Validation

`node --test backend/test/social.test.mjs` executes the real migration in PGlite and tests the actual routes, role privileges, privacy, blocks, moderation, limits and pagination. `flutter test test/social_test.dart` checks mobile/desktop layouts, opt-in and compose actions, account-switch clearing and late-response rejection. Tests use isolated local fixtures, never production member interactions.

Release boundaries: no chat attachments, global app presence, background call delivery/push notifications, group calling or end-to-end encryption claim. Discussion refresh is manual; chat refreshes automatically. No existing user is enrolled automatically.

## Profiles, photos and calling (September 28 update)

- Profession is optional (100 characters), member-visible, and included in partial People/connection searches. Older clients that omit it preserve the saved value.
- A separate authenticated multipart route accepts one still JPG/PNG/WebP up to 8 MB and 32 megapixels. Sharp applies EXIF rotation, center-crops to 512×512, re-encodes JPEG and removes metadata. Profile creation precedes uploads. Private bucket `korlix-social-avatars` has a restrictive browser-deny policy; the server signs only authorized member-card photo paths for ten minutes. Replacements/removal delete the previous object. Signed URLs are bearer links until they expire or the object is removed; downloaded photos cannot be recalled.
- Emoji remain ordinary Unicode message text. The client includes a searchable picker and cursor-aware insertion; the API decodes UTF-8 explicitly.
- Audio/video calls use Flutter WebRTC. Caller and recipient need Social open in the foreground; incoming invitations poll every three seconds. The recipient must tap Answer before devices open. A session-specific random device ID claims the call, preventing another tab from taking over. Calls between nonconnections, blocked or suspended members are rejected.
- Signaling uses service-only `korlix_social_calls_v1`, with two RLS-protected tables. No audio/video recordings are made or stored. Offer/answer roles and ownership are enforced; signaling retries use stable UUIDs, signals use sequence cursors, and crossed/busy calls serialize under ordered participant locks. Network candidates can expose each caller's network address to the other participant; this is direct WebRTC, not an anonymity feature.
- Ringing expires after 45 seconds, stale participants after 60 seconds, and calls after four hours. Foreground clients poll every two seconds and stop devices on logout, route disposal, hidden/paused app state, rejected access, permission failure or prolonged network loss. Blocks/removal are rechecked on every signaling/poll action. Signals are deleted at call termination; old call rows and their signals are deleted opportunistically when a participant next checks their inbox after 24 hours. This is not a scheduled retention guarantee.
- Ten new calls per ten minutes per account; 300 signaling writes/minute, bounded payloads and pages. `SOCIAL_CALLS_ENABLED=false` disables starting/answering calls without affecting text chat or ending calls.

### Relay configuration

Direct calling uses Google's public STUN endpoints. No new provider subscription is created. Some mobile, corporate and symmetric-NAT networks require TURN. Set optional backend environment variable `SOCIAL_ICE_SERVERS` to a JSON array of WebRTC ICE servers, e.g. `[{"urls":["turns:YOUR_RELAY:443"],"username":"ISSUED_USERNAME","credential":"ISSUED_CREDENTIAL"}]`. Use credentials intended for client-side TURN access and rotate them; never use a provider management API key. The authenticated call configuration endpoint supplies ICE credentials to the calling client. Do not claim universal connectivity until a relay is configured and tested on the target networks.

### Release checks

Apply `20260928205903_korlix_social_profiles_calls.sql` before the backend, then deploy the Flutter web release. Local PGlite tests cover real SQL/HTTP authorization, uploads/metadata removal, existing permissive storage-policy interaction, Unicode, role-restricted/idempotent signaling, decline, busy calls, stale calls and revocation. Flutter tests cover responsive profiles, emoji composition, call consent, mocked two-party offer/answer/ICE exchange, late device permission, account switches and teardown. Device I/O is mocked in that suite: a real two-account, two-device microphone/camera check on mobile data and Wi-Fi is still required to assess end-to-end media and browser-specific permissions/autoplay. No real users were called or messaged by the test suite.

## Replies to specific chat messages

Apply `20260928225119_korlix_social_message_replies.sql` before deploying the reply-aware backend and frontend. `send` accepts optional `reply_to`; `messages` includes a bounded original-message preview; `GET message` opens one original message within the same accepted conversation. All three use the service-only, security-invoker `korlix_social_chat_v1` RPC. Existing plain-message clients remain compatible.

The server checks both participants, current connection/block state, and the original message’s conversation. Reply previews resolve from the original row rather than preserving a text snapshot, so removing an original hides its text in subsequent responses. Retries must keep the same body and reply target to reuse the same message ID. Local tests cover cross-conversation rejection, blocked access, removal, Unicode, paging, idempotence, and browser-role privileges.
