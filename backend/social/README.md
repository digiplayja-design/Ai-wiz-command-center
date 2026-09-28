# KORLIX Social v1

Native Flutter entry: **For personal use → KORLIX Social**. This release adds opt-in member profiles, approval-based connections, private text conversations, and category forums. It uses the existing KORLIX account, backend, and Supabase project; there are no new paid services or AI calls.

## Permissions and behavior

- `requireUser` verifies the access token with Supabase Auth. Anonymous and unconfirmed accounts cannot use Social. Actor identity always comes from that verified user, never a body or query parameter.
- All ten tables have RLS and explicitly deny browser roles. The security-invoker RPC and helpers are executable only by `service_role`. Deploy the migration before the backend.
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

Release boundaries: text chat only; no voice/video calls, attachments, global app presence, push notifications or end-to-end encryption claim. Discussion refresh is manual; chat refreshes automatically. No existing user is enrolled automatically.
