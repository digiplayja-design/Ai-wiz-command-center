# KORLIX Social shared module

One implementation of Social conversations, groups, voice notes, media, calls, notification routing, themes and accessibility for both the KORLIX AI hub and independently installed Messenger.

Existing hub imports forward to this package; there is no duplicated chat database or forked message UI. `SocialScreen(messengerMode: true)` opens Chats and narrows primary navigation to Chats, Groups and People. Its default constructor preserves the hub's existing Wall-first navigation. `SocialAppAlerts(messengerMode: true)` retains that mode for notification-opened routes. Social client authorization and media disposal still follow the signed-in session.

The shared HTTP/session/token adapters remain in `korlix_receipt_core`. Only reusable UI/support dependencies are included; the Messenger app does not import the full AI hub or its advertising/billing plugins. Package assets are resolved through `packages/korlix_social_core/` in both hosts.

Native Android/iOS method-channel implementations must be installed by the host application. The independent app includes the existing Social/sound bridges under its own package/bundle identifier. Separate push provider registration and live-device acceptance tests are required before release.
