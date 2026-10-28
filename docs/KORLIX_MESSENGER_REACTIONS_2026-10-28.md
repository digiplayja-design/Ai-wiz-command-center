# Messenger reactions, selection tools and realistic media

This continues the app work in PR #26 and backend work in PR #27. It preserves the previously approved Pure Black/Bubbles default, yellow message bubbles and call/sharing work.

## Conversation behavior

- Hold message text to open quick reactions (thumbs up, smile, laugh, cry, love and celebration) together with the text selection menu. Hold the rest of a bubble, use the reaction icon, or choose React in Message options to open the searchable 60-emoji picker, including hand skin tones.
- Each member has one reaction per message. Choosing another replaces it; tapping one's current reaction or Remove my reaction removes it. Counts and the current member's selection come from the server. Failed writes leave the previous count intact and can be retried.
- Reactions work in direct and group conversations and survive reopening. Current-page reactions refresh with the existing four-second conversation refresh; this is not a new realtime subscription.
- Select text to Copy/Share/Select all. Selecting one word adds Dictionary, opening that word in Wiktionary through an explicit browser action. No whole message is sent to the dictionary.
- Selected composer text supports Bold, Italic, Strikethrough and Highlight, including combinations. Formatting is visible while composing and after delivery. It is stored as validated style ranges beside plain text; offsets on the wire are Unicode code points. Copy/share/notification text stays plain. Received messages are not rewritten by formatting controls.
- Large text or a short keyboard viewport uses a horizontally scrollable attachment toolbar, leaving room for messages and the composer.

## Sticker/GIF collection

The bundled collection grows from 24 to 48 designs: 48 transparent PNG stickers and 48 animated GIFs. The added packs contain 12 realistic people, six animals and six everyday/celebration designs. Search covers labels, categories, keywords and pack names. A style selector offers People, Animals, Moments and Classic, with the new designs first. Selection still previews locally and requires Use and then Send; uploads keep existing validation and reduced-motion controls.

The 24 new designs use original artwork generated with the built-in Image Generation tool. Four 4-column/6-row atlases were sliced into 256px frames with alpha preserved, then encoded into six-frame ping-pong GIF loops. These are short pose animations, not licensed television/movie clips or a third-party GIF feed. Final assets live at `packages/korlix_social_core/assets/social_reactions/real-*.png` and `real-*.gif`; metadata is in `catalog.json`.

Prompt specification: photorealistic-natural studio cutouts, exactly four sequential poses for each of six subjects per atlas; identical identity/camera/scale within each row; transparent background; no lettering/logos/grid; generous cell padding. Subject sets: thumbs-up/laugh/wave/thanks/kiss/cheer; tears/surprise/skepticism/applause/thinking/giggle; puppy/tabby/rabbit/red panda/pug/kitten; fist bump/clapping/rose and heart/coffee/birthday cake/peace sign.

## Backend rollout

Apply `20261028145105_korlix_social_message_interactions.sql` from the backend PR before deploying its route change or distributing the app update. The migration adds service-only reaction storage and formatting columns, wraps the existing media-chat RPC without replacing its access checks, and adds the authenticated POST `/api/social/react` action. A missing emoji field is rejected; an explicit JSON null removes the caller's reaction. Do not distribute this app with an older backend that ignores formatting or lacks reactions.

Authorization remains governed by accepted connections/group membership, joined-history floors, blocks, suspension, deletion and personal/everyone Auto Dump. Public/anonymous/authenticated database roles receive no direct table or RPC access. A message-row lock and deletion cleanup prevent a reaction from surviving a concurrent removal. New sends validate ranges before delivery; retrying an existing send ID with changed styles fails atomically.

## Validation and remaining release work

Local validation includes 86 Flutter interaction/media/reply/group/read-receipt/Auto Dump/share checks, all 96 media assets decoded, and 24 backend SQL/HTTP/media/privacy checks. The new interaction test covers Unicode and style combinations, changing/removing reactions in both scopes, request failures, account changes, dictionary scope and retry identity. The mobile validation workflow includes the new interaction tests and the expanded asset tests.

No store release or production backend/database mutation is part of this implementation. Retain the physical two-device call/sharing checks from the earlier work and add Android/iPhone long-press selection, keyboard/IME input, reaction synchronization, and GIF playback checks before distribution. Signed Play/App Store release remains separate from a passing debug/simulator build.
