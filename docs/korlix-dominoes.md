# KORLIX Dominoes backend

Apply `supabase/migrations/20260929043337_korlix_social_domino_video.sql`, then deploy the backend. `/api/social/domino` requires the existing verified Social account authentication. Its public actions are list, create, invite, join, decline, leave, sync, move, media, and signal. Browser input cannot invoke the private snapshot or commit operations. No AI credit or payment endpoints are involved.

The Node engine securely shuffles double-six tiles and enforces two-player or four-player partnership block dominoes, readiness, legal moves, passing, turn order, blocked rounds, and scoring. It redacts all other players' hands and replay receipts. Unique action IDs and revision compare-and-swap prevent duplicate or conflicting moves.

All three tables use RLS and deny browser roles all access. The invoker RPC executes only for service_role; authenticated identity is supplied by the backend. Private table operations lock one table for a short transaction. Host invitations require accepted connections and send one direct Social message only when a new invitation is created. Joining rechecks the relationship. Blocking, suspension, expiry, and departure revoke access/close a table. Active tables are limited to three per host and expire in four hours.

Media signals carry sender and recipient session epochs; stale sessions and other recipients cannot read or write a current call's signaling. Camera-control updates cannot take over a newer device session. Signals expire after two minutes, are bounded and rate limited, and contain no streamed audio or video. Media travels peer-to-peer or through the existing TURN service. Table reads use no-store responses. Expired tables older than seven days are opportunistically removed during creation.

Use the same optional `SOCIAL_ICE_SERVERS` TURN/STUN JSON and `SOCIAL_CALLS_ENABLED` switch as Social calling. No new provider account is created. TURN is necessary for reliable operation across restrictive networks. Disabling calling prevents new media/signals while game play continues.

Validation:

```sh
node --test backend/test/domino.test.mjs backend/test/social.test.mjs
```

Tests use PGlite and fake Social accounts, not production messages. They cover private invitations, duplicate notification prevention, denied/revoked access, hidden hands, complete game simulations, scoring, stale revisions, media epochs, browser grants, and RLS. Real two/four-device audio/video validation remains necessary; automated media-boundary tests do not prove physical microphone or network behavior.
